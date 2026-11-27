import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../document/pdf_writer.dart';
import '../text/truetype.dart';

/// Registro do que a pintura não conseguiu traduzir em vetor, para o
/// relatório da prova de conceito.
class PdfLog {
  final Map<String, int> entries = {};
  void add(String message) => entries.update(message, (n) => n + 1, ifAbsent: () => 1);
}

/// Imagem a embutir: pixels lidos depois da pintura, porque a leitura é
/// assíncrona e a pintura do Flutter é síncrona.
class PdfPendingImage {
  PdfPendingImage(this.name, this.image, {this.isTextFallback = false});
  final String name;
  final ui.Image image;
  final bool isTextFallback;
}

/// Recursos compartilhados entre as páginas: fontes, estados de opacidade e
/// imagens.
class PdfResources {
  final Map<String, PdfEmbeddedFont> fonts = {};
  final Map<String, double> alphaStates = {};
  final List<PdfPendingImage> images = [];
  final Map<ui.Image, String> _imageNames = {};

  String alphaState(double alpha) {
    final key = PdfWriter.num(alpha);
    final name = 'GA${key.replaceAll('.', '_')}';
    alphaStates[name] = double.parse(key);
    return name;
  }

  String image(ui.Image image, {bool isTextFallback = false}) {
    return _imageNames.putIfAbsent(image, () {
      final name = 'Im${images.length + 1}';
      images.add(PdfPendingImage(name, image, isTextFallback: isTextFallback));
      return name;
    });
  }
}

/// Transformação afim 2D: x' = a·x + c·y + e; y' = b·x + d·y + f.
class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _Affine(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  /// Esta transformação depois de [m] (m é aplicada primeiro).
  _Affine times(_Affine m) => _Affine(
    a * m.a + c * m.b,
    b * m.a + d * m.b,
    a * m.c + c * m.d,
    b * m.c + d * m.d,
    a * m.e + c * m.f + e,
    b * m.e + d * m.f + f,
  );

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  Rect applyRect(Rect r) {
    final pts = [apply(r.topLeft), apply(r.topRight), apply(r.bottomLeft), apply(r.bottomRight)];
    var l = pts.first.dx, t = pts.first.dy, rr = l, bb = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      rr = math.max(rr, p.dx);
      bb = math.max(bb, p.dy);
    }
    return Rect.fromLTRB(l, t, rr, bb);
  }

  Float64List toMatrix4() => Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
}

class _State {
  _State(this.m, this.alpha, this.emittedAlpha);
  _Affine m;
  double alpha;
  double emittedAlpha;
  _State copy() => _State(m, alpha, emittedAlpha);
}

/// Canvas que escreve operadores PDF em vez de pixels.
///
/// As coordenadas são as do Flutter (origem no canto superior esquerdo, Y
/// para baixo): a página recebe uma inversão de eixo uma vez, no começo do
/// stream, e o resto do código não pensa mais nisso.
class PdfCanvas implements Canvas {
  PdfCanvas(this.resources, this.log, {required this.visibleWindow});

  final PdfResources resources;
  final PdfLog log;

  /// Área da página (em coordenadas de página) usada para pular o que não
  /// aparece nela.
  final Rect visibleWindow;

  final StringBuffer ops = StringBuffer();
  final List<_State> _stack = [];
  _State _s = _State(_Affine.identity, 1, 1);

  static String _n(double v) => PdfWriter.num(v);

  // ---------------------------------------------------------------- estado

  /// Multiplica a opacidade de tudo que for pintado até o próximo restore
  /// (usado para as camadas de opacidade do Flutter).
  void multiplyAlpha(double alpha) => _s.alpha *= alpha;

  bool isVisible(Rect localRect) => _s.m.applyRect(localRect).overlaps(visibleWindow);

  void writeRaw(String s) => ops.write(s);

  @override
  void save() {
    _stack.add(_s.copy());
    ops.write('q\n');
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    save();
    if (paint.blendMode != BlendMode.srcOver || paint.colorFilter != null || paint.imageFilter != null) {
      log.add('saveLayer com efeito (${paint.blendMode.name}); pintado sem o efeito');
    }
    multiplyAlpha(paint.color.a);
  }

