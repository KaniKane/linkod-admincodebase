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
        final resolvedLabelWidth = math.min(labelWidth, constraints.maxWidth * 0.38);
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
                                    Container(height: 8, color: const Color(0xFFEAEAEA)),
                                    FractionallySizedBox(
                                      widthFactor:
                                          (item.value / safeMax).clamp(0.0, 1.0),
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
                                      Container(height: 8, color: const Color(0xFFEAEAEA)),
                                      FractionallySizedBox(
                                        widthFactor:
                                            (item.value / safeMax).clamp(0.0, 1.0),
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

class LineTrendChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          emptyLabel ?? 'No trend data available',
          style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
      );
    }

    final values = points.map((e) => e.value).toList(growable: false);
    final maxValue = values.fold<int>(0, (prev, e) => math.max(prev, e));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CustomPaint(
            painter: _LineTrendPainter(values: values),
            child: const SizedBox.expand(),
          ),
        ),
        if (insightLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            insightLabel!,
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
              points.first.label,
              style: const TextStyle(fontSize: 11, color: AppColors.mediumGrey),
            ),
            Text(
              'Peak: $maxValue',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.darkGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              points.last.label,
              style: const TextStyle(fontSize: 11, color: AppColors.mediumGrey),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineTrendPainter extends CustomPainter {
  const _LineTrendPainter({required this.values});

  final List<int> values;

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
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
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
      final radius = i == points.length - 1 ? 4.1 : 2.6;
      canvas.drawCircle(point, radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineTrendPainter oldDelegate) {
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
  const VerticalBarsChart({
    super.key,
    required this.items,
    this.emptyLabel,
  });

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
  const MiniStatPill({
    super.key,
    required this.label,
    required this.value,
  });

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
