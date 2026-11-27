// Contrato com o Flutter.
//
// A lib pinta a árvore de render objects por conta própria, então depende de
// como cada widget do Flutter se pinta: quais camadas cria, quais render
// objects usa. Esses detalhes mudam entre versões (o Opacity, por exemplo,
// deixou de chamar pushOpacity e passou a criar a camada em
// updateCompositedLayer). Cada teste aqui trava um desses pontos: se uma
// atualização do Flutter quebrar um deles, o teste falha antes do relatório.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'support/build.dart';
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
  });

  group('cada widget sai com o operador PDF esperado', () {
    testWidgets('Opacity vira estado gráfico com alfa', (tester) async {
      final (result, pdf) = await buildPdf(tester, fonts, [
        const Opacity(
          opacity: 0.5,
          child: ColoredBox(color: Colors.black, child: SizedBox(height: 20)),
        ),
      ]);
      expect(result.warnings, isEmpty);
      expect(pdf.text, contains('/ca 0.502'));
      expect(pdf.pageContents.single, contains(' gs'));
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

class _LinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), Paint()..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => false;
}
