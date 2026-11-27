import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Gráfico de linha do `fl_chart`, escrito como numa tela, com uma série
/// opcional num eixo secundário à direita.
///
/// O mesmo widget serve para a tela e para o PDF: a lib pinta o que o
/// `fl_chart` desenha, em vetor, e os rótulos dos eixos saem como texto.
class SampleLineChart extends StatelessWidget {
  const SampleLineChart({
    super.key,
    required this.spots,
    required this.maxY,
    required this.interval,
    this.secondarySpots,
    this.secondaryMaxY = 1,
    this.secondaryInterval = 1,
  });

  final List<FlSpot> spots;
  final double maxY;
  final double interval;
  final List<FlSpot>? secondarySpots;
  final double secondaryMaxY;
  final double secondaryInterval;

  static const _secondaryColor = Color(0xFFFFEB3B);

  @override
  Widget build(BuildContext context) {
    final secondary = secondarySpots;
    // A série secundária é desenhada na escala do eixo principal.
    final scale = maxY / secondaryMaxY;
    Widget label(String text, Color color) => Text(
      text,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.last.x,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.35), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: const BorderSide(color: Colors.white),
            bottom: const BorderSide(color: Colors.white),
            right: secondary == null ? BorderSide.none : const BorderSide(color: _secondaryColor),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, meta) => label(meta.formattedValue, Colors.white),
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: secondary != null,
              reservedSize: 18,
              interval: secondaryInterval * scale,
              getTitlesWidget: (value, meta) => label((value / scale).toStringAsFixed(0), _secondaryColor),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.white,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          if (secondary != null)
            LineChartBarData(
              spots: [for (final s in secondary) FlSpot(s.x, s.y * scale)],
              isCurved: true,
              color: _secondaryColor,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}
