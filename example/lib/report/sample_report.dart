import 'package:flutter/material.dart';
import 'package:lib_pdf/lib_pdf.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'sample_chart.dart';
import 'sample_data.dart';

const _headerBlue = Color(0xFFD9E1F3);
const _cardBlue = Color(0xFF2563EB);

/// Relatório de exemplo, no molde do relatório de NOx do diagnox: só widgets
/// do Flutter, do `fl_chart` e do `qr_flutter`, escritos como numa tela.
///
/// É a lista de filhos de um `MultiPage`; a lib decide onde quebrar a página.
class SampleReport {
  const SampleReport(this.data);

  final SampleData data;

  List<Widget> get children => [
    const _Header(),
    const SizedBox(height: 10),
    _Section(
      title: 'Dados da empresa',
      child: _KeyValueTable(
        rows: const [
          ['Empresa', 'Oficina Exemplo Ltda.', 'CNPJ', '00.000.000/0001-00'],
          ['Endereço', 'Rua das Válvulas, 123', 'Cidade', 'São José dos Campos/SP'],
        ],
      ),
    ),
    _Section(
      title: 'Dados do veículo',
      child: _KeyValueTable(
        rows: const [
          ['Montadora', 'Scania', 'Modelo', 'R 450'],
          ['Ano', '2022', 'Placa', 'ABC-1D23'],
        ],
      ),
    ),
    _Section(
      title: 'Resultados encontrados',
      child: _GridTable(
        header: const ['Parâmetro', 'Valor final', 'Mínimo', 'Máximo', 'Referência'],
        rows: data.resultados,
        flex: const [3, 2, 2, 2, 3],
      ),
    ),
    const SizedBox(height: 6),
    Text.rich(
      const TextSpan(
        children: [
          TextSpan(
            text: 'Observação: ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text:
                'texto corrido com acentuação (ação, válvula, coração, pistão) e quebra de linha automática, '
                'medida pelo próprio Flutter. O PDF tem de quebrar nas mesmas palavras que a tela quebraria, '
                'e o texto precisa poder ser selecionado, copiado e pesquisado no leitor.',
          ),
        ],
      ),
    ),
    const SizedBox(height: 10),
    KeepTogether(child: SampleCharts(data: data)),
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: const Color(0xFFFFC3C3),
              padding: const EdgeInsets.all(8),
              child: const Text('ClipRRect + Container: possível obstrução', textAlign: TextAlign.center),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Opacity(
            opacity: 0.35,
            child: Text(
              'Opacity 35 %: este texto sai mais claro',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    KeepTogether(
      child: _Section(
        title: 'Desenho livre (CustomPaint)',
        child: SizedBox(height: 90, child: CustomPaint(painter: _SparkPainter(data))),
      ),
    ),
    _Section(
      title: 'Leituras (tabela longa, para testar a quebra de página)',
      child: _GridTable(
        header: const ['#', 'Tempo', 'NOx', 'O₂', 'Tensão'],
        rows: data.leituras,
        flex: const [1, 2, 2, 2, 2],
      ),
    ),
  ];
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 70,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'LOGO',
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ),
        const Expanded(
          child: Text(
            'Relatório do sensor de NOx',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Column(
          children: [
            const Text('27/11/2026 10:30', style: TextStyle(fontSize: 7)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: QrImageView(
                data: 'https://exemplo.invalid/validar/0000-1111',
                size: 56,
                padding: EdgeInsets.zero,
                gapless: true,
              ),
            ),
            const Text('Autenticação online', style: TextStyle(fontSize: 6)),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: _headerBlue, border: Border.all()),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _KeyValueTable extends StatelessWidget {
  const _KeyValueTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1), 3: FlexColumnWidth(2)},
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < row.length; i++)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(row[i], style: TextStyle(fontWeight: i.isEven ? FontWeight.w600 : FontWeight.normal)),
                ),
            ],
          ),
      ],
    );
  }
}

class _GridTable extends StatelessWidget {
  const _GridTable({required this.header, required this.rows, required this.flex});

  final List<String> header;
  final List<List<String>> rows;
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(),
      columnWidths: {for (var i = 0; i < flex.length; i++) i: FlexColumnWidth(flex[i].toDouble())},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            for (final h in header)
              Padding(
                padding: const EdgeInsets.all(3),
                child: Text(
                  h,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(cell, textAlign: TextAlign.center),
                ),
            ],
          ),
      ],
    );
  }
}

/// Os três cards de gráfico do relatório. O mesmo widget aparece na tela do
/// exemplo e no PDF.
class SampleCharts extends StatelessWidget {
  const SampleCharts({super.key, required this.data});

  final SampleData data;

  @override
  Widget build(BuildContext context) {
    Widget card(String title, String value, Widget chart) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        decoration: BoxDecoration(color: _cardBlue, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            SizedBox(height: 130, child: chart),
          ],
        ),
      ),
    );

    return _Section(
      title: 'Gráficos',
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            card(
              'NOx',
              '${SampleData.fmt(data.nox.last.y, 0)} ppm',
              SampleLineChart(spots: data.nox, maxY: 1500, interval: 500),
            ),
            const SizedBox(width: 6),
            card(
              'Oxigênio',
              '${SampleData.fmt(data.o2.last.y, 2)} %',
              SampleLineChart(spots: data.o2, maxY: 30, interval: 5),
            ),
            const SizedBox(width: 6),
            card(
              'Tensão e consumo',
              '${SampleData.fmt(data.tensao.last.y, 2)} V · ${SampleData.fmt(data.corrente.last.y, 2)} A',
              SampleLineChart(
                spots: data.tensao,
                maxY: 30,
                interval: 5,
                secondarySpots: data.corrente,
                secondaryMaxY: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desenho livre com a API de canvas do Flutter (Y para baixo), como o
/// gráfico dos testes especiais do diagnox, mais um texto pintado com
/// TextPainter (caso que vira imagem no PDF).
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data);

  final SampleData data;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), grid);
    }
    final values = data.nox.map((s) => s.y).toList();
    final path = Path();
    final area = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - values[i] / 1100 * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      area.lineTo(x, y);
    }
    area
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0x552290FF));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2290FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(size.width, size.height - values.last / 1100 * size.height),
      3,
      Paint()..color = const Color(0xFF2290FF),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'texto via TextPainter',
        style: TextStyle(fontFamily: 'Montserrat', fontSize: 8, color: Color(0xFF475569)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => false;
}
