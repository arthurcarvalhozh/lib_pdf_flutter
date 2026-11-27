import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../document/pdf_writer.dart';
import '../text/truetype.dart';
import 'pdf_shading.dart';

/// Registro do que a pintura não conseguiu traduzir em vetor. Vira os
/// avisos do `PdfBuildResult`.
class PdfLog {
  final Map<String, int> entries = {};
  void add(String message) => entries.update(message, (n) => n + 1, ifAbsent: () => 1);
}

/// Imagem a embutir: pixels lidos depois da pintura, porque a leitura é
/// assíncrona e a pintura do Flutter é síncrona.
///
/// O [image] é sempre da lib (um clone do handle do widget, ou uma imagem
/// criada por rasterização) e é descartado depois da escrita: o `RenderImage`
/// descarta o handle dele quando a árvore é desmontada, antes de a lib ler
/// os pixels.
class PdfPendingImage {
  PdfPendingImage(this.name, this.image, {this.isTextFallback = false, this.interpolate = true});
  final String name;
  final ui.Image image;
  final bool isTextFallback;

  /// Suavizar ao ampliar (`/Interpolate`). Falso quando o Flutter desenha
  /// com `FilterQuality.none`, que mostra os pixels nítidos.
  final bool interpolate;
}

/// Grupo de transparência: um Form XObject pintado com opacidade e modo de
/// mistura próprios, como uma camada do Flutter.
class PdfForm {
  PdfForm(this.name, this.bbox, this.ops);
  final String name;
  final Rect bbox;
  final String ops;
}

/// Recursos compartilhados entre as páginas: fontes, estados gráficos,
/// shadings, imagens e grupos.
class PdfResources {
  final Map<String, PdfEmbeddedFont> fonts = {};
  final Map<String, Map<String, Object>> graphicsStates = {};
  final Map<String, Map<String, Object>> shadings = {};
  final List<PdfPendingImage> images = [];
  final List<PdfForm> forms = [];
  final Map<String, String> _graphicsStateNames = {};

  /// Estado gráfico com opacidade (de preenchimento e de traço) e modo de
  /// mistura. O modo vai sempre, para que voltar ao normal também seja
  /// explícito.
  String graphicsState(double alpha, String blendMode) {
    final a = PdfWriter.num(alpha);
    return _graphicsStateNames.putIfAbsent('$a $blendMode', () {
      final name = 'GS${_graphicsStateNames.length + 1}';
      final value = double.parse(a);
      graphicsStates[name] = {'Type': const PdfName('ExtGState'), 'ca': value, 'CA': value, 'BM': PdfName(blendMode)};
      return name;
    });
  }

  String shading(Map<String, Object> dict) {
    final name = 'Sh${shadings.length + 1}';
    shadings[name] = dict;
    return name;
  }

  /// Nome da imagem nos recursos. A mesma imagem (ou outro handle dela)
  /// entra uma vez só. [created] diz que a imagem foi criada pela lib; as
  /// outras são clonadas.
  String image(ui.Image image, {bool created = false, bool isTextFallback = false, bool interpolate = true}) {
    for (final pending in images) {
      if (pending.image.isCloneOf(image) && pending.interpolate == interpolate) {
        if (created) image.dispose();
        return pending.name;
      }
    }
    final name = 'Im${images.length + 1}';
    images.add(
      PdfPendingImage(name, created ? image : image.clone(), isTextFallback: isTextFallback, interpolate: interpolate),
    );
    return name;
  }

  String form(Rect bbox, String ops) {
    final name = 'Fm${forms.length + 1}';
    forms.add(PdfForm(name, bbox, ops));
    return name;
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

  double get determinant => a * d - b * c;

  /// Quanto uma unidade local mede na página (média dos dois eixos).
  double get scale => math.sqrt(determinant.abs());

  _Affine? inverse() {
    final det = determinant;
    if (det.abs() < 1e-12) return null;
    return _Affine(d / det, -b / det, -c / det, a / det, (c * f - d * e) / det, (b * e - a * f) / det);
  }
}

class _State {
  _State(this.m, this.clip, this.emittedAlpha, this.emittedBlend);
  _Affine m;

