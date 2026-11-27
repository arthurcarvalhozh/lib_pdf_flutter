// Cópia fiel de `NoxGrafico` do diagnox
// (diagnox/lib/src/core/components/dashboard/graph/nox/nox_grafico.dart),
// sem nenhuma adaptação para o PDF: a prova de conceito precisa mostrar que o
// widget da tela funciona no papel como está.
// ignore_for_file: file_names

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

///Renderiza apenas o gráfico (LineChart) com seus eixos, grades e linhas

class NoxGrafico extends StatelessWidget {
  final String title;
  final double maxY;
  final double minY;
  final double interval;
  final double? secondaryInterval;
  final List<FlSpot> spots;
  final bool showGrid;
  final bool showDecimals;
  final double? minX;
  final double? maxX;
  final List<FlSpot>? secondarySpots;
  final Color? secondaryLineColor;
  final double? secondaryMaxY;
  final double? secondaryMinY;
  final String secondaryUnit;
  final String unit;
  final double? reservedSize;

  const NoxGrafico({
    super.key,
    required this.title,
    required this.maxY,
    required this.minY,
    required this.interval,
    this.secondaryInterval,
    required this.spots,
    this.showGrid = true,
    this.showDecimals = false,
    this.maxX,
    this.minX,
    this.secondarySpots,
    this.secondaryLineColor,
    this.secondaryMaxY,
    this.secondaryMinY,
    required this.secondaryUnit,
    required this.unit,
    this.reservedSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: showGrid,
          horizontalInterval: interval,
          verticalInterval: null,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            if (value >= minY && value <= maxY && _isMultipleOf(value, interval)) {
              return FlLine(
                color: Colors.grey[400]!,
                strokeWidth: 0.5,
              );
            }

            return const FlLine(strokeWidth: 0);
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: secondaryInterval ?? interval,
              //reservedSize: 5,
              reservedSize: MediaQuery.of(context).size.height * 0.008,
              getTitlesWidget: (value, meta) {
                if (secondarySpots != null) {
                  final scaledValue = value * (secondaryMaxY ?? maxY) / maxY;
                  if (scaledValue >= (secondaryMinY ?? 0) && scaledValue <= (secondaryMaxY ?? maxY) && _isMultipleOf(scaledValue, secondaryInterval ?? interval)) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 2.0),
                      child: Text(
                        scaledValue.toStringAsFixed(showDecimals ? 1 : 0),
                        style: TextStyle(
                          color: Colors.yellow,
                          fontSize: MediaQuery.of(context).size.height * 0.017,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                }

                return Container();
              },
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              interval: interval,
              showTitles: true,
              reservedSize: reservedSize ?? MediaQuery.of(context).size.height * 0.06,
              getTitlesWidget: (value, meta) {
                if (value < minY || value > maxY || !_isMultipleOf(value, interval)) {
                  return Container();
                }

                final label = (maxY == 2) ? value.toStringAsFixed(1) : value.toStringAsFixed(showDecimals ? 1 : 0);

                return Padding(
                  padding: EdgeInsets.only(right: MediaQuery.of(context).size.height * 0.01),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.height * 0.017,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ),





        borderData: FlBorderData(
          show: true,
          border: Border(
            left: const BorderSide(color: Colors.white, width: 0.5),
            bottom: const BorderSide(color: Colors.white, width: 0.5),
            right: secondaryMaxY != null ? const BorderSide(color: Colors.yellow, width: 0.5) : BorderSide.none,
          ),
        ),
        minY: minY,
        maxY: maxY,
        minX: minX ?? 0,
        maxX: maxX,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBorder: const BorderSide(color: Colors.white),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map(
                (LineBarSpot touchedSpot) {
                  final isSecondaryLine = touchedSpot.barIndex == 1;
                  final value = isSecondaryLine ? (touchedSpot.y * (secondaryMaxY ?? maxY) / maxY).toStringAsFixed(3) : touchedSpot.y.toStringAsFixed(0);
                  final unitt = isSecondaryLine ? secondaryUnit : unit;

                  return LineTooltipItem(
                    '$value $unitt',
                    TextStyle(
                      color: isSecondaryLine ? Colors.yellow : Colors.white,
                      //fontSize: 12,
                      fontSize: MediaQuery.of(context).size.height * 0.026,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                    ),
                  );
                },
              ).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.white,
            barWidth: 2,
            dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) {
                  return spot == spots.last;
                }),
          ),
          if (secondarySpots != null)
            LineChartBarData(
              spots: secondarySpots!.map((spot) => FlSpot(spot.x, spot.y * maxY / (secondaryMaxY ?? maxY))).toList(),
              color: secondaryLineColor ?? Colors.blue,
              isCurved: true,
              barWidth: 1.2,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}


bool _isMultipleOf(double value, double step) {
  if (step == 0) return false;
  final ratio = value / step;
  return (ratio - ratio.round()).abs() < 1e-4;
}
