import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import 'pdf_canvas.dart';
import 'truetype.dart';

/// Liga o nome da família do `TextStyle` aos bytes da fonte.
class PdfFontRegistry {
  PdfFontRegistry(this.resources, this.log);

  final PdfResources resources;
  final PdfLog log;
  final Map<String, Map<int, PdfEmbeddedFont>> _families = {};
  PdfEmbeddedFont? _fallback;

  void register(String family, Uint8List bytes, {int weight = 400}) {
    final font = PdfEmbeddedFont(TrueTypeFont(bytes), 'F${resources.fonts.length + 1}');
    resources.fonts[font.resourceName] = font;
    (_families[family] ??= {})[weight] = font;
    _fallback ??= font;
  }

  PdfEmbeddedFont get fallback => _fallback!;

  PdfEmbeddedFont resolve(TextStyle style) {
    final family = style.fontFamily;
    final weights = family == null ? null : _families[family];
    if (weights == null) {
      log.add('família "${family ?? '(padrão)'}" não registrada; usada a fonte padrão');
      return _fallback!;
    }
    final wanted = style.fontWeight?.value ?? 400;
    var best = weights.keys.first;
    for (final w in weights.keys) {
      if ((w - wanted).abs() < (best - wanted).abs()) best = w;
    }
    return weights[best]!;
  }
}

class _Run {
  _Run(this.start, this.end, this.style);
  final int start;
  final int end;
  final TextStyle style;
}

/// Escreve o texto de um [RenderParagraph] como texto real no PDF.
///
/// O `Paragraph` que o Flutter pinta é opaco, então o texto é lido do próprio
/// render object, medido de novo com os mesmos parâmetros, e cada caractere
/// vai para a posição que o Flutter calculou.
class PdfParagraphPainter {
  PdfParagraphPainter(this.fonts, this.log);

  final PdfFontRegistry fonts;
  final PdfLog log;

  void paint(RenderParagraph p, Offset offset, PdfCanvas canvas) {
    final constraints = p.constraints;
    final tp = TextPainter(
      text: p.text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
    );
    final widthMatters = p.softWrap || p.overflow == TextOverflow.ellipsis;
    tp.layout(minWidth: constraints.minWidth, maxWidth: widthMatters ? constraints.maxWidth : double.infinity);

    final runs = <_Run>[];
    var cursor = 0;
    void walk(InlineSpan span, TextStyle? parent) {
      final style = parent == null ? span.style : (span.style == null ? parent : parent.merge(span.style));
      if (span is TextSpan) {
        final text = span.text;
        if (text != null && text.isNotEmpty) {
          runs.add(_Run(cursor, cursor + text.length, style ?? const TextStyle()));
          cursor += text.length;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      } else {
        log.add('WidgetSpan dentro de texto não tratado na prova');
        cursor += 1;
      }
    }

    walk(p.text, null);
    final plain = p.text.toPlainText(includeSemanticsLabels: false);
    final lines = tp.computeLineMetrics();

    final clip = p.overflow != TextOverflow.visible && (tp.width > p.size.width + 0.5 || tp.height > p.size.height + 0.5);
    if (clip) {
      canvas.save();
      canvas.clipRect(offset & p.size);
    }

    for (final run in runs) {
      final font = fonts.resolve(run.style);
      final fontSize = tp.textScaler.scale(run.style.fontSize ?? 14);
      final color = run.style.color ?? run.style.foreground?.color ?? const Color(0xFF000000);
      if (run.style.decoration != null && run.style.decoration != TextDecoration.none) {
        log.add('decoração de texto (sublinhado) não tratada na prova');
      }

      var lineIndex = -1;
      final glyphs = <int>[];
      final xs = <double>[];
      double baseline = 0;

      void flush() {
        if (glyphs.isEmpty) return;
        canvas.drawGlyphRun(
          font: font,
          fontSize: fontSize,
          color: color,
          baseline: offset.dy + baseline,
          glyphs: List.of(glyphs),
          xs: List.of(xs),
        );
        glyphs.clear();
        xs.clear();
      }

      var i = run.start;
      while (i < run.end && i < plain.length) {
        final cp = plain.codeUnitAt(i) >= 0xD800 && plain.codeUnitAt(i) < 0xDC00 && i + 1 < plain.length
            ? plain.runes.elementAt(_runeIndex(plain, i))
            : plain.codeUnitAt(i);
        final len = cp > 0xFFFF ? 2 : 1;
        if (cp == 0x0A) {
          i += len;
          continue;
        }
        final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + len));
        if (boxes.isEmpty) {
          i += len;
          continue;
        }
        final box = boxes.first;
        final centerY = (box.top + box.bottom) / 2;
        var li = 0;
        for (var k = 0; k < lines.length; k++) {
          final l = lines[k];
          if (centerY >= l.baseline - l.ascent - 0.5 && centerY <= l.baseline + l.descent + 0.5) {
            li = k;
            break;
          }
        }
        if (li != lineIndex) {
          flush();
          lineIndex = li;
          baseline = lines.isEmpty ? box.bottom : lines[li].baseline;
        }
        if (!font.has(cp) && cp != 0x20) log.add('caractere U+${cp.toRadixString(16)} sem glifo na fonte');
        glyphs.add(font.glyph(cp));
        xs.add(offset.dx + box.left);
        i += len;
      }
      flush();
    }

    if (clip) canvas.restore();
    tp.dispose();
  }

  static int _runeIndex(String s, int codeUnitIndex) {
    var runeIndex = 0;
    for (var i = 0; i < codeUnitIndex; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0xD800 && c < 0xDC00) i++;
      runeIndex++;
    }
    return runeIndex;
  }
}
