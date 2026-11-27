import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pdf_canvas.dart';
import 'pdf_painting_context.dart';
import 'pdf_text.dart';
import 'pdf_writer.dart';

/// Formato da página em pontos (1/72 de polegada).
class PdfPageFormat {
  const PdfPageFormat(this.width, this.height, {this.margin = 28});
  static const a4 = PdfPageFormat(595.28, 841.89);
  final double width;
  final double height;
  final double margin;
  double get contentWidth => width - 2 * margin;
  double get contentHeight => height - 2 * margin;
}

/// Mantém o filho inteiro na mesma página, se ele couber numa página.
class KeepTogether extends SingleChildRenderObjectWidget {
  const KeepTogether({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderKeepTogether();
}

class RenderKeepTogether extends RenderProxyBox {}

class PdfFontSpec {
  const PdfFontSpec(this.family, this.bytes, {this.weight = 400});
  final String family;
  final Uint8List bytes;
  final int weight;
}

/// Resultado da geração, com as medidas que a prova de conceito registra.
class PdfResult {
  PdfResult({
    required this.bytes,
    required this.pages,
    required this.log,
    required this.layout,
    required this.paint,
    required this.write,
    required this.textFallbackImages,
    required this.images,
  });

  final Uint8List bytes;
  final int pages;
  final Map<String, int> log;
  final Duration layout;
  final Duration paint;
  final Duration write;
  final int textFallbackImages;
  final int images;
  Duration get total => layout + paint + write;
}

/// Gera um PDF a partir de uma árvore de widgets do Flutter.
///
/// 1. Monta e mede a árvore fora da tela, na largura útil da página.
/// 2. Escolhe pontos de quebra que não cortam linha de texto, linha de
///    tabela, desenho nem bloco marcado com [KeepTogether].
/// 3. Pinta cada página como uma janela sobre o conteúdo contínuo.
class PdfDocumentPoc {
  PdfDocumentPoc({required this.fonts, this.format = PdfPageFormat.a4, this.title = 'Relatório'});

  final List<PdfFontSpec> fonts;
  final PdfPageFormat format;
  final String title;

  Future<PdfResult> render(Widget content) async {
    final log = PdfLog();
    final resources = PdfResources();
    final registry = PdfFontRegistry(resources, log);
    for (final f in fonts) {
      registry.register(f.family, f.bytes, weight: f.weight);
    }
    final paragraphs = PdfParagraphPainter(registry, log);

    // 1. Montagem e layout fora da tela --------------------------------
    final sw = Stopwatch()..start();
    final width = format.contentWidth;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ?? dispatcher.views.first;
    final boundary = RenderRepaintBoundary();
    final constraints = BoxConstraints(minWidth: width, maxWidth: width);
    final renderView = RenderView(
      view: view,
      child: boundary,
      configuration: ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints,
      ),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final focusManager = FocusManager();
    final buildOwner = BuildOwner(focusManager: focusManager);
    final wrapped = MediaQuery(
      data: MediaQueryData(size: Size(format.width, format.height)),
      child: Directionality(textDirection: TextDirection.ltr, child: content),
    );
    final element = RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: wrapped)
        .attachToRenderTree(buildOwner);
    void pump() {
      buildOwner.buildScope(element);
      buildOwner.finalizeTree();
      pipelineOwner.flushLayout();
    }

    pump();
    // Imagens e outros carregamentos assíncronos marcam a árvore como suja.
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
      pump();
    }
    pipelineOwner.flushCompositingBits();
    final contentHeight = boundary.size.height;
    final pageStarts = _pageBreaks(boundary, contentHeight, format.contentHeight);
    final layoutTime = sw.elapsed;

    // 2. Pintura de cada página -----------------------------------------
    sw.reset();
    final pageOps = <String>[];
    for (var i = 0; i < pageStarts.length; i++) {
      final start = pageStarts[i];
      final end = i + 1 < pageStarts.length ? pageStarts[i + 1] : contentHeight;
      final window = Rect.fromLTWH(format.margin, format.margin, width, end - start);
      final canvas = PdfCanvas(resources, log, visibleWindow: window);
      canvas.writeRaw('1 0 0 -1 0 ${PdfWriter.num(format.height)} cm\n');
      canvas.save();
      canvas.clipRect(window);
      canvas.translate(format.margin, format.margin - start);
      PdfPaintingContext(canvas, paragraphs, log, Offset.zero & boundary.size).paintChild(boundary, Offset.zero);
      canvas.restore();
      _footer(canvas, registry, 'Página ${i + 1} de ${pageStarts.length}');
      pageOps.add(canvas.ops.toString());
    }
    final paintTime = sw.elapsed;

    // 3. Escrita do arquivo ---------------------------------------------
    sw.reset();
    final w = PdfWriter();
    final catalog = w.reserve();
    final pagesRef = w.reserve();
    final fontRefs = <String, Object>{
      for (final e in resources.fonts.entries) e.key: e.value.write(w),
    };
    final xobjects = <String, Object>{};
    for (final pending in resources.images) {
      xobjects[pending.name] = await _writeImage(w, pending.image);
    }
    final gstates = <String, Object>{
      for (final e in resources.alphaStates.entries)
        e.key: <String, Object>{'Type': const PdfName('ExtGState'), 'ca': e.value, 'CA': e.value},
    };
    final resourcesRef = w.add(<String, Object>{
      'Font': fontRefs,
      if (gstates.isNotEmpty) 'ExtGState': gstates,
      if (xobjects.isNotEmpty) 'XObject': xobjects,
    });
    final kids = <PdfRef>[];
    for (final ops in pageOps) {
      final contents = w.addStream({}, ops.codeUnits);
      kids.add(w.add(<String, Object>{
        'Type': const PdfName('Page'),
        'Parent': pagesRef,
        'MediaBox': [0, 0, format.width, format.height],
        'Contents': contents,
        'Resources': resourcesRef,
      }));
    }
    w.set(pagesRef, <String, Object>{'Type': const PdfName('Pages'), 'Kids': kids, 'Count': kids.length});
    w.set(catalog, <String, Object>{'Type': const PdfName('Catalog'), 'Pages': pagesRef});
    final info = w.add(<String, Object>{
      'Title': PdfString(title),
      'Producer': 'lib_pdf (prova de conceito)',
    });
    final bytes = w.build(root: catalog, info: info);
    final writeTime = sw.elapsed;

    // Desmonta a árvore (descarta States, controllers e tickers). Se o
    // sistema avisou de troca de fontes durante a geração, os textos
    // agendaram um callback para o próximo frame: espera ele rodar antes de
    // desmontar, senão o Flutter acusa o callback órfão.
    if (SchedulerBinding.instance.transientCallbackCount > 0) {
      await SchedulerBinding.instance.endOfFrame.timeout(const Duration(seconds: 1), onTimeout: () {});
    }
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(buildOwner, element);
    buildOwner.buildScope(element);
    buildOwner.finalizeTree();
    focusManager.dispose();

    return PdfResult(
      bytes: bytes,
      pages: pageStarts.length,
      log: Map.of(log.entries),
      layout: layoutTime,
      paint: paintTime,
      write: writeTime,
      textFallbackImages: resources.images.where((i) => i.isTextFallback).length,
      images: resources.images.length,
    );
  }

