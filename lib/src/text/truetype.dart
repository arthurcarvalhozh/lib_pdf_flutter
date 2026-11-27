import 'dart:typed_data';

import '../document/pdf_writer.dart';

/// Leitura mínima de um arquivo TrueType: o suficiente para embutir a fonte
/// inteira num PDF (sem subset, que fica para a etapa 5).
class TrueTypeFont {
  TrueTypeFont(this.bytes) : _data = ByteData.sublistView(bytes) {
    _readTables();
    _readHead();
    _readHhea();
    _readMaxp();
    _readHmtx();
    _readCmap();
    _readOs2();
    _readPost();
    _readName();
  }

  final Uint8List bytes;
  final ByteData _data;
  final Map<String, int> _tables = {};

  late final int unitsPerEm;
  late final List<int> bbox;
  late final int ascender;
  late final int descender;
  late final int numGlyphs;
  late final int _numberOfHMetrics;
  late final List<int> advances;
  final Map<int, int> _cmap = {};
  int capHeight = 0;
  int weightClass = 400;
  double italicAngle = 0;
  bool fixedPitch = false;
  String postScriptName = 'Font';

  int glyphFor(int codePoint) => _cmap[codePoint] ?? 0;

  int advanceOf(int glyph) => glyph < advances.length ? advances[glyph] : advances.last;

  int _u16(int o) => _data.getUint16(o);
  int _i16(int o) => _data.getInt16(o);
  int _u32(int o) => _data.getUint32(o);

  int _table(String tag) {
    final o = _tables[tag];
    if (o == null) throw FormatException('Tabela $tag ausente na fonte');
    return o;
  }

  void _readTables() {
    final n = _u16(4);
    for (var i = 0; i < n; i++) {
      final r = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(r, r + 4));
      _tables[tag] = _u32(r + 8);
    }
  }

  void _readHead() {
    final o = _table('head');
    unitsPerEm = _u16(o + 18);
    bbox = [_i16(o + 36), _i16(o + 38), _i16(o + 40), _i16(o + 42)];
  }

  void _readHhea() {
    final o = _table('hhea');
    ascender = _i16(o + 4);
    descender = _i16(o + 6);
    _numberOfHMetrics = _u16(o + 34);
  }

  void _readMaxp() => numGlyphs = _u16(_table('maxp') + 4);

  void _readHmtx() {
    final o = _table('hmtx');
    final list = List<int>.filled(numGlyphs, 0);
    var last = 0;
    for (var g = 0; g < numGlyphs; g++) {
      if (g < _numberOfHMetrics) last = _u16(o + g * 4);
      list[g] = last;
    }
    advances = list;
  }

  void _readCmap() {
    final o = _table('cmap');
    final n = _u16(o + 2);
    int? fmt12;
    int? fmt4;
    for (var i = 0; i < n; i++) {
      final r = o + 4 + i * 8;
      final platform = _u16(r);
      final encoding = _u16(r + 2);
      final sub = o + _u32(r + 4);
      final format = _u16(sub);
      if (format == 12 && (platform == 3 && encoding == 10 || platform == 0)) fmt12 ??= sub;
      if (format == 4 && (platform == 3 && encoding == 1 || platform == 0)) fmt4 ??= sub;
    }
    if (fmt12 != null) {
      final groups = _u32(fmt12 + 12);
      for (var i = 0; i < groups; i++) {
        final g = fmt12 + 16 + i * 12;
        final start = _u32(g);
        final end = _u32(g + 4);
        final glyph = _u32(g + 8);
        for (var c = start; c <= end; c++) {
          _cmap[c] = glyph + (c - start);
        }
      }
    } else if (fmt4 != null) {
      final segX2 = _u16(fmt4 + 6);
      final ends = fmt4 + 14;
      final starts = ends + segX2 + 2;
      final deltas = starts + segX2;
      final ranges = deltas + segX2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = _u16(ends + s * 2);
        final start = _u16(starts + s * 2);
        final delta = _i16(deltas + s * 2);
        final rangeOffsetPos = ranges + s * 2;
        final rangeOffset = _u16(rangeOffsetPos);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          int glyph;
          if (rangeOffset == 0) {
            glyph = (c + delta) & 0xFFFF;
          } else {
            final p = rangeOffsetPos + rangeOffset + (c - start) * 2;
            glyph = _u16(p);
            if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
          }
          if (glyph != 0) _cmap[c] = glyph;
        }
      }
    }
  }

  void _readOs2() {
    final o = _tables['OS/2'];
    if (o == null) return;
    weightClass = _u16(o + 4);
    final version = _u16(o);
    if (version >= 2) capHeight = _i16(o + 88);
  }

  void _readPost() {
    final o = _tables['post'];
    if (o == null) return;
    italicAngle = _data.getInt32(o + 4) / 65536.0;
    fixedPitch = _u32(o + 12) != 0;
  }

  void _readName() {
    final o = _tables['name'];
    if (o == null) return;
    final count = _u16(o + 2);
    final strings = o + _u16(o + 4);
    for (var i = 0; i < count; i++) {
      final r = o + 6 + i * 12;
      final platform = _u16(r);
      final nameId = _u16(r + 6);
      if (nameId != 6) continue;
      final length = _u16(r + 8);
      final start = strings + _u16(r + 10);
      final raw = bytes.sublist(start, start + length);
      final name = platform == 3 || platform == 0
          ? String.fromCharCodes([for (var j = 0; j + 1 < raw.length; j += 2) (raw[j] << 8) | raw[j + 1]])
          : String.fromCharCodes(raw);
      postScriptName = name.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
      return;
    }
  }
}

