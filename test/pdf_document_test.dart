import 'package:flutter/material.dart';
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

  testWidgets('Text sai como texto real, copiável e com acentos', (tester) async {
    final (result, pdf) = await buildPdf(tester, fonts, [const Text('Válvula de pressão: ação corretiva — O₂')]);

    expect(result.pageCount, 1);
    expect(pdf.pageCount, 1);
    expect(result.imageCount, 0, reason: 'nenhum texto pode virar imagem');
    final ops = pdf.pageContents.single;
    expect(ops, contains('BT'));
    expect(ops, contains('TJ'));
    expect(pdf.text, contains('/FontFile2'), reason: 'a fonte vai embutida');
    expect(pdf.unicodeCodePoints, containsAll('áçã—₂'.runes), reason: 'ToUnicode permite copiar os acentos');
  });

  testWidgets('o peso do TextStyle escolhe a fonte registrada', (tester) async {
    final (_, pdf) = await buildPdf(tester, fonts, [
      const Text('normal'),
      const Text('negrito', style: TextStyle(fontWeight: FontWeight.bold)),
    ]);

    final usedFonts = RegExp(r'/(F\d+) [\d.]+ Tf').allMatches(pdf.pageContents.single).map((m) => m.group(1)).toSet();
    expect(usedFonts, hasLength(2));
  });

  testWidgets('conteúdo longo vira várias páginas', (tester) async {
    final (result, pdf) = await buildPdf(tester, fonts, [for (var i = 0; i < 120; i++) Text('Linha $i')]);

    expect(result.pageCount, greaterThan(1));
    expect(pdf.pageCount, result.pageCount);
  });

  testWidgets('título e autor vão para os metadados', (tester) async {
    final result = await tester.runAsync(
      () => PdfDocument(
        fonts: fonts,
        title: 'Relatorio',
        author: 'Equipe',
        pages: [
          const MultiPage(children: [Text('x')]),
        ],
      ).buildWithReport(),
    );
    final text = String.fromCharCodes(result!.bytes);
    expect(text, contains('/Title (Relatorio)'));
    expect(text, contains('/Author (Equipe)'));
  });

  testWidgets('cada MultiPage pode ter formato próprio', (tester) async {
    final result = await tester.runAsync(
      () => PdfDocument(
        fonts: fonts,
        pages: [
          const MultiPage(children: [Text('retrato')]),
          MultiPage(format: PdfPageFormat.a4.landscape, children: const [Text('paisagem')]),
        ],
      ).buildWithReport(),
    );
    final text = String.fromCharCodes(result!.bytes);
    expect(result.pageCount, 2);
    expect(text, contains('/MediaBox [0 0 595.28 841.89]'));
    expect(text, contains('/MediaBox [0 0 841.89 595.28]'));
  });

  testWidgets('o que não sai fiel vira aviso, sem quebrar a geração', (tester) async {
    final (result, _) = await buildPdf(tester, fonts, [
      Container(
        height: 40,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.red, Colors.blue])),
      ),
    ]);

    expect(result.pageCount, 1);
    expect(result.warnings.keys, contains(contains('gradiente')));
  });

  testWidgets('a geração não deixa erro pendente quando as fontes do sistema mudam no meio', (tester) async {
    // Recarregar a fonte dispara o aviso de troca de fontes do sistema
    // enquanto a árvore do PDF existe (visto na prova de conceito).
    final reload = loadTestFonts();
    final (result, _) = await buildPdf(tester, fonts, [const Text('texto')]);
    await reload;
    await tester.pump();

    expect(result.pageCount, 1);
    expect(tester.takeException(), isNull);
  });
}
