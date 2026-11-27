import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';
import 'package:lib_pdf_example/report/sample_data.dart';
import 'package:lib_pdf_example/report/sample_report.dart';

void main() {
  late List<PdfFont> fonts;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fonts = [
      for (final (file, weight) in [
        ('Regular', FontWeight.w400),
        ('SemiBold', FontWeight.w600),
        ('Bold', FontWeight.w700),
      ])
        await PdfFont.asset('assets/fonts/Montserrat-$file.ttf', family: 'Montserrat', weight: weight),
    ];
    // No `flutter test` as fontes do pubspec não são carregadas no motor.
    final loader = FontLoader('Montserrat');
    for (final f in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(f.bytes)));
    }
    await loader.load();
  });

  testWidgets('o relatório de exemplo sai em vetor, com fl_chart e qr_flutter', (tester) async {
    final result = await tester.runAsync(
      () => PdfDocument(
        fonts: fonts,
        title: 'Relatório de exemplo',
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.black),
        pages: [MultiPage(children: SampleReport(SampleData()).children)],
      ).buildWithReport(),
    );

    // Para conferir a olho: build/exemplo/relatorio_exemplo.pdf
    File('build/exemplo/relatorio_exemplo.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(result!.bytes);

    expect(result.pageCount, 2);
    // O único ponto não vetorial é o texto de TextPainter no desenho livre,
    // de propósito (ver docs/prova-de-conceito.md).
    expect(result.rasterizedTextCount, 1);
    expect(result.warnings.keys, ['texto pintado por painter (drawParagraph) rasterizado']);
  });
}