  /// Caixa envolvente do recorte atual, em coordenadas de página.
  Rect clip;
  double emittedAlpha;
  String emittedBlend;
  _State copy() => _State(m, clip, emittedAlpha, emittedBlend);
}

class _Group {
  _Group(this.parent, this.alpha, this.blendMode, this.bbox, this.parentAlpha, this.parentBlend);
  final StringBuffer parent;
  final double alpha;
  final String blendMode;
  final Rect bbox;
  final double parentAlpha;
  final String parentBlend;
}

/// Canvas que escreve operadores PDF em vez de pixels.
///
/// As coordenadas são as do Flutter (origem no canto superior esquerdo, Y
/// para baixo): a página recebe uma inversão de eixo uma vez, no começo do
/// stream, e o resto do código não pensa mais nisso.
///
/// O que tem equivalente em PDF sai em vetor. O que não tem (desfoque, sombra
/// de elevação, shader de gradiente desconhecido, filtro de cor) é desenhado
/// só naquele trecho por um `Canvas` de verdade e entra como imagem, com um
/// aviso no [log].
class PdfCanvas implements Canvas {
  PdfCanvas(this.resources, this.log, {required this.visibleWindow});

  final PdfResources resources;
  final PdfLog log;

  /// Área da página (em coordenadas de página) que aparece nela. O que fica
  /// fora não é pintado.
  final Rect visibleWindow;

  /// Pixels por ponto das rasterizações, na escala 1 da página.
  static const rasterDensity = 3.0;

  /// Limite de pixels de uma rasterização; acima dele a densidade cai.
  static const maxRasterPixels = 4000000;

  static const _unbounded = Rect.fromLTRB(-1e5, -1e5, 1e5, 1e5);

  StringBuffer _ops = StringBuffer();
  final List<_State> _stack = [];
  final List<_Group> _groups = [];

  /// Profundidade da pilha em que cada `saveLayer` abriu um grupo.
  final List<int> _layerDepths = [];
  _State _s = _State(_Affine.identity, _unbounded, 1, 'Normal');

  /// Gradiente da decoração que está sendo pintada (ver [PdfGradientHint]).
  /// A primeira pintura com shader o consome.
  PdfGradientHint? pendingGradient;

  /// Quanto um desfoque (`MaskFilter.blur`) pode se espalhar além da forma.
  /// O shader de desfoque é opaco; o `PdfPaintingContext` ajusta este valor
  /// pelas sombras da decoração.
  double blurOutset = 16;

  /// Operadores da página (ou do grupo aberto).
  StringBuffer get ops => _ops;

  static String _n(double v) => PdfWriter.num(v);

  // ---------------------------------------------------------------- estado

  bool isVisible(Rect localRect) {
    final r = _s.m.applyRect(localRect);
    return r.overlaps(visibleWindow) && r.overlaps(_s.clip);
  }

  void writeRaw(String s) => _ops.write(s);

  @override
  void save() {
    _stack.add(_s.copy());
    _ops.write('q\n');
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    save();
    if (paint.colorFilter != null || paint.imageFilter != null) {
      log.add('saveLayer com filtro de cor ou de imagem; pintado sem o filtro');
    }
    final blend = _blendMode(paint.blendMode, paint.color.a);
    if (paint.color.a < 1 || blend != 'Normal') {
      beginGroup(alpha: paint.color.a, blendMode: blend);
      _layerDepths.add(_stack.length);
    }
  }

  @override
  void restore() {
    if (_stack.isEmpty) return;
    if (_layerDepths.isNotEmpty && _layerDepths.last == _stack.length) {
      _layerDepths.removeLast();
      endGroup();
    }
    _s = _stack.removeLast();
    _ops.write('Q\n');
  }

