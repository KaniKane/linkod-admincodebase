import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class SuggestedAudienceTag extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const SuggestedAudienceTag({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<SuggestedAudienceTag> createState() => _SuggestedAudienceTagState();
}

class _SuggestedAudienceTagState extends State<SuggestedAudienceTag> {
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
            color: AppColors.inputBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered
                  ? AppColors.primaryGreen
                  : AppColors.lightGrey,
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
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
