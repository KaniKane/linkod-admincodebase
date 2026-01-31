import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/insight_card.dart';
import '../widgets/activity_item.dart';
import '../widgets/user_header.dart';
import '../utils/app_colors.dart';
import 'announcements_screen.dart';
import 'user_management_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _totalUsers = 0;
  int _awaitingApproval = 0;
  int _totalAnnouncements = 0;
  bool _isLoading = false;
  String? _errorMessage;
  final List<Map<String, dynamic>> _recentActivities = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final usersSnapshot =
          await FirebaseFirestore.instance.collection('users').get();
      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      final awaitingSnapshot = await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .get();

      final activities = <Map<String, dynamic>>[];
      for (final doc in announcementsSnapshot.docs) {
        final d = doc.data();
        final title = d['title'] as String? ?? 'Announcement';
        final postedBy = d['postedBy'] as String? ?? 'Barangay';
        final createdAt = d['createdAt'];
        String timestamp = '';
        if (createdAt != null && createdAt is Timestamp) {
          final dt = createdAt.toDate();
          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          timestamp = '${months[dt.month - 1]} ${dt.day}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
        }
        activities.add({
          'description': '$postedBy posted an announcement titled $title',
          'timestamp': timestamp,
          'boldText': title,
        });
      }

      setState(() {
        _totalUsers = usersSnapshot.size;
        _totalAnnouncements = announcementsSnapshot.size;
        _awaitingApproval = awaitingSnapshot.size;
        _recentActivities
          ..clear()
          ..addAll(activities);
        _isLoading = false;
      });
    } catch (e) {
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
            onNavigate: (route) {
              if (route == '/announcements') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AnnouncementsScreen(),
                  ),
                );
              } else if (route == '/user-management') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserManagementScreen(),
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
                                final isSmallScreen = constraints.maxWidth < 900;
                                return isSmallScreen
                                    ? Column(
                                        children: [
                                          InsightCard(
                                            iconPath: 'assets/img/icon/gray_group_icon.png',
                                            label: 'Total Users',
                                            value: _totalUsers.toString(),
                                            change: '+ 0',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath: 'assets/img/icon/gray_add_person_icon.png',
                                            label: 'Awaiting Approval',
                                            value: _awaitingApproval.toString(),
                                            change: '+ 0',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath: 'assets/img/icon/gray_speaker_icon.png',
                                            label: 'Total Announcements',
                                            value: _totalAnnouncements.toString(),
                                            change: '+ 0',
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_group_icon.png',
                                              label: 'Total Users',
                                              value: _totalUsers.toString(),
                                              change: '+ 0',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_add_person_icon.png',
                                              label: 'Awaiting Approval',
                                              value: _awaitingApproval.toString(),
                                              change: '+ 0',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_speaker_icon.png',
                                              label: 'Total Announcements',
                                              value: _totalAnnouncements.toString(),
                                              change: '+ 0',
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
                              const Center(
                                child: CircularProgressIndicator(),
                              ),
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
                                    ..._recentActivities.map((a) => ActivityItem(
                                          description: a['description'] as String,
                                          timestamp: a['timestamp'] as String,
                                          boldText: a['boldText'] as String?,
                                        )),
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