  void _footer(PdfCanvas canvas, PdfFontRegistry registry, String text) {
    final font = registry.fallback;
    const size = 8.0;
    final glyphs = <int>[];
    final xs = <double>[];
    var x = 0.0;
    for (final cp in text.runes) {
      final g = font.glyph(cp);
      glyphs.add(g);
      xs.add(x);
      x += font.advance1000(g) * size / 1000;
    }
    final left = format.width - format.margin - x;
    canvas.drawGlyphRun(
      font: font,
      fontSize: size,
      color: const Color(0xFF666666),
      baseline: format.height - format.margin / 2,
      glyphs: glyphs,
      xs: [for (final v in xs) v + left],
    );
  }

  /// Escolhe onde cada página começa.
  ///
  /// Intervalos "inquebráveis": linhas de texto, linhas de tabela, desenhos,
  /// imagens e blocos [KeepTogether]. A quebra é o maior y da página que não
  /// cai dentro de nenhum deles; se não houver, corta no fim da página.
  List<double> _pageBreaks(RenderBox root, double contentHeight, double pageHeight) {
    final intervals = <(double, double)>[];
    void add(double top, double bottom) {
      if (bottom - top > 0.5) intervals.add((top, bottom));
    }

    void visit(RenderObject node) {
      if (node is RenderBox && node.hasSize) {
        final top = node.localToGlobal(Offset.zero, ancestor: root).dy;
        if (node is RenderParagraph) {
          final len = node.text.toPlainText(includeSemanticsLabels: false).length;
          for (final b in node.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len))) {
            add(top + b.top, top + b.bottom);
          }
          return;
        }
        if (node is RenderKeepTogether && node.size.height <= pageHeight) {
          add(top, top + node.size.height);
        } else if (node is RenderCustomPaint && (node.painter != null || node.foregroundPainter != null)) {
          add(top, top + node.size.height);
        } else if (node is RenderImage) {
          add(top, top + node.size.height);
        } else if (node is RenderTable) {
          for (var r = 0; r < node.rows; r++) {
            final row = node.getRowBox(r);
            add(top + row.top, top + row.bottom);
          }
        }
      }
      node.visitChildren(visit);
    }

    visit(root);
    final edges = <double>{for (final (t, b) in intervals) ...[t, b]}.toList()..sort((a, b) => b.compareTo(a));
    bool inside(double y) => intervals.any((iv) => iv.$1 < y - 0.01 && iv.$2 > y + 0.01);

    final starts = <double>[0];
    while (starts.last + pageHeight < contentHeight - 0.5) {
      final start = starts.last;
      final target = start + pageHeight;
      var chosen = target;
      if (inside(target)) {
        chosen = edges.firstWhere(
          (y) => y <= target && y > start + 1 && !inside(y),
          orElse: () => target,
        );
      }
      starts.add(chosen);
    }
    return starts;
  }

  Future<PdfRef> _writeImage(PdfWriter w, ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final rgba = data!.buffer.asUint8List();
    final n = image.width * image.height;
    final rgb = Uint8List(n * 3);
    final alpha = Uint8List(n);
    var opaque = true;
    for (var i = 0; i < n; i++) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
      alpha[i] = rgba[i * 4 + 3];
      if (alpha[i] != 255) opaque = false;
    }
    PdfRef? smask;
    if (!opaque) {
      smask = w.addStream({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Image'),
        'Width': image.width,
        'Height': image.height,
        'ColorSpace': const PdfName('DeviceGray'),
        'BitsPerComponent': 8,
      }, alpha);
    }
    return w.addStream({
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Image'),
      'Width': image.width,
      'Height': image.height,
      'ColorSpace': const PdfName('DeviceRGB'),
      'BitsPerComponent': 8,
      'Interpolate': true,
      'SMask': ?smask,
    }, rgb);
  }
}
