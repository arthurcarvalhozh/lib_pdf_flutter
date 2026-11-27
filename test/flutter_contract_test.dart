// Contrato com o Flutter.
//
// A lib pinta a árvore de render objects por conta própria, então depende de
// como cada widget do Flutter se pinta: quais camadas cria, quais render
// objects usa. Esses detalhes mudam entre versões (o Opacity, por exemplo,
// deixou de chamar pushOpacity e passou a criar a camada em
// updateCompositedLayer). Cada teste aqui trava um desses pontos: se uma
// atualização do Flutter quebrar um deles, o teste falha antes do relatório.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'support/build.dart';
import 'support/shadows.dart';
import 'support/test_fonts.dart';

void main() {
  late List<PdfFont> fonts;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fonts = await loadTestFonts();
  });

  group('detalhes internos do Flutter', () {
    test('RenderOpacity é fronteira de repintura e entrega o alfa numa OpacityLayer', () {
      final opacity = RenderOpacity(
        opacity: 0.5,
        child: RenderConstrainedBox(additionalConstraints: const BoxConstraints()),
      );
      expect(opacity.isRepaintBoundary, isTrue);
      final layer = opacity.updateCompositedLayer(oldLayer: null);
      expect(layer, isA<OpacityLayer>());
      expect((layer as OpacityLayer).alpha, 128);
    });

    testWidgets('ImageFiltered é fronteira de repintura e entrega o filtro numa ImageFilterLayer', (tester) async {
      await tester.pumpWidget(
        ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1), child: const SizedBox()),
      );
      final filtered = tester.renderObject(find.byType(ImageFiltered));
      expect(filtered.isRepaintBoundary, isTrue);
      expect(filtered.updateCompositedLayer(oldLayer: null), isA<ImageFilterLayer>());
    });

    testWidgets('Text e RichText pintam com RenderParagraph', (tester) async {
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: Text('x')));
      expect(tester.renderObject(find.byType(RichText)), isA<RenderParagraph>());
    });

    testWidgets('Table expõe a caixa de cada linha', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Table(
            children: const [
              TableRow(children: [SizedBox(height: 10)]),
              TableRow(children: [SizedBox(height: 20)]),
            ],
          ),
        ),
      );
      final table = tester.renderObject<RenderTable>(find.byType(Table));
      expect(table.getRowBox(1), const Rect.fromLTRB(0, 10, 800, 30));
    });

    testWidgets('BoxDecoration pinta sombras com desfoque e o fundo com shader, nessa ordem', (tester) async {
      await withShadows(() async {
        // O aviso de gradiente da lib vale para a primeira pintura com shader
        // e o alcance do desfoque vem das sombras: depende desta ordem.
        final box = RenderDecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFFF0000), Color(0xFF0000FF)]),
            boxShadow: [BoxShadow(blurRadius: 4)],
          ),
        );
        final calls = <String>[];
        box.decoration.createBoxPainter().paint(
          _RecordingCanvas(calls),
          Offset.zero,
          const ImageConfiguration(size: Size(100, 40), textDirection: TextDirection.ltr),
        );
        expect(calls, ['drawRect maskFilter', 'drawRect shader']);
      });
    });

    testWidgets('Material com elevação pinta a sombra com drawShadow', (tester) async {
      await withShadows(() async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: Material(elevation: 4, child: SizedBox(width: 40, height: 40))),
          ),
        );
        final calls = <String>[];
        final shape = tester.allRenderObjects.whereType<RenderPhysicalModel>().firstWhere((r) => r.elevation == 4);
        final recorder = PictureRecorder();
        final context = _RecordingContext(_RecordingCanvas(calls, Canvas(recorder)), shape.paintBounds);
        shape.paint(context, Offset.zero);
        recorder.endRecording().dispose();
        expect(calls, contains('drawShadow'));
      });
    });

    testWidgets('ColorFiltered e ShaderMask empurram camadas próprias', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              const ColorFiltered(
                colorFilter: ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcIn),
                child: SizedBox(width: 10, height: 10),
              ),
              ShaderMask(
                shaderCallback: (r) =>
                    const LinearGradient(colors: [Color(0xFF000000), Color(0x00000000)]).createShader(r),
                child: const SizedBox(width: 10, height: 10),
              ),
            ],
          ),
        ),
      );
      final layers = <Type>[];
      void collect(Layer? layer) {
        while (layer != null) {
          layers.add(layer.runtimeType);
          if (layer is ContainerLayer) collect(layer.firstChild);
          layer = layer.nextSibling;
        }
      }

      collect(tester.binding.renderViews.first.debugLayer);
      expect(layers, containsAll([ColorFilterLayer, ShaderMaskLayer]));
    });
  });

  group('cada widget sai com o operador PDF esperado', () {
    testWidgets('Opacity vira grupo de transparência com alfa', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        const Opacity(
          opacity: 0.5,
          child: ColoredBox(color: Colors.black, child: SizedBox(height: 20)),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.text, contains('/ca 0.502'));
      expect(pdf.pageContents.single, matches(RegExp(r'q /GS\d+ gs /Fm\d+ Do Q')));
    });

    testWidgets('ClipRRect vira recorte', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const ColoredBox(color: Colors.black, child: SizedBox(height: 20)),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.pageContents.single, contains('W n'));
    });

    testWidgets('Transform.rotate vira matriz de transformação', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        SizedBox(
          height: 40,
          child: Transform.rotate(
            angle: math.pi / 2,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.pageContents.single, matches(RegExp(r'\n0 1 -1 0 [-\d.]+ [-\d.]+ cm\n')));
    });

    testWidgets('CustomPaint desenha em vetor', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        SizedBox(height: 40, child: CustomPaint(painter: _LinePainter())),
      ]);
      expect(result.warnings, isEmpty);
      expect(result.imageCount, 0);
      expect(pdf.pageContents.single, contains('\nS\n'));
    });

    testWidgets('bordas e fundos de Container saem em vetor', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        Container(
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFFF0000),
            border: Border.all(),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.pageContents.single, contains('1 0 0 rg'));
    });
  });
}

