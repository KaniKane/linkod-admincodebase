import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class AcceptDeclineButtons extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const AcceptDeclineButtons({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<AcceptDeclineButtons> createState() => _AcceptDeclineButtonsState();
}

class _AcceptDeclineButtonsState extends State<AcceptDeclineButtons> {
  bool _isAcceptHovered = false;
  bool _isDeclineHovered = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Accept button
        MouseRegion(
          onEnter: (_) => setState(() => _isAcceptHovered = true),
          onExit: (_) => setState(() => _isAcceptHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onAccept,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isAcceptHovered
                    ? AppColors.primaryGreenAlt
                    : AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Accept',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Decline button
        MouseRegion(
          onEnter: (_) => setState(() => _isDeclineHovered = true),
          onExit: (_) => setState(() => _isDeclineHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onDecline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isDeclineHovered
                    ? AppColors.deleteRedAlt
                    : AppColors.deleteRed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Decline',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
