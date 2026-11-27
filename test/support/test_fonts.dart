import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lib_pdf/lib_pdf.dart';

/// Montserrat das fixtures, registrada no motor do Flutter (no `flutter test`
/// as fontes de app não são carregadas sozinhas) e pronta para a lib.
Future<List<PdfFont>> loadTestFonts() async {
  final fonts = [
    for (final (file, weight) in [
      ('Regular', FontWeight.w400),
      ('SemiBold', FontWeight.w600),
      ('Bold', FontWeight.w700),
    ])
      PdfFont(
        family: 'Montserrat',
        bytes: File('test/fixtures/fonts/Montserrat-$file.ttf').readAsBytesSync(),
        weight: weight,
      ),
  ];
  final loader = FontLoader('Montserrat');
  for (final f in fonts) {
    loader.addFont(Future.value(ByteData.sublistView(f.bytes)));
  }
  await loader.load();
  return fonts;
}
