import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Uma árvore de widgets montada e medida fora da tela.
///
/// A lib cria a própria `RenderView`, `PipelineOwner` e `BuildOwner`, como o
/// Flutter faz para uma janela, mas nada é desenhado em pixels: depois do
/// layout, a árvore é pintada pelo `PdfPaintingContext`.
class OffscreenTree {
  OffscreenTree._(this.root, this._pipelineOwner, this._buildOwner, this._focusManager, this._element);

  /// Raiz do conteúdo, já medida.
  final RenderRepaintBoundary root;
  final PipelineOwner _pipelineOwner;
  final BuildOwner _buildOwner;
  final FocusManager _focusManager;
  final RenderObjectToWidgetElement<RenderBox> _element;

  /// Monta [widget] com largura fixa [width] e altura livre.
  ///
  /// [mediaSize] é o tamanho que os widgets veem em `MediaQuery` (a página).
  static Future<OffscreenTree> mount(Widget widget, {required double width, required Size mediaSize}) async {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ?? dispatcher.views.first;
    final boundary = RenderRepaintBoundary();
    final constraints = BoxConstraints(minWidth: width, maxWidth: width);
    final renderView = RenderView(
      view: view,
      child: boundary,
      configuration: ViewConfiguration(logicalConstraints: constraints, physicalConstraints: constraints),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final focusManager = FocusManager();
    final buildOwner = BuildOwner(focusManager: focusManager);
    final wrapped = MediaQuery(
      data: MediaQueryData(size: mediaSize),
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    );
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: wrapped,
    ).attachToRenderTree(buildOwner);
    final tree = OffscreenTree._(boundary, pipelineOwner, buildOwner, focusManager, element);
    tree._pump();
    // Imagens e outros carregamentos assíncronos marcam a árvore como suja
    // depois do primeiro build.
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
      tree._pump();
    }
    pipelineOwner.flushCompositingBits();
    return tree;
  }

  void _pump() {
    _buildOwner.buildScope(_element);
    _buildOwner.finalizeTree();
    _pipelineOwner.flushLayout();
  }

  /// Desmonta a árvore, descartando States, controllers e tickers.
  void dispose() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.transientCallbackCount == 0) {
      _unmount();
      return;
    }
    // Se o sistema avisou troca de fontes durante a geração (um app que
    // carrega fontes com FontLoader, por exemplo), cada texto agendou um
    // callback para o próximo frame e não pode ser desmontado antes dele
    // rodar: o Flutter acusa o callback órfão. Os callbacks de frame rodam
    // antes dos pós-frame, então desmontar no pós-frame é seguro.
    scheduler.addPostFrameCallback((_) => _unmount(), debugLabel: 'lib_pdf.OffscreenTree.dispose');
    scheduler.ensureVisualUpdate();
  }

  void _unmount() {
    RenderObjectToWidgetAdapter<RenderBox>(container: root).attachToRenderTree(_buildOwner, _element);
    _buildOwner.buildScope(_element);
    _buildOwner.finalizeTree();
    _focusManager.dispose();
  }
}