  @override
  void restoreToCount(int count) {
    while (getSaveCount() > count && _stack.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _stack.length + 1;

  /// Abre um grupo de transparência: tudo até [endGroup] é composto junto e
  /// só depois recebe [alpha] e [blendMode], como uma camada do Flutter. Com
  /// opacidade aplicada objeto a objeto, um fundo apareceria através do
  /// texto pintado em cima dele.
  void beginGroup({double alpha = 1, String blendMode = 'Normal'}) {
    _groups.add(_Group(_ops, alpha.clamp(0.0, 1.0), blendMode, getLocalClipBounds(), _s.emittedAlpha, _s.emittedBlend));
    _ops = StringBuffer();
    // Dentro do grupo, opacidade e mistura começam nos valores iniciais.
    _s.emittedAlpha = 1;
    _s.emittedBlend = 'Normal';
  }

  void endGroup() {
    final group = _groups.removeLast();
    final content = _ops.toString();
    _ops = group.parent;
    _s.emittedAlpha = group.parentAlpha;
    _s.emittedBlend = group.parentBlend;
    if (content.isEmpty || group.alpha == 0 || group.bbox.isEmpty) return;
    final form = resources.form(group.bbox, content);
    final gs = resources.graphicsState(group.alpha, group.blendMode);
    _ops.write('q /$gs gs /$form Do Q\n');
  }

  void _concat(_Affine m) {
    _s.m = _s.m.times(m);
    _ops.write('${_n(m.a)} ${_n(m.b)} ${_n(m.c)} ${_n(m.d)} ${_n(m.e)} ${_n(m.f)} cm\n');
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
  Rect getDestinationClipBounds() {
    final r = _s.clip.intersect(visibleWindow);
    return r.width <= 0 || r.height <= 0 ? Rect.zero : r;
  }

  @override
  Rect getLocalClipBounds() {
    final destination = getDestinationClipBounds();
    final inverse = _s.m.inverse();
    if (destination.isEmpty || inverse == null) return Rect.zero;
    return inverse.applyRect(destination);
  }

  // ---------------------------------------------------------------- recorte

  void _intersectClip(Rect localBounds) {
    _s.clip = _s.clip.intersect(_s.m.applyRect(localBounds));
  }

  void _clipCurrentPath(Rect localBounds, {bool evenOdd = false}) {
    _ops.write(evenOdd ? 'W* n\n' : 'W n\n');
    _intersectClip(localBounds);
  }

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.difference) {
      // Tudo menos o retângulo: par-ímpar entre um retângulo enorme e ele.
      final all = getLocalClipBounds().inflate(1);
      _rect(all);
      _rect(rect);
      _ops.write('W* n\n');
      return;
    }
    _rect(rect);
    _clipCurrentPath(rect);
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    _rrectPath(rrect);
    _clipCurrentPath(rrect.outerRect);
  }

  @override
  void clipRSuperellipse(ui.RSuperellipse rsuperellipse, {bool doAntiAlias = true}) =>
      clipPath(Path()..addRSuperellipse(rsuperellipse));

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    _samplePath(path);
    _clipCurrentPath(path.getBounds(), evenOdd: path.fillType == PathFillType.evenOdd);
  }

  // ---------------------------------------------------------------- tinta

  static const _pdfBlendModes = {
    BlendMode.srcOver: 'Normal',
    BlendMode.multiply: 'Multiply',
    BlendMode.screen: 'Screen',
    BlendMode.overlay: 'Overlay',
    BlendMode.darken: 'Darken',
    BlendMode.lighten: 'Lighten',
    BlendMode.colorDodge: 'ColorDodge',
    BlendMode.colorBurn: 'ColorBurn',
    BlendMode.hardLight: 'HardLight',
    BlendMode.softLight: 'SoftLight',
    BlendMode.difference: 'Difference',
    BlendMode.exclusion: 'Exclusion',
    BlendMode.hue: 'Hue',
    BlendMode.saturation: 'Saturation',
    BlendMode.color: 'Color',
    BlendMode.luminosity: 'Luminosity',
  };

