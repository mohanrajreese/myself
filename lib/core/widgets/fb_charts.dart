import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import 'fb_card.dart';
import 'tokens.dart';

/// One point of a chart: an x position (usually days since the range
/// start) and a value already converted to display units.
typedef ChartPoint = ({double x, double y});

/// Range choices for history charts (PRD §4.7).
enum ChartRange {
  week(7),
  month(30),
  quarter(90),
  year(365);

  const ChartRange(this.days);
  final int days;
}

/// Card wrapper: title, optional range selector, chart, and a text summary
/// that screen readers announce instead of the drawing.
class FbChartCard extends StatelessWidget {
  const FbChartCard({
    required this.summary,
    required this.chart,
    this.title,
    this.footer,
    this.height = 180,
    super.key,
  });

  final String? title;
  final String summary;
  final Widget chart;
  final Widget? footer;
  final double height;

  @override
  Widget build(BuildContext context) => FbCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: context.text.bodyStrong),
          const SizedBox(height: FbSpace.sm),
        ],
        Semantics(
          label: summary,
          image: true,
          child: ExcludeSemantics(
            child: SizedBox(height: height, child: chart),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: FbSpace.sm), footer!],
      ],
    ),
  );
}

FlTitlesData _titles(
  BuildContext context, {
  required String Function(double x) bottom,
  String Function(double y)? left,
  double? bottomInterval,
}) {
  final style = context.text.caption;
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: left != null,
        reservedSize: 40,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(left?.call(value) ?? '', style: style),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: bottomInterval,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(bottom(value), style: style),
        ),
      ),
    ),
  );
}

/// A line through dated values (weight, measurements, scores).
class FbLineChart extends StatelessWidget {
  const FbLineChart({
    required this.points,
    required this.bottomLabel,
    this.leftLabel,
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    this.target,
    this.bottomInterval,
    super.key,
  });

  final List<ChartPoint> points;
  final String Function(double x) bottomLabel;
  final String Function(double y)? leftLabel;
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;

  /// Dashed horizontal line, for a goal.
  final double? target;
  final double? bottomInterval;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: c.surfaceVariant, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(
          context,
          bottom: bottomLabel,
          left: leftLabel,
          bottomInterval: bottomInterval,
        ),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: target == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: target!,
                    color: c.secondary,
                    strokeWidth: 1.5,
                    dashArray: [4, 4],
                  ),
                ],
              ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final p in points) FlSpot(p.x, p.y)],
            color: c.primary,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 31,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3.5, color: c.primary, strokeWidth: 0),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bar per day (water, sleep), with an optional dashed goal line.
class FbBarChart extends StatelessWidget {
  const FbBarChart({
    required this.values,
    required this.bottomLabel,
    this.leftLabel,
    this.target,
    this.color,
    this.maxY,
    super.key,
  });

  /// Bar heights in display units, one per x position starting at 0.
  final List<double> values;
  final String Function(int index) bottomLabel;
  final String Function(double y)? leftLabel;
  final double? target;
  final Color? color;
  final double? maxY;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final highest = [...values, target ?? 0].fold<double>(0, (a, b) => b > a ? b : a);
    final width = values.length > 14 ? 6.0 : 22.0;
    final every = values.length > 14 ? 7 : 1;
    return BarChart(
      BarChartData(
        maxY: maxY ?? (highest == 0 ? 1 : highest * 1.15),
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: _titles(
          context,
          bottom: (x) => x.toInt() % every == 0 ? bottomLabel(x.toInt()) : '',
          left: leftLabel,
        ),
        extraLinesData: target == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: target!,
                    color: c.textPrimary,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ],
              ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: width,
                  color: color ?? c.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
