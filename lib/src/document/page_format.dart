import 'dart:ui';

/// Tamanho da página em pontos (1/72 de polegada), a unidade do PDF.
///
/// No PDF, 1 pixel lógico do Flutter vale 1 ponto: um `SizedBox(width: 72)`
/// sai com uma polegada.
class PdfPageFormat {
  const PdfPageFormat(this.width, this.height);

  static const a4 = PdfPageFormat(595.28, 841.89);
  static const a5 = PdfPageFormat(419.53, 595.28);
  static const letter = PdfPageFormat(612, 792);

  final double width;
  final double height;

  Size get size => Size(width, height);

  /// A mesma página deitada.
  PdfPageFormat get landscape => width >= height ? this : PdfPageFormat(height, width);

  @override
  bool operator ==(Object other) => other is PdfPageFormat && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PdfPageFormat($width × $height pt)';
}
