import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Leitor mínimo dos PDFs que a própria lib escreve, para os testes
/// verificarem o que saiu: objetos, streams descomprimidos e páginas.
///
/// Não é um leitor de PDF genérico: depende do formato do `PdfWriter`
/// (`N 0 obj` / `stream` / `endstream`, um objeto por vez).
class PdfInspector {
  PdfInspector(Uint8List bytes) : text = latin1.decode(bytes) {
    final objRe = RegExp(r'(\d+) 0 obj\n');
    for (final m in objRe.allMatches(text)) {
      final id = int.parse(m.group(1)!);
      final end = text.indexOf('\nendobj', m.end);
      final body = text.substring(m.end, end);
      final streamAt = body.indexOf('\nstream\n');
      if (streamAt < 0) {
        objects[id] = body;
        continue;
      }
      final dict = body.substring(0, streamAt);
      final rawStart = m.end + streamAt + '\nstream\n'.length;
      final rawEnd = text.indexOf('\nendstream', rawStart);
      final raw = latin1.encode(text.substring(rawStart, rawEnd));
      objects[id] = dict;
      streams[id] = dict.contains('/FlateDecode') ? latin1.decode(zlib.decode(raw)) : latin1.decode(raw);
    }
  }

  /// O arquivo inteiro como texto latin1 (para buscar nomes e dicionários).
  final String text;

  /// Dicionário de cada objeto (sem o stream).
  final Map<int, String> objects = {};

  /// Stream de cada objeto, já descomprimido.
  final Map<int, String> streams = {};

  int get pageCount => int.parse(RegExp(r'/Type /Pages\b.*?/Count (\d+)', dotAll: true).firstMatch(text)!.group(1)!);

  /// Operadores de cada página, na ordem.
  List<String> get pageContents {
    final pages = objects.entries.where((e) => RegExp(r'/Type /Page\b(?!s)').hasMatch(e.value)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [for (final p in pages) streams[int.parse(RegExp(r'/Contents (\d+) 0 R').firstMatch(p.value)!.group(1)!)]!];
  }

  int get imageCount => objects.values.where((d) => d.contains('/Subtype /Image') && d.contains('/DeviceRGB')).length;

  /// Textos mapeados no `ToUnicode` das fontes, para conferir que um
  /// caractere pode ser copiado do PDF.
  Set<int> get unicodeCodePoints {
    final cps = <int>{};
    for (final s in streams.values.where((s) => s.contains('beginbfchar'))) {
      for (final m in RegExp(r'<[0-9A-Fa-f]+> <([0-9A-Fa-f]+)>').allMatches(s)) {
        final hex = m.group(1)!;
        final units = [for (var i = 0; i < hex.length; i += 4) int.parse(hex.substring(i, i + 4), radix: 16)];
        cps.addAll(String.fromCharCodes(units).runes);
      }
    }
    return cps;
  }
}