  /// Nome PDF do modo de mistura. Os modos de Porter-Duff (`dstIn`, `xor`...)
  /// não existem em PDF e viram `srcOver`, com aviso.
  String _blendMode(BlendMode mode, double alpha) {
    final name = _pdfBlendModes[mode];
    if (name != null) return name;
    // `src` com cor opaca dá o mesmo resultado que `srcOver`.
    if (mode == BlendMode.src && alpha >= 1) return 'Normal';
    log.add('BlendMode ${mode.name} sem equivalente em PDF; tratado como srcOver');
    return 'Normal';
  }

  void _graphicsState(double alpha, String blendMode) {
    final a = alpha.clamp(0.0, 1.0);
    if ((a - _s.emittedAlpha).abs() < 0.001 && blendMode == _s.emittedBlend) return;
    _ops.write('/${resources.graphicsState(a, blendMode)} gs\n');
    _s.emittedAlpha = a;
    _s.emittedBlend = blendMode;
  }

  String _rgb(Color c) => '${_n(c.r.clamp(0, 1))} ${_n(c.g.clamp(0, 1))} ${_n(c.b.clamp(0, 1))}';

  static Paint _copy(Paint p, PaintingStyle style) => Paint()
    ..color = p.color
    ..blendMode = p.blendMode
    ..style = style
    ..strokeWidth = p.strokeWidth
    ..strokeCap = p.strokeCap
    ..strokeJoin = p.strokeJoin
    ..strokeMiterLimit = p.strokeMiterLimit
    ..shader = p.shader
    ..maskFilter = p.maskFilter
    ..colorFilter = p.colorFilter
    ..imageFilter = p.imageFilter
    ..invertColors = p.invertColors
    ..filterQuality = p.filterQuality
    ..isAntiAlias = p.isAntiAlias;

  /// Desenha uma forma. [path] escreve o caminho em PDF; [draw] desenha a
  /// mesma forma num `Canvas` de verdade, para quando é preciso rasterizar.
  void _shape(Paint paint, Rect bounds, void Function() path, void Function(Canvas c) draw, {bool evenOdd = false}) {
    final stroke = paint.style == PaintingStyle.stroke;
    final outset = stroke ? paint.strokeWidth * 2 + 1 : 1.0;
    final blend = _blendMode(paint.blendMode, paint.color.a);
    if (paint.maskFilter != null || paint.imageFilter != null) {
      _raster(bounds.inflate(outset + blurOutset), draw, density: 2, blendMode: blend, reason: 'desfoque rasterizado');
      return;
    }
    if (paint.colorFilter != null || paint.invertColors) {
      _raster(bounds.inflate(outset), draw, blendMode: blend, reason: 'Paint com filtro de cor rasterizado');
      return;
    }
    if (paint.shader != null) {
      if (stroke) {
        _raster(bounds.inflate(outset), draw, blendMode: blend, reason: 'traço com shader (gradiente) rasterizado');
        return;
      }
      final hint = pendingGradient;
      pendingGradient = null;
      final shading = hint == null ? null : PdfShading.from(hint);
      save();
      path();
      _clipCurrentPath(bounds, evenOdd: evenOdd);
      if (shading != null) {
        _graphicsState(shading.alpha * paint.color.a, blend);
        if (shading.transform != null) transform(shading.transform!);
        _ops.write('/${resources.shading(shading.dict)} sh\n');
      } else {
        // O interior vem do Flutter; a borda continua sendo o caminho vetorial.
        _raster(
          bounds,
          (c) => c.drawRect(bounds, paint),
          blendMode: blend,
          reason: hint == null
              ? 'shader sem gradiente conhecido rasterizado'
              : 'gradiente sem equivalente em PDF rasterizado',
        );
      }
      restore();
      return;
    }
    _graphicsState(paint.color.a, blend);
    final String op;
    if (stroke) {
      _ops.write(
        '${_rgb(paint.color)} RG ${_n(paint.strokeWidth)} w '
        '${paint.strokeCap.index} J ${paint.strokeJoin.index} j ${_n(paint.strokeMiterLimit)} M\n',
      );
      op = 'S';
    } else {
      _ops.write('${_rgb(paint.color)} rg\n');
      op = evenOdd ? 'f*' : 'f';
    }
    path();
    _ops.write('$op\n');
  }

