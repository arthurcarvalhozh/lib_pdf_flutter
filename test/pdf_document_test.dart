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

  testWidgets('metadados vão para o dicionário Info', (tester) async {
    final (_, pdf) = await buildDocument(
      tester,
      () => PdfDocument(
        fonts: fonts,
        title: 'Relatorio',
        author: 'Equipe',
        subject: 'Bomba de ARLA',
        keywords: 'arla, dosagem',
        creator: 'diagnox 3.7.3',
        creationDate: DateTime.utc(2026, 11, 27, 13, 14, 5),
        pages: [
          const MultiPage(children: [Text('x')]),
        ],
      ),
    );
    expect(pdf.text, contains('/Title (Relatorio)'));
    expect(pdf.text, contains('/Author (Equipe)'));
    expect(pdf.text, contains('/Subject (Bomba de ARLA)'));
    expect(pdf.text, contains('/Keywords (arla, dosagem)'));
    expect(pdf.text, contains('/Creator (diagnox 3.7.3)'));
    expect(pdf.text, contains('/Producer (lib_pdf)'));
    expect(pdf.text, contains('/CreationDate (D:20261127131405Z)'));
  });

  testWidgets('o mesmo documento gera os mesmos bytes', (tester) async {
    PdfDocument document() => PdfDocument(
      fonts: fonts,
      creationDate: DateTime.utc(2026),
      pages: [
        MultiPage(children: [const Text('Relatório'), for (var i = 0; i < 60; i++) Text('Linha $i com acentuação')]),
      ],
    );
    final (first, _) = await buildDocument(tester, document);
    final (second, _) = await buildDocument(tester, document);
    expect(second.bytes, first.bytes);
  });

  testWidgets('cada MultiPage pode ter formato próprio', (tester) async {
    final (result, pdf) = await buildDocument(
      tester,
      () => PdfDocument(
        fonts: fonts,
        pages: [
          const MultiPage(children: [Text('A4 retrato')]),
          MultiPage(format: PdfPageFormat.a4.landscape, children: const [Text('A4 paisagem')]),
          const MultiPage(format: PdfPageFormat.letter, children: [Text('Carta')]),
          MultiPage(format: PdfPageFormat.letter.landscape, children: const [Text('Carta paisagem')]),
        ],
      ),
    );
    expect(result.pageCount, 4);
    expect(pdf.text, contains('/MediaBox [0 0 595.28 841.89]'));
    expect(pdf.text, contains('/MediaBox [0 0 841.89 595.28]'));
    expect(pdf.text, contains('/MediaBox [0 0 612 792]'));
    expect(pdf.text, contains('/MediaBox [0 0 792 612]'));
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
