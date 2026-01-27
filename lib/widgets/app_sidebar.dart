import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class AppSidebar extends StatelessWidget {
  final String currentRoute;
  final Function(String) onNavigate;

  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;
    
    return Container(
      width: isSmallScreen ? 200 : 250,
      color: AppColors.white,
      child: Column(
        children: [
          const SizedBox(height: 30),
          // Logo
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 20),
            child: Image.asset(
              'assets/img/logo/linkod_logo_2.png',
              height: isSmallScreen ? 48 : 56,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 40),
          // Navigation items
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12),
            child: Column(
              children: [
                _NavItem(
                  iconPath: 'assets/img/icon/boxes.png',
                  label: 'Dashboard',
                  isActive: currentRoute == '/dashboard',
                  onTap: () => onNavigate('/dashboard'),
                  isSmallScreen: isSmallScreen,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  iconPath: 'assets/img/icon/sound_mute.png',
                  label: 'Announcements',
                  isActive: currentRoute == '/announcements',
                  onTap: () => onNavigate('/announcements'),
                  isSmallScreen: isSmallScreen,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  iconPath: 'assets/img/icon/user-profile-group.png',
                  label: 'User Management',
                  isActive: currentRoute == '/user-management',
                  onTap: () => onNavigate('/user-management'),
                  isSmallScreen: isSmallScreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String iconPath;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isSmallScreen;

  const _NavItem({
    required this.iconPath,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isSmallScreen = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
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
          padding: EdgeInsets.symmetric(
            horizontal: widget.isSmallScreen ? 12 : 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.primaryGreen
                : (_isHovered && !widget.isActive
                    ? AppColors.primaryGreen.withOpacity(0.1)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Image.asset(
                widget.iconPath,
                width: 24,
                height: 24,
                color: widget.isActive
                    ? AppColors.white
                    : AppColors.darkGrey,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.normal,
                    color: widget.isActive
                        ? AppColors.white
                        : AppColors.darkGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
