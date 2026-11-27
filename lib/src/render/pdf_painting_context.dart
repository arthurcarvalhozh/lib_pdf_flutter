// O PaintingContext do Flutter foi feito para gravar camadas e pixels; aqui
// ele é desviado para o PdfCanvas. Os membros @protected sobrescritos ou
// chamados são justamente os pontos de desvio.
// ignore_for_file: invalid_use_of_protected_member

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../canvas/pdf_canvas.dart';
import '../canvas/pdf_shading.dart';
import '../text/pdf_text.dart';

/// Pinta a árvore de render objects do Flutter no [PdfCanvas], sem criar
/// camadas de composição.
///
/// As camadas viram o equivalente em PDF: opacidade vira grupo de
/// transparência; transformação e recorte viram operadores. Camadas sem
/// equivalente (filtro de cor, máscara de shader, filtro de imagem) são
/// pintadas pelo próprio Flutter só naquele trecho e entram como imagem.
class PdfPaintingContext extends PaintingContext {
  PdfPaintingContext(this._canvas, this._paragraphs, this._log, Rect bounds) : super(ContainerLayer(), bounds);

  final PdfCanvas _canvas;
  final PdfParagraphPainter _paragraphs;
  final PdfLog _log;

  /// Área (no espaço local) do render object sendo pintado, usada como
  /// limite quando uma camada dele precisa ser rasterizada.
  Rect? _currentBounds;

  /// Camadas-raiz das rasterizações de subárvore. Só são desmontadas em
  /// [dispose]: o render object guarda a camada dele (`layer = ...`) depois
  /// que o `pushLayer` volta, e desmontar antes a deixaria sem dono.
  final List<OffsetLayer> _rasterRoots = [];

  /// Libera as camadas criadas pelas rasterizações. Chamar depois de pintar
  /// a página.
  void dispose() {
    for (final root in _rasterRoots) {
      root
        ..removeAllChildren()
        ..dispose();
    }
    _rasterRoots.clear();
  }

  @override
  Canvas get canvas => _canvas;

  // Nunca há gravação ativa (o canvas é o PdfCanvas), então o super não faz nada.
  @override
  void stopRecordingIfNeeded() => super.stopRecordingIfNeeded();

  @override
  void setIsComplexHint() {}

  @override
  void setWillChangeHint() {}

  @override
  void appendLayer(Layer layer) {}

  @override
  void addLayer(Layer layer) => _log.add('camada ${layer.runtimeType} adicionada diretamente; ignorada');

  @override
  void paintChild(RenderObject child, Offset offset) {
    // O aviso de gradiente vale só para a decoração do próprio render
    // object, nunca para os filhos.
    _canvas.pendingGradient = null;
    if (child is RenderBox && !_canvas.isVisible(offset & child.size)) {
      // Fora da página: nada a pintar. Filhos que desenham fora da própria
      // caixa são raros nos relatórios; a etapa 7 trata isso direito.
      return;
    }
    if (child is RenderParagraph) {
      _paragraphs.paint(child, offset, _canvas);
      return;
    }
    final previousBounds = _currentBounds;
    final previousOutset = _canvas.blurOutset;
    _currentBounds = child is RenderBox ? offset & child.size : child.paintBounds.shift(offset);
    try {
      if (child.isRepaintBoundary) {
        _paintRepaintBoundary(child, offset);
      } else {
        if (child is RenderDecoratedBox) _announceDecoration(child, offset);
        child.paint(this, offset);
      }
    } finally {
      _currentBounds = previousBounds;
      _canvas
        ..pendingGradient = null
        ..blurOutset = previousOutset;
    }
  }

  /// Fronteiras de repintura aplicam o efeito na própria camada (no 3.47, o
  /// `Opacity` e o `ImageFiltered` fazem assim): pede a camada e aplica o
  /// equivalente no canvas.
  void _paintRepaintBoundary(RenderObject child, Offset offset) {
    final layer = child.updateCompositedLayer(oldLayer: null);
    if (layer is OpacityLayer) {
      final alpha = (layer.alpha ?? 255) / 255;
      if (alpha == 0) return;
      _canvas.save();
      if (alpha < 1) _canvas.beginGroup(alpha: alpha);
      child.paint(this, offset);
      if (alpha < 1) _canvas.endGroup();
      _canvas.restore();
      return;
    }
    if (layer is ImageFilterLayer) {
      // O `ImageFiltered` (desfoque e afins) faz o mesmo que o Opacity.
      _rasterizeLayer(layer, child.paint, offset, null);
      return;
    }
    if (layer.runtimeType != OffsetLayer) {
      _log.add('camada ${layer.runtimeType} de fronteira de repintura sem equivalente; pintada sem o efeito');
    }
    child.paint(this, offset);
  }