/// Uma fonte TrueType embutida no PDF como Type0/CIDFontType2 com
/// codificação Identity-H: o texto é escrito por número de glifo, e o
/// `ToUnicode` permite copiar e pesquisar.
class PdfEmbeddedFont {
  PdfEmbeddedFont(this.font, this.resourceName);

  final TrueTypeFont font;
  final String resourceName;
  final Map<int, int> _usedGlyphs = {}; // glifo → code point

  /// Glifo do code point, registrando o uso para o `ToUnicode` e o `/W`.
  int glyph(int codePoint) {
    final g = font.glyphFor(codePoint);
    _usedGlyphs.putIfAbsent(g, () => codePoint);
    return g;
  }

  bool has(int codePoint) => font.glyphFor(codePoint) != 0;

  /// Avanço do glifo em milésimos do tamanho da fonte (espaço de texto PDF).
  double advance1000(int glyph) => font.advanceOf(glyph) * 1000 / font.unitsPerEm;

  PdfRef write(PdfWriter w) {
    double s(int v) => v * 1000 / font.unitsPerEm;
    final fontFile = w.addStream({'Length1': font.bytes.length}, font.bytes);
    final descriptor = w.add(<String, Object>{
      'Type': const PdfName('FontDescriptor'),
      'FontName': PdfName(font.postScriptName),
      'Flags': 32 | (font.fixedPitch ? 1 : 0) | (font.italicAngle != 0 ? 64 : 0),
      'FontBBox': [for (final v in font.bbox) s(v)],
      'ItalicAngle': font.italicAngle,
      'Ascent': s(font.ascender),
      'Descent': s(font.descender),
      'CapHeight': s(font.capHeight == 0 ? font.ascender : font.capHeight),
      'StemV': font.weightClass >= 600 ? 140 : 80,
      'FontFile2': fontFile,
    });
    final glyphs = _usedGlyphs.keys.toList()..sort();
    final widths = StringBuffer('[');
    for (final g in glyphs) {
      widths.write('$g [${PdfWriter.num(advance1000(g))}] ');
    }
    widths.write(']');
    final cid = w.add(<String, Object>{
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('CIDFontType2'),
      'BaseFont': PdfName(font.postScriptName),
      'CIDSystemInfo': <String, Object>{'Registry': 'Adobe', 'Ordering': 'Identity', 'Supplement': 0},
      'FontDescriptor': descriptor,
      'W': PdfRaw(widths.toString()),
      'CIDToGIDMap': const PdfName('Identity'),
    });
    final toUnicode = w.addStream({}, _toUnicodeCMap(glyphs).codeUnits);
    return w.add(<String, Object>{
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('Type0'),
      'BaseFont': PdfName(font.postScriptName),
      'Encoding': const PdfName('Identity-H'),
      'DescendantFonts': [cid],
      'ToUnicode': toUnicode,
    });
  }

  String _toUnicodeCMap(List<int> glyphs) {
    final b = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def')
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');
    final mapped = glyphs.where((g) => g != 0).toList();
    for (var i = 0; i < mapped.length; i += 100) {
      final chunk = mapped.sublist(i, i + 100 > mapped.length ? mapped.length : i + 100);
      b.writeln('${chunk.length} beginbfchar');
      for (final g in chunk) {
        final units = String.fromCharCode(_usedGlyphs[g]!).codeUnits;
        final hex = units.map((u) => u.toRadixString(16).padLeft(4, '0')).join();
        b.writeln('<${g.toRadixString(16).padLeft(4, '0')}> <$hex>');
      }
      b.writeln('endbfchar');
    }
    b
      ..writeln('endcmap')
      ..writeln('CMapName currentdict /CMap defineresource pop')
      ..writeln('end')
      ..writeln('end');
    return b.toString();
  }
}
