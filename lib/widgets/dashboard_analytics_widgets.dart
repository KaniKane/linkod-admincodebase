import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.height,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor.withOpacity(0.75),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF202020),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.mediumGrey,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class HorizontalBarDatum {
  const HorizontalBarDatum({
    required this.label,
    required this.value,
    this.trailingLabel,
  });

  final String label;
  final int value;
  final String? trailingLabel;
}

class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.items,
    this.emptyLabel,
    this.labelWidth = 96,
  });

  final List<HorizontalBarDatum> items;
  final String? emptyLabel;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyLabel ?? 'No data available',
          style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
      );
    }

    final maxValue = items.fold<int>(0, (prev, e) => math.max(prev, e.value));
    final safeMax = maxValue == 0 ? 1 : maxValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        final resolvedLabelWidth = math.min(
          labelWidth,
          constraints.maxWidth * 0.38,
        );
        final resolvedTrailingWidth = compact
            ? 72.0
            : math.min(96.0, constraints.maxWidth * 0.28);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.darkGrey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: resolvedTrailingWidth,
                                    child: Text(
                                      item.trailingLabel ?? '${item.value}',
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF2C2C2C),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 8,
                                      color: const Color(0xFFEAEAEA),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: (item.value / safeMax).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      child: Container(
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              SizedBox(
                                width: resolvedLabelWidth,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.darkGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 8,
                                        color: const Color(0xFFEAEAEA),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: (item.value / safeMax)
                                            .clamp(0.0, 1.0),
                                        child: Container(
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.primaryGreen,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: resolvedTrailingWidth,
                                child: Text(
                                  item.trailingLabel ?? '${item.value}',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2C2C2C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class TrendPoint {
  const TrendPoint({required this.label, required this.value});

  final String label;
  final int value;
}

class LineTrendChart extends StatefulWidget {
  const LineTrendChart({
    super.key,
    required this.points,
    this.emptyLabel,
    this.insightLabel,
  });

  final List<TrendPoint> points;
  final String? emptyLabel;
  final String? insightLabel;

  @override
  State<LineTrendChart> createState() => _LineTrendChartState();
}

class _LineTrendChartState extends State<LineTrendChart> {
  static const _horizontalPadding = 10.0;
  static const _verticalPadding = 12.0;

  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.points.isEmpty ? -1 : widget.points.length - 1;
  }

  @override
  void didUpdateWidget(covariant LineTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.isEmpty) {
      _selectedIndex = -1;
      return;
    }
    if (_selectedIndex < 0 || _selectedIndex >= widget.points.length) {
      _selectedIndex = widget.points.length - 1;
    }
  }

  int _resolveIndex(double localX, Size size, int count) {
    if (count <= 1) return 0;
    final chartWidth = size.width - (_horizontalPadding * 2);
    if (chartWidth <= 0) return 0;
    final chartX = (localX - _horizontalPadding).clamp(0.0, chartWidth);
    final ratio = chartX / chartWidth;
    final raw = ratio * (count - 1);
    final rounded = raw.round();
    return rounded.clamp(0, count - 1);
  }

  List<Offset> _computePoints(Size size, List<int> values) {
    if (values.isEmpty) return const [];
    final chartRect = Rect.fromLTWH(
      _horizontalPadding,
      _verticalPadding,
      size.width - (_horizontalPadding * 2),
      size.height - (_verticalPadding * 2),
    );

    final maxValue = values.fold<int>(0, (prev, e) => math.max(prev, e));
    final safeMax = maxValue == 0 ? 1 : maxValue;
    final stepX = values.length <= 1
        ? 0.0
        : chartRect.width / (values.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = chartRect.left + (stepX * i);
      final ratio = values[i] / safeMax;
      final y = chartRect.bottom - (chartRect.height * ratio);
      points.add(Offset(x, y));
    }
    return points;
  }

  String _formatPercent(double value) {
    if (value.isNaN || value.isInfinite) return '0%';
    final abs = value.abs();
    final text = abs >= 10 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(1);
    return '$text%';
  }

  Widget _metricChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E8EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.mediumGrey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return Center(
        child: Text(
          widget.emptyLabel ?? 'No trend data available',
          style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
      );
    }

    final values = widget.points.map((e) => e.value).toList(growable: false);
    final maxValue = values.fold<int>(0, (prev, e) => math.max(prev, e));
    final selectedIndex = _selectedIndex.clamp(0, widget.points.length - 1);
    final selectedPoint = widget.points[selectedIndex];
    final prevValue = selectedIndex > 0
        ? widget.points[selectedIndex - 1].value
        : null;
    final delta = prevValue == null ? 0 : selectedPoint.value - prevValue;
    final deltaPercent = (prevValue == null || prevValue == 0)
        ? null
        : (delta / prevValue) * 100;
    final deltaColor = delta >= 0
        ? const Color(0xFF1E9E5A)
        : const Color(0xFFE05252);
    final deltaIcon = delta >= 0 ? Icons.trending_up : Icons.trending_down;
    final deltaText = prevValue == null
        ? 'Start'
        : '${delta >= 0 ? '+' : ''}$delta (${deltaPercent == null ? '0%' : _formatPercent(deltaPercent)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final resolvedPoints = _computePoints(size, values);
              final selectedOffset = resolvedPoints.isEmpty
                  ? Offset.zero
                  : resolvedPoints[selectedIndex];

              final tooltipLeft = (selectedOffset.dx - 56).clamp(
                0.0,
                (constraints.maxWidth - 112).clamp(0.0, double.infinity),
              );
              final tooltipTop = (selectedOffset.dy - 52).clamp(
                0.0,
                (constraints.maxHeight - 34).clamp(0.0, double.infinity),
              );

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = _resolveIndex(
                      details.localPosition.dx,
                      size,
                      widget.points.length,
                    );
                  });
                },
                onHorizontalDragUpdate: (details) {
                  if (!mounted) return;
                  setState(() {
                    _selectedIndex = _resolveIndex(
                      details.localPosition.dx,
                      size,
                      widget.points.length,
                    );
                  });
                },
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _LineTrendPainter(
                        values: values,
                        selectedIndex: selectedIndex,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    if (resolvedPoints.isNotEmpty)
                      Positioned(
                        left: tooltipLeft,
                        top: tooltipTop,
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1B1B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedPoint.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFBDBDBD),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${selectedPoint.value} users',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      top: 4,
                      child: Text(
                        '$maxValue',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.mediumGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: (constraints.maxHeight / 2) - 6,
                      child: Text(
                        '${(maxValue / 2).round()}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.mediumGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: const Text(
                        '0',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.mediumGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricChip(
              icon: Icons.touch_app,
              iconColor: AppColors.darkGrey,
              label: selectedPoint.label,
              value: '${selectedPoint.value}',
            ),
            _metricChip(
              icon: Icons.flag,
              iconColor: AppColors.primaryGreen,
              label: 'Peak',
              value: '$maxValue',
            ),
            _metricChip(
              icon: deltaIcon,
              iconColor: deltaColor,
              label: 'Change',
              value: deltaText,
            ),
          ],
        ),
        if (widget.insightLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.insightLabel!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.darkGrey,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.points.first.label,
              style: const TextStyle(fontSize: 11, color: AppColors.mediumGrey),
            ),
            Text(
              'Tap/drag to inspect points',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.darkGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.points.last.label,
              style: const TextStyle(fontSize: 11, color: AppColors.mediumGrey),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineTrendPainter extends CustomPainter {
  const _LineTrendPainter({required this.values, required this.selectedIndex});

  final List<int> values;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalPadding = 10.0;
    const verticalPadding = 12.0;

    final chartRect = Rect.fromLTWH(
      horizontalPadding,
      verticalPadding,
      size.width - (horizontalPadding * 2),
      size.height - (verticalPadding * 2),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = chartRect.top + (chartRect.height * (i / 3));
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    if (values.isEmpty) return;

    final maxValue = values.fold<int>(0, (prev, e) => math.max(prev, e));
    final safeMax = maxValue == 0 ? 1 : maxValue;

    final points = <Offset>[];
    final stepX = values.length <= 1
        ? 0.0
        : chartRect.width / (values.length - 1);

    for (var i = 0; i < values.length; i++) {
      final x = chartRect.left + (stepX * i);
      final ratio = values[i] / safeMax;
      final y = chartRect.bottom - (chartRect.height * ratio);
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final cpX = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }

    final areaPath = Path.from(path)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();

    final areaPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x662ECC71), Color(0x082ECC71)],
      ).createShader(chartRect);
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = AppColors.primaryGreenAlt;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final radius = i == selectedIndex
          ? 5.0
          : (i == points.length - 1 ? 4.1 : 2.6);
      canvas.drawCircle(point, radius, dotPaint);
      if (i == selectedIndex) {
        final haloPaint = Paint()
          ..color = AppColors.primaryGreen.withOpacity(0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6;
        canvas.drawCircle(point, 7.2, haloPaint);

        final crosshair = Paint()
          ..color = const Color(0x332ECC71)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(point.dx, chartRect.top),
          Offset(point.dx, chartRect.bottom),
          crosshair,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineTrendPainter oldDelegate) {
    if (oldDelegate.selectedIndex != selectedIndex) return true;
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

class VerticalBarDatum {
  const VerticalBarDatum({required this.label, required this.value});

  final String label;
  final int value;
}

class VerticalBarsChart extends StatelessWidget {
  const VerticalBarsChart({super.key, required this.items, this.emptyLabel});

  final List<VerticalBarDatum> items;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyLabel ?? 'No data available',
          style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
      );
    }

    final maxValue = items.fold<int>(0, (prev, e) => math.max(prev, e.value));
    final safeMax = maxValue == 0 ? 1 : maxValue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${item.value}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.darkGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (item.value / safeMax).clamp(0.08, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF8FDFAF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class MiniStatPill extends StatelessWidget {
  const MiniStatPill({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final badgeColor = _badgeColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.darkGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _badgeColor(int value) {
    if (value <= 0) return AppColors.primaryGreen;
    if (value <= 2) return const Color(0xFFF0AD4E);
    return const Color(0xFFE35D5D);
  }
}
