import 'dart:typed_data';
import 'dart:ui' as ui;

import '../document/pdf_writer.dart';

/// Embute uma imagem já decodificada pelo Flutter: pixels RGB comprimidos e,
/// se houver transparência, uma máscara (SMask) com o canal alfa.
Future<PdfRef> writeImage(PdfWriter w, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final rgba = data!.buffer.asUint8List();
  final n = image.width * image.height;
  final rgb = Uint8List(n * 3);
  final alpha = Uint8List(n);
  var opaque = true;
  for (var i = 0; i < n; i++) {
    rgb[i * 3] = rgba[i * 4];
    rgb[i * 3 + 1] = rgba[i * 4 + 1];
    rgb[i * 3 + 2] = rgba[i * 4 + 2];
    alpha[i] = rgba[i * 4 + 3];
    if (alpha[i] != 255) opaque = false;
  }
  PdfRef? smask;
  if (!opaque) {
    smask = w.addStream({
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Image'),
      'Width': image.width,
      'Height': image.height,
      'ColorSpace': const PdfName('DeviceGray'),
      'BitsPerComponent': 8,
    }, alpha);
  }
  return w.addStream({
    'Type': const PdfName('XObject'),
    'Subtype': const PdfName('Image'),
    'Width': image.width,
    'Height': image.height,
    'ColorSpace': const PdfName('DeviceRGB'),
    'BitsPerComponent': 8,
    'Interpolate': true,
    'SMask': ?smask,
  }, rgb);
}
