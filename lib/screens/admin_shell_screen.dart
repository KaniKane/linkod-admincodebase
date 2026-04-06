import 'package:flutter/material.dart';

import '../utils/admin_navigation.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'barangay_information_screen.dart';
import 'dashboard_screen.dart';
import 'user_management_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({
    super.key,
    this.initialRoute = '/dashboard',
  });

  final String initialRoute;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  static const List<String> _routes = <String>[
    '/dashboard',
    '/barangay-information',
    '/announcements',
    '/approvals',
    '/user-management',
  ];

  late String _currentRoute;
  late final Map<String, Widget> _pagesByRoute;

  @override
  void initState() {
    super.initState();
    _currentRoute = _normalizeRoute(widget.initialRoute);
    _pagesByRoute = <String, Widget>{
      _currentRoute: _createPageForRoute(_currentRoute),
    };
  }

  String _normalizeRoute(String route) {
    if (_routes.contains(route)) return route;
    return '/dashboard';
  }

  int _indexForRoute(String route) {
    final normalized = _normalizeRoute(route);
    return _routes.indexOf(normalized);
  }

  void _selectRoute(String route, {Widget? page}) {
    final normalized = _normalizeRoute(route);
    if (_currentRoute == normalized && page == null) {
      return;
    }

    if (page != null) {
      _pagesByRoute[normalized] = page;
    } else if (!_pagesByRoute.containsKey(normalized)) {
      _pagesByRoute[normalized] = _createPageForRoute(normalized);
    }

    setState(() {
      _currentRoute = normalized;
    });
  }

  Widget _createPageForRoute(String route) {
    return switch (route) {
      '/dashboard' => const DashboardScreen(),
      '/barangay-information' => const BarangayInformationScreen(),
      '/announcements' => const AnnouncementsScreen(),
      '/approvals' => const ApprovalsScreen(),
      '/user-management' => const UserManagementScreen(initialTabIndex: 2),
      _ => const DashboardScreen(),
    };
  }

  Widget _buildPageForRoute(String route) {
    final existingPage = _pagesByRoute[route];
    if (existingPage != null) {
      return existingPage;
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return AdminNavigationScope(
      currentRoute: _currentRoute,
      selectRoute: _selectRoute,
      child: IndexedStack(
        index: _indexForRoute(_currentRoute),
        children: _routes
            .map(_buildPageForRoute)
            .toList(growable: false),
      ),
    );
  }
}