  /// Escala (pixels por unidade local) de uma rasterização de [area].
  double rasterScale(Rect area, {double density = rasterDensity}) {
    var scale = density * math.max(_s.m.scale, 1e-6);
    final pixels = area.width * area.height * scale * scale;
    if (pixels > maxRasterPixels) scale *= math.sqrt(maxRasterPixels / pixels);
    return scale;
  }

  /// Desenha [draw] num `Canvas` de verdade, só dentro de [bounds] (cortado
  /// pelo recorte atual), e põe o resultado na página como imagem.
  void _raster(
    Rect bounds,
    void Function(Canvas c) draw, {
    required String reason,
    double density = rasterDensity,
    double? pixelsPerUnit,
    String blendMode = 'Normal',
  }) {
    final area = bounds.intersect(getLocalClipBounds());
    if (area.width <= 0 || area.height <= 0) return;
    var scale = pixelsPerUnit ?? rasterScale(area, density: density);
    final pixels = area.width * area.height * scale * scale;
    if (pixels > maxRasterPixels) scale *= math.sqrt(maxRasterPixels / pixels);
    final w = math.max(1, (area.width * scale).ceil());
    final h = math.max(1, (area.height * scale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-area.left, -area.top);
    draw(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    log.add(reason);
    drawRasterImage(image, Rect.fromLTWH(area.left, area.top, w / scale, h / scale), blendMode: blendMode);
  }

  /// Desenha uma imagem criada pela lib; ela é descartada depois que o
  /// arquivo é escrito.
  void drawRasterImage(ui.Image image, Rect dst, {String blendMode = 'Normal', bool isTextFallback = false}) {
    final name = resources.image(image, created: true, isTextFallback: isTextFallback);
    _graphicsState(1, blendMode);
    _placeImage(name, dst);
  }

  void _placeImage(String name, Rect dst) {
    _ops.write('q ${_n(dst.width)} 0 0 ${_n(-dst.height)} ${_n(dst.left)} ${_n(dst.bottom)} cm /$name Do Q\n');
  }

  // ---------------------------------------------------------------- caminhos

  void _m(double x, double y) => _ops.write('${_n(x)} ${_n(y)} m\n');
  void _l(double x, double y) => _ops.write('${_n(x)} ${_n(y)} l\n');
  void _c(double x1, double y1, double x2, double y2, double x3, double y3) =>
      _ops.write('${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} ${_n(x3)} ${_n(y3)} c\n');
  void _rect(Rect r) => _ops.write('${_n(r.left)} ${_n(r.top)} ${_n(r.width)} ${_n(r.height)} re\n');

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
    _ops.write('h\n');
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
    _ops.write('h\n');
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
      if (metric.isClosed) _ops.write('h\n');
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
    final area = getLocalClipBounds();
    if (area.isEmpty) return;
    _shape(_copy(paint, PaintingStyle.fill), area, () => _rect(area), (c) => c.drawPaint(paint));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    _shape(_copy(paint, PaintingStyle.stroke), Rect.fromPoints(p1, p2), () {
      _m(p1.dx, p1.dy);
      _l(p2.dx, p2.dy);
    }, (c) => c.drawLine(p1, p2, paint));
  }

  @override
  void drawRect(Rect rect, Paint paint) => _shape(paint, rect, () => _rect(rect), (c) => c.drawRect(rect, paint));

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      _shape(paint, rrect.outerRect, () => _rrectPath(rrect), (c) => c.drawRRect(rrect, paint));

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    _shape(
      paint,
      outer.outerRect,
      () {
        _rrectPath(outer);
        _rrectPath(inner);
      },
      (c) => c.drawDRRect(outer, inner, paint),
      evenOdd: true,
    );
  }

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, Paint paint) =>
      drawPath(Path()..addRSuperellipse(rsuperellipse), paint);

