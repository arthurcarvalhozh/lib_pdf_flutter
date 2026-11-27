import 'dart:ui';

/// Tamanho da página em pontos (1/72 de polegada), a unidade do PDF.
///
/// No PDF, 1 pixel lógico do Flutter vale 1 ponto: um `SizedBox(width: 72)`
/// sai com uma polegada.
class PdfPageFormat {
  const PdfPageFormat(this.width, this.height) : assert(width > 0 && height > 0);

  /// Formato a partir de milímetros (1 mm = 72 / 25,4 pontos).
  PdfPageFormat.millimeters(double width, double height) : this(width * _pointsPerMm, height * _pointsPerMm);

  static const _pointsPerMm = 72 / 25.4;

  static const a3 = PdfPageFormat(841.89, 1190.55);
  static const a4 = PdfPageFormat(595.28, 841.89);
  static const a5 = PdfPageFormat(419.53, 595.28);

  /// Carta (8,5 × 11 polegadas).
  static const letter = PdfPageFormat(612, 792);

  /// Legal americano (8,5 × 14 polegadas).
  static const legal = PdfPageFormat(612, 1008);

  final double width;
  final double height;

  Size get size => Size(width, height);

  /// A mesma página deitada.
  PdfPageFormat get landscape => width >= height ? this : PdfPageFormat(height, width);

  /// A mesma página em pé.
  PdfPageFormat get portrait => height >= width ? this : PdfPageFormat(height, width);

  @override
  bool operator ==(Object other) => other is PdfPageFormat && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PdfPageFormat($width × $height pt)';
}
