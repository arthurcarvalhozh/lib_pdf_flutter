import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../document/pdf_writer.dart';

/// O gradiente de uma decoração (`BoxDecoration`, `ShapeDecoration`), lido no
/// render object antes da pintura.
///
/// O shader que o Flutter entrega ao canvas (`ui.Gradient`) é opaco: não dá
/// para ler cores nem pontos dele. Por isso o `PdfPaintingContext` avisa o
/// canvas qual gradiente vem a seguir, e o canvas usa este aviso na primeira
/// pintura com shader.
class PdfGradientHint {
  const PdfGradientHint(this.gradient, this.rect, this.textDirection);

  final Gradient gradient;

  /// Retângulo que a decoração passa para `createShader`.
  final Rect rect;
  final TextDirection? textDirection;
}

/// Um gradiente traduzido para um shading do PDF (tipo 2, axial, ou tipo 3,
/// radial).
class PdfShading {
  const PdfShading(this.dict, this.alpha, this.transform);

  final Map<String, Object> dict;

  /// Opacidade comum a todas as cores (o shading do PDF não tem alfa por cor).
  final double alpha;

  /// `GradientTransform` do Flutter, a aplicar antes do `sh`.
  final Float64List? transform;

  /// Traduz [hint], ou devolve null quando o PDF não tem equivalente direto:
  /// gradiente de varredura, repetição diferente de `clamp` e cores com
  /// opacidades diferentes entre si. Nesses casos o canvas rasteriza.
  static PdfShading? from(PdfGradientHint hint) {
    final g = hint.gradient;
    final dir = hint.textDirection ?? TextDirection.ltr;
    final alpha = g.colors.first.a;
    if (g.colors.any((c) => (c.a - alpha).abs() > 0.002)) return null;
    final function = _function(g.colors, g.stops);
    if (function == null) return null;

    final List<double> coords;
    final int type;
    switch (g) {
      case LinearGradient(:final tileMode) when tileMode == TileMode.clamp:
        final begin = g.begin.resolve(dir).withinRect(hint.rect);
        final end = g.end.resolve(dir).withinRect(hint.rect);
        type = 2;
        coords = [begin.dx, begin.dy, end.dx, end.dy];
      case RadialGradient(:final tileMode) when tileMode == TileMode.clamp:
        final center = g.center.resolve(dir).withinRect(hint.rect);
        final radius = g.radius * hint.rect.shortestSide;
        // Com foco, o Flutter usa um gradiente cônico de dois pontos: o
        // círculo do foco é o começo (t = 0) e o círculo principal, o fim.
        final focal = g.focal?.resolve(dir).withinRect(hint.rect);
        final focalRadius = g.focalRadius * hint.rect.shortestSide;
        type = 3;
        coords = focal == null
            ? [center.dx, center.dy, 0, center.dx, center.dy, radius]
            : [focal.dx, focal.dy, focalRadius, center.dx, center.dy, radius];
      default:
        return null;
    }
    return PdfShading(
      {
        'ShadingType': type,
        'ColorSpace': const PdfName('DeviceRGB'),
        'Coords': coords,
        'Function': function,
        'Extend': [true, true],
      },
      alpha,
      g.transform?.transform(hint.rect, textDirection: dir)?.storage,
    );
  }

  /// Função de cor do shading: uma interpolação linear (tipo 2) por trecho
  /// entre paradas, costuradas por uma função tipo 3. Trechos de largura zero
  /// (troca seca de cor) são descartados: a fronteira entre os vizinhos já
  /// faz a troca.
  static Map<String, Object>? _function(List<Color> colors, List<double>? stops) {
    final n = colors.length;
    final points = <(double, Color)>[
      for (var i = 0; i < n; i++) ((stops?[i] ?? (n == 1 ? 0.0 : i / (n - 1))).clamp(0.0, 1.0), colors[i]),
    ];
    if (points.first.$1 > 0) points.insert(0, (0, points.first.$2));
    if (points.last.$1 < 1) points.add((1, points.last.$2));

    final segments = <(double, Map<String, Object>)>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final (start, c0) = points[i];
      final (end, c1) = points[i + 1];
      if (end - start <= 1e-6) continue;
      segments.add((start, _interpolation(c0, c1)));
    }
    if (segments.isEmpty) return null;
    if (segments.length == 1) return segments.single.$2;
    return {
      'FunctionType': 3,
      'Domain': [0, 1],
      'Functions': [for (final s in segments) s.$2],
      'Bounds': [for (final s in segments.skip(1)) s.$1],
      'Encode': [
        for (final _ in segments) ...[0, 1],
      ],
    };
  }

  static Map<String, Object> _interpolation(Color c0, Color c1) => {
    'FunctionType': 2,
    'Domain': [0, 1],
    'C0': [c0.r, c0.g, c0.b],
    'C1': [c1.r, c1.g, c1.b],
    'N': 1,
  };
}
