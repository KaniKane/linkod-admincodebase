import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/admin_notification_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/activity_item.dart';
import '../widgets/dashboard_analytics_widgets.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/fast_fade_in.dart';
import '../utils/app_colors.dart';
import '../utils/admin_navigation.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'user_management_screen.dart';
import 'barangay_information_screen.dart';

enum _InsightDatePreset { today, last7Days, last30Days, custom }

class _InsightDateWindow {
  const _InsightDateWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _acceptedUsers = 0;
  int _pendingUsers = 0;
  int _postedAnnouncements = 0;
  int _pendingAnnouncements = 0;
  int _acceptedUsersGrowth = 0;
  int _pendingUsersGrowth = 0;
  int _postedAnnouncementsGrowth = 0;
  int _pendingAnnouncementsGrowth = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentUserRole;
  _InsightDatePreset _selectedDatePreset = _InsightDatePreset.last30Days;
  DateTimeRange? _customDateRange;
  final List<Map<String, dynamic>> _recentActivities = [];

  // Pending counts for sidebar badges
  int _pendingApprovalsCount = 0;
  int _pendingUsersCount = 0;
  int _pendingProductsCount = 0;
  int _pendingTasksCount = 0;
  int _totalAnnouncementViews = 0;
  int _usersThisWeek = 0;
  String _actionableInsight = '';

  Map<String, int> _demographicsBreakdown = const {};
  List<TrendPoint> _userGrowthTrendPoints = const [];
  List<VerticalBarDatum> _topAnnouncementViews = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadCurrentUserRole();
    await _loadDashboardData();

