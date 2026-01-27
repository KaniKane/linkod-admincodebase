import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class CustomLink extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;

  const CustomLink({
    super.key,
    required this.text,
    this.onTap,
  });

  @override
  State<CustomLink> createState() => _CustomLinkState();
}

class _CustomLinkState extends State<CustomLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.primaryGreen,
            decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: AppColors.primaryGreen,
          ),
          child: Text(widget.text),
        ),
      ),
    );
  }
}
