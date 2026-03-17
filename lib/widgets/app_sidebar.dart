import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class AppSidebar extends StatelessWidget {
  final String currentRoute;
  final Function(String) onNavigate;

  /// When non-null, Approvals and User Management are grayed out for non–Super Admin (e.g. Admin). Only Super Admin can access all features; Admin is limited to Dashboard and Announcements (need approval).
  final String? currentUserRole;

  /// Pending counts for badges
  final int pendingApprovalsCount;
  final int pendingUsersCount;

  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
    this.currentUserRole,
    this.pendingApprovalsCount = 0,
    this.pendingUsersCount = 0,
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
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  isActive: currentRoute == '/dashboard',
                  onTap: () => onNavigate('/dashboard'),
                  isSmallScreen: isSmallScreen,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  isActive: currentRoute == '/announcements',
                  onTap: () => onNavigate('/announcements'),
                  isSmallScreen: isSmallScreen,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.location_city_outlined,
                  label: 'Barangay Information',
                  isActive: currentRoute == '/barangay-information',
                  onTap: () => onNavigate('/barangay-information'),
                  isSmallScreen: isSmallScreen,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.fact_check_outlined,
                  label: 'Post Approvals',
                  isActive: currentRoute == '/approvals',
                  onTap: () => onNavigate('/approvals'),
                  isSmallScreen: isSmallScreen,
                  isDisabled: _isAdminRestricted,
                  badgeCount: pendingApprovalsCount,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.manage_accounts_outlined,
                  label: 'User Management',
                  isActive: currentRoute == '/user-management',
                  onTap: () => onNavigate('/user-management'),
                  isSmallScreen: isSmallScreen,
                  isDisabled: _isAdminRestricted,
                  badgeCount: pendingUsersCount,
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
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isSmallScreen;
  final bool isDisabled;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isSmallScreen = false,
    this.isDisabled = false,
    this.badgeCount = 0,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
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

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isSmallScreen ? 12 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: effectiveActive ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 24, color: iconColor),
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
            if (widget.badgeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: effectiveActive
                      ? AppColors.white
                      : AppColors.deleteRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.badgeCount.toString(),
                  style: TextStyle(
                    fontSize: widget.isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.bold,
                    color: effectiveActive
                        ? AppColors.primaryGreen
                        : AppColors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
