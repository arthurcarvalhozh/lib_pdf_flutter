import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../report/sample_data.dart';

/// O método de hoje, como o diagnox faz: foto do gráfico na tela
/// (`RepaintBoundary.toImage` com `pixelRatio: 3`, PNG) colada num PDF do
/// `package:pdf` com as mesmas tabelas do relatório da prova.
class CurrentMethod {
  CurrentMethod._(this._theme);

  final pw.ThemeData _theme;

  static Future<CurrentMethod> load() async {
    Future<pw.Font> font(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-$name.ttf'));
    return CurrentMethod._(pw.ThemeData.withFont(base: await font('Regular'), bold: await font('Bold')));
  }

  /// Devolve o PDF e o tempo só da captura.
  Future<(Uint8List, Duration)> generate(RenderRepaintBoundary chartBoundary, PocData data) async {
    final capture = Stopwatch()..start();
    final image = await chartBoundary.toImage(pixelRatio: 3.0);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    capture.stop();

    final doc = pw.Document(theme: _theme);
    pw.Widget section(String title, pw.Widget child) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFD9E1F3), border: pw.Border.all()),
              child: pw.Text(title, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            child,
            pw.SizedBox(height: 8),
          ],
        );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Center(child: pw.Text('Relatório do sensor de NOx', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 10),
          section(
            'Dados da empresa',
            pw.TableHelper.fromTextArray(data: const [
              ['Empresa', 'Oficina Exemplo Ltda.', 'CNPJ', '00.000.000/0001-00'],
              ['Endereço', 'Rua das Válvulas, 123', 'Cidade', 'São José dos Campos/SP'],
            ]),
          ),
          section(
            'Resultados encontrados',
            pw.TableHelper.fromTextArray(
              headers: const ['Parâmetro', 'Valor final', 'Mínimo', 'Máximo', 'Referência'],
              data: data.resultados,
            ),
          ),
          section('Gráficos', pw.Image(pw.MemoryImage(png))),
          pw.TableHelper.fromTextArray(headers: const ['#', 'Tempo', 'NOx', 'O2', 'Tensão'], data: data.leituras),
        ],
      ),
    );
    final bytes = await doc.save();
    return (bytes, capture.elapsed);
  }
}