  @override
  void drawOval(Rect rect, Paint paint) => _shape(paint, rect, () => _ovalPath(rect), (c) => c.drawOval(rect, paint));

  @override
  void drawCircle(Offset c, double radius, Paint paint) => drawOval(Rect.fromCircle(center: c, radius: radius), paint);

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    _shape(paint, rect, () {
      if (useCenter) {
        _m(rect.center.dx, rect.center.dy);
        _arcSegments(rect, startAngle, sweepAngle, moveToStart: false);
        _ops.write('h\n');
      } else {
        _arcSegments(rect, startAngle, sweepAngle, moveToStart: true);
      }
    }, (c) => c.drawArc(rect, startAngle, sweepAngle, useCenter, paint));
  }

  @override
  void drawPath(Path path, Paint paint) {
    _shape(
      paint,
      path.getBounds(),
      () => _samplePath(path),
      (c) => c.drawPath(path, paint),
      evenOdd: path.fillType == PathFillType.evenOdd,
    );
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    switch (pointMode) {
      case ui.PointMode.points:
        // Cada ponto é um quadrado (ou um círculo, com ponta redonda) do
        // tamanho da espessura da linha, qualquer que seja o estilo.
        final r = math.max(paint.strokeWidth, 1) / 2;
        final dot = _copy(paint, PaintingStyle.fill);
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
        var bounds = Rect.fromPoints(points.first, points.first);
        for (final p in points) {
          bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
        }
        _shape(_copy(paint, PaintingStyle.stroke), bounds, () {
          _m(points.first.dx, points.first.dy);
          for (final p in points.skip(1)) {
            _l(p.dx, p.dy);
          }
        }, (c) => c.drawPoints(pointMode, points, paint));
    }
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) {
    drawPoints(pointMode, [for (var i = 0; i + 1 < points.length; i += 2) Offset(points[i], points[i + 1])], paint);
  }

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
    if (elevation <= 0 || color.a == 0) return;
    // A sombra é um desfoque calculado pelo Flutter: rasterizada em volta da
    // forma, com folga para o espalhamento.
    _raster(
      path.getBounds().inflate(elevation * 3 + 2),
      (c) => c.drawShadow(path, color, elevation, transparentOccluder),
      density: 2,
      reason: 'sombra de elevação (drawShadow) rasterizada',
    );
  }

  // ---------------------------------------------------------------- imagens

  /// Imagem inteira esticada em [dst], com a opacidade da tinta.
  void _imageInRect(ui.Image image, Rect dst, Paint paint) {
    final name = resources.image(image, interpolate: paint.filterQuality != FilterQuality.none);
    _graphicsState(paint.color.a, _blendMode(paint.blendMode, paint.color.a));
    _placeImage(name, dst);
  }

  void _image(ui.Image image, Rect src, Rect dst, Paint paint, void Function(Canvas c) draw) {
    if (src.isEmpty || dst.width <= 0 || dst.height <= 0) return;
    if (paint.colorFilter != null ||
        paint.maskFilter != null ||
        paint.imageFilter != null ||
        paint.shader != null ||
        paint.invertColors) {
      // Na resolução da própria imagem.
      final ppu = math.max(src.width / dst.width.abs(), src.height / dst.height.abs()) * _s.m.scale;
      _raster(
        dst,
        draw,
        pixelsPerUnit: math.max(ppu, 1),
        blendMode: _blendMode(paint.blendMode, paint.color.a),
        reason: 'imagem com filtro rasterizada',
      );
      return;
    }
    final full = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    if (src == full) {
      _imageInRect(image, dst, paint);
      return;
    }
    final sx = dst.width / src.width, sy = dst.height / src.height;
    save();
    clipRect(dst);
    _imageInRect(
      image,
      Rect.fromLTWH(dst.left - src.left * sx, dst.top - src.top * sy, image.width * sx, image.height * sy),
      paint,
    );
    restore();
  }

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    _image(image, src, src.shift(offset), paint, (c) => c.drawImage(image, offset, paint));
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    _image(image, src, dst, paint, (c) => c.drawImageRect(image, src, dst, paint));
  }

  /// Nove partes: os cantos ficam no tamanho original, as bordas esticam num
  /// sentido e o centro nos dois. Se o destino é menor que os cantos, eles
  /// encolhem na mesma proporção.
  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final left = center.left, right = iw - center.right, top = center.top, bottom = ih - center.bottom;
    final kx = left + right > dst.width ? dst.width / (left + right) : 1.0;
    final ky = top + bottom > dst.height ? dst.height / (top + bottom) : 1.0;
    final sx = [0.0, center.left, center.right, iw];
    final sy = [0.0, center.top, center.bottom, ih];
    final dx = [dst.left, dst.left + left * kx, dst.right - right * kx, dst.right];
    final dy = [dst.top, dst.top + top * ky, dst.bottom - bottom * ky, dst.bottom];
    for (var j = 0; j < 3; j++) {
      for (var i = 0; i < 3; i++) {
        final s = Rect.fromLTRB(sx[i], sy[j], sx[i + 1], sy[j + 1]);
        final d = Rect.fromLTRB(dx[i], dy[j], dx[i + 1], dy[j + 1]);
        if (s.width <= 0 || s.height <= 0 || d.width <= 0 || d.height <= 0) continue;
        drawImageRect(image, s, d, paint);
      }
    }
  }

  @override
  void drawAtlas(
    ui.Image atlas,
    List<RSTransform> transforms,
    List<Rect> rects,
    List<Color>? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    if (colors != null && colors.isNotEmpty) log.add('drawAtlas com cores: pintado sem as cores');
    for (var i = 0; i < math.min(transforms.length, rects.length); i++) {
      final t = transforms[i], r = rects[i];
      save();
      _concat(_Affine(t.scos, t.ssin, -t.ssin, t.scos, t.tx, t.ty));
      drawImageRect(atlas, r, Rect.fromLTWH(0, 0, r.width, r.height), paint);
      restore();
    }
  }

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    final n = math.min(rstTransforms.length, rects.length) ~/ 4;
    drawAtlas(
      atlas,
      [
        for (var i = 0; i < n; i++)
          RSTransform(
            rstTransforms[i * 4],
            rstTransforms[i * 4 + 1],
            rstTransforms[i * 4 + 2],
            rstTransforms[i * 4 + 3],
          ),
      ],
      [for (var i = 0; i < n; i++) Rect.fromLTRB(rects[i * 4], rects[i * 4 + 1], rects[i * 4 + 2], rects[i * 4 + 3])],
      colors == null ? null : [for (final c in colors) Color(c)],
      blendMode,
      cullRect,
      paint,
    );
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
    final picture = recorder.endRecording();
    final img = picture.toImageSync((w * k).ceil(), (h * k).ceil());
    picture.dispose();
    log.add('texto pintado por painter (drawParagraph) rasterizado');
    drawRasterImage(img, Rect.fromLTWH(offset.dx, offset.dy, w, h), isTextFallback: true);
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
    _graphicsState(color.a, 'Normal');
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
    _ops.write(
      'BT /${font.resourceName} ${_n(fontSize)} Tf ${_rgb(color)} rg '
      '1 0 0 -1 ${_n(xs.first)} ${_n(baseline)} Tm $tj TJ ET\n',
    );
  }

  // ---------------------------------------------------------------- sem tradução

  @override
  void drawPicture(ui.Picture picture) => log.add('drawPicture ignorado (Picture é opaco)');

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) => log.add('drawVertices ignorado');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    log.add('Canvas.${invocation.memberName} sem tradução');
    return null;
  }
}