  @override
  void restore() {
    if (_stack.isEmpty) return;
    _s = _stack.removeLast();
    ops.write('Q\n');
  }

  @override
  void restoreToCount(int count) {
    while (getSaveCount() > count && _stack.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _stack.length + 1;

  void _concat(_Affine m) {
    _s.m = _s.m.times(m);
    ops.write('${_n(m.a)} ${_n(m.b)} ${_n(m.c)} ${_n(m.d)} ${_n(m.e)} ${_n(m.f)} cm\n');
  }

  @override
  void translate(double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    _concat(_Affine(1, 0, 0, 1, dx, dy));
  }

  @override
  void scale(double sx, [double? sy]) => _concat(_Affine(sx, 0, 0, sy ?? sx, 0, 0));

  @override
  void rotate(double radians) {
    final c = math.cos(radians), s = math.sin(radians);
    _concat(_Affine(c, s, -s, c, 0, 0));
  }

  @override
  void skew(double sx, double sy) => _concat(_Affine(1, sy, sx, 1, 0, 0));

  @override
  void transform(Float64List m) => _concat(_Affine(m[0], m[1], m[4], m[5], m[12], m[13]));

  @override
  Float64List getTransform() => _s.m.toMatrix4();

  @override
  Rect getLocalClipBounds() => const Rect.fromLTRB(-1e5, -1e5, 1e5, 1e5);

  @override
  Rect getDestinationClipBounds() => const Rect.fromLTRB(-1e5, -1e5, 1e5, 1e5);

  // ---------------------------------------------------------------- recorte

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.difference) {
      log.add('clipRect com ClipOp.difference ignorado');
      return;
    }
    ops.write('${_n(rect.left)} ${_n(rect.top)} ${_n(rect.width)} ${_n(rect.height)} re W n\n');
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    _rrectPath(rrect);
    ops.write('W n\n');
  }

