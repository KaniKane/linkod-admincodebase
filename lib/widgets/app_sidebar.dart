import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';
import '../utils/admin_navigation.dart';
import 'user_header.dart';

class AppSidebar extends StatefulWidget {
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

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  static const String _seenApprovalsKey = 'sidebar_seen_post_approvals';
  static const String _seenUsersKey = 'sidebar_seen_user_approvals';
  static const AssetImage _sidebarLogoImage = AssetImage(
    'assets/img/logo/linkod_logo_2.png',
  );

  int _seenApprovals = 0;
  int _seenUsers = 0;
  int? _livePendingUsersCount;

  /// Gray out Approvals and User Management for everyone except Super Admin.
  bool get _isAdminRestricted =>
      (widget.currentUserRole ?? '').toLowerCase() != 'super_admin';

  @override
  void initState() {
    super.initState();
    _livePendingUsersCount = AdminRefreshBus.pendingUsersCount.value;
    AdminRefreshBus.pendingUsersCount.addListener(_handleLivePendingUsersChanged);

    // Immediately set seen counts for current route to pending counts
    // This ensures badges disappear immediately on initial page load
    if (widget.currentRoute == '/approvals') {
      _seenApprovals = widget.pendingApprovalsCount;
    } else if (widget.currentRoute == '/user-management') {
      _seenUsers = _effectivePendingUsersCount;
    }
    _initSeenState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(_sidebarLogoImage, context);
    });
  }

  @override
  void dispose() {
    AdminRefreshBus.pendingUsersCount.removeListener(
      _handleLivePendingUsersChanged,
    );
    super.dispose();
  }

  void _handleLivePendingUsersChanged() {
    final next = AdminRefreshBus.pendingUsersCount.value;
    if (_livePendingUsersCount == next) return;
    if (!mounted) return;

    setState(() {
      _livePendingUsersCount = next;
    });
    _normalizeSeenBaselines();
  }

  int get _effectivePendingUsersCount =>
      _livePendingUsersCount ?? widget.pendingUsersCount;

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute ||
        oldWidget.pendingApprovalsCount != widget.pendingApprovalsCount ||
        oldWidget.pendingUsersCount != widget.pendingUsersCount) {
      _normalizeSeenBaselines();
      _markCurrentRouteAsSeen();
    }
  }

  Future<void> _initSeenState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _seenApprovals = prefs.getInt(_seenApprovalsKey) ?? 0;
      _seenUsers = prefs.getInt(_seenUsersKey) ?? 0;
    });
    await _normalizeSeenBaselines();
    await _markCurrentRouteAsSeen();
  }

  Future<void> _markCurrentRouteAsSeen() async {
    int? nextApprovals;
    int? nextUsers;

    if (widget.currentRoute == '/approvals') {
      nextApprovals = widget.pendingApprovalsCount;
    }
    if (widget.currentRoute == '/user-management') {
      nextUsers = _effectivePendingUsersCount;
    }

    if (nextApprovals == null && nextUsers == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      if (nextApprovals != null) {
        _seenApprovals = nextApprovals;
      }
      if (nextUsers != null) {
        _seenUsers = nextUsers;
      }
    });

    await prefs.setInt(_seenApprovalsKey, _seenApprovals);
    await prefs.setInt(_seenUsersKey, _seenUsers);
  }

  Future<void> _normalizeSeenBaselines() async {
    final pendingUsersCount = _effectivePendingUsersCount;
    final normalizedApprovals = _seenApprovals > widget.pendingApprovalsCount
        ? widget.pendingApprovalsCount
        : _seenApprovals;
    final normalizedUsers = _seenUsers > pendingUsersCount
      ? pendingUsersCount
        : _seenUsers;

    if (normalizedApprovals == _seenApprovals &&
        normalizedUsers == _seenUsers) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _seenApprovals = normalizedApprovals;
      _seenUsers = normalizedUsers;
    });

    await prefs.setInt(_seenApprovalsKey, _seenApprovals);
    await prefs.setInt(_seenUsersKey, _seenUsers);
  }

  int _buildUnseenCount({required int total, required int seen}) {
    if (total <= seen) return 0;
    return total - seen;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;
    final horizontalPadding = isSmallScreen ? 8.0 : 12.0;

    final unseenApprovals = _buildUnseenCount(
      total: widget.pendingApprovalsCount,
      seen: _seenApprovals,
    );
    final unseenUsers = _buildUnseenCount(
      total: _effectivePendingUsersCount,
      seen: _seenUsers,
    );

    return Container(
      width: isSmallScreen ? 200 : 250,
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 20,
                      ),
                      child: Image.asset(
                        'assets/img/logo/linkod_logo_2.png',
                        height: isSmallScreen ? 54 : 82,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        children: [
                          _NavItem(
                            icon: Icons.dashboard_outlined,
                            label: 'Dashboard',
                            isActive: widget.currentRoute == '/dashboard',
                            onTap: () => widget.onNavigate('/dashboard'),
                            isSmallScreen: isSmallScreen,
                          ),
                          const SizedBox(height: 8),
                          _NavItem(
                            icon: Icons.location_city_outlined,
                            label: 'Barangay Information',
                            isActive:
                                widget.currentRoute == '/barangay-information',
                            onTap: () =>
                                widget.onNavigate('/barangay-information'),
                            isSmallScreen: isSmallScreen,
                          ),
                          const SizedBox(height: 8),
                          _NavItem(
                            icon: Icons.campaign_outlined,
                            label: 'Announcements',
                            isActive: widget.currentRoute == '/announcements',
                            onTap: () => widget.onNavigate('/announcements'),
                            isSmallScreen: isSmallScreen,
                          ),

                          const SizedBox(height: 8),
                          _NavItem(
                            icon: Icons.fact_check_outlined,
                            label: 'Post Approvals',
                            isActive: widget.currentRoute == '/approvals',
                            onTap: () => widget.onNavigate('/approvals'),
                            isSmallScreen: isSmallScreen,
                            isDisabled: _isAdminRestricted,
                            badgeCount: unseenApprovals,
                          ),
                          const SizedBox(height: 8),
                          _NavItem(
                            icon: Icons.manage_accounts_outlined,
                            label: 'User Management',
                            isActive: widget.currentRoute == '/user-management',
                            onTap: () => widget.onNavigate('/user-management'),
                            isSmallScreen: isSmallScreen,
                            isDisabled: _isAdminRestricted,
                            badgeCount: unseenUsers,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                12,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 10 : 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBackground),
                ),
                child: UserHeader(compact: true),
              ),
            ),
          ],
        ),
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
      onTap: (disabled || effectiveActive) ? null : widget.onTap,
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