/// Canvas que anota as chamadas de desenho (e repassa a [inner], se houver).
class _RecordingCanvas implements Canvas {
  _RecordingCanvas(this.calls, [this.inner]);
  final List<String> calls;
  final Canvas? inner;

  String _describe(Paint p) => p.shader != null ? 'shader' : (p.maskFilter != null ? 'maskFilter' : 'cor');

  @override
  void drawRect(Rect rect, Paint paint) => calls.add('drawRect ${_describe(paint)}');

  @override
  void drawRRect(RRect rrect, Paint paint) => calls.add('drawRRect ${_describe(paint)}');

  @override
  void drawPath(Path path, Paint paint) => calls.add('drawPath ${_describe(paint)}');

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) => calls.add('drawShadow');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final inner = this.inner;
    if (inner == null) return null;
    return reflectlessForward(inner, invocation);
  }
}

/// Repassa as chamadas que o teste não anota (save, translate...).
dynamic reflectlessForward(Canvas c, Invocation i) {
  final args = i.positionalArguments;
  switch (i.memberName) {
    case #save:
      return c.save();
    case #restore:
      return c.restore();
    case #translate:
      return c.translate(args[0] as double, args[1] as double);
    case #getSaveCount:
      return c.getSaveCount();
    case #clipPath:
      return c.clipPath(args[0] as Path);
    case #clipRRect:
      return c.clipRRect(args[0] as RRect);
    case #clipRect:
      return c.clipRect(args[0] as Rect);
  }
  return null;
}

// ignore: invalid_use_of_protected_member
class _RecordingContext extends PaintingContext {
  // ignore: invalid_use_of_protected_member
  _RecordingContext(this._canvas, Rect bounds) : super(ContainerLayer(), bounds);
  final Canvas _canvas;

  @override
  Canvas get canvas => _canvas;

  @override
  void paintChild(RenderObject child, Offset offset) {}
}

class _LinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), Paint()..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => false;
}
