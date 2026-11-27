import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'pdf_inspector.dart';
import 'pdf_validator.dart';

/// Gera um PDF de uma página A4 (ou mais, se o conteúdo não couber) com
/// [children], fora do relógio falso do `testWidgets`.
///
/// Todo PDF gerado aqui passa pelo [validatePdf] e fica salvo em
/// `build/pdfs/`, onde o CI roda o `qpdf --check`.
Future<(PdfBuildResult, PdfInspector)> buildPdf(
  WidgetTester tester,
  List<PdfFont> fonts,
  List<Widget> children, {
  PdfPageFormat format = PdfPageFormat.a4,
}) {
  return buildDocument(
    tester,
    () => PdfDocument(
      fonts: fonts,
      pages: [MultiPage(format: format, children: children)],
    ),
  );
}

/// Como [buildPdf], para um [PdfDocument] montado pelo teste.
Future<(PdfBuildResult, PdfInspector)> buildDocument(WidgetTester tester, PdfDocument Function() document) async {
  final result = (await tester.runAsync(() => document().buildWithReport()))!;
  checkAndSave(tester.testDescription, result.bytes);
  return (result, PdfInspector(result.bytes));
}

/// Valida [bytes] e salva em `build/pdfs/<nome>.pdf`.
void checkAndSave(String name, Uint8List bytes) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  final plain = name.toLowerCase().split('').map((c) => accents[c] ?? c).join();
  final file = plain.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  File('build/pdfs/$file.pdf')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  expect(validatePdf(bytes), isEmpty, reason: 'estrutura do PDF (build/pdfs/$file.pdf)');
}
