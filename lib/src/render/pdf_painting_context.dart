// O PaintingContext do Flutter foi feito para gravar camadas e pixels; aqui
// ele é desviado para o PdfCanvas. Os membros @protected sobrescritos ou
// chamados são justamente os pontos de desvio.
// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/rendering.dart';

import '../canvas/pdf_canvas.dart';
import '../text/pdf_text.dart';

/// Pinta a árvore de render objects do Flutter no [PdfCanvas], sem criar
/// camadas de composição.
class PdfPaintingContext extends PaintingContext {
  PdfPaintingContext(this._canvas, this._paragraphs, this._log, Rect bounds) : super(ContainerLayer(), bounds);

  final PdfCanvas _canvas;
  final PdfParagraphPainter _paragraphs;
  final PdfLog _log;

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
    if (child is RenderBox && !_canvas.isVisible(offset & child.size)) {
      // Fora da página: nada a pintar. Filhos que desenham fora da própria
      // caixa são raros nos relatórios; a etapa 7 trata isso direito.
      return;
    }
    if (child is RenderParagraph) {
      _paragraphs.paint(child, offset, _canvas);
      return;
    }
    if (child.isRepaintBoundary) {
      // Fronteiras de repintura aplicam o efeito na própria camada
      // (no 3.47, o Opacity faz assim): pede a camada e aplica no canvas.
      final layer = child.updateCompositedLayer(oldLayer: null);
      _canvas.save();
      if (layer is OpacityLayer) {
        _canvas.multiplyAlpha((layer.alpha ?? 255) / 255);
      } else if (layer.runtimeType != OffsetLayer) {
        _log.add('camada ${layer.runtimeType} de fronteira de repintura sem equivalente; pintada sem o efeito');
      }
      child.paint(this, offset);
      _canvas.restore();
      return;
    }
    child.paint(this, offset);
  }

  @override
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, {Rect? childPaintBounds}) {
    _canvas.save();
    if (childLayer is OpacityLayer) {
      _canvas.translate(childLayer.offset.dx, childLayer.offset.dy);
      _canvas.multiplyAlpha((childLayer.alpha ?? 255) / 255);
    } else if (childLayer is TransformLayer) {
      final t = childLayer.transform;
      if (t != null) _canvas.transform(t.storage);
    } else if (childLayer is ClipRectLayer) {
      final r = childLayer.clipRect;
      if (r != null && childLayer.clipBehavior != Clip.none) _canvas.clipRect(r);
    } else if (childLayer is ClipRRectLayer) {
      final r = childLayer.clipRRect;
      if (r != null && childLayer.clipBehavior != Clip.none) _canvas.clipRRect(r);
    } else if (childLayer is ClipPathLayer) {
      final p = childLayer.clipPath;
      if (p != null && childLayer.clipBehavior != Clip.none) _canvas.clipPath(p);
    } else if (childLayer is ImageFilterLayer) {
      _canvas.translate(childLayer.offset.dx, childLayer.offset.dy);
      _log.add('ImageFilterLayer (blur e afins) sem equivalente em PDF; pintada sem o efeito');
    } else if (childLayer is OffsetLayer) {
      _canvas.translate(childLayer.offset.dx, childLayer.offset.dy);
    } else {
      _log.add('camada ${childLayer.runtimeType} sem equivalente em PDF; pintada sem o efeito');
    }
    painter(this, offset);
    _canvas.restore();
  }
}
