import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class AudienceTag extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const AudienceTag({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<AudienceTag> createState() => _AudienceTagState();
}

class _AudienceTagState extends State<AudienceTag> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.selectedAudienceBg
                : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.lightGrey,
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
        ),
      ),
    );
  }
}
