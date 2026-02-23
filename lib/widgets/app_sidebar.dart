import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class AppSidebar extends StatelessWidget {
  final String currentRoute;
  final Function(String) onNavigate;
  /// When non-null, Approvals and User Management are grayed out for non–Super Admin (e.g. Admin). Only Super Admin can access all features; Admin is limited to Dashboard and Announcements (need approval).
  final String? currentUserRole;

  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
    this.currentUserRole,
  });

  /// Gray out Approvals and User Management for everyone except Super Admin.
  bool get _isAdminRestricted =>
      (currentUserRole ?? '').toLowerCase() != 'super_admin';

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
              height: isSmallScreen ? 60 : 100,
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
                  iconPath: 'assets/img/icon/boxes.png',
                  label: 'Approvals',
                  isActive: currentRoute == '/approvals',
                  onTap: () => onNavigate('/approvals'),
                  isSmallScreen: isSmallScreen,
                  isDisabled: _isAdminRestricted,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  iconPath: 'assets/img/icon/user-profile-group.png',
                  label: 'User Management',
                  isActive: currentRoute == '/user-management',
                  onTap: () => onNavigate('/user-management'),
                  isSmallScreen: isSmallScreen,
                  isDisabled: _isAdminRestricted,
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
  final bool isDisabled;

  const _NavItem({
    required this.iconPath,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isSmallScreen = false,
    this.isDisabled = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isDisabled;
    final effectiveActive = widget.isActive && !disabled;
    final textColor = effectiveActive
        ? AppColors.white
        : (disabled ? AppColors.lightGrey : AppColors.darkGrey);
    final iconColor = effectiveActive
        ? AppColors.white
        : (disabled ? AppColors.lightGrey : AppColors.darkGrey);
    final hoverBg = !disabled && _isHovered && !widget.isActive
        ? AppColors.primaryGreen.withOpacity(0.1)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isSmallScreen ? 12 : 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: effectiveActive ? AppColors.primaryGreen : hoverBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Image.asset(
                widget.iconPath,
                width: 24,
                height: 24,
                color: iconColor,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.normal,
                    color: textColor,
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
