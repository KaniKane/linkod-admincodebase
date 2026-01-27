import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class BrandSection extends StatelessWidget {
  final bool useGradient;
  
  const BrandSection({
    super.key,
    this.useGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;
    
    return Container(
      width: isSmallScreen ? screenWidth : screenWidth * 0.6,
      decoration: BoxDecoration(
        color: useGradient ? null : AppColors.primaryGreen,
        gradient: useGradient
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.gradientStart,
                  AppColors.gradientEnd,
                ],
              )
            : null,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo icon - using a simple icon representation
                  Container(
                    width: isSmallScreen ? 40 : 48,
                    height: isSmallScreen ? 40 : 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.white,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.link,
                      color: AppColors.white,
                      size: isSmallScreen ? 24 : 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'LINKod',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 36 : 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Ai-Assisted Barangay-based Social Platform',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 18,
                  fontWeight: FontWeight.normal,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
