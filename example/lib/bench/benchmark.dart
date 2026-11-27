import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lib_pdf/lib_pdf.dart';

import '../report/sample_data.dart';
import '../report/sample_report.dart';
import 'current_method.dart';

/// Mede a geração do relatório de exemplo pela lib e pelo método atual
/// (foto do gráfico + package:pdf): uma rodada de aquecimento e a mediana de
/// [runs] gerações de cada. Escreve linhas com [out]; a última é `FIM`.
Future<void> runBenchmark({
  required List<PdfFont> fonts,
  required SampleData data,
  required RenderRepaintBoundary chartBoundary,
  required Size screen,
  required void Function(String) out,
  int runs = 5,
}) async {
  out(
    'aparelho: tela ${screen.width.toStringAsFixed(0)}x${screen.height.toStringAsFixed(0)} lógicos, '
    'gráfico capturado ${chartBoundary.size.width.toStringAsFixed(0)}x'
    '${chartBoundary.size.height.toStringAsFixed(0)} × 3',
  );

  final current = await CurrentMethod.load();
  Future<PdfBuildResult> lib() => PdfDocument(
    fonts: fonts,
    textStyle: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.black),
    pages: [MultiPage(children: SampleReport(data).children)],
  ).buildWithReport();

  await current.generate(chartBoundary, data);
  await lib();

  final currentTotal = <Duration>[];
  final currentCapture = <Duration>[];
  var currentBytes = 0;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    final (bytes, capture) = await current.generate(chartBoundary, data);
    currentTotal.add(sw.elapsed);
    currentCapture.add(capture);
    currentBytes = bytes.length;
    if (i == 0) await File('${Directory.systemTemp.path}/bench_atual.pdf').writeAsBytes(bytes);
  }

  final libTotal = <Duration>[];
  final libLayout = <Duration>[];
  final libPaint = <Duration>[];
  final libWrite = <Duration>[];
  late PdfBuildResult last;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    last = await lib();
    libTotal.add(sw.elapsed);
    libLayout.add(last.layoutTime);
    libPaint.add(last.paintTime);
    libWrite.add(last.writeTime);
    if (i == 0) await File('${Directory.systemTemp.path}/bench_lib.pdf').writeAsBytes(last.bytes);
  }

  int ms(List<Duration> d) => (List.of(d)..sort())[d.length ~/ 2].inMilliseconds;
  out('atual: total ${ms(currentTotal)} ms (captura ${ms(currentCapture)} ms), $currentBytes bytes');
  out(
    'lib: total ${ms(libTotal)} ms (layout ${ms(libLayout)} ms, pintura ${ms(libPaint)} ms, '
    'escrita ${ms(libWrite)} ms), ${last.bytes.length} bytes, ${last.pageCount} páginas',
  );
  for (final w in last.warnings.entries) {
    out('aviso: ${w.key} ×${w.value}');
  }
  out('FIM');
}