  /// Conta ao canvas o gradiente e as sombras da decoração que vem a seguir:
  /// o shader e o desfoque que o Flutter passa ao canvas são opacos.
  void _announceDecoration(RenderDecoratedBox box, Offset offset) {
    if (box.position != DecorationPosition.background) return;
    final (Gradient? gradient, List<BoxShadow>? shadows) = switch (box.decoration) {
      BoxDecoration(:final gradient, :final boxShadow) => (gradient, boxShadow),
      ShapeDecoration(:final gradient, :final shadows) => (gradient, shadows),
      _ => (null, null),
    };
    if (gradient != null) {
      _canvas.pendingGradient = PdfGradientHint(gradient, offset & box.size, box.configuration.textDirection);
    }
    if (shadows != null && shadows.isNotEmpty) {
      // O desfoque se espalha por cerca de 3 sigmas.
      _canvas.blurOutset = shadows
          .map((s) => s.blurSigma * 3 + s.offset.distance + s.spreadRadius.abs() + 2)
          .reduce(math.max);
    }
  }

  @override
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, {Rect? childPaintBounds}) {
    if (childLayer is ColorFilterLayer || childLayer is ShaderMaskLayer || childLayer is ImageFilterLayer) {
      _rasterizeLayer(childLayer, painter, offset, childPaintBounds);
      return;
    }
    _canvas.save();
    if (childLayer is OpacityLayer) {
      _canvas.translate(childLayer.offset.dx, childLayer.offset.dy);
      final alpha = (childLayer.alpha ?? 255) / 255;
      if (alpha < 1) _canvas.beginGroup(alpha: alpha);
      painter(this, offset);
      if (alpha < 1) _canvas.endGroup();
      _canvas.restore();
      return;
    }
    if (childLayer is TransformLayer) {
      final t = childLayer.transform;
      if (t != null) _canvas.transform(t.storage);
    } else if (childLayer is ClipRectLayer) {
      final r = childLayer.clipRect;
      if (r != null && childLayer.clipBehavior != Clip.none) _canvas.clipRect(r);
    } else if (childLayer is ClipRRectLayer) {
      final r = childLayer.clipRRect;
      if (r != null && childLayer.clipBehavior != Clip.none) _canvas.clipRRect(r);
    } else if (childLayer is ClipRSuperellipseLayer) {
      final r = childLayer.clipRSuperellipse;
      if (r != null && childLayer.clipBehavior != Clip.none) _canvas.clipRSuperellipse(r);
    } else if (childLayer is ClipPathLayer) {
      final p = childLayer.clipPath;
      if (p != null && childLayer.clipBehavior != Clip.none) _canvas.clipPath(p);
    } else if (childLayer is BackdropFilterLayer) {
      _log.add('BackdropFilter sem equivalente em PDF (precisa do que está atrás); pintado sem o efeito');
    } else if (childLayer is OffsetLayer) {
      _canvas.translate(childLayer.offset.dx, childLayer.offset.dy);
    } else {
      _log.add('camada ${childLayer.runtimeType} sem equivalente em PDF; pintada sem o efeito');
    }
    painter(this, offset);
    _canvas.restore();
  }

  /// Pinta a subárvore com o `PaintingContext` de verdade do Flutter, dentro
  /// da camada [childLayer], e põe o resultado na página como imagem.
  void _rasterizeLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, Rect? bounds) {
    var area = _layerBounds(bounds);
    // O filtro de imagem (desfoque) espalha a pintura além da caixa.
    if (childLayer is ImageFilterLayer) area = area.inflate(16);
    area = area.intersect(_canvas.getLocalClipBounds());
    if (area.width <= 0 || area.height <= 0) return;

    final container = OffsetLayer();
    final context = PaintingContext(container, area);
    context.pushLayer(childLayer, painter, offset, childPaintBounds: bounds);
    context.stopRecordingIfNeeded();
    final scale = _canvas.rasterScale(area);
    final image = container.toImageSync(area, pixelRatio: scale);
    _rasterRoots.add(container);

    _log.add('camada ${childLayer.runtimeType} (filtro sem equivalente em PDF) rasterizada');
    _canvas.drawRasterImage(image, Rect.fromLTWH(area.left, area.top, image.width / scale, image.height / scale));
  }

  /// Limite da subárvore: o informado pela camada, senão a caixa do render
  /// object que a empurrou.
  Rect _layerBounds(Rect? bounds) => bounds ?? _currentBounds ?? estimatedBounds;
}
