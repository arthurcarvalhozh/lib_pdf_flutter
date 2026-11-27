import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Confere a estrutura de um PDF escrito pela lib e devolve os problemas
/// encontrados (lista vazia: arquivo bem formado).
///
/// Não substitui um validador completo (o CI também roda `qpdf --check`),
/// mas pega os erros que um escritor PDF costuma cometer: deslocamento
/// errado na xref, `/Length` que não bate, stream que não descomprime,
/// referência para objeto inexistente, árvore de páginas inconsistente e
/// `q`/`Q` ou `BT`/`ET` desequilibrados.
List<String> validatePdf(Uint8List bytes) {
  final problems = <String>[];
  final text = latin1.decode(bytes);

  if (!RegExp(r'^%PDF-1\.[0-7]\n').hasMatch(text)) problems.add('cabeçalho %PDF-1.x ausente');
  if (!RegExp(r'%%EOF\s*$').hasMatch(text)) problems.add('arquivo não termina com %%EOF');

  // startxref → xref
  final startxref = RegExp(r'startxref\s+(\d+)\s+%%EOF\s*$').firstMatch(text);
  if (startxref == null) {
    problems.add('startxref ausente');
    return problems;
  }
  final xrefAt = int.parse(startxref.group(1)!);
  if (!text.startsWith('xref', xrefAt)) {
    problems.add('startxref ($xrefAt) não aponta para a tabela xref');
    return problems;
  }

  // Tabela xref: uma subseção "0 N", entradas de 20 bytes.
  final head = RegExp(r'xref\n0 (\d+)\n').matchAsPrefix(text, xrefAt);
  if (head == null) {
    problems.add('tabela xref sem a subseção "0 N"');
    return problems;
  }
  final size = int.parse(head.group(1)!);
  final offsets = <int, int>{};
  var at = head.end;
  for (var i = 0; i < size; i++) {
    final entry = text.substring(at, at + 20);
    final m = RegExp(r'^(\d{10}) (\d{5}) ([nf])(?: \n|\r\n)$').firstMatch(entry);
    if (m == null) {
      problems.add('entrada $i da xref malformada: ${jsonEncode(entry)}');
      return problems;
    }
    if (m.group(3) == 'n') offsets[i] = int.parse(m.group(1)!);
    at += 20;
  }
  if (offsets.containsKey(0)) problems.add('objeto 0 marcado como em uso');

  // Trailer.
  final trailerAt = text.indexOf('trailer', at);
  final trailer = trailerAt < 0 ? '' : text.substring(trailerAt, text.indexOf('startxref', trailerAt));
  final trailerSize = RegExp(r'/Size (\d+)').firstMatch(trailer);
  if (trailerSize == null || int.parse(trailerSize.group(1)!) != size) {
    problems.add('/Size do trailer não bate com a xref ($size)');
  }
  final root = RegExp(r'/Root (\d+) 0 R').firstMatch(trailer);
  if (root == null) problems.add('trailer sem /Root');
  if (!RegExp(r'/ID \[<[0-9a-fA-F]{32}> <[0-9a-fA-F]{32}>\]').hasMatch(trailer)) {
    problems.add('trailer sem /ID de 16 bytes');
  }

  // Objetos: deslocamento, dicionário e stream.
  final dicts = <int, String>{};
  final streams = <int, Uint8List>{};
  for (final MapEntry(key: id, value: offset) in offsets.entries) {
    if (!text.startsWith('$id 0 obj', offset)) {
      problems.add('xref do objeto $id aponta para $offset, que não é "$id 0 obj"');
      continue;
    }
    final end = text.indexOf('endobj', offset);
    if (end < 0) {
      problems.add('objeto $id sem endobj');
      continue;
    }
    final body = text.substring(offset, end);
    final streamAt = body.indexOf('stream\n');
    if (streamAt < 0 || !body.substring(0, streamAt).trimRight().endsWith('>>')) {
      dicts[id] = body;
      continue;
    }
    final dict = body.substring(0, streamAt);
    dicts[id] = dict;
    final dataStart = offset + streamAt + 'stream\n'.length;
    final dataEnd = text.indexOf('\nendstream', dataStart);
    final length = RegExp(r'/Length (\d+)').firstMatch(dict);
    if (length == null) {
      problems.add('stream do objeto $id sem /Length');
      continue;
    }
    if (int.parse(length.group(1)!) != dataEnd - dataStart) {
      problems.add('/Length do objeto $id é ${length.group(1)}, mas o stream tem ${dataEnd - dataStart} bytes');
      continue;
    }
    final raw = bytes.sublist(dataStart, dataEnd);
    if (dict.contains('/FlateDecode')) {
      try {
        streams[id] = Uint8List.fromList(zlib.decode(raw));
      } on Object catch (e) {
        problems.add('stream do objeto $id não descomprime: $e');
      }
    } else {
      streams[id] = raw;
    }
  }

  // Referências.
  for (final MapEntry(key: id, value: dict) in dicts.entries) {
    for (final m in RegExp(r'(\d+) 0 R').allMatches(dict)) {
      final target = int.parse(m.group(1)!);
      if (!offsets.containsKey(target)) problems.add('objeto $id referencia o objeto $target, que não existe');
    }
  }
  for (final m in RegExp(r'(\d+) 0 R').allMatches(trailer)) {
    if (!offsets.containsKey(int.parse(m.group(1)!))) problems.add('trailer referencia objeto inexistente');
  }
  if (root == null) return problems;

  // Árvore de páginas.
  final catalog = dicts[int.parse(root.group(1)!)] ?? '';
  final pagesRef =
      RegExp(r'/Type /Catalog\b.*?/Pages (\d+) 0 R', dotAll: true).firstMatch(catalog) ??
      RegExp(r'/Pages (\d+) 0 R').firstMatch(catalog);
  if (!catalog.contains('/Type /Catalog') || pagesRef == null) {
    problems.add('/Root não é um /Catalog com /Pages');
    return problems;
  }
  final pagesId = int.parse(pagesRef.group(1)!);
  final pages = dicts[pagesId] ?? '';
  final kids = RegExp(r'/Kids \[([^\]]*)\]').firstMatch(pages);
  final count = RegExp(r'/Count (\d+)').firstMatch(pages);
  if (!pages.contains('/Type /Pages') || kids == null || count == null) {
    problems.add('objeto /Pages malformado');
    return problems;
  }
  final kidIds = RegExp(r'(\d+) 0 R').allMatches(kids.group(1)!).map((m) => int.parse(m.group(1)!)).toList();
  if (kidIds.length != int.parse(count.group(1)!)) problems.add('/Count não bate com /Kids');
  for (final kid in kidIds) {
    final page = dicts[kid] ?? '';
    if (!RegExp(r'/Type /Page\b').hasMatch(page)) problems.add('kid $kid não é /Page');
    if (!page.contains('/Parent $pagesId 0 R')) problems.add('página $kid sem /Parent para /Pages');
    if (!RegExp(r'/MediaBox \[0 0 [\d.]+ [\d.]+\]').hasMatch(page)) problems.add('página $kid sem /MediaBox válida');
    if (!page.contains('/Resources')) problems.add('página $kid sem /Resources');
    final contents = RegExp(r'/Contents (\d+) 0 R').firstMatch(page);
    final ops = contents == null ? null : streams[int.parse(contents.group(1)!)];
    if (ops == null) {
      problems.add('página $kid sem conteúdo');
      continue;
    }
    problems.addAll(_balance(latin1.decode(ops)).map((p) => 'página $kid: $p'));
  }
  return problems;
}

/// `q`/`Q` e `BT`/`ET` equilibrados, ignorando o que está dentro de strings.
List<String> _balance(String ops) {
  final clean = ops.replaceAll(RegExp(r'<(?!<)[0-9A-Fa-f\s]*>'), ' ').replaceAll(RegExp(r'\((?:\\.|[^\\)])*\)'), ' ');
  var q = 0;
  var bt = 0;
  for (final token in clean.split(RegExp(r'[\s\[\]]+'))) {
    switch (token) {
      case 'q':
        q++;
      case 'Q':
        if (--q < 0) return ['Q sem q correspondente'];
      case 'BT':
        if (++bt > 1) return ['BT dentro de BT'];
      case 'ET':
        if (--bt < 0) return ['ET sem BT'];
    }
  }
  return [if (q != 0) '$q q sem Q', if (bt != 0) 'BT sem ET'];
}
