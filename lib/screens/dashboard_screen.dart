import 'package:flutter/material.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/insight_card.dart';
import '../widgets/activity_item.dart';
import '../widgets/user_header.dart';
import '../utils/app_colors.dart';
import 'announcements_screen.dart';
import 'user_management_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
                                const Text(
                                  'Nov 1 - Today',
                                  style: TextStyle(
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
                                            value: '100',
                                            change: '+ 20',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath: 'assets/img/icon/gray_add_person_icon.png',
                                            label: 'Awaiting Approval',
                                            value: '5',
                                            change: '+ 5',
                                          ),
                                          const SizedBox(height: 16),
                                          InsightCard(
                                            iconPath: 'assets/img/icon/gray_speaker_icon.png',
                                            label: 'Total Announcements',
                                            value: '20',
                                            change: '+ 5',
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_group_icon.png',
                                              label: 'Total Users',
                                              value: '100',
                                              change: '+ 20',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_add_person_icon.png',
                                              label: 'Awaiting Approval',
                                              value: '5',
                                              change: '+ 5',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: InsightCard(
                                              iconPath: 'assets/img/icon/gray_speaker_icon.png',
                                              label: 'Total Announcements',
                                              value: '20',
                                              change: '+ 5',
                                            ),
                                          ),
                                        ],
                                      );
                              },
                            ),
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
                                  // Activity list
                                  const ActivityItem(
                                    description:
                                        'Noly Hinampas approved 5 new signup request.',
                                    timestamp: 'Nov 14, 4:30pm',
                                  ),
                                  const ActivityItem(
                                    description:
                                        'Loyda Pacheco posted an announcement titled Livelihood Training Program',
                                    timestamp: 'Nov 14, 1:24pm',
                                    boldText: 'Livelihood Training Program',
                                  ),
                                  const ActivityItem(
                                    description:
                                        'Junty Bandayanun decline 1 signup request',
                                    timestamp: 'Nov 3, 1:24pm',
                                  ),
                                  const ActivityItem(
                                    description:
                                        'Junty Bandayanun edited 1 user\'s demographic category',
                                    timestamp: 'Nov 3, 1:24pm',
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
