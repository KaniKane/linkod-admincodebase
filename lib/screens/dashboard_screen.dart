import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/admin_notification_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/insight_card.dart';
import '../widgets/activity_item.dart';
import '../widgets/user_header.dart';
import '../widgets/draft_saved_notification.dart';
import '../utils/app_colors.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'user_management_screen.dart';
import 'barangay_information_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _totalUsers = 0;
  int _awaitingApproval = 0;
  int _totalAnnouncements = 0;
  int _usersAddedThisMonth = 0;
  int _approvalsThisMonth = 0;
  int _announcementsThisMonth = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentUserRole;
  final List<Map<String, dynamic>> _recentActivities = [];

  // Pending counts for sidebar badges
  int _pendingApprovalsCount = 0;
  int _pendingUsersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
    _loadDashboardData();
    // Initialize admin notification service after login (real-time alerts for new registrations)
    AdminNotificationService().initialize();
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

    int totalUsers = 0;
    int totalAwaiting = 0;
    int usersAddedThisMonth = 0;
    int approvalsThisMonth = 0;
    int announcementsThisMonth = 0;

    // Calculate start of month
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    try {
      // Use count() for accurate total users count
      final usersCountSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      totalUsers = usersCountSnapshot.count ?? 0;
      
      // Fetch users docs separately for monthly count
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      
      // Count users added this month
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          if (createdAt.toDate().isAfter(startOfMonth)) {
            usersAddedThisMonth++;
          }
        }
      }
    } catch (_) {
      // Admin cannot read users; show 0
    }
    try {
      final awaitingSnapshot = await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .get();
      totalAwaiting = awaitingSnapshot.size;
      
      // Count approvals added this month
      for (final doc in awaitingSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          if (createdAt.toDate().isAfter(startOfMonth)) {
            approvalsThisMonth++;
          }
        }
      }
    } catch (_) {
      // Admin cannot read awaitingApproval; show 0
    }

    try {
      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      // Load pending counts for sidebar badges
      int pendingAnnouncements = 0;
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
      } catch (_) {}
      try {
        final pendingTasksSnap = await FirebaseFirestore.instance
            .collection('tasks')
            .where('approvalStatus', isEqualTo: 'Pending')
            .count()
            .get();
        pendingTasks = pendingTasksSnap.count ?? 0;
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
        // Count announcements created this month
        final createdAt = d['createdAt'];
        if (createdAt is Timestamp) {
          if (createdAt.toDate().isAfter(startOfMonth)) {
            announcementsThisMonth++;
          }
        }
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
      setState(() {
        _totalUsers = totalUsers;
        _totalAnnouncements = announcementsSnapshot.size;
        _awaitingApproval = totalAwaiting;
        _usersAddedThisMonth = usersAddedThisMonth;
        _approvalsThisMonth = approvalsThisMonth;
        _announcementsThisMonth = announcementsThisMonth;
        _pendingApprovalsCount = pendingAnnouncements + pendingProducts + pendingTasks;
        _pendingUsersCount = totalAwaiting;
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

  String _buildDateRangeLabel() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
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
    final startLabel = '${months[start.month - 1]} ${start.day}';
    final endLabel = '${months[now.month - 1]} ${now.day}';
    return '$startLabel - $endLabel';
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
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const AnnouncementsScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder: (context, animation, secondaryAnimation,
                            child) =>
                        child,
                  ),
                );
              } else if (route == '/barangay-information') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const BarangayInformationScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder: (context, animation, secondaryAnimation,
                            child) =>
                        child,
                  ),
                );
              } else if (route == '/approvals') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const ApprovalsScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder: (context, animation, secondaryAnimation,
                            child) =>
                        child,
                  ),
                );
              } else if (route == '/user-management') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const UserManagementScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    transitionsBuilder: (context, animation, secondaryAnimation,
                            child) =>
                        child,
                  ),
                );
              }
            },
          ),
          // Main content
          Expanded(
            child: Container(
              color: AppColors.white,
              child: Column(
                children: [
                  // Top header with user profile
                  Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dashboard',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGrey,
                          ),
                        ),
                        const UserHeader(),
                      ],
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
                                Text(
                                  _buildDateRangeLabel(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: AppColors.mediumGrey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Insight cards
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isSmallScreen =
                                    constraints.maxWidth < 900;
                                return isSmallScreen
                                    ? Column(
                                        children: [
                                          InsightCard(
                                            iconPath:
                                                'assets/img/icon/gray_group_icon.png',
                                            label: 'Total Users',
                                            value: _totalUsers.toString(),
                                            change: '+ $_usersAddedThisMonth',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath:
                                                'assets/img/icon/gray_add_person_icon.png',
                                            label: 'Awaiting Approval',
                                            value: _awaitingApproval.toString(),
                                            change: '+ $_approvalsThisMonth',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath:
                                                'assets/img/icon/gray_speaker_icon.png',
                                            label: 'Total Announcements',
                                            value: _totalAnnouncements
                                                .toString(),
                                            change: '+ $_announcementsThisMonth',
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: InsightCard(
                                              iconPath:
                                                  'assets/img/icon/gray_group_icon.png',
                                              label: 'Total Users',
                                              value: _totalUsers.toString(),
                                              change: '+ $_usersAddedThisMonth',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath:
                                                  'assets/img/icon/gray_add_person_icon.png',
                                              label: 'Awaiting Approval',
                                              value: _awaitingApproval
                                                  .toString(),
                                              change: '+ $_approvalsThisMonth',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath:
                                                  'assets/img/icon/gray_speaker_icon.png',
                                              label: 'Total Announcements',
                                              value: _totalAnnouncements
                                                  .toString(),
                                              change: '+ $_announcementsThisMonth',
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
        ],
      ),
    );
  }
}
