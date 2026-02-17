import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Reusable modal container matching User Management edit dialogs.
/// Use for all admin modals: same white card, shadow, title style.
/// Pass `actions` as a Row of buttons; use DialogActionButton for consistent sizing.
class DialogContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget actions;
  final double? maxWidth;

  const DialogContainer({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.maxWidth = 520,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth ?? 520),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.loginGreen,
                ),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: child,
                ),
              ),
              const SizedBox(height: 24),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Single dialog action button with unified sizing and typography.
class DialogActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;

  const DialogActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final BorderSide? side;

    if (isPrimary) {
      bgColor = AppColors.primaryGreen;
      fgColor = AppColors.white;
      side = null;
    } else {
      bgColor = Colors.white;
      fgColor = isDestructive ? AppColors.deleteRed : AppColors.darkGrey;
      side = BorderSide(
        color: isDestructive ? AppColors.deleteRed : AppColors.lightGrey,
        width: 1,
      );
    }

    return SizedBox(
      width: 120,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: side ?? BorderSide.none,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
