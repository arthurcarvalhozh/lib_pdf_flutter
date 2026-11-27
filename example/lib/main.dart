import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'bench/benchmark.dart';
import 'report/sample_data.dart';
import 'report/sample_report.dart';

/// Com `--dart-define=BENCH=true`, o app mede a geração assim que abre e
/// escreve o resultado no log (linhas com o prefixo BENCH). É assim que o
/// `benchmark/run_android.sh` usa o app.
const _benchOnStart = bool.fromEnvironment('BENCH');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'lib_pdf',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2563EB), fontFamily: 'Montserrat'),
    home: const ExamplePage(),
  );
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final _chartKey = GlobalKey();
  final _data = SampleData();
  final _lines = <String>[];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (_benchOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(seconds: 1), _benchmark));
    }
  }

  void _out(String line) {
    debugPrint('BENCH $line');
    if (mounted) setState(() => _lines.add(line));
  }

  Future<List<PdfFont>> _fonts() async => [
    for (final (file, weight) in [
      ('Regular', FontWeight.w400),
      ('SemiBold', FontWeight.w600),
      ('Bold', FontWeight.w700),
    ])
      await PdfFont.asset('assets/fonts/Montserrat-$file.ttf', family: 'Montserrat', weight: weight),
  ];

  Future<void> _generate() async {
    setState(() => _busy = true);
    final result = await PdfDocument(
      fonts: await _fonts(),
      title: 'Relatório de exemplo',
      textStyle: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.black),
      pages: [MultiPage(children: SampleReport(_data).children)],
    ).buildWithReport();
    final file = File('${Directory.systemTemp.path}/relatorio_exemplo.pdf');
    await file.writeAsBytes(result.bytes);
    setState(() {
      _busy = false;
      _lines.add(
        '${result.pageCount} páginas, ${result.bytes.length ~/ 1024} KB, '
        '${result.totalTime.inMilliseconds} ms → ${file.path}',
      );
      for (final w in result.warnings.entries) {
        _lines.add('  aviso: ${w.key} ×${w.value}');
      }
    });
  }

  Future<void> _benchmark() async {
    setState(() => _busy = true);
    final boundary = _chartKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screen = MediaQuery.sizeOf(context);
    await runBenchmark(fonts: await _fonts(), data: _data, chartBoundary: boundary, screen: screen, out: _out);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('lib_pdf: exemplo')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // O mesmo widget de gráficos que vai para o PDF. O benchmark também
          // usa este trecho da tela para medir o método atual (captura).
          RepaintBoundary(
            key: _chartKey,
            child: SizedBox(
              height: size.height * 0.4,
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.black),
                child: SingleChildScrollView(child: SampleCharts(data: _data)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: _busy ? null : _generate, child: const Text('Gerar PDF')),
                OutlinedButton(onPressed: _busy ? null : _benchmark, child: const Text('Medir')),
              ],
            ),
          ),
          Expanded(child: ListView(children: [for (final l in _lines) Text(l)])),
        ],
      ),
    );
  }
}
