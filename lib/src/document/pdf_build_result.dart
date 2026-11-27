import 'dart:typed_data';

/// O PDF gerado e o que aconteceu na geração.
class PdfBuildResult {
  const PdfBuildResult({
    required this.bytes,
    required this.pageCount,
    required this.warnings,
    required this.layoutTime,
    required this.paintTime,
    required this.writeTime,
    required this.imageCount,
    required this.rasterizedTextCount,
  });

  final Uint8List bytes;
  final int pageCount;

  /// O que a lib não conseguiu reproduzir fielmente, com quantas vezes
  /// aconteceu. Por exemplo: um gradiente que saiu em cor sólida.
  final Map<String, int> warnings;

  final Duration layoutTime;
  final Duration paintTime;
  final Duration writeTime;
  Duration get totalTime => layoutTime + paintTime + writeTime;

  /// Imagens embutidas, incluindo os textos que precisaram ser rasterizados.
  final int imageCount;

  /// Textos pintados dentro de painters (`TextPainter` num `CustomPainter`),
  /// que hoje saem como imagem em vez de texto real.
  final int rasterizedTextCount;
}
