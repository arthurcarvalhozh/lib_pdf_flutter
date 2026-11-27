import 'package:flutter/rendering.dart';

import '../widgets/keep_together.dart';

/// Escolhe onde cada página começa, num conteúdo medido como uma faixa
/// contínua de altura [contentHeight].
///
/// Intervalos "inquebráveis": linhas de texto, linhas de tabela, desenhos,
/// imagens e blocos [KeepTogether] que cabem numa página. A quebra é o maior
/// y da página que não cai dentro de nenhum deles; se não houver, corta no
/// fim da página.
List<double> computePageStarts(RenderBox root, double contentHeight, double pageHeight) {
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
  final edges = <double>{
    for (final (t, b) in intervals) ...[t, b],
  }.toList()..sort((a, b) => b.compareTo(a));
  bool inside(double y) => intervals.any((iv) => iv.$1 < y - 0.01 && iv.$2 > y + 0.01);

  final starts = <double>[0];
  while (starts.last + pageHeight < contentHeight - 0.5) {
    final start = starts.last;
    final target = start + pageHeight;
    var chosen = target;
    if (inside(target)) {
      chosen = edges.firstWhere((y) => y <= target && y > start + 1 && !inside(y), orElse: () => target);
    }
    starts.add(chosen);
  }
  return starts;
}
