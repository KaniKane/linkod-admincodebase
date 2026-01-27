import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class SuccessNotification extends StatelessWidget {
  final String message;

  const SuccessNotification({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.primaryGreen,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Checkmark icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryGreen,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.check,
              color: AppColors.primaryGreen,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          // Message text
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGreyAlt,
            ),
          ),
        ],
      ),
    );
  }
}
