import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class DraftSavedNotification extends StatelessWidget {
  final String message;

  const DraftSavedNotification({
    super.key,
    this.message = 'Successfully saved to draft',
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
        painter: _RibbonPainter(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.draftBannerBg
      ..style = PaintingStyle.fill;

    final path = Path();
    final triangleSize = 12.0;

    // Start from top-left (after left triangle cutout)
    path.moveTo(0, triangleSize);
    // Top edge
    path.lineTo(size.width - triangleSize, triangleSize);
    // Top-right triangle cutout (inward pointing down)
    path.lineTo(size.width, 0);
    path.lineTo(size.width, triangleSize);
    // Right edge
    path.lineTo(size.width, size.height - triangleSize);
    // Bottom-right triangle cutout (inward pointing up)
    path.lineTo(size.width - triangleSize, size.height);
    path.lineTo(size.width - triangleSize, size.height - triangleSize);
    // Bottom edge
    path.lineTo(triangleSize, size.height - triangleSize);
    // Bottom-left triangle cutout (inward pointing up)
    path.lineTo(0, size.height);
    path.lineTo(0, size.height - triangleSize);
    // Left edge
    path.lineTo(0, triangleSize);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
