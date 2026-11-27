import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf_poc/pdf/pdf_document.dart';
import 'package:lib_pdf_poc/report/poc_report.dart';
import 'package:lib_pdf_poc/report/sample_data.dart';

/// Gera o relatório da prova de conceito em `build/poc/relatorio_poc.pdf`,
/// para conferência nos leitores e com o poppler (`pdftotext`, `pdftoppm`).
void main() {
  testWidgets('gera o relatório de NOx em PDF vetorial', (tester) async {
    final fonts = <PdfFontSpec>[];
    for (final (file, weight) in [('Regular', 400), ('SemiBold', 600), ('Bold', 700)]) {
      final bytes = File('assets/fonts/Montserrat-$file.ttf').readAsBytesSync();
      fonts.add(PdfFontSpec('Montserrat', bytes, weight: weight));
    }
    // No `flutter test` as fontes do pubspec não são carregadas no motor:
    // sem isso o Flutter mede o texto com a fonte de teste.
    final loader = FontLoader('Montserrat');
    for (final f in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(f.bytes)));
    }
    await loader.load();
    // O motor avisa "fontes mudaram" de forma assíncrona: espera o aviso
    // chegar antes de montar a árvore do PDF.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final result = await tester.runAsync(() async {
      final doc = PdfDocumentPoc(fonts: fonts, title: 'Relatório do sensor de NOx (prova de conceito)');
      return doc.render(PocReport(data: PocData()));
    });

    final out = File('build/poc/relatorio_poc.pdf')..createSync(recursive: true);
    out.writeAsBytesSync(result!.bytes);
    // ignore: avoid_print
    print('PDF: ${out.path} · ${result.bytes.length} bytes · ${result.pages} páginas · '
        'layout ${result.layout.inMilliseconds} ms · pintura ${result.paint.inMilliseconds} ms · '
        'escrita ${result.write.inMilliseconds} ms · imagens ${result.images} '
        '(${result.textFallbackImages} de texto rasterizado)');
    result.log.forEach((k, v) => print('  log: $k ×$v')); // ignore: avoid_print

    expect(result.pages, greaterThan(1));
  });
}
