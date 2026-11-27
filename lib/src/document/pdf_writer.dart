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

/// Monta o arquivo PDF a partir de objetos numerados.
///
/// Prova de conceito: só o que a etapa 1 precisa (dicionários, arrays,
/// streams comprimidos, xref e trailer).
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
    final trailer = <String, Object>{'Size': _bodies.length + 1, 'Root': root, 'Info': ?info};
    xref
      ..write('trailer\n${encode(trailer)}\n')
      ..write('startxref\n$xrefOffset\n%%EOF\n');
    out.add(latin1.encode(xref.toString()));
    return out.toBytes();
  }

  static String encode(Object? value) {
    if (value == null) return 'null';
    if (value is PdfRef) return '${value.id} 0 R';
    if (value is PdfName) return '/${value.value}';
    if (value is PdfRaw) return value.value;
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) return num(value);
    if (value is PdfString) return _string(value.value);
    if (value is String) return _string(value);
    if (value is List) return '[${value.map(encode).join(' ')}]';
    if (value is Map<String, Object?>) {
      final b = StringBuffer('<<');
      value.forEach((k, v) => b.write(' /$k ${encode(v)}'));
      b.write(' >>');
      return b.toString();
    }
    throw ArgumentError('Valor sem codificação PDF: ${value.runtimeType}');
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
