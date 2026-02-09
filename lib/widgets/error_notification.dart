import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Error/info notification in the same ribbon style as DraftSavedNotification for theme consistency.
class ErrorNotification extends StatelessWidget {
  final String message;

  const ErrorNotification({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 300,
        maxWidth: 400,
        minHeight: 60,
      ),
      child: CustomPaint(
        painter: _ErrorRibbonPainter(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGreyAlt,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.errorBannerBg
      ..style = PaintingStyle.fill;

    final path = Path();
    final triangleSize = 12.0;

    path.moveTo(0, triangleSize);
    path.lineTo(size.width - triangleSize, triangleSize);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, triangleSize);
    path.lineTo(size.width, size.height - triangleSize);
    path.lineTo(size.width - triangleSize, size.height);
    path.lineTo(size.width - triangleSize, size.height - triangleSize);
    path.lineTo(triangleSize, size.height - triangleSize);
    path.lineTo(0, size.height);
    path.lineTo(0, size.height - triangleSize);
    path.lineTo(0, triangleSize);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