    // Never let notification setup crash the dashboard on startup.
    try {
      // Initialize admin notification service after login
      // (real-time alerts for new registrations).
      await AdminNotificationService().initialize();
    } catch (_) {
      // Keep the app usable even if Windows notification APIs are unavailable.
    }
  }

  Future<void> _loadCurrentUserRole() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDoc.exists && mounted) {
          final role = (userDoc.data()?['role'] as String? ?? 'admin')
              .toLowerCase();
          setState(() => _currentUserRole = role);
        }
      } catch (_) {
        if (mounted) setState(() => _currentUserRole = 'admin');
      }
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    int acceptedUsers = 0;
    int pendingUsers = 0;
    int postedAnnouncements = 0;
    int pendingAnnouncements = 0;
    int acceptedUsersGrowth = 0;
    int pendingUsersGrowth = 0;
    int postedAnnouncementsGrowth = 0;
    int pendingAnnouncementsGrowth = 0;
    int pendingProductsCount = 0;
    int pendingTasksCount = 0;
    int totalAnnouncementViews = 0;

    final demographicsBreakdown = <String, int>{};
    final acceptedUserCreatedDates = <DateTime>[];
    final topAnnouncementViews = <Map<String, dynamic>>[];

    final dateWindow = _buildDateWindow();
    final rangeStart = Timestamp.fromDate(dateWindow.start);
    final rangeEnd = Timestamp.fromDate(dateWindow.end);
    final canReadAwaitingApproval =
        (_currentUserRole ?? '').toLowerCase() == 'super_admin';

    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        if (_isAcceptedUser(data)) {
          acceptedUsers++;
          final createdAtDate = _extractDate(data['createdAt']);
          if (createdAtDate != null) {
            acceptedUserCreatedDates.add(createdAtDate);
          }

          final purok = (data['purok'] ?? '').toString().trim();
          final userType = (data['userType'] ?? '').toString().trim();
          final demographicLabel = purok.isNotEmpty
              ? _formatPurokLabel(purok)
              : (userType.isNotEmpty ? _toTitleCase(userType) : 'Unspecified');
          demographicsBreakdown[demographicLabel] =
              (demographicsBreakdown[demographicLabel] ?? 0) + 1;

          if (_isInDateWindow(data['createdAt'], dateWindow)) {
            acceptedUsersGrowth++;
          }
        }
      }
    } catch (_) {
      // Keep dashboard readable even if this metric fails.
    }

    if (canReadAwaitingApproval) {
      try {
        final awaitingSnapshot = await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .get();

        final awaitingIds = <String>{};
        for (final doc in awaitingSnapshot.docs) {
          awaitingIds.add(doc.id);
          pendingUsers++;
          final data = doc.data();
          if (_isInDateWindow(data['createdAt'], dateWindow)) {
            pendingUsersGrowth++;
          }
        }

        // Include re-applications stored in users/{uid} with pending status.
        try {
          final usersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .get();
          for (final doc in usersSnapshot.docs) {
            if (!_isPendingUser(doc.data()) || awaitingIds.contains(doc.id)) {
              continue;
            }
            pendingUsers++;
            if (_isInDateWindow(doc.data()['createdAt'], dateWindow)) {
              pendingUsersGrowth++;
            }
          }
        } catch (_) {}
      } catch (_) {
        // Keep dashboard readable even if this optional metric fails.
      }
    }

    try {
      final allAnnouncementsSnapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .get();

      for (final doc in allAnnouncementsSnapshot.docs) {
        final data = doc.data();
        final normalizedStatus = (data['status'] as String? ?? '')
            .trim()
            .toLowerCase();

        if (normalizedStatus == 'approved') {
          postedAnnouncements++;
          final viewCount = _asInt(data['viewCount']);
          totalAnnouncementViews += viewCount;
          topAnnouncementViews.add({
            'title': (data['title'] as String? ?? 'Announcement').trim(),
            'views': viewCount,
          });

          if (_isInDateWindow(data['createdAt'], dateWindow)) {
            postedAnnouncementsGrowth++;
          }
        }

        if (normalizedStatus == 'pending') {
          pendingAnnouncements++;
          if (_isInDateWindow(data['createdAt'], dateWindow)) {
            pendingAnnouncementsGrowth++;
          }
        }
      }

      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .where('createdAt', isGreaterThanOrEqualTo: rangeStart)
          .where('createdAt', isLessThanOrEqualTo: rangeEnd)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      // Load pending counts for sidebar badges
      int pendingProducts = 0;
      int pendingTasks = 0;
      try {
        final pendingAnnouncementsSnap = await FirebaseFirestore.instance
            .collection('announcements')
            .where('status', isEqualTo: 'Pending')
            .count()
            .get();
        pendingAnnouncements = pendingAnnouncementsSnap.count ?? 0;
      } catch (_) {}
      try {
        final pendingProductsSnap = await FirebaseFirestore.instance
            .collection('products')
            .where('status', isEqualTo: 'Pending')
            .count()
            .get();
        pendingProducts = pendingProductsSnap.count ?? 0;
        pendingProductsCount = pendingProducts;
      } catch (_) {}
      try {
        final pendingTasksSnap = await FirebaseFirestore.instance
            .collection('tasks')
            .where('approvalStatus', isEqualTo: 'Pending')
            .count()
            .get();
        pendingTasks = pendingTasksSnap.count ?? 0;
        pendingTasksCount = pendingTasks;
      } catch (_) {}

      final activities = <Map<String, dynamic>>[];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      for (final doc in announcementsSnapshot.docs) {
        final d = doc.data();
        final createdAt = d['createdAt'];
        final title = d['title'] as String? ?? 'Announcement';
        final postedBy = d['postedBy'] as String? ?? 'Barangay';
        String timestamp = '';
        DateTime? sortAt;
        if (createdAt != null && createdAt is Timestamp) {
          final dt = createdAt.toDate();
          sortAt = dt;
          timestamp =
              '${months[dt.month - 1]} ${dt.day}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
        }
        activities.add({
          'description': '$postedBy posted an announcement titled $title',
          'timestamp': timestamp,
          'boldText': title,
          'sortAt': sortAt,
        });
      }

      final adminActivitiesSnapshot = await FirebaseFirestore.instance
          .collection('adminActivities')
          .where('createdAt', isGreaterThanOrEqualTo: rangeStart)
          .where('createdAt', isLessThanOrEqualTo: rangeEnd)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      for (final doc in adminActivitiesSnapshot.docs) {
        final d = doc.data();
        final description = d['description'] as String? ?? 'Activity';
        final fullName = d['fullName'] as String? ?? '';
        final createdAt = d['createdAt'];
        String timestamp = '';
        DateTime? sortAt;
        if (createdAt != null && createdAt is Timestamp) {
          final dt = createdAt.toDate();
          sortAt = dt;
          timestamp =
              '${months[dt.month - 1]} ${dt.day}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
        }
        activities.add({
          'description': description,
          'timestamp': timestamp,
          'boldText': fullName.isNotEmpty ? fullName : null,
          'sortAt': sortAt,
        });
      }

      activities.sort((a, b) {
        final aAt = a['sortAt'] as DateTime?;
        final bAt = b['sortAt'] as DateTime?;
        if (aAt == null && bAt == null) return 0;
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        return bAt.compareTo(aAt);
      });

      if (!mounted) return;
      topAnnouncementViews.sort(
        (a, b) => ((b['views'] as int?) ?? 0).compareTo((a['views'] as int?) ?? 0),
      );

      final userGrowthTrendPoints = _buildUserGrowthTrend(
        acceptedUserCreatedDates,
        dateWindow,
      );

      final topAnnouncementBars = topAnnouncementViews
          .take(3)
          .map(
            (entry) => VerticalBarDatum(
              label: _shortenLabel((entry['title'] as String?) ?? 'Announcement'),
              value: (entry['views'] as int?) ?? 0,
            ),
          )
          .toList(growable: false);

      final usersThisWeek = _countUsersWithinDays(acceptedUserCreatedDates, 7);

      final topDemographic = demographicsBreakdown.entries.isEmpty
          ? null
          : (demographicsBreakdown.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
      final topPercent = acceptedUsers <= 0 || topDemographic == null
          ? 0
          : ((topDemographic.value / acceptedUsers) * 100).round();

      final queueTotal = pendingUsers + pendingAnnouncements + pendingProducts + pendingTasks;
      final actionableInsight = topDemographic != null
          ? 'Most active resident segment: ${topDemographic.key} ($topPercent%).'
          : (queueTotal > 0
                ? 'You have $queueTotal items waiting in the approval queue.'
                : 'No pending queue items right now. Operations are up to date.');

      setState(() {
        _acceptedUsers = acceptedUsers;
        _pendingUsers = pendingUsers;
        _postedAnnouncements = postedAnnouncements;
        _pendingAnnouncements = pendingAnnouncements;
        _acceptedUsersGrowth = acceptedUsersGrowth;
        _pendingUsersGrowth = pendingUsersGrowth;
        _postedAnnouncementsGrowth = postedAnnouncementsGrowth;
        _pendingAnnouncementsGrowth = pendingAnnouncementsGrowth;
        _pendingApprovalsCount =
            pendingAnnouncements + pendingProducts + pendingTasks;
        _pendingUsersCount = pendingUsers;
        _pendingProductsCount = pendingProductsCount;
        _pendingTasksCount = pendingTasksCount;
        _totalAnnouncementViews = totalAnnouncementViews;
        _usersThisWeek = usersThisWeek;
        _actionableInsight = actionableInsight;
        _demographicsBreakdown = demographicsBreakdown;
        _userGrowthTrendPoints = userGrowthTrendPoints;
        _topAnnouncementViews = topAnnouncementBars;
        _recentActivities
          ..clear()
          ..addAll(activities);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load dashboard data: $e';
      });
    }
  }

  bool _isAcceptedUser(Map<String, dynamic> userData) {
    final role = (userData['role'] as String? ?? '').toLowerCase();
    if (role == 'super_admin' || role == 'admin') {
      return false;
    }

    final accountStatus =
        (userData['accountStatus'] as String?)?.toLowerCase().trim() ?? '';
    final status = (userData['status'] as String?)?.toLowerCase().trim() ?? '';

    // Pending users can still carry stale status values; prefer accountStatus.
    if (accountStatus == 'pending' || status == 'pending') {
      return false;
    }

    if (accountStatus.isNotEmpty) {
      return accountStatus == 'accepted' || accountStatus == 'active';
    }

    return status == 'accepted' || status == 'active';
  }

  bool _isPendingUser(Map<String, dynamic> userData) {
    final status =
        (userData['status'] as String? ?? userData['accountStatus'] as String?)
            ?.toLowerCase() ??
        '';
    return status == 'pending';
  }

  _InsightDateWindow _buildDateWindow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final custom = _customDateRange;

    DateTime start;
    DateTime end;
    switch (_selectedDatePreset) {
      case _InsightDatePreset.today:
        start = today;
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case _InsightDatePreset.last7Days:
        start = today.subtract(const Duration(days: 6));
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case _InsightDatePreset.last30Days:
        start = today.subtract(const Duration(days: 29));
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case _InsightDatePreset.custom:
        if (custom != null) {
          start = DateTime(
            custom.start.year,
            custom.start.month,
            custom.start.day,
          );
          end = DateTime(
            custom.end.year,
            custom.end.month,
            custom.end.day,
            23,
            59,
            59,
            999,
          );
        } else {
          start = today;
          end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        }
    }

    return _InsightDateWindow(
      start: start,
      end: end,
      label: _buildDateLabel(start, end, now),
    );
  }

  String _buildDateLabel(DateTime start, DateTime end, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (start.year == today.year &&
        start.month == today.month &&
        start.day == today.day) {
      return 'Today';
    }

    final startLabel = '${months[start.month - 1]} ${start.day}';
    if (end.year == today.year &&
        end.month == today.month &&
        end.day == today.day) {
      return '$startLabel - Today';
    }

    final endLabel = '${months[end.month - 1]} ${end.day}';
    return '$startLabel - $endLabel';
  }

  bool _isInDateWindow(dynamic createdAt, _InsightDateWindow window) {
    if (createdAt is! Timestamp && createdAt is! DateTime) return false;
    final date = createdAt is Timestamp
        ? createdAt.toDate()
        : createdAt as DateTime;
    return !date.isBefore(window.start) && !date.isAfter(window.end);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  DateTime? _extractDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _toTitleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _shortenLabel(String label) {
    if (label.length <= 22) return label;
    return '${label.substring(0, 21)}...';
  }

  String _formatPurokLabel(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return 'Unspecified';
    final lower = normalized.toLowerCase();
    if (lower.startsWith('purok')) return _toTitleCase(normalized);
    final numericOnly = RegExp(r'^\d+$').hasMatch(normalized);
    if (numericOnly) return 'Purok $normalized';
    return _toTitleCase(normalized);
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  List<TrendPoint> _buildUserGrowthTrend(
    List<DateTime> acceptedDates,
    _InsightDateWindow window,
  ) {
    if (acceptedDates.isEmpty) return const [];

    final start = DateTime(window.start.year, window.start.month, window.start.day);
    final end = DateTime(window.end.year, window.end.month, window.end.day);
    final dayCount = end.difference(start).inDays + 1;
    if (dayCount <= 0) return const [];

    final dailyCounts = <DateTime, int>{};
    for (var i = 0; i < dayCount; i++) {
      final day = start.add(Duration(days: i));
      dailyCounts[day] = 0;
    }

    for (final date in acceptedDates) {
      final normalized = DateTime(date.year, date.month, date.day);
      if (normalized.isBefore(start) || normalized.isAfter(end)) continue;
      dailyCounts[normalized] = (dailyCounts[normalized] ?? 0) + 1;
    }

    final entries = dailyCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.length <= 10) {
      return entries
          .map((e) => TrendPoint(label: _formatShortDate(e.key), value: e.value))
          .toList(growable: false);
    }

    final targetBuckets = 10;
    final bucketSize = (entries.length / targetBuckets).ceil();
    final compressed = <TrendPoint>[];

    for (var i = 0; i < entries.length; i += bucketSize) {
      final chunk = entries.skip(i).take(bucketSize).toList(growable: false);
      if (chunk.isEmpty) continue;

      final startLabel = _formatShortDate(chunk.first.key);
      final endLabel = _formatShortDate(chunk.last.key);
      final label = startLabel == endLabel ? startLabel : '$startLabel-$endLabel';
      final value = chunk.fold<int>(0, (sum, e) => sum + e.value);
      compressed.add(TrendPoint(label: label, value: value));
    }

    return compressed;
  }

  int _countUsersWithinDays(List<DateTime> dates, int days) {
    if (days <= 0) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return dates.where((d) {
      final normalized = DateTime(d.year, d.month, d.day);
      return !normalized.isBefore(start) && !normalized.isAfter(now);
    }).length;
  }

  Widget _buildStatNumber({required String label, required int value}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mediumGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDatePresetSelected(_InsightDatePreset preset) async {
    if (preset == _InsightDatePreset.custom) {
      final now = DateTime.now();
      final currentYearStart = DateTime(now.year, 1, 1);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 2),
        initialDateRange:
            _customDateRange ??
            DateTimeRange(start: currentYearStart, end: now),
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _customDateRange = picked;
        _selectedDatePreset = _InsightDatePreset.custom;
      });
      await _loadDashboardData();
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedDatePreset = preset;
    });
    await _loadDashboardData();
  }

  void _navigateToMetricDestination({
    required String route,
    int? initialTabIndex,
    bool showAcceptedUsersOnly = false,
  }) {
    final isSuperAdmin =
        (_currentUserRole ?? '').toLowerCase() == 'super_admin';
    final requiresSuperAdmin =
        route == '/approvals' || route == '/user-management';

    if (!isSuperAdmin && requiresSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
            message: 'Only Super Admin can access this.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Widget page;
    if (route == '/announcements') {
      page = AnnouncementsScreen(
        initialTabIndex: initialTabIndex ?? 0,
        rememberLastTab: false,
      );
    } else if (route == '/approvals') {
      page = ApprovalsScreen(
        initialTabIndex: initialTabIndex ?? 0,
        rememberLastTab: false,
      );
    } else if (route == '/user-management') {
      page = UserManagementScreen(
        initialTabIndex: initialTabIndex ?? 2,
        showAcceptedUsersOnly: showAcceptedUsersOnly,
        rememberLastTab: false,
      );
    } else {
      return;
    }

    navigateToAdminScreen(
      context,
      currentRoute: '/dashboard',
      targetRoute: route,
      page: page,
    );
  }

  Widget _buildMetricTile({
    required String title,
    required int value,
    required int growth,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            height: 144,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEDED),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '+$growth',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightGroupCard({
    required IconData icon,
    required String title,
    required Widget leftMetric,
    required Widget rightMetric,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF474747),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(child: leftMetric),
              const SizedBox(width: 12),
              Expanded(child: rightMetric),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          // Sidebar
          AppSidebar(
            currentRoute: '/dashboard',
            currentUserRole: _currentUserRole,
            pendingApprovalsCount: _pendingApprovalsCount,
            pendingUsersCount: _pendingUsersCount,
            onNavigate: (route) {
              if ((_currentUserRole ?? '').toLowerCase() != 'super_admin' &&
                  (route == '/approvals' || route == '/user-management')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const DraftSavedNotification(
                      message: 'Only Super Admin can access this.',
                    ),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (route == '/announcements') {
                navigateToAdminScreen(
                  context,
                  currentRoute: '/dashboard',
                  targetRoute: route,
                  page: const AnnouncementsScreen(),
                );
              } else if (route == '/barangay-information') {
                navigateToAdminScreen(
                  context,
                  currentRoute: '/dashboard',
                  targetRoute: route,
                  page: const BarangayInformationScreen(),
                );
              } else if (route == '/approvals') {
                navigateToAdminScreen(
                  context,
                  currentRoute: '/dashboard',
                  targetRoute: route,
                  page: const ApprovalsScreen(),
                );
              } else if (route == '/user-management') {
                navigateToAdminScreen(
                  context,
                  currentRoute: '/dashboard',
                  targetRoute: route,
                  page: const UserManagementScreen(initialTabIndex: 2),
                );
              }
            },
          ),
          // Main content
          Expanded(
            child: FastFadeIn(
              child: Container(
                color: AppColors.white,
                child: Column(
                children: [
                  // Top header
                  Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(24),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Dashboard',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                      ),
                    ),
                  ),
                  // Content area with inner background panel
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.dashboardInnerBg,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Insights section
                            Row(
                              children: [
                                const Text(
                                  'Insights',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkGrey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<_InsightDatePreset>(
                                  tooltip: 'Select date range',
                                  onSelected: _onDatePresetSelected,
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: _InsightDatePreset.today,
                                      child: Text('Today'),
                                    ),
                                    const PopupMenuItem(
                                      value: _InsightDatePreset.last7Days,
                                      child: Text('Last 7 Days'),
                                    ),
                                    const PopupMenuItem(
                                      value: _InsightDatePreset.last30Days,
                                      child: Text('Last 30 Days'),
                                    ),
                                    const PopupMenuItem(
                                      value: _InsightDatePreset.custom,
                                      child: Text('Custom Range'),
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE0E0E0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          _buildDateWindow().label,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.mediumGrey,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: AppColors.mediumGrey,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Insight cards (grouped to match reference)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const minRowWidth = 980.0;
                                final rowWidth =
                                    constraints.maxWidth < minRowWidth
                                    ? minRowWidth
                                    : constraints.maxWidth;
                                final cardWidth = (rowWidth - 16) / 2;

                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: rowWidth,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: cardWidth,
                                          child: _buildInsightGroupCard(
                                            icon: Icons.groups_2_outlined,
                                            title: 'Users',
                                            leftMetric: _buildMetricTile(
                                              title: 'Total Users',
                                              value: _acceptedUsers,
                                              growth: _acceptedUsersGrowth,
                                              onTap: () =>
                                                  _navigateToMetricDestination(
                                                    route: '/user-management',
                                                    initialTabIndex: 0,
                                                    showAcceptedUsersOnly: true,
                                                  ),
                                            ),
                                            rightMetric: _buildMetricTile(
                                              title: 'Awaiting Approval',
                                              value: _pendingUsers,
                                              growth: _pendingUsersGrowth,
                                              onTap: () =>
                                                  _navigateToMetricDestination(
                                                    route: '/user-management',
                                                    initialTabIndex: 2,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: cardWidth,
                                          child: _buildInsightGroupCard(
                                            icon: Icons.campaign_outlined,
                                            title: 'Announcements',
                                            leftMetric: _buildMetricTile(
                                              title: 'Posted',
                                              value: _postedAnnouncements,
                                              growth:
                                                  _postedAnnouncementsGrowth,
                                              onTap: () =>
                                                  _navigateToMetricDestination(
                                                    route: '/announcements',
                                                    initialTabIndex: 2,
                                                  ),
                                            ),
                                            rightMetric: _buildMetricTile(
                                              title: 'Awaiting Approval',
                                              value: _pendingAnnouncements,
                                              growth:
                                                  _pendingAnnouncementsGrowth,
                                              onTap: () =>
                                                  _navigateToMetricDestination(
                                                    route: '/approvals',
                                                    initialTabIndex: 0,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Analytics Overview',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkGrey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Lightweight view of resident mix, growth trend, and content reach.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.mediumGrey,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_actionableInsight.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF8F2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.insights_outlined,
                                      size: 18,
                                      color: AppColors.primaryGreenAlt,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _actionableInsight,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.darkGrey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final twoColumns = constraints.maxWidth >= 1100;
                                final cardWidth = twoColumns
                                    ? (constraints.maxWidth - 16) / 2
                                    : constraints.maxWidth;

                                final demographicItems = _demographicsBreakdown.entries
                                    .toList()
                                  ..sort((a, b) => b.value.compareTo(a.value));

                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    SizedBox(
                                      width: cardWidth,
                                      height: 270,
                                      child: AnalyticsCard(
                                        title: 'Demographics Breakdown',
                                        subtitle: 'Resident distribution by purok / category',
                                        child: HorizontalBarChart(
                                          items: demographicItems
                                              .take(6)
                                              .map(
                                                (entry) {
                                                  final percent = _acceptedUsers <= 0
                                                      ? 0
                                                      : ((entry.value / _acceptedUsers) * 100)
                                                            .round();
                                                  return HorizontalBarDatum(
                                                    label: entry.key,
                                                    value: entry.value,
                                                    trailingLabel:
                                                        '${entry.value} ($percent%)',
                                                  );
                                                },
                                              )
                                              .toList(growable: false),
                                          emptyLabel: 'No resident category data yet',
                                          labelWidth: 124,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: cardWidth,
                                      height: 270,
                                      child: AnalyticsCard(
                                        title: 'User Growth Trend',
                                        subtitle: _buildDateWindow().label,
                                        child: LineTrendChart(
                                          points: _userGrowthTrendPoints,
                                          insightLabel:
                                              '+$_usersThisWeek users in the last 7 days',
                                          emptyLabel:
                                              'No registrations found in selected period',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: cardWidth,
                                      height: 300,
                                      child: AnalyticsCard(
                                        title: 'Announcement Performance',
                                        subtitle: 'Top viewed announcements and status totals',
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: HorizontalBarChart(
                                                items: _topAnnouncementViews
                                                    .map(
                                                      (item) => HorizontalBarDatum(
                                                        label: item.label,
                                                        value: item.value,
                                                        trailingLabel:
                                                            '${item.value} views',
                                                      ),
                                                    )
                                                    .toList(growable: false),
                                                emptyLabel:
                                                    'No viewed announcements available',
                                                labelWidth: 170,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                _buildStatNumber(
                                                  label: 'Posted',
                                                  value: _postedAnnouncements,
                                                ),
                                                _buildStatNumber(
                                                  label: 'Pending',
                                                  value: _pendingAnnouncements,
                                                ),
                                                _buildStatNumber(
                                                  label: 'Total Views',
                                                  value: _totalAnnouncementViews,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            if (_errorMessage != null) ...[
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_isLoading) ...[
                              const SizedBox(height: 8),
                              const Center(child: CircularProgressIndicator()),
                              const SizedBox(height: 32),
                            ] else
                              const SizedBox(height: 40),
                            // Recent Activities section
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Recent Activities',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (_recentActivities.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'No recent activities.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.mediumGrey,
                                        ),
                                      ),
                                    )
                                  else
                                    ..._recentActivities.map(
                                      (a) => ActivityItem(
                                        description: a['description'] as String,
                                        timestamp: a['timestamp'] as String,
                                        boldText: a['boldText'] as String?,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}
