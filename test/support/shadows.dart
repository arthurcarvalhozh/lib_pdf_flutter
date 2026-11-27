import 'package:flutter/rendering.dart';

/// O `flutter_test` desliga as sombras (`debugDisableShadows`) para as
/// imagens de referência não variarem; no app elas existem. Liga durante o
/// [body] e desliga antes do fim do teste, como o framework exige.
Future<void> withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}
