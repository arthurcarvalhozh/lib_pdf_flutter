import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../canvas/pdf_canvas.dart';
import '../document/pdf_build_result.dart';
import '../document/pdf_writer.dart';
import '../image/image_writer.dart';
import '../pagination/page_breaks.dart';
import '../render/offscreen_tree.dart';
import '../render/pdf_painting_context.dart';
import '../text/pdf_font.dart';
import '../text/pdf_text.dart';
import 'multi_page.dart';

/// Um documento PDF feito de widgets do Flutter.
///
/// ```dart
/// final bytes = await PdfDocument(
///   fonts: fonts,
///   pages: [
///     MultiPage(children: [
///       Text('Relatório', style: TextStyle(fontSize: 18)),
///       Table(...),
///       KeepTogether(child: MeuGrafico(...)),
///     ]),
///   ],
/// ).build();
/// ```
///
/// Os widgets são montados e medidos fora da tela pelo próprio Flutter, e o
/// desenho deles vai para o PDF em vetor: texto real, linhas e curvas.
class PdfDocument {
  PdfDocument({required this.fonts, required this.pages, this.title, this.author, this.textStyle})
    : assert(fonts.isNotEmpty, 'Registre pelo menos uma fonte.');

  /// Fontes que o PDF pode usar. A primeira é a padrão.
  final List<PdfFont> fonts;

  final List<MultiPage> pages;

  /// Metadados do arquivo.
  final String? title;
  final String? author;

  /// Estilo de texto padrão, como um `DefaultTextStyle` em volta de tudo.
  /// Sem ele: a primeira fonte registrada, tamanho 10, preto.
  final TextStyle? textStyle;

  /// Gera o PDF e devolve os bytes.
  ///
  /// Em modo debug, escreve no console o que não saiu fiel ao Flutter.
  Future<Uint8List> build() async {
    final result = await buildWithReport();
    if (kDebugMode && result.warnings.isNotEmpty) {
      debugPrint('lib_pdf: ${result.warnings.entries.map((e) => '${e.key} ×${e.value}').join('; ')}');
    }
    return result.bytes;
  }

  /// Gera o PDF e devolve também os avisos, os tempos e as contagens.
  Future<PdfBuildResult> buildWithReport() async {
    final log = PdfLog();
    final resources = PdfResources();
    final registry = PdfFontRegistry(resources, log);
    for (final f in fonts) {
      registry.register(f.family, f.bytes, weight: f.weight.value);
    }
    final paragraphs = PdfParagraphPainter(registry, log);
    final style = textStyle ?? TextStyle(fontFamily: fonts.first.family, fontSize: 10, color: const Color(0xFF000000));

    final pageOps = <(MultiPage, String)>[];
    var layoutTime = Duration.zero;
    var paintTime = Duration.zero;
    final sw = Stopwatch();

    for (final spec in pages) {
      // 1. Monta e mede a árvore fora da tela.
      sw
        ..reset()
        ..start();
      final tree = await OffscreenTree.mount(
        DefaultTextStyle(
          style: style,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spec.children,
          ),
        ),
        width: spec.contentWidth,
        mediaSize: spec.format.size,
      );
      final root = tree.root;
      final contentHeight = root.size.height;
      final starts = computePageStarts(root, contentHeight, spec.contentHeight);
      layoutTime += sw.elapsed;

      // 2. Pinta cada página como uma janela sobre o conteúdo contínuo.
      sw
        ..reset()
        ..start();
      final margin = spec.margin;
      for (var i = 0; i < starts.length; i++) {
        final start = starts[i];
        final end = i + 1 < starts.length ? starts[i + 1] : contentHeight;
        final window = Rect.fromLTWH(margin.left, margin.top, spec.contentWidth, end - start);
        final canvas = PdfCanvas(resources, log, visibleWindow: window)
          ..writeRaw('1 0 0 -1 0 ${PdfWriter.num(spec.format.height)} cm\n')
          ..save()
          ..clipRect(window)
          ..translate(margin.left, margin.top - start);
        PdfPaintingContext(canvas, paragraphs, log, Offset.zero & root.size).paintChild(root, Offset.zero);
        canvas.restore();
        pageOps.add((spec, canvas.ops.toString()));
      }
      paintTime += sw.elapsed;
      tree.dispose();
    }

    // 3. Escreve o arquivo.
    sw
      ..reset()
      ..start();
    final w = PdfWriter();
    final catalog = w.reserve();
    final pagesRef = w.reserve();
    final fontRefs = <String, Object>{for (final e in resources.fonts.entries) e.key: e.value.write(w)};
    final xobjects = <String, Object>{};
    for (final pending in resources.images) {
      xobjects[pending.name] = await writeImage(w, pending.image);
      // Só as imagens criadas pela lib são dela para descartar; as dos
      // widgets pertencem ao cache de imagens do Flutter.
      if (pending.isTextFallback) pending.image.dispose();
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
    for (final (spec, ops) in pageOps) {
      final contents = w.addStream({}, ops.codeUnits);
      kids.add(
        w.add(<String, Object>{
          'Type': const PdfName('Page'),
          'Parent': pagesRef,
          'MediaBox': [0, 0, spec.format.width, spec.format.height],
          'Contents': contents,
          'Resources': resourcesRef,
        }),
      );
    }
    w.set(pagesRef, <String, Object>{'Type': const PdfName('Pages'), 'Kids': kids, 'Count': kids.length});
    w.set(catalog, <String, Object>{'Type': const PdfName('Catalog'), 'Pages': pagesRef});
    final info = w.add(<String, Object>{
      if (title != null) 'Title': PdfString(title!),
      if (author != null) 'Author': PdfString(author!),
      'Producer': const PdfString('lib_pdf'),
    });
    final bytes = w.build(root: catalog, info: info);
    final writeTime = sw.elapsed;

    return PdfBuildResult(
      bytes: bytes,
      pageCount: kids.length,
      warnings: Map.unmodifiable(log.entries),
      layoutTime: layoutTime,
      paintTime: paintTime,
      writeTime: writeTime,
      imageCount: resources.images.length,
      rasterizedTextCount: resources.images.where((i) => i.isTextFallback).length,
    );
  }
}
