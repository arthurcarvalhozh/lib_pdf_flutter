import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'bench/current_method.dart';
import 'pdf/pdf_document.dart';
import 'report/poc_report.dart';
import 'report/sample_data.dart';

/// App de benchmark da prova de conceito: gera o mesmo relatório pelo método
/// atual (foto do gráfico + package:pdf) e pela lib nova, cinco vezes cada,
/// e escreve as medianas no log (linhas com o prefixo BENCH).
void main() => runApp(const PocApp());

class PocApp extends StatelessWidget {
  const PocApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: BenchPage());
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final _chartKey = GlobalKey();
  final _data = PocData();
  final _lines = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(seconds: 1), _bench));
  }

  void _out(String line) {
    debugPrint('BENCH $line');
    setState(() => _lines.add(line));
  }

  static Duration _median(List<Duration> d) => (List.of(d)..sort())[d.length ~/ 2];

  Future<void> _bench() async {
    final screen = MediaQuery.of(context).size;
    final fonts = <PdfFontSpec>[
      for (final (name, weight) in [('Regular', 400), ('SemiBold', 600), ('Bold', 700)])
        PdfFontSpec('Montserrat', (await rootBundle.load('assets/fonts/Montserrat-$name.ttf')).buffer.asUint8List(), weight: weight),
    ];
    final current = await CurrentMethod.load();
    final boundary = _chartKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    _out('aparelho: tela ${screen.width.toStringAsFixed(0)}x${screen.height.toStringAsFixed(0)} lógicos, '
        'gráfico capturado ${boundary.size.width.toStringAsFixed(0)}x${boundary.size.height.toStringAsFixed(0)} × 3');

    Future<PdfResult> renderNew() => PdfDocumentPoc(fonts: fonts).render(PocReport(data: _data));

    // Aquecimento dos dois caminhos.
    await current.generate(boundary, _data);
    await renderNew();

    const runs = 5;
    final currentTotal = <Duration>[];
    final currentCapture = <Duration>[];
    var currentBytes = 0;
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      final (bytes, capture) = await current.generate(boundary, _data);
      currentTotal.add(sw.elapsed);
      currentCapture.add(capture);
      currentBytes = bytes.length;
      if (i == 0) await File('${Directory.systemTemp.path}/poc_atual.pdf').writeAsBytes(bytes);
    }

    final newTotal = <Duration>[];
    final newLayout = <Duration>[];
    final newPaint = <Duration>[];
    final newWrite = <Duration>[];
    var newBytes = 0;
    var pages = 0;
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      final r = await renderNew();
      newTotal.add(sw.elapsed);
      newLayout.add(r.layout);
      newPaint.add(r.paint);
      newWrite.add(r.write);
      newBytes = r.bytes.length;
      pages = r.pages;
      if (i == 0) await File('${Directory.systemTemp.path}/poc_nova.pdf').writeAsBytes(r.bytes);
    }

    _out('atual: total ${_median(currentTotal).inMilliseconds} ms (captura ${_median(currentCapture).inMilliseconds} ms), '
        '$currentBytes bytes');
    _out('nova: total ${_median(newTotal).inMilliseconds} ms (layout ${_median(newLayout).inMilliseconds} ms, '
        'pintura ${_median(newPaint).inMilliseconds} ms, escrita ${_median(newWrite).inMilliseconds} ms), '
        '$newBytes bytes, $pages páginas');
    _out('FIM');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mesmo enquadramento do diagnox: largura da tela, 58 % da altura.
            RepaintBoundary(
              key: _chartKey,
              child: SizedBox(
                height: size.height * 0.58,
                child: DefaultTextStyle(
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.black),
                  child: SingleChildScrollView(child: PocCharts(data: _data)),
                ),
              ),
            ),
            Expanded(child: ListView(children: [for (final l in _lines) Text(l)])),
          ],
        ),
      ),
    );
  }
}
