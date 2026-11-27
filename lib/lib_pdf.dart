/// PDF feito com widgets do Flutter.
///
/// O relatório é uma árvore de widgets comum; a lib monta, mede e pinta essa
/// árvore direto em PDF, em vetor e com texto real.
library;

export 'src/document/page_format.dart' show PdfPageFormat;
export 'src/document/pdf_build_result.dart' show PdfBuildResult;
export 'src/text/pdf_font.dart' show PdfFont;
export 'src/widgets/keep_together.dart' show KeepTogether;
export 'src/widgets/multi_page.dart' show MultiPage;
export 'src/widgets/pdf_document.dart' show PdfDocument;