  @override
  void clipRSuperellipse(ui.RSuperellipse rsuperellipse, {bool doAntiAlias = true}) {
    log.add('RSuperellipse aproximado por retângulo arredondado');
    clipRRect(
      RRect.fromLTRBAndCorners(
        rsuperellipse.left,
        rsuperellipse.top,
        rsuperellipse.right,
        rsuperellipse.bottom,
        topLeft: rsuperellipse.tlRadius,
        topRight: rsuperellipse.trRadius,
        bottomLeft: rsuperellipse.blRadius,
        bottomRight: rsuperellipse.brRadius,
      ),
    );
  }

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    _samplePath(path);
    ops.write(path.fillType == PathFillType.evenOdd ? 'W* n\n' : 'W n\n');
  }

  // ---------------------------------------------------------------- tinta

  void _alpha(double a) {
    final alpha = (a * _s.alpha).clamp(0.0, 1.0);
    if ((alpha - _s.emittedAlpha).abs() < 0.001) return;
    ops.write('/${resources.alphaState(alpha)} gs\n');
    _s.emittedAlpha = alpha;
  }

  String _rgb(Color c) => '${_n(c.r.clamp(0, 1))} ${_n(c.g.clamp(0, 1))} ${_n(c.b.clamp(0, 1))}';

  /// Prepara cor e linha da tinta e devolve o operador de pintura do
  /// caminho.
  String _applyPaint(Paint paint, {bool evenOdd = false}) {
    if (paint.shader != null) log.add('Paint com shader (gradiente) pintado com cor sólida');
    if (paint.maskFilter != null) log.add('Paint com maskFilter (blur) pintado sem o efeito');
    if (paint.blendMode != BlendMode.srcOver) log.add('BlendMode ${paint.blendMode.name} tratado como srcOver');
    _alpha(paint.color.a);
    if (paint.style == PaintingStyle.stroke) {
      ops.write(
        '${_rgb(paint.color)} RG ${_n(paint.strokeWidth)} w '
        '${paint.strokeCap.index} J ${paint.strokeJoin.index} j ${_n(paint.strokeMiterLimit)} M\n',
      );
      return 'S';
    }
    ops.write('${_rgb(paint.color)} rg\n');
    return evenOdd ? 'f*' : 'f';
  }

  // ---------------------------------------------------------------- caminhos

  void _m(double x, double y) => ops.write('${_n(x)} ${_n(y)} m\n');
  void _l(double x, double y) => ops.write('${_n(x)} ${_n(y)} l\n');
  void _c(double x1, double y1, double x2, double y2, double x3, double y3) =>
      ops.write('${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} ${_n(x3)} ${_n(y3)} c\n');

  static const _k = 0.5522847498;

  void _rrectPath(RRect r) {
    final tl = r.tlRadius, tr = r.trRadius, br = r.brRadius, bl = r.blRadius;
    _m(r.left + tl.x, r.top);
    _l(r.right - tr.x, r.top);
    if (tr != Radius.zero) {
      _c(r.right - tr.x + tr.x * _k, r.top, r.right, r.top + tr.y - tr.y * _k, r.right, r.top + tr.y);
    }
    _l(r.right, r.bottom - br.y);
    if (br != Radius.zero) {
      _c(r.right, r.bottom - br.y + br.y * _k, r.right - br.x + br.x * _k, r.bottom, r.right - br.x, r.bottom);
    }
    _l(r.left + bl.x, r.bottom);
    if (bl != Radius.zero) {
      _c(r.left + bl.x - bl.x * _k, r.bottom, r.left, r.bottom - bl.y + bl.y * _k, r.left, r.bottom - bl.y);
    }
    _l(r.left, r.top + tl.y);
    if (tl != Radius.zero) {
      _c(r.left, r.top + tl.y - tl.y * _k, r.left + tl.x - tl.x * _k, r.top, r.left + tl.x, r.top);
    }
    ops.write('h\n');
  }

  void _arcSegments(Rect oval, double start, double sweep, {required bool moveToStart}) {
    final cx = oval.center.dx, cy = oval.center.dy, rx = oval.width / 2, ry = oval.height / 2;
    final segments = math.max(1, (sweep.abs() / (math.pi / 2)).ceil());
    final step = sweep / segments;
    var a0 = start;
    if (moveToStart) {
      _m(cx + rx * math.cos(a0), cy + ry * math.sin(a0));
    } else {
      _l(cx + rx * math.cos(a0), cy + ry * math.sin(a0));
    }
    for (var i = 0; i < segments; i++) {
      final a1 = a0 + step;
      final k = 4 / 3 * math.tan((a1 - a0) / 4);
      final x0 = cx + rx * math.cos(a0), y0 = cy + ry * math.sin(a0);
      final x3 = cx + rx * math.cos(a1), y3 = cy + ry * math.sin(a1);
      _c(
        x0 - k * rx * math.sin(a0),
        y0 + k * ry * math.cos(a0),
        x3 + k * rx * math.sin(a1),
        y3 - k * ry * math.cos(a1),
        x3,
        y3,
      );
      a0 = a1;
    }
  }

  void _ovalPath(Rect r) {
    _arcSegments(r, 0, 2 * math.pi, moveToStart: true);
    ops.write('h\n');
  }

  /// O `dart:ui` não expõe os segmentos de um [Path]: o caminho é amostrado
  /// pelo comprimento e simplificado (Ramer-Douglas-Peucker).
  void _samplePath(Path path) {
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      if (length <= 0) continue;
      final step = math.min(0.5, length / 8);
      final n = math.max(2, (length / step).ceil() + 1);
      final pts = <Offset>[];
      for (var i = 0; i < n; i++) {
        final t = metric.getTangentForOffset(math.min(length, i * length / (n - 1)));
        if (t != null) pts.add(t.position);
      }
      final simplified = _rdp(pts, 0.02);
      if (simplified.isEmpty) continue;
      _m(simplified.first.dx, simplified.first.dy);
      for (final p in simplified.skip(1)) {
        _l(p.dx, p.dy);
      }
      if (metric.isClosed) ops.write('h\n');
    }
  }

  static List<Offset> _rdp(List<Offset> pts, double eps) {
    if (pts.length < 3) return pts;
    final keep = List<bool>.filled(pts.length, false);
    keep[0] = true;
    keep[pts.length - 1] = true;
    final stack = <(int, int)>[(0, pts.length - 1)];
    while (stack.isNotEmpty) {
      final (s, e) = stack.removeLast();
      var maxD = 0.0;
      var idx = -1;
      final a = pts[s], b = pts[e];
      final dx = b.dx - a.dx, dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      for (var i = s + 1; i < e; i++) {
        final p = pts[i];
        final d = len == 0 ? (p - a).distance : ((dy * p.dx - dx * p.dy + b.dx * a.dy - b.dy * a.dx).abs() / len);
        if (d > maxD) {
          maxD = d;
          idx = i;
        }
      }
      if (maxD > eps && idx > 0) {
        keep[idx] = true;
        stack
          ..add((s, idx))
          ..add((idx, e));
      }
    }
    return [
      for (var i = 0; i < pts.length; i++)
        if (keep[i]) pts[i],
    ];
  }

  // ---------------------------------------------------------------- desenho

  @override
  void drawColor(Color color, BlendMode blendMode) => drawPaint(
    Paint()
      ..color = color
      ..blendMode = blendMode,
  );

  @override
  void drawPaint(Paint paint) {
    final op = _applyPaint(
      Paint()
        ..color = paint.color
        ..shader = paint.shader
        ..blendMode = paint.blendMode,
    );
    ops.write('-100000 -100000 200000 200000 re $op\n');
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..style = PaintingStyle.stroke;
    _applyPaint(stroke);
    _m(p1.dx, p1.dy);
    _l(p2.dx, p2.dy);
    ops.write('S\n');
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    final op = _applyPaint(paint);
    ops.write('${_n(rect.left)} ${_n(rect.top)} ${_n(rect.width)} ${_n(rect.height)} re $op\n');
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    final op = _applyPaint(paint);
    _rrectPath(rrect);
    ops.write('$op\n');
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    final op = _applyPaint(paint, evenOdd: true);
    _rrectPath(outer);
    _rrectPath(inner);
    ops.write('$op\n');
  }

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, Paint paint) {
    log.add('RSuperellipse aproximado por retângulo arredondado');
    drawRRect(
      RRect.fromLTRBAndCorners(
        rsuperellipse.left,
        rsuperellipse.top,
        rsuperellipse.right,
        rsuperellipse.bottom,
        topLeft: rsuperellipse.tlRadius,
        topRight: rsuperellipse.trRadius,
        bottomLeft: rsuperellipse.blRadius,
        bottomRight: rsuperellipse.brRadius,
      ),
      paint,
    );
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    final op = _applyPaint(paint);
    _ovalPath(rect);
    ops.write('$op\n');
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) => drawOval(Rect.fromCircle(center: c, radius: radius), paint);

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    final op = _applyPaint(paint);
    if (useCenter) {
      _m(rect.center.dx, rect.center.dy);
      _arcSegments(rect, startAngle, sweepAngle, moveToStart: false);
      ops.write('h\n');
    } else {
      _arcSegments(rect, startAngle, sweepAngle, moveToStart: true);
    }
    ops.write('$op\n');
  }

  @override
  void drawPath(Path path, Paint paint) {
    final op = _applyPaint(paint, evenOdd: path.fillType == PathFillType.evenOdd);
    _samplePath(path);
    ops.write('$op\n');
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    switch (pointMode) {
      case ui.PointMode.points:
        final r = math.max(paint.strokeWidth, 1) / 2;
        final dot = Paint()..color = paint.color;
        for (final p in points) {
          if (paint.strokeCap == StrokeCap.round) {
            drawCircle(p, r, dot);
          } else {
            drawRect(Rect.fromCircle(center: p, radius: r), dot);
          }
        }
      case ui.PointMode.lines:
        for (var i = 0; i + 1 < points.length; i += 2) {
          drawLine(points[i], points[i + 1], paint);
        }
      case ui.PointMode.polygon:
        if (points.length < 2) return;
        _applyPaint(
          Paint()
            ..color = paint.color
            ..strokeWidth = paint.strokeWidth
            ..style = PaintingStyle.stroke,
        );
        _m(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          _l(p.dx, p.dy);
        }
        ops.write('S\n');
    }
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) {
    drawPoints(pointMode, [for (var i = 0; i + 1 < points.length; i += 2) Offset(points[i], points[i + 1])], paint);
  }

  // ---------------------------------------------------------------- imagens

  void drawImageInRect(ui.Image image, Rect dst, {bool isTextFallback = false}) {
    final name = resources.image(image, isTextFallback: isTextFallback);
    _alpha(1);
    ops.write('q ${_n(dst.width)} 0 0 ${_n(-dst.height)} ${_n(dst.left)} ${_n(dst.bottom)} cm /$name Do Q\n');
  }

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {
    drawImageInRect(image, Rect.fromLTWH(offset.dx, offset.dy, image.width.toDouble(), image.height.toDouble()));
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    final sx = dst.width / src.width, sy = dst.height / src.height;
    final full = Rect.fromLTWH(dst.left - src.left * sx, dst.top - src.top * sy, image.width * sx, image.height * sy);
    save();
    clipRect(dst);
    drawImageInRect(image, full);
    restore();
  }

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) {
    log.add('drawImageNine desenhado como imagem esticada');
    drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), dst, paint);
  }

  /// O texto de um [ui.Paragraph] não pode ser lido: o trecho é rasterizado
  /// em alta resolução (só acontece com texto pintado dentro de painters).
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    const k = 4.0;
    final w = paragraph.width.isFinite ? math.max(paragraph.width, paragraph.longestLine) : paragraph.longestLine;
    final h = paragraph.height;
    if (w <= 0 || h <= 0) return;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(k);
    c.drawParagraph(paragraph, Offset.zero);
    final img = recorder.endRecording().toImageSync((w * k).ceil(), (h * k).ceil());
    log.add('texto pintado por painter (drawParagraph) rasterizado');
    drawImageInRect(img, Rect.fromLTWH(offset.dx, offset.dy, w, h), isTextFallback: true);
  }

  // ---------------------------------------------------------------- texto real

  /// Escreve uma sequência de glifos com a posição horizontal de cada um,
  /// medida pelo Flutter. O operador TJ corrige a diferença entre o avanço da
  /// fonte e a posição real (kerning, espaçamento entre letras).
  void drawGlyphRun({
    required PdfEmbeddedFont font,
    required double fontSize,
    required Color color,
    required double baseline,
    required List<int> glyphs,
    required List<double> xs,
  }) {
    if (glyphs.isEmpty) return;
    _alpha(color.a);
    final tj = StringBuffer('[<');
    for (var i = 0; i < glyphs.length; i++) {
      if (i > 0) {
        final expected = xs[i - 1] + font.advance1000(glyphs[i - 1]) * fontSize / 1000;
        final adjust = -(xs[i] - expected) * 1000 / fontSize;
        if (adjust.abs() >= 0.5) tj.write('> ${_n(adjust)} <');
      }
      tj.write(glyphs[i].toRadixString(16).padLeft(4, '0'));
    }
    tj.write('>]');
    ops.write(
      'BT /${font.resourceName} ${_n(fontSize)} Tf ${_rgb(color)} rg '
      '1 0 0 -1 ${_n(xs.first)} ${_n(baseline)} Tm $tj TJ ET\n',
    );
  }

  // ---------------------------------------------------------------- sem tradução

  @override
  void drawPicture(ui.Picture picture) => log.add('drawPicture ignorado (Picture é opaco)');

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) =>
      log.add('drawShadow (sombra de elevação) ignorado');

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) => log.add('drawVertices ignorado');

  @override
  void drawAtlas(
    ui.Image atlas,
    List<RSTransform> transforms,
    List<Rect> rects,
    List<Color>? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => log.add('drawAtlas ignorado');

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => log.add('drawRawAtlas ignorado');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    log.add('Canvas.${invocation.memberName} sem tradução');
    return null;
  }
}
