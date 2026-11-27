import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// Referência indireta a um objeto do arquivo (`12 0 R`).
class PdfRef {
  const PdfRef(this.id);
  final int id;
}

/// Um nome PDF (`/Type`).
class PdfName {
  const PdfName(this.value);
  final String value;
}

/// Texto copiado como está para o arquivo (operadores, arrays prontos).
class PdfRaw {
  const PdfRaw(this.value);
  final String value;
}

/// String PDF: literal quando é ASCII, UTF-16BE em hexadecimal quando não é.
class PdfString {
  const PdfString(this.value);
  final String value;
}

/// Monta o arquivo PDF (versão 1.7) a partir de objetos numerados.
///
/// Os objetos são escritos na ordem dos números, com a tabela xref clássica
/// e o trailer no fim. Streams são comprimidos com Flate.
class PdfWriter {
  final List<Uint8List?> _bodies = [];

  PdfRef reserve() {
    _bodies.add(null);
    return PdfRef(_bodies.length);
  }

  PdfRef add(Object value) {
    final ref = reserve();
    set(ref, value);
    return ref;
  }

  void set(PdfRef ref, Object value) {
    _bodies[ref.id - 1] = latin1.encode(encode(value));
  }

  PdfRef addStream(Map<String, Object> dict, List<int> data, {bool compress = true}) {
    final ref = reserve();
    setStream(ref, dict, data, compress: compress);
    return ref;
  }

  void setStream(PdfRef ref, Map<String, Object> dict, List<int> data, {bool compress = true}) {
    final payload = compress ? ZLibEncoder(level: 6).convert(data) : data;
    final full = <String, Object>{
      ...dict,
      'Length': payload.length,
      if (compress) 'Filter': const PdfName('FlateDecode'),
    };
    final out = BytesBuilder(copy: false)
      ..add(latin1.encode(encode(full)))
      ..add(latin1.encode('\nstream\n'))
      ..add(payload)
      ..add(latin1.encode('\nendstream'));
    _bodies[ref.id - 1] = out.toBytes();
  }

  /// Escreve o arquivo. O `/ID` do trailer é derivado do conteúdo: o mesmo
  /// documento gera sempre o mesmo arquivo, byte a byte.
  Uint8List build({required PdfRef root, PdfRef? info}) {
    final out = BytesBuilder(copy: false);
    out.add(latin1.encode('%PDF-1.7\n'));
    out.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final offsets = <int>[];
    for (var i = 0; i < _bodies.length; i++) {
      final body = _bodies[i];
      if (body == null) {
        throw StateError('Objeto ${i + 1} reservado e nunca preenchido');
      }
      offsets.add(out.length);
      out.add(latin1.encode('${i + 1} 0 obj\n'));
      out.add(body);
      out.add(latin1.encode('\nendobj\n'));
    }
    final xrefOffset = out.length;
    final xref = StringBuffer()
      ..write('xref\n0 ${_bodies.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets) {
      xref.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    final id = PdfRaw('<${_fingerprint(out.toBytes())}>');
    final trailer = <String, Object>{
      'Size': _bodies.length + 1,
      'Root': root,
      'Info': ?info,
      'ID': [id, id],
    };
    xref
      ..write('trailer\n${encode(trailer)}\n')
      ..write('startxref\n$xrefOffset\n%%EOF\n');
    out.add(latin1.encode(xref.toString()));
    return out.toBytes();
  }

  static String encode(Object? value) {
    if (value == null) return 'null';
    if (value is PdfRef) return '${value.id} 0 R';
    if (value is PdfName) return name(value.value);
    if (value is PdfRaw) return value.value;
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) return num(value);
    if (value is PdfString) return _string(value.value);
    if (value is String) return _string(value);
    if (value is List) return '[${value.map(encode).join(' ')}]';
    if (value is Map<String, Object?>) {
      final b = StringBuffer('<<');
      value.forEach((k, v) => b.write(' ${name(k)} ${encode(v)}'));
      b.write(' >>');
      return b.toString();
    }
    throw ArgumentError('Valor sem codificação PDF: ${value.runtimeType}');
  }

  /// Nome PDF com os caracteres especiais escapados como `#xx` (seção
  /// 7.3.5 da ISO 32000-1): fora de `!`..`~`, delimitadores e o próprio `#`.
  static String name(String value) {
    final b = StringBuffer('/');
    for (final byte in utf8.encode(value)) {
      final regular = byte > 0x20 && byte < 0x7F && !'()<>[]{}/%#'.codeUnits.contains(byte);
      b.write(regular ? String.fromCharCode(byte) : '#${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
    return b.toString();
  }

  /// Data no formato PDF (`D:AAAAMMDDHHmmSS-03'00'`), com o fuso de [date].
  static PdfRaw date(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    final offset = date.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final zone = date.isUtc ? 'Z' : "$sign${two(abs.inHours)}'${two(abs.inMinutes % 60)}'";
    return PdfRaw(
      '(D:${date.year.toString().padLeft(4, '0')}${two(date.month)}${two(date.day)}'
      '${two(date.hour)}${two(date.minute)}${two(date.second)}$zone)',
    );
  }

  /// 16 bytes em hexadecimal derivados de [data] (dois FNV-1a de 64 bits
  /// com sementes diferentes). Não é criptográfico: só identifica o arquivo.
  /// Usa a multiplicação de 64 bits do `int` nativo, que dá a volta.
  static String _fingerprint(Uint8List data) {
    var a = 0xcbf29ce484222325;
    var b = 0x84222325cbf29ce4;
    const prime = 0x100000001b3;
    for (final byte in data) {
      a = (a ^ byte) * prime;
      b = (b ^ byte ^ 0x5a) * prime;
    }
    String hex(int v) => BigInt.from(v).toUnsigned(64).toRadixString(16).padLeft(16, '0');
    return hex(a) + hex(b);
  }

  /// Número com até 4 casas, sem zeros sobrando.
  static String num(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    final r = (v * 10000).round() / 10000;
    if (r == r.roundToDouble()) return r.toInt().toString();
    var s = r.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s;
  }

  static String _string(String s) {
    final ascii = s.codeUnits.every((c) => c >= 0x20 && c < 0x7F);
    if (ascii) {
      final escaped = s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
      return '($escaped)';
    }
    final b = StringBuffer('<FEFF');
    for (final unit in s.codeUnits) {
      b.write(unit.toRadixString(16).padLeft(4, '0'));
    }
    b.write('>');
    return b.toString();
  }
}
