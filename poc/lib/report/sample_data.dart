import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

/// Dados fictícios de um teste de sensor de NOx, no formato que o diagnox
/// grava (`calculosValidados` e `calculosTC`).
class PocData {
  PocData({int samples = 120})
      : nox = [for (var i = 0; i < samples; i++) FlSpot(i.toDouble(), 120 + 900 * math.pow(math.sin(i / 18), 2) + 40 * math.sin(i * 1.7))],
        o2 = [for (var i = 0; i < samples; i++) FlSpot(i.toDouble(), 20.4 + 0.6 * math.sin(i / 9))],
        tensao = [for (var i = 0; i < samples; i++) FlSpot(i.toDouble(), 13.6 + 0.4 * math.sin(i / 7))],
        corrente = [for (var i = 0; i < samples; i++) FlSpot(i.toDouble(), 0.9 + 0.5 * math.cos(i / 11))];

  final List<FlSpot> nox;
  final List<FlSpot> o2;
  final List<FlSpot> tensao;
  final List<FlSpot> corrente;

  double get maxX => (nox.length - 1).toDouble();

  static String fmt(double v, int d) => v.toStringAsFixed(d).replaceAll('.', ',');

  static double minOf(List<FlSpot> s) => s.map((e) => e.y).reduce(math.min);
  static double maxOf(List<FlSpot> s) => s.map((e) => e.y).reduce(math.max);

  /// Linhas da tabela de resultados: parâmetro, final, mínimo, máximo, referência.
  List<List<String>> get resultados => [
        ['NOx', '${fmt(nox.last.y, 0)} ppm', '${fmt(minOf(nox), 0)} ppm', '${fmt(maxOf(nox), 0)} ppm', 'Menor que 30 ppm'],
        ['O₂', '${fmt(o2.last.y, 2)} %', '${fmt(minOf(o2), 2)} %', '${fmt(maxOf(o2), 2)} %', 'Entre 19 e 21 %'],
        ['Tensão média', '${fmt(tensao.last.y, 2)} V', '${fmt(minOf(tensao), 2)} V', '${fmt(maxOf(tensao), 2)} V', '-'],
        ['Consumo médio', '${fmt(corrente.last.y, 3)} A', '${fmt(minOf(corrente), 3)} A', '${fmt(maxOf(corrente), 3)} A', '-'],
      ];

  /// Linhas longas, para forçar a quebra de página.
  List<List<String>> get leituras => [
        for (var i = 0; i < nox.length; i += 3)
          ['${i + 1}', '00:${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}', '${fmt(nox[i].y, 0)} ppm', '${fmt(o2[i].y, 2)} %', '${fmt(tensao[i].y, 2)} V'],
      ];
}
