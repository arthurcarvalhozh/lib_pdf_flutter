import 'package:flutter/widgets.dart';

import '../document/page_format.dart';

/// Conteúdo que flui por quantas páginas forem necessárias.
///
/// Os [children] são widgets comuns do Flutter, empilhados como numa
/// `Column` com `crossAxisAlignment: CrossAxisAlignment.stretch`. A lib mede
/// tudo na largura útil da página e quebra a página entre linhas de texto,
/// linhas de tabela e blocos `KeepTogether`, nunca no meio deles.
class MultiPage {
  const MultiPage({this.format = PdfPageFormat.a4, this.margin = const EdgeInsets.all(28), required this.children});

  final PdfPageFormat format;
  final EdgeInsets margin;
  final List<Widget> children;

  /// Largura disponível para o conteúdo.
  double get contentWidth => format.width - margin.horizontal;

  /// Altura disponível para o conteúdo em cada página.
  double get contentHeight => format.height - margin.vertical;
}
