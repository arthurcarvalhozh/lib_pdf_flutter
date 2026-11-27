import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'pdf_inspector.dart';

/// Gera um PDF de uma página A4 (ou mais, se o conteúdo não couber) com
/// [children], fora do relógio falso do `testWidgets`.
Future<(PdfBuildResult, PdfInspector)> buildPdf(
  WidgetTester tester,
  List<PdfFont> fonts,
  List<Widget> children, {
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final result = await tester.runAsync(
    () => PdfDocument(
      fonts: fonts,
      pages: [MultiPage(format: format, children: children)],
    ).buildWithReport(),
  );
  return (result!, PdfInspector(result.bytes));
}
