// Etapa 4: cada comando do canvas do Flutter tem tradução, em vetor quando o
// PDF tem equivalente e em imagem (com aviso) quando não tem.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

  Widget painted(void Function(Canvas canvas, Size size) paint, {double height = 60}) => SizedBox(
    height: height,
    child: CustomPaint(painter: _Painter(paint)),
  );

  group('gradientes', () {
    testWidgets('LinearGradient de decoração vira shading axial, sem imagem', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(colors: [Color(0xFFFF0000), Color(0xFF0000FF)]),
          ),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(result.imageCount, 0);
      expect(pdf.text, contains('/ShadingType 2'));
      expect(pdf.text, contains('/C0 [1 0 0] /C1 [0 0 1]'));
      // Recorte no contorno arredondado e o shading dentro dele.
      expect(pdf.pageContents.single, matches(RegExp(r' c\nh\nW n\n/Sh\d+ sh\n')));
    });

    testWidgets('paradas com troca seca de cor viram função costurada', (tester) async {
      final (_, pdf) = await buildPdf(tester, fonts, [
        Container(
          height: 40,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF0000), Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)],
              stops: [0.2, 0.5, 0.5, 1],
            ),
          ),
        ),
      ]);
      // Trechos: 0–0,2 (vermelho fixo), 0,2–0,5 (vermelho fixo), 0,5–1
      // (verde para azul); o de largura zero em 0,5 é a troca seca.
      expect(pdf.text, contains('/FunctionType 3'));
      expect(pdf.text, contains('/Bounds [0.2 0.5]'));
    });

    testWidgets('RadialGradient com foco vira shading radial de dois círculos', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        Container(
          height: 100,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFF000000)],
              focal: Alignment(-0.5, -0.5),
              focalRadius: 0.1,
            ),
          ),
        ),
      ]);
      expect(result.imageCount, 0);
      expect(pdf.text, contains('/ShadingType 3'));
      expect(pdf.text, matches(RegExp(r'/Coords \[[\d.]+ 25 10 [\d.]+ 50 50\]')));
    });

    testWidgets('GradientTransform vira matriz antes do shading', (tester) async {
      final (_, pdf) = await buildPdf(tester, fonts, [
        Container(
          height: 40,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF0000), Color(0xFF0000FF)],
              transform: GradientRotation(math.pi / 2),
            ),
          ),
        ),
      ]);
      expect(pdf.pageContents.single, matches(RegExp(r'\n0 1 -1 0 [-\d.]+ [-\d.]+ cm\n/Sh\d+ sh\n')));
    });

    testWidgets('cores com opacidades diferentes e varredura viram imagem, com aviso', (tester) async {
      final (result, _) = await buildPdf(tester, fonts, [
        Container(
          height: 40,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF0000), Color(0x000000FF)])),
        ),
        Container(
          height: 40,
          decoration: const BoxDecoration(gradient: SweepGradient(colors: [Color(0xFFFF0000), Color(0xFF0000FF)])),
        ),
      ]);
      expect(result.imageCount, 2);
      expect(result.warnings['gradiente sem equivalente em PDF rasterizado'], 2);
    });

    testWidgets('shader pintado por painter vira imagem recortada pelo caminho vetorial', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          final rect = Offset.zero & size;
          canvas.drawOval(
            rect,
            Paint()..shader = const LinearGradient(colors: [Colors.red, Colors.blue]).createShader(rect),
          );
        }),
      ]);
      expect(result.imageCount, 1);
      expect(result.warnings.keys, contains('shader sem gradiente conhecido rasterizado'));
      expect(pdf.pageContents.single, matches(RegExp(r' c\nh\nW n\n.*/Im\d+ Do', dotAll: true)));
    });
  });

  group('opacidade e mistura', () {
    testWidgets('Opacity compõe o conteúdo antes de aplicar o alfa', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        Opacity(
          opacity: 0.4,
          child: Container(height: 30, color: Colors.blue, child: const Text('texto sobre o fundo')),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.text, contains('/Subtype /Form'));
      expect(pdf.text, contains('/S /Transparency'));
      expect(pdf.text, contains('/ca 0.4'));
      // Dentro do grupo, fundo e texto saem opacos.
      final group = pdf.formContents.single;
      expect(group, contains('rg'));
      expect(group, contains('BT'));
      expect(group, isNot(contains(' gs')));
    });

    testWidgets('saveLayer com alfa vira grupo; aninhados multiplicam', (tester) async {
      final (_, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.saveLayer(null, Paint()..color = const Color(0x80000000));
          canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = Colors.red);
          canvas.saveLayer(null, Paint()..color = const Color(0x80000000));
          canvas.drawRect(const Rect.fromLTWH(20, 20, 40, 40), Paint()..color = Colors.green);
          canvas.restore();
          canvas.restore();
        }),
      ]);
      expect(pdf.formContents, hasLength(2));
      expect(pdf.formContents.where((f) => f.contains(' Do Q')), hasLength(1));
    });

    testWidgets('BlendMode separável vira /BM; Porter-Duff vira aviso', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.drawCircle(const Offset(30, 30), 20, Paint()..color = Colors.yellow);
          canvas.drawCircle(
            const Offset(45, 30),
            20,
            Paint()
              ..color = Colors.cyan
              ..blendMode = BlendMode.multiply,
          );
          canvas.drawCircle(
            const Offset(60, 30),
            20,
            Paint()
              ..color = Colors.red
              ..blendMode = BlendMode.xor,
          );
        }),
      ]);
      expect(pdf.text, contains('/BM /Multiply'));
      expect(result.warnings.keys, contains('BlendMode xor sem equivalente em PDF; tratado como srcOver'));
    });
  });

  group('efeitos sem equivalente viram imagem só no trecho', () {
    testWidgets('BoxShadow e Card com elevação', (tester) async {
      await withShadows(() async {
        final (result, _) = await buildPdf(tester, fonts, [
          Container(
            height: 40,
            margin: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
          const Card(elevation: 4, child: SizedBox(height: 40)),
        ]);
        expect(
          result.warnings.keys,
          containsAll(['desfoque rasterizado', 'sombra de elevação (drawShadow) rasterizada']),
        );
        expect(result.imageCount, 2);
      });
    });

    testWidgets('ColorFiltered, ShaderMask e ImageFiltered', (tester) async {
      final (result, _) = await buildPdf(tester, fonts, [
        const ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.red, BlendMode.srcIn),
          child: SizedBox(height: 20, child: Text('filtrado')),
        ),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [Colors.black, Colors.transparent]).createShader(r),
          child: Container(height: 20, color: Colors.blue),
        ),
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Container(height: 20, color: Colors.green),
        ),
      ]);
      expect(result.imageCount, 3, reason: '${result.warnings}');
      expect(
        result.warnings.keys,
        containsAll([
          'camada ColorFilterLayer (filtro sem equivalente em PDF) rasterizada',
          'camada ShaderMaskLayer (filtro sem equivalente em PDF) rasterizada',
          'camada ImageFilterLayer (filtro sem equivalente em PDF) rasterizada',
        ]),
      );
    });

    testWidgets('Image com cor (filtro de cor) é rasterizada na resolução da imagem', (tester) async {
      final image = _checker(16);
      final (result, _) = await buildPdf(tester, fonts, [
        SizedBox(
          height: 32,
          child: RawImage(image: image, color: Colors.red, colorBlendMode: BlendMode.modulate),
        ),
      ]);
      expect(result.warnings.keys, contains('imagem com filtro rasterizada'));
      expect(result.imageCount, 1);
    });
  });

  group('recorte, imagens e o resto do canvas', () {
    testWidgets('recorte por diferença vira par-ímpar', (tester) async {
      final (_, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.clipRect(const Rect.fromLTWH(10, 10, 20, 20), clipOp: ui.ClipOp.difference);
          canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
        }),
      ]);
      expect(pdf.pageContents.single, contains('re\nW* n\n'));
    });

    testWidgets('getLocalClipBounds acompanha recorte e transformação', (tester) async {
      Rect? seen;
      await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.clipRect(const Rect.fromLTWH(10, 10, 50, 30));
          canvas.translate(10, 10);
          canvas.scale(2);
          seen = canvas.getLocalClipBounds();
        }),
      ]);
      expect(seen, const Rect.fromLTWH(0, 0, 25, 15));
    });

    testWidgets('imagem de widget sobrevive à desmontagem da árvore', (tester) async {
      // O RenderImage descarta o handle dele ao ser desmontado, e a lib lê os
      // pixels depois disso: sem clonar o handle, a leitura falhava.
      final image = _checker(20);
      final (result, _) = await buildPdf(tester, fonts, [
        SizedBox(height: 40, child: RawImage(image: image)),
        SizedBox(height: 40, child: RawImage(image: image)),
      ]);
      expect(result.imageCount, 1);
      expect(result.warnings, isEmpty);
    });

    testWidgets('drawImageNine desenha nove partes da mesma imagem', (tester) async {
      final image = _checker(30);
      final (result, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.drawImageNine(image, const Rect.fromLTRB(10, 10, 20, 20), const Rect.fromLTWH(0, 0, 120, 60), Paint());
        }),
      ]);
      expect(result.warnings, isEmpty);
      expect(result.imageCount, 1);
      expect(RegExp(r'/Im1 Do').allMatches(pdf.pageContents.single), hasLength(9));
    });

    testWidgets('drawAtlas desenha cada recorte com a sua transformação', (tester) async {
      final image = _checker(20);
      final (result, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          canvas.drawAtlas(
            image,
            [
              RSTransform.fromComponents(
                rotation: math.pi / 2,
                scale: 1,
                anchorX: 0,
                anchorY: 0,
                translateX: 40,
                translateY: 0,
              ),
            ],
            [const Rect.fromLTWH(0, 0, 10, 10)],
            null,
            null,
            null,
            Paint(),
          );
        }),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.pageContents.single, contains('0 1 -1 0 40 0 cm'));
    });

    testWidgets('formas, arcos, pontos e caminhos saem em vetor, sem aviso', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        painted((canvas, size) {
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.bevel;
          canvas.drawRRect(RRect.fromLTRBR(0, 0, 40, 30, const Radius.circular(6)), Paint());
          canvas.drawDRRect(
            RRect.fromLTRBR(50, 0, 90, 30, const Radius.circular(6)),
            RRect.fromLTRBR(55, 5, 85, 25, const Radius.circular(3)),
            Paint(),
          );
          canvas.drawArc(const Rect.fromLTWH(100, 0, 30, 30), 0, math.pi * 1.5, true, Paint());
          canvas.drawArc(const Rect.fromLTWH(140, 0, 30, 30), 0, math.pi, false, stroke);
          canvas.drawPoints(ui.PointMode.points, const [Offset(180, 10), Offset(190, 10)], stroke);
          canvas.drawPoints(ui.PointMode.polygon, const [Offset(200, 0), Offset(220, 30), Offset(240, 0)], stroke);
          canvas.drawPath(
            Path()
              ..fillType = PathFillType.evenOdd
              ..addOval(const Rect.fromLTWH(250, 0, 40, 40))
              ..addOval(const Rect.fromLTWH(260, 10, 20, 20)),
            Paint(),
          );
          canvas.drawRSuperellipse(
            RSuperellipse.fromLTRBR(300, 0, 340, 40, const Radius.circular(10)),
            Paint()..color = Colors.purple,
          );
          canvas.drawPaint(Paint()..color = const Color(0x10000000));
        }),
      ]);
      expect(result.warnings, isEmpty);
      expect(result.imageCount, 0);
      final ops = pdf.pageContents.single;
      expect(ops, contains('1 J 2 j'));
      expect(ops, contains('\nf*\n'));
    });
  });
}

/// Imagem quadriculada criada na hora, para os testes de imagem.
ui.Image _checker(int size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < size; y += 5) {
    for (var x = 0; x < size; x += 5) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 5, 5),
        Paint()..color = (x + y) % 10 == 0 ? Colors.black : Colors.amber,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size, size);
  picture.dispose();
  return image;
}

class _Painter extends CustomPainter {
  _Painter(this.onPaint);
  final void Function(Canvas canvas, Size size) onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint(canvas, size);

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}
