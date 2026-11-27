import 'package:flutter/services.dart';

/// Uma fonte TrueType para embutir no PDF.
///
/// O `TextStyle` dos widgets continua escolhendo a fonte pelo nome da
/// família e pelo peso, como na tela: a lib liga essa escolha aos bytes
/// registrados aqui.
///
/// A mesma fonte também precisa estar carregada no Flutter (declarada no
/// `pubspec.yaml` do app), porque é o Flutter quem mede o texto.
class PdfFont {
  const PdfFont({required this.family, required this.bytes, this.weight = FontWeight.normal});

  /// Lê a fonte de um asset do app.
  static Future<PdfFont> asset(String path, {required String family, FontWeight weight = FontWeight.normal}) async {
    final data = await rootBundle.load(path);
    return PdfFont(
      family: family,
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      weight: weight,
    );
  }

  final String family;
  final Uint8List bytes;
  final FontWeight weight;
}
