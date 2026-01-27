import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class CustomTabs extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final Function(int) onTabChanged;

  const CustomTabs({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(tabs.length, (index) {
        final isActive = index == activeIndex;
        return _TabItem(
          label: tabs[index],
          isActive: isActive,
          onTap: () => onTabChanged(index),
        );
      }),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 32),
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.isActive
                    ? AppColors.primaryGreen
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: widget.isActive
                  ? AppColors.darkGrey
                  : AppColors.lightGrey,
            ),
          ),
        ),
      ),
    );
  }
}
