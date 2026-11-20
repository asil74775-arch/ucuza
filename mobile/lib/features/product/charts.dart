import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';

/// Fiyat geçmişi ve puanlama geçmişi için zaman serisi grafiği.
class HistoryChart extends StatelessWidget {
  const HistoryChart({super.key, required this.points, required this.valueKey, this.money = false, this.minY, this.maxY});
  final List<Map> points;
  final String valueKey;
  final bool money;
  final double? minY, maxY;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const Center(child: Text('Yeterli geçmiş verisi yok'));
    final xs = points.map((p) => DateTime.parse(p['t']).millisecondsSinceEpoch.toDouble()).toList();
    final ys = points.map((p) => ((p[valueKey] ?? 0) as num).toDouble()).toList();
    final color = Theme.of(context).colorScheme.primary;
    final fmt = DateFormat('MMM yy', 'tr_TR');
    final lo = ys.reduce((a, b) => a < b ? a : b), hi = ys.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) * .1 + 1;
    return LineChart(LineChartData(
      minY: minY ?? lo - pad,
      maxY: maxY ?? hi + pad,
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: money ? 56 : 28,
            getTitlesWidget: (v, m) => Text(money ? tl(v) : v.toStringAsFixed(1), style: const TextStyle(fontSize: 9)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (xs.last - xs.first) / 4,
            getTitlesWidget: (v, m) =>
                Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())), style: const TextStyle(fontSize: 9)),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    '${money ? tl(s.y) : s.y.toStringAsFixed(2)}\n${DateFormat('d MMM y', 'tr_TR').format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < xs.length; i++) FlSpot(xs[i], ys[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .12)),
        ),
      ],
    ));
  }
}
