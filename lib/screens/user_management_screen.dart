import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/search_bar.dart';
import '../widgets/custom_button.dart';
import '../widgets/outline_button.dart';
import '../widgets/accept_decline_buttons.dart';
import '../widgets/audience_tag.dart';
import '../widgets/dialog_container.dart';
import '../widgets/error_notification.dart';
import '../widgets/decline_reason_dialog.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/fast_fade_in.dart';
import '../api/announcement_backend_api.dart';
import '../utils/app_colors.dart';
import '../utils/admin_navigation.dart';
import 'dashboard_screen.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'barangay_information_screen.dart';

enum _UsersSortOption { nameAsc, nameDesc, dateNewest, dateOldest }

enum _UsersDateFilter { allTime, today, last7Days, last30Days, custom }

const List<String> _mainDemographicOptions = [
  'Senior',
  'Pregnant/Lactating Mother',
  'Student',
  'PWD',
  'Youth',
  'Farmer',
  'Fisherman',
  'Public Utility Drivers',
  'Small Business Owner',
  '4Ps',
  'Tanod',
  'Barangay Official',
  'Barangay Health Worker(BHW)',
  'Indigenous People(IP)',
  'Parent',
];

const List<String> _mainPurokOptions = [
  'Purok 1',
  'Purok 2',
  'Purok 3',
  'Purok 4',
  'Purok 5',
];

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({
    super.key,
    this.initialTabIndex = 0,
    this.showAcceptedUsersOnly = false,
    this.rememberLastTab = true,
  });

  final int initialTabIndex;
  final bool showAcceptedUsersOnly;
  final bool rememberLastTab;

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  static const String _lastTabPrefsKey = 'user_management_last_tab';
  static const String _usersFilterAll = '__all__';
  static const String _usersFilterNoPurok = '__no_purok__';

  int _activeTabIndex = 0;
  final _searchController = TextEditingController();
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final Set<int> _selectedIndices = {};

  _UsersSortOption _usersSortOption = _UsersSortOption.nameAsc;
  _UsersDateFilter _usersDateFilter = _UsersDateFilter.allTime;
  DateTimeRange? _usersCustomDateRange;
  String _usersPurokFilter = _usersFilterAll;
  String _usersDemographicFilter = _usersFilterAll;

  bool _isLoading = false;
  String? _errorMessage;

  // Users data (loaded from Firestore)
  List<Map<String, String>> _users = [];

  // Admins data (loaded from Firestore)
  List<Map<String, String>> _admins = [];

  // Awaiting Approval data (loaded from Firestore)
  List<Map<String, String>> _awaitingApproval = [];

  // Inactive (declined/suspended) for reactivation
  List<Map<String, String>> _inactive = [];

  // Current user role for permission checks
  String? _currentUserRole;

  // Pending counts for sidebar badges
  int _pendingApprovalsCount = 0;
  int _lastHandledRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex.clamp(0, 3);
    if (widget.rememberLastTab) {
      _restoreLastTabIndex();
    } else {
      _persistActiveTabIndex();
    }
    _loadAccounts();
    _loadCurrentUserRole();
    _loadPendingApprovalsCount();
    _lastHandledRefreshTick = AdminRefreshBus.userManagementRefreshTick.value;
    AdminRefreshBus.userManagementRefreshTick.addListener(
      _handleExternalRefreshRequest,
    );
  }

  Future<void> _restoreLastTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_lastTabPrefsKey);
    if (savedIndex == null || !mounted) return;
    final normalized = savedIndex.clamp(0, 3);
    if (normalized == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = normalized;
      _currentPage = 1;
      _selectedIndices.clear();
    });
  }

  Future<void> _persistActiveTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastTabPrefsKey, _activeTabIndex.clamp(0, 3));
  }

  void _setActiveTab(int index) {
    final nextIndex = index.clamp(0, 3);
    if (nextIndex == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = nextIndex;
      _currentPage = 1;
      _selectedIndices.clear();
    });
    _persistActiveTabIndex();
  }

  String _stripLinkodEmailSuffix(String value) {
    final trimmed = value.trim();
    const suffix = '@linkod.com';
    if (trimmed.toLowerCase().endsWith(suffix)) {
      return trimmed.substring(0, trimmed.length - suffix.length);
    }
    return trimmed;
  }

  String _residentDisplayContact({
    required String phone,
    required String email,
  }) {
    final phoneValue = phone.trim();
    if (phoneValue.isNotEmpty) return phoneValue;
    return _stripLinkodEmailSuffix(email);
  }

  int? _extractEpochMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return null;
  }

  Future<void> _loadPendingApprovalsCount() async {
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
    if (mounted) {
      setState(() {
        _pendingApprovalsCount =
            pendingAnnouncements + pendingProducts + pendingTasks;
      });
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
          setState(() {
            _currentUserRole = role;
          });
          if (role != 'super_admin' && mounted) {
            if (!context.mounted) return;
            navigateToAdminScreen(
              context,
              currentRoute: '/user-management',
              targetRoute: '/dashboard',
              page: const DashboardScreen(),
            );
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _currentUserRole = 'admin';
          });
        }
      }
    }
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      final awaitingSnapshot = await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .get();

      final loadedUsers = <Map<String, String>>[];
      final loadedAdmins = <Map<String, String>>[];
      final loadedAwaiting = <Map<String, String>>[];
      final loadedInactive = <Map<String, String>>[];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final accountStatus = (data['accountStatus'] as String?)?.toLowerCase();
        final status = (data['status'] as String?)?.toLowerCase();
        final fullName = (data['fullName'] ?? '') as String;
        final email = (data['email'] ?? '') as String;
        final phoneNumber = (data['phoneNumber'] ?? '') as String;
        final contact = email.isNotEmpty ? email : phoneNumber;
        final residentContact = _residentDisplayContact(
          phone: phoneNumber,
          email: email,
        );
        final role = ((data['role'] ?? '') as String).toLowerCase();
        final position = (data['position'] ?? '') as String;
        final demographicCategory =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;
        final purok = (data['purok'] ?? '').toString().trim();

        if (accountStatus == 'declined' || accountStatus == 'suspended') {
          loadedInactive.add({
            'id': doc.id,
            'name': fullName.isNotEmpty ? fullName : 'Unnamed',
            'phone': contact,
            'purok': purok,
            'category': role == 'super_admin' || role == 'admin'
                ? (position.isNotEmpty ? position : 'Admin')
                : (demographicCategory.isNotEmpty
                      ? demographicCategory
                      : 'User'),
            'status': accountStatus == 'suspended' ? 'suspended' : 'declined',
          });
          continue;
        }

        // Only two roles: super_admin and admin. Position is a label (e.g. Barangay Secretary).
        if (role == 'super_admin' || role == 'admin') {
          loadedAdmins.add({
            'id': doc.id,
            'name': fullName.isNotEmpty ? fullName : 'Unnamed admin',
            'phone': contact,
            'purok': purok,
            'position': position.isNotEmpty ? position : 'Admin',
          });
        } else {
          if (widget.showAcceptedUsersOnly) {
            final isAccepted =
                accountStatus == 'active' ||
                accountStatus == 'accepted' ||
                status == 'accepted';
            if (!isAccepted) continue;
          }
          final mainDemographics = _extractMainDemographics(data);
          final subDemographies = _extractSubDemographies(data);
          loadedUsers.add({
            'id': doc.id,
            'name': fullName.isNotEmpty ? fullName : 'Unnamed user',
            'phone': residentContact,
            'purok': purok,
            'createdAtEpoch': (_extractEpochMillis(data['createdAt']) ?? '')
                .toString(),
            'demographics': mainDemographics.join(', '),
            'mainCategory': mainDemographics.join(', '),
            'subDemographies': subDemographies.join(', '),
            'category': demographicCategory.isNotEmpty
                ? demographicCategory
                : (role.isNotEmpty ? role : 'User'),
          });
        }
      }

      for (final doc in awaitingSnapshot.docs) {
        final data = doc.data();
        final fullName = (data['fullName'] ?? '') as String;
        final phoneNumber = (data['phoneNumber'] ?? '') as String;
        final email = (data['email'] ?? '') as String;
        final role = ((data['role'] ?? '') as String).toLowerCase();
        final userType = ((data['userType'] ?? '') as String).toLowerCase();
        final inferredUserType = userType.isNotEmpty
            ? userType
            : ((role == 'admin' || role == 'super_admin')
                  ? 'admin'
                  : 'resident');
        final awaitingContact = inferredUserType == 'admin'
            ? (phoneNumber.isNotEmpty ? phoneNumber : email)
            : _residentDisplayContact(phone: phoneNumber, email: email);
        final position = (data['position'] ?? '') as String;
        final purok = (data['purok'] ?? '').toString().trim();
        final category =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;
        final subDemographyEnabled = data['subDemographyEnabled'] == true;
        final subDemographies =
            (data['subDemographies'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

        final mainCategory = role == 'admin' || role == 'super_admin'
            ? (position.isNotEmpty ? position : 'Admin')
            : (category.isNotEmpty ? category : 'User');

        loadedAwaiting.add({
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unnamed user',
          'phone': awaitingContact,
          'email': email,
          'purok': purok,
          'category': mainCategory,
          'mainCategory': mainCategory,
          'role': role,
          'userType': inferredUserType,
          'position': position,
          'subDemographyEnabled': subDemographyEnabled ? 'true' : 'false',
          'subDemographies': subDemographies.join(', '),
          'source': 'awaitingApproval',
        });
      }
      // Re-applications: users who were declined and re-applied (accountStatus == 'pending')
      // Skip users who already have an entry in awaitingApproval to avoid duplicates
      final awaitingIds = loadedAwaiting.map((a) => a['id']).toSet();
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        if ((data['accountStatus'] as String?)?.toLowerCase() != 'pending')
          continue;
        // Skip if this user already has an awaitingApproval document
        if (awaitingIds.contains(doc.id)) continue;
        final fullName = (data['fullName'] ?? '') as String;
        final phoneNumber = (data['phoneNumber'] ?? '') as String;
        final email = (data['email'] ?? '') as String;
        final role = ((data['role'] ?? '') as String).toLowerCase();
        final userType = ((data['userType'] ?? '') as String).toLowerCase();
        final inferredUserType = userType.isNotEmpty
            ? userType
            : ((role == 'admin' || role == 'super_admin')
                  ? 'admin'
                  : 'resident');
        final awaitingContact = inferredUserType == 'admin'
            ? (phoneNumber.isNotEmpty ? phoneNumber : email)
            : _residentDisplayContact(phone: phoneNumber, email: email);
        final position = (data['position'] ?? '') as String;
        final purok = (data['purok'] ?? '').toString().trim();
        final category =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;
        final subDemographyEnabled = data['subDemographyEnabled'] == true;
        final subDemographies =
            (data['subDemographies'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
        final mainCategory = category.isNotEmpty ? category : 'User';
        loadedAwaiting.add({
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unnamed user',
          'phone': awaitingContact,
          'email': email,
          'purok': purok,
          'category': mainCategory,
          'mainCategory': mainCategory,
          'role': role,
          'userType': inferredUserType,
          'position': position,
          'subDemographyEnabled': subDemographyEnabled ? 'true' : 'false',
          'subDemographies': subDemographies.join(', '),
          'source': 'users',
          'reapplication': 'true',
        });
      }

      if (!mounted) return;
      setState(() {
        _users = loadedUsers;
        _admins = loadedAdmins;
        _awaitingApproval = loadedAwaiting;
        _inactive = loadedInactive;
        _selectedIndices.clear();
        _isLoading = false;
      });
      AdminRefreshBus.publishPendingUsersCount(loadedAwaiting.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load accounts: $e';
      });
    }
  }

  @override
  void dispose() {
    AdminRefreshBus.userManagementRefreshTick.removeListener(
      _handleExternalRefreshRequest,
    );
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleExternalRefreshRequest() async {
    final nextTick = AdminRefreshBus.userManagementRefreshTick.value;
    if (nextTick == _lastHandledRefreshTick) return;
    _lastHandledRefreshTick = nextTick;
    await _loadAccounts();
    await _loadPendingApprovalsCount();
  }

  void _navigateTo(String route) {
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
    if (route == '/dashboard') {
      navigateToAdminScreen(
        context,
        currentRoute: '/user-management',
        targetRoute: route,
        page: const DashboardScreen(),
      );
    } else if (route == '/announcements') {
      navigateToAdminScreen(
        context,
        currentRoute: '/user-management',
        targetRoute: route,
        page: const AnnouncementsScreen(),
      );
    } else if (route == '/approvals') {
      navigateToAdminScreen(
        context,
        currentRoute: '/user-management',
        targetRoute: route,
        page: const ApprovalsScreen(),
      );
    } else if (route == '/barangay-information') {
      navigateToAdminScreen(
        context,
        currentRoute: '/user-management',
        targetRoute: route,
        page: const BarangayInformationScreen(),
      );
    }
  }

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  String _normalizePurok(String purok) => purok.trim().toLowerCase();

  String _normalizePurokSelection(String purok) {
    final normalized = purok.trim().toLowerCase();
    final match = RegExp(r'\b(\d+)\b').firstMatch(normalized);
    if (match != null) {
      return match.group(1)!;
    }
    return normalized.replaceAll(RegExp(r'^purok\s+'), '').trim();
  }

  List<String> _extractDemographics(Map<String, dynamic> data) {
    final categories = data['categories'];
    if (categories is List) {
      final normalized = categories
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (normalized.isNotEmpty) return normalized;
    }

    final category = (data['category'] ?? data['demographicCategory'] ?? '')
        .toString()
        .trim();
    if (category.isEmpty) return const [];

    return category
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  List<String> _extractSubDemographies(Map<String, dynamic> data) {
    final raw = data['subDemographies'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }

    if (raw is String) {
      return raw
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }

    return const [];
  }

  List<String> _extractMainDemographics(Map<String, dynamic> data) {
    final demographics = _extractDemographics(data);
    final subDemographies = _extractSubDemographies(data);
    if (subDemographies.isEmpty) return demographics;

    final subLookup = subDemographies
        .map((value) => value.toLowerCase())
        .toSet();
    final mainOnly = demographics
        .where((value) => !subLookup.contains(value.toLowerCase()))
        .toList();

    if (mainOnly.isNotEmpty) return mainOnly;

    final fallbackMain = (data['demographicCategory'] ?? '')
        .toString()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .where((value) => !subLookup.contains(value.toLowerCase()))
        .toList();
    return fallbackMain;
  }

  bool _matchesDemographicFilter(Map<String, String> user) {
    if (_usersDemographicFilter == _usersFilterAll) return true;

    final target = _usersDemographicFilter.toLowerCase();
    final values = <String>{
      ...(user['demographics'] ?? '')
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
      ...(user['subDemographies'] ?? '')
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
      ...(user['category'] ?? '')
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
    };

    return values.contains(target);
  }

  int _createdAtEpochForUser(Map<String, String> user) {
    return int.tryParse((user['createdAtEpoch'] ?? '').trim()) ?? -1;
  }

  String _usersSortLabel(_UsersSortOption option) {
    switch (option) {
      case _UsersSortOption.nameAsc:
        return 'Name (A-Z)';
      case _UsersSortOption.nameDesc:
        return 'Name (Z-A)';
      case _UsersSortOption.dateNewest:
        return 'Date (Newest)';
      case _UsersSortOption.dateOldest:
        return 'Date (Oldest)';
    }
  }

  String _usersDateFilterLabel(_UsersDateFilter option) {
    switch (option) {
      case _UsersDateFilter.allTime:
        return 'All time';
      case _UsersDateFilter.today:
        return 'Today';
      case _UsersDateFilter.last7Days:
        return 'Last 7 days';
      case _UsersDateFilter.last30Days:
        return 'Last 30 days';
      case _UsersDateFilter.custom:
        return 'Custom range';
    }
  }

  List<String> get _usersPurokOptions {
    final values =
        _users
            .map((u) => (u['purok'] ?? '').trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  bool _matchesPurokFilter(Map<String, String> user) {
    if (_usersPurokFilter == _usersFilterAll) return true;
    if (_usersPurokFilter == _usersFilterNoPurok) {
      return (user['purok'] ?? '').trim().isEmpty;
    }

    final selected = _normalizePurokSelection(_usersPurokFilter);
    final userPurok = _normalizePurokSelection(user['purok'] ?? '');
    if (selected.isEmpty || userPurok.isEmpty) return false;
    return userPurok == selected;
  }

  List<String> get _usersDemographicOptions {
    final subDemographyOptions =
        _users
            .map((user) => (user['subDemographies'] ?? '').trim())
            .where((value) => value.isNotEmpty)
            .expand((value) => value.split(','))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final seen = <String>{};
    final merged = <String>[];
    for (final value in [..._mainDemographicOptions, ...subDemographyOptions]) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        merged.add(value);
      }
    }
    return merged;
  }

  bool _matchesUsersDateFilter(Map<String, String> user) {
    if (_usersDateFilter == _UsersDateFilter.allTime) return true;
    final epoch = _createdAtEpochForUser(user);
    if (epoch <= 0) return false;

    final createdAt = DateTime.fromMillisecondsSinceEpoch(epoch);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (_usersDateFilter) {
      case _UsersDateFilter.allTime:
        return true;
      case _UsersDateFilter.today:
        return createdAt.isAfter(todayStart) || createdAt == todayStart;
      case _UsersDateFilter.last7Days:
        final start = todayStart.subtract(const Duration(days: 6));
        return createdAt.isAfter(start) || createdAt == start;
      case _UsersDateFilter.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return createdAt.isAfter(start) || createdAt == start;
      case _UsersDateFilter.custom:
        final range = _usersCustomDateRange;
        if (range == null) return true;
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        );
        return !createdAt.isBefore(start) && !createdAt.isAfter(end);
    }
  }

  void _resetUsersFilters() {
    setState(() {
      _usersSortOption = _UsersSortOption.nameAsc;
      _usersDateFilter = _UsersDateFilter.allTime;
      _usersCustomDateRange = null;
      _usersPurokFilter = _usersFilterAll;
      _usersDemographicFilter = _usersFilterAll;
      _currentPage = 1;
      _selectedIndices.clear();
    });
  }

  Future<void> _handleUsersDateFilterChanged(_UsersDateFilter? value) async {
    if (value == null) return;
    if (value == _UsersDateFilter.custom) {
      final now = DateTime.now();
      final pickedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _usersCustomDateRange,
      );
      if (!mounted || pickedRange == null) return;
      setState(() {
        _usersDateFilter = _UsersDateFilter.custom;
        _usersCustomDateRange = pickedRange;
        _currentPage = 1;
        _selectedIndices.clear();
      });
      return;
    }

    setState(() {
      _usersDateFilter = value;
      _currentPage = 1;
      _selectedIndices.clear();
    });
  }

  List<Map<String, String>> get _filteredUsers {
    final query = _searchQuery;
    final filtered = _users.where((u) {
      final name = (u['name'] ?? '').toLowerCase();
      final phone = (u['phone'] ?? '').toLowerCase();
      final purokRaw = (u['purok'] ?? '').trim();
      final purokNormalized = _normalizePurok(purokRaw);
      final category = (u['category'] ?? '').trim();

      if (query.isNotEmpty &&
          !(name.contains(query) ||
              phone.contains(query) ||
              purokRaw.toLowerCase().contains(query) ||
              category.toLowerCase().contains(query))) {
        return false;
      }

      if (_usersPurokFilter == _usersFilterNoPurok && purokRaw.isNotEmpty) {
        return false;
      }
      if (!_matchesPurokFilter(u)) {
        return false;
      }

      if (_usersDemographicFilter != _usersFilterAll &&
          !_matchesDemographicFilter(u)) {
        return false;
      }

      if (!_matchesUsersDateFilter(u)) return false;

      return true;
    }).toList();

    filtered.sort((a, b) {
      final aName = (a['name'] ?? '').toLowerCase();
      final bName = (b['name'] ?? '').toLowerCase();
      final aDate = _createdAtEpochForUser(a);
      final bDate = _createdAtEpochForUser(b);
      switch (_usersSortOption) {
        case _UsersSortOption.nameAsc:
          return aName.compareTo(bName);
        case _UsersSortOption.nameDesc:
          return bName.compareTo(aName);
        case _UsersSortOption.dateNewest:
          return bDate.compareTo(aDate);
        case _UsersSortOption.dateOldest:
          return aDate.compareTo(bDate);
      }
    });

    return filtered;
  }

  List<Map<String, String>> get _filteredAdmins {
    if (_searchQuery.isEmpty) return _admins;
    return _admins.where((u) {
      final name = (u['name'] ?? '').toLowerCase();
      final phone = (u['phone'] ?? '').toLowerCase();
      final position = (u['position'] ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          position.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, String>> get _filteredInactive {
    if (_searchQuery.isEmpty) return _inactive;
    return _inactive.where((u) {
      final name = (u['name'] ?? '').toLowerCase();
      final phone = (u['phone'] ?? '').toLowerCase();
      final cat = (u['category'] ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          cat.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, String>> get _filteredAwaiting {
    if (_searchQuery.isEmpty) return _awaitingApproval;
    return _awaitingApproval.where((u) {
      final name = (u['name'] ?? '').toLowerCase();
      final phone = (u['phone'] ?? '').toLowerCase();
      final cat = (u['category'] ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          cat.contains(_searchQuery);
    }).toList();
  }

  int get _totalRecords {
    switch (_activeTabIndex) {
      case 0:
        return _filteredUsers.length;
      case 1:
        return _filteredAdmins.length;
      case 2:
        return _filteredAwaiting.length;
      case 3:
        return _filteredInactive.length;
      default:
        return 0;
    }
  }

  List<Map<String, String>> get _currentList {
    switch (_activeTabIndex) {
      case 0:
        return _filteredUsers;
      case 1:
        return _filteredAdmins;
      case 2:
        return _filteredAwaiting;
      case 3:
        return _filteredInactive;
      default:
        return [];
    }
  }

  int get _effectiveCurrentPage => _currentPage.clamp(1, _totalPages);

  int get _paginatedStartIndex =>
      ((_effectiveCurrentPage - 1) * _itemsPerPage).clamp(0, _totalRecords);

  List<Map<String, String>> get _paginatedList {
    final list = _currentList;
    final start = _paginatedStartIndex;
    if (start >= list.length) return [];
    final end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  int get _totalPages {
    if (_totalRecords == 0) return 1;
    return (_totalRecords / _itemsPerPage).ceil();
  }

  void _handlePreviousPage() {
    if (_currentPage > 1) {
      setState(() {
        _currentPage--;
      });
    }
  }

  void _handleNextPage() {
    if (_currentPage < _totalPages) {
      setState(() {
        _currentPage++;
      });
    }
  }

  void _handleItemsPerPageChange(String? value) {
    if (value != null) {
      setState(() {
        _itemsPerPage = int.parse(value);
        _currentPage = 1;
      });
    }
  }

  void _handleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedIndices.clear();
        for (int i = 0; i < _currentList.length; i++) {
          _selectedIndices.add(i);
        }
      } else {
        _selectedIndices.clear();
      }
    });
  }

  void _handleSelectItem(int index, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIndices.add(index);
      } else {
        _selectedIndices.remove(index);
      }
    });
  }

  List<Map<String, String>> _selectedAwaitingItems() {
    if (_activeTabIndex != 2 || _selectedIndices.isEmpty) return const [];
    final list = _currentList;
    final selected = _selectedIndices.toList()..sort();
    return selected
        .where((index) => index >= 0 && index < list.length)
        .map((index) => list[index])
        .toList();
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  }

  Future<void> _approveSelectedAwaiting() async {
    final selectedItems = _selectedAwaitingItems();
    if (selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve selected requests'),
        content: Text('Approve ${selectedItems.length} selected request(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve all'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final item in selectedItems) {
      final docId = item['id'] ?? '';
      if (docId.isEmpty) continue;
      final isReapplication = item['source'] == 'users';
      if (isReapplication) {
        await _approveReapplication(docId);
      } else {
        String? approvedRole;
        final userType = (item['userType'] ?? '').toLowerCase();
        if (userType == 'admin') {
          final selectedRole = await _showAdminRolePicker();
          if (selectedRole == null) {
            continue;
          }
          approvedRole = selectedRole;
        }
        await _approveAwaiting(docId, item, approvedRole: approvedRole);
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedIndices.clear();
    });
  }

  Future<void> _declineSelectedAwaiting() async {
    final selectedItems = _selectedAwaitingItems();
    if (selectedItems.isEmpty) return;

    final result = await showDialog<DeclineReasonResult>(
      context: context,
      builder: (context) => DeclineReasonDialog(
        title: 'Reason for declining selected requests',
        submitLabel: 'Decline all',
        showStatusDropdown: false,
      ),
    );
    if (result == null) return;

    for (final item in selectedItems) {
      final docId = item['id'] ?? '';
      if (docId.isEmpty) continue;
      await _declineAwaiting(docId, result.reason, item, result.reapplyType);
    }

    if (!mounted) return;
    setState(() {
      _selectedIndices.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          // Sidebar
          AppSidebar(
            currentRoute: '/user-management',
            currentUserRole: _currentUserRole,
            pendingApprovalsCount: _pendingApprovalsCount,
            pendingUsersCount: _awaitingApproval.length,
            onNavigate: _navigateTo,
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
                          'User Management',
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
                        child: Column(
                          children: [
                            // Tabs bar at top of inner panel
                            _buildTabsBar(),
                            // Content area
                            Expanded(
                              child: Column(
                                children: [
                                  // Action bar (search + add button)
                                  if (_activeTabIndex ==
                                      1) // Awaiting Approval tab
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        32,
                                        24,
                                        32,
                                        16,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: CustomSearchBar(
                                                  placeholder:
                                                      'Search awaiting request',
                                                  controller: _searchController,
                                                  onChanged: (_) => setState(
                                                    () {
                                                      _currentPage = 1;
                                                      _selectedIndices.clear();
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: CustomSearchBar(
                                                  placeholder:
                                                      _activeTabIndex == 0
                                                      ? 'Search user'
                                                      : _activeTabIndex == 1
                                                      ? 'Search admin'
                                                      : 'Search inactive',
                                                  controller: _searchController,
                                                  onChanged: (_) => setState(
                                                    () {
                                                      _currentPage = 1;
                                                      _selectedIndices.clear();
                                                    },
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Users tab: "Add New User" button
                                              if (_activeTabIndex == 0)
                                                CustomButton(
                                                  text: 'Add New User',
                                                  onPressed: () =>
                                                      _showAddAccountDialog(
                                                        isAdmin: false,
                                                      ),
                                                  isFullWidth: false,
                                                )
                                              // Admins tab: "Create Official Account" button (SUPER ADMIN only)
                                              else if (_activeTabIndex == 1 &&
                                                  _currentUserRole ==
                                                      'super_admin')
                                                CustomButton(
                                                  text:
                                                      'Create Official Account',
                                                  onPressed: () =>
                                                      _showCreateOfficialAccountDialog(),
                                                  isFullWidth: false,
                                                )
                                              // Inactive tab: no add button
                                              else if (_activeTabIndex == 3)
                                                const SizedBox.shrink(),
                                            ],
                                          ),
                                          if (_activeTabIndex == 0) ...[
                                            const SizedBox(height: 12),
                                            _buildUsersFilterControls(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  // Table content
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                      ),
                                      child: _isLoading
                                          ? const Padding(
                                              padding: EdgeInsets.only(top: 48),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            )
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                if (_errorMessage != null) ...[
                                                  ErrorNotification(
                                                    message: _errorMessage!,
                                                  ),
                                                  const SizedBox(height: 16),
                                                ],
                                                _buildTable(),
                                              ],
                                            ),
                                    ),
                                  ),
                                  // Footer
                                  Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: _buildTableFooter(),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

  Widget _buildTabsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Users', 0),
          const SizedBox(width: 32),
          // Admins tab: SUPER ADMIN only
          if (_currentUserRole == 'super_admin') ...[
            _buildTab('Admins', 1),
            const SizedBox(width: 32),
          ],
          _buildTab(
            'Awaiting Approval',
            2,
            // Only show badge if not currently viewing this tab
            badgeCount: _activeTabIndex == 2 ? 0 : _awaitingApproval.length,
          ),
          const SizedBox(width: 32),
          _buildTab('Inactive', 3),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, {int badgeCount = 0}) {
    final isActive = _activeTabIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _setActiveTab(index),
        child: Container(
          padding: const EdgeInsets.only(bottom: 16, top: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppColors.primaryGreen : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: isActive ? AppColors.darkGrey : AppColors.mediumGrey,
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryGreen
                        : AppColors.deleteRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    // If OFFICIAL/STAFF tries to access Admins tab (index 1), show empty or redirect
    if (_activeTabIndex == 1 && _currentUserRole != 'super_admin') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Access restricted. Only SUPER ADMIN can view admin accounts.',
            style: TextStyle(color: AppColors.mediumGrey),
          ),
        ),
      );
    }

    switch (_activeTabIndex) {
      case 0:
        return _buildUsersTable();
      case 1:
        return _buildAdminsTable();
      case 2:
        return _buildAwaitingApprovalTable();
      case 3:
        return _buildInactiveTable();
      default:
        return const SizedBox();
    }
  }

  Widget _buildUsersFilterControls() {
    final purokItems = [
      _usersFilterAll,
      _usersFilterNoPurok,
      ..._mainPurokOptions,
    ];
    final demographicItems = [_usersFilterAll, ..._usersDemographicOptions];
    final selectedPurok = purokItems.contains(_usersPurokFilter)
        ? _usersPurokFilter
        : _usersFilterAll;
    final selectedDemographic =
        demographicItems.contains(_usersDemographicFilter)
        ? _usersDemographicFilter
        : _usersFilterAll;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildUsersFilterDropdown<_UsersSortOption>(
          width: 180,
          value: _usersSortOption,
          labelText: 'Sort',
          items: _UsersSortOption.values,
          itemLabelBuilder: _usersSortLabel,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _usersSortOption = value;
              _currentPage = 1;
              _selectedIndices.clear();
            });
          },
        ),
        _buildUsersFilterDropdown<_UsersDateFilter>(
          width: 170,
          value: _usersDateFilter,
          labelText: 'Date',
          items: _UsersDateFilter.values,
          itemLabelBuilder: _usersDateFilterLabel,
          onChanged: (value) {
            _handleUsersDateFilterChanged(value);
          },
        ),
        _buildUsersFilterDropdown<String>(
          width: 180,
          value: selectedPurok,
          labelText: 'Purok',
          items: purokItems,
          itemLabelBuilder: (value) {
            if (value == _usersFilterAll) return 'All Purok';
            if (value == _usersFilterNoPurok) return 'No Purok';
            return value;
          },
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _usersPurokFilter = value;
              _currentPage = 1;
              _selectedIndices.clear();
            });
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUsersFilterDropdown<String>(
              width: 220,
              value: selectedDemographic,
              labelText: 'Demographic',
              items: demographicItems,
              itemLabelBuilder: (value) {
                if (value == _usersFilterAll) return 'All Demographics';
                return value;
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _usersDemographicFilter = value;
                  _currentPage = 1;
                  _selectedIndices.clear();
                });
              },
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: OutlineButton(
                text: 'Reset Filters',
                onPressed: _resetUsersFilters,
                isFullWidth: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUsersFilterDropdown<T>({
    required double width,
    required T value,
    required String labelText,
    required List<T> items,
    required String Function(T value) itemLabelBuilder,
    required void Function(T? value) onChanged,
  }) {
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: const TextStyle(
            fontSize: 12,
            color: AppColors.mediumGrey,
          ),
          isDense: true,
          filled: true,
          fillColor: AppColors.inputBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.loginGreen),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            onChanged: onChanged,
            items: items
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      itemLabelBuilder(item),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddAccountDialog({required bool isAdmin}) async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final roleController = TextEditingController(
      text: isAdmin ? 'admin' : 'user',
    );
    // For selectable position / demographic options
    final Set<String> selectedCategories = {};
    String? selectedPosition;
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    bool passwordObscure = true;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxDialogHeight,
                    ),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isAdmin ? 'Add New Admin' : 'Add New User',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.loginGreen,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildDialogTextField(
                            label: 'Full Name',
                            controller: nameController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Email',
                            controller: emailController,
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) {
                                return 'Email is required';
                              }
                              if (!_isValidEmail(email)) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildDialogPasswordField(
                            label: 'Password (min 6 characters)',
                            controller: passwordController,
                            obscure: passwordObscure,
                            onToggle: () => setState(
                              () => passwordObscure = !passwordObscure,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          if (isAdmin)
                            _buildPositionSelector(
                              selectedPosition: selectedPosition,
                              onSelect: (value) {
                                setState(() {
                                  selectedPosition = value;
                                });
                              },
                            )
                          else
                            _buildDemographicSelector(
                              selectedCategories: selectedCategories,
                              onToggle: (value) {
                                setState(() {
                                  if (selectedCategories.contains(value)) {
                                    selectedCategories.remove(value);
                                  } else {
                                    selectedCategories.add(value);
                                  }
                                });
                              },
                            ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Role',
                            controller: roleController,
                            enabled: false,
                          ),
                          const SizedBox(height: 16),
                          if (dialogError != null) ...[
                            ErrorNotification(message: dialogError!),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlineButton(
                                text: 'Cancel',
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.loginGreen,
                                  foregroundColor: AppColors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate()) {
                                          return;
                                        }

                                        if (isAdmin &&
                                            (selectedPosition == null)) {
                                          setState(() {
                                            dialogError =
                                                'Please select a position';
                                          });
                                          return;
                                        }
                                        if (!isAdmin &&
                                            selectedCategories.isEmpty) {
                                          setState(() {
                                            dialogError =
                                                'Please select at least one demographic category';
                                          });
                                          return;
                                        }

                                        setState(() {
                                          isSubmitting = true;
                                          dialogError = null;
                                        });

                                        try {
                                          final name = nameController.text
                                              .trim();
                                          final email = emailController.text
                                              .trim()
                                              .toLowerCase();
                                          final password =
                                              passwordController.text;
                                          if (!_isValidEmail(email)) {
                                            setState(() {
                                              dialogError =
                                                  'Valid email is required';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }
                                          if (password.isEmpty ||
                                              password.length < 6) {
                                            setState(() {
                                              dialogError =
                                                  'Password must be at least 6 characters';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }

                                          final now =
                                              FieldValue.serverTimestamp();
                                          final firestoreRole = isAdmin
                                              ? 'admin'
                                              : 'resident';

                                          FirebaseApp secondaryApp;
                                          try {
                                            secondaryApp = Firebase.app(
                                              'AuthHelper',
                                            );
                                          } catch (_) {
                                            secondaryApp =
                                                await Firebase.initializeApp(
                                                  name: 'AuthHelper',
                                                  options:
                                                      Firebase.app().options,
                                                );
                                          }
                                          final authHelper =
                                              FirebaseAuth.instanceFor(
                                                app: secondaryApp,
                                              );
                                          UserCredential? userCredential;
                                          try {
                                            userCredential = await authHelper
                                                .createUserWithEmailAndPassword(
                                                  email: email,
                                                  password: password,
                                                );
                                          } on FirebaseAuthException catch (e) {
                                            if (e.code ==
                                                'email-already-in-use') {
                                              userCredential = await authHelper
                                                  .signInWithEmailAndPassword(
                                                    email: email,
                                                    password: password,
                                                  );
                                            } else {
                                              rethrow;
                                            }
                                          }
                                          final newUser = userCredential?.user;
                                          if (newUser == null) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to create account.';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }
                                          final uid = newUser.uid;

                                          final data = <String, dynamic>{
                                            'userId': uid,
                                            'fullName': name,
                                            'phoneNumber': '',
                                            'email': email,
                                            'role': firestoreRole,
                                            'userType': isAdmin
                                                ? 'admin'
                                                : 'resident',
                                            'createdAt': now,
                                            'updatedAt': now,
                                            'isActive': true,
                                            'isApproved': true,
                                          };
                                          if (isAdmin) {
                                            data['position'] =
                                                selectedPosition ?? 'Admin';
                                          } else {
                                            data['category'] =
                                                selectedCategories.isEmpty
                                                ? 'User'
                                                : selectedCategories.join(', ');
                                            data['categories'] =
                                                selectedCategories.toList();
                                          }

                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(uid)
                                              .set(data);

                                          final verifyDoc =
                                              await FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(uid)
                                                  .get();
                                          if (!verifyDoc.exists) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to create user document. Please try again.';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }

                                          await authHelper.signOut();

                                          String adminName =
                                              'Barangay Official';
                                          final adminUid = FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid;
                                          if (adminUid != null) {
                                            final adminDoc =
                                                await FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(adminUid)
                                                    .get();
                                            if (adminDoc.exists) {
                                              adminName =
                                                  (adminDoc.data()?['fullName']
                                                      as String?) ??
                                                  adminName;
                                            }
                                          }
                                          await FirebaseFirestore.instance
                                              .collection('adminActivities')
                                              .add({
                                                'type': 'user_created',
                                                'description':
                                                    '$adminName added user $name',
                                                'fullName': name,
                                                'createdAt':
                                                    FieldValue.serverTimestamp(),
                                              });

                                          if (mounted) {
                                            await _loadAccounts();
                                            Navigator.of(context).pop();
                                          }
                                        } on FirebaseAuthException catch (e) {
                                          String msg;
                                          switch (e.code) {
                                            case 'email-already-in-use':
                                              msg =
                                                  'An account already exists for this email. Please use a different email or reset the password.';
                                              break;
                                            case 'invalid-email':
                                              msg =
                                                  'The provided email is invalid.';
                                              break;
                                            case 'operation-not-allowed':
                                              msg =
                                                  'Email/password sign-in is disabled in Firebase Auth settings.';
                                              break;
                                            case 'weak-password':
                                              msg =
                                                  'The password is too weak. Please use at least 6 characters.';
                                              break;
                                            default:
                                              msg =
                                                  e.message ??
                                                  'Auth error: ${e.code}';
                                          }
                                          setState(() {
                                            dialogError = msg;
                                            isSubmitting = false;
                                          });
                                        } catch (e) {
                                          setState(() {
                                            dialogError =
                                                'Unexpected error: $e';
                                            isSubmitting = false;
                                          });
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppColors.white,
                                              ),
                                        ),
                                      )
                                    : const Text('Create'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateOfficialAccountDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String? selectedRole = 'admin'; // SUPER ADMIN and ADMIN only
    String? selectedPosition;
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    bool passwordObscure = true;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxDialogHeight,
                    ),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Create Official Account',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.loginGreen,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildDialogTextField(
                            label: 'Full Name',
                            controller: nameController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Email',
                            controller: emailController,
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) {
                                return 'Email is required';
                              }
                              if (!_isValidEmail(email)) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildDialogPasswordField(
                            label: 'Password (min 6 characters)',
                            controller: passwordController,
                            obscure: passwordObscure,
                            onToggle: () => setState(
                              () => passwordObscure = !passwordObscure,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Role dropdown: SUPER ADMIN, ADMIN only (position is a label)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Role',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: AppColors.darkGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedRole,
                                    isExpanded: true,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.darkGrey,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'super_admin',
                                        child: Text('SUPER ADMIN'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'admin',
                                        child: Text('ADMIN'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        selectedRole = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildPositionSelector(
                            selectedPosition: selectedPosition,
                            onSelect: (value) {
                              setState(() {
                                selectedPosition = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          if (dialogError != null) ...[
                            ErrorNotification(message: dialogError!),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlineButton(
                                text: 'Cancel',
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.loginGreen,
                                  foregroundColor: AppColors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate())
                                          return;

                                        if (selectedPosition == null) {
                                          setState(() {
                                            dialogError =
                                                'Please select a position';
                                          });
                                          return;
                                        }

                                        setState(() {
                                          isSubmitting = true;
                                          dialogError = null;
                                        });

                                        try {
                                          final name = nameController.text
                                              .trim();
                                          final email = emailController.text
                                              .trim()
                                              .toLowerCase();
                                          final password =
                                              passwordController.text;
                                          if (!_isValidEmail(email)) {
                                            setState(() {
                                              dialogError =
                                                  'Valid email is required';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }
                                          if (password.isEmpty ||
                                              password.length < 6) {
                                            setState(() {
                                              dialogError =
                                                  'Password must be at least 6 characters';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }

                                          final now =
                                              FieldValue.serverTimestamp();
                                          final role = selectedRole ?? 'admin';

                                          // Create Firebase Auth user using secondary app
                                          FirebaseApp secondaryApp;
                                          try {
                                            secondaryApp = Firebase.app(
                                              'AuthHelper',
                                            );
                                          } catch (_) {
                                            secondaryApp =
                                                await Firebase.initializeApp(
                                                  name: 'AuthHelper',
                                                  options:
                                                      Firebase.app().options,
                                                );
                                          }
                                          final authHelper =
                                              FirebaseAuth.instanceFor(
                                                app: secondaryApp,
                                              );
                                          UserCredential? userCredential;
                                          try {
                                            userCredential = await authHelper
                                                .createUserWithEmailAndPassword(
                                                  email: email,
                                                  password: password,
                                                );
                                          } on FirebaseAuthException catch (e) {
                                            if (e.code ==
                                                'email-already-in-use') {
                                              userCredential = await authHelper
                                                  .signInWithEmailAndPassword(
                                                    email: email,
                                                    password: password,
                                                  );
                                            } else {
                                              rethrow;
                                            }
                                          }
                                          final newUser = userCredential?.user;
                                          if (newUser == null) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to create account.';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }
                                          final uid = newUser.uid;

                                          final data = <String, dynamic>{
                                            'userId': uid,
                                            'fullName': name,
                                            'phoneNumber': '',
                                            'email': email,
                                            'role': role,
                                            'userType': 'admin',
                                            'position':
                                                selectedPosition ?? 'Admin',
                                            'createdAt': now,
                                            'updatedAt': now,
                                            'isActive': true,
                                            'isApproved': true,
                                          };

                                          // Create Firestore document - use set() without merge to ensure all fields are written
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(uid)
                                              .set(data);

                                          // Verify document was created successfully
                                          final verifyDoc =
                                              await FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(uid)
                                                  .get();
                                          if (!verifyDoc.exists) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to create user document. Please try again.';
                                              isSubmitting = false;
                                            });
                                            return;
                                          }

                                          await authHelper.signOut();

                                          String adminName =
                                              'Barangay Official';
                                          final adminUid = FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid;
                                          if (adminUid != null) {
                                            final adminDoc =
                                                await FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(adminUid)
                                                    .get();
                                            if (adminDoc.exists) {
                                              adminName =
                                                  (adminDoc.data()?['fullName']
                                                      as String?) ??
                                                  adminName;
                                            }
                                          }
                                          await FirebaseFirestore.instance
                                              .collection('adminActivities')
                                              .add({
                                                'type': 'user_created',
                                                'description':
                                                    '$adminName created official account: $name ($role)',
                                                'fullName': name,
                                                'createdAt':
                                                    FieldValue.serverTimestamp(),
                                              });

                                          if (mounted) {
                                            await _loadAccounts();
                                            Navigator.of(context).pop();
                                          }
                                        } on FirebaseAuthException catch (e) {
                                          // More helpful error messages for admin when creating official accounts
                                          String msg;
                                          switch (e.code) {
                                            case 'email-already-in-use':
                                              msg =
                                                  'An account already exists for this email. Please use a different email or reset the password.';
                                              break;
                                            case 'invalid-email':
                                              msg =
                                                  'The provided email is invalid.';
                                              break;
                                            case 'operation-not-allowed':
                                              msg =
                                                  'Email/password sign-in is disabled in Firebase Auth settings.';
                                              break;
                                            case 'weak-password':
                                              msg =
                                                  'The password is too weak. Please use at least 6 characters.';
                                              break;
                                            default:
                                              msg =
                                                  e.message ??
                                                  'Auth error: ${e.code}';
                                          }
                                          setState(() {
                                            dialogError = msg;
                                            isSubmitting = false;
                                          });
                                        } catch (e) {
                                          setState(() {
                                            dialogError =
                                                'Unexpected error: $e';
                                            isSubmitting = false;
                                          });
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppColors.white,
                                              ),
                                        ),
                                      )
                                    : const Text('Create'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPositionSelector({
    required String? selectedPosition,
    required ValueChanged<String> onSelect,
  }) {
    const barangayPositions = [
      'Barangay Captain',
      'Barangay Secretary',
      'Barangay Treasurer',
      'Barangay Councilor',
      'SK Chairman',
      'Barangay Health Worker',
      'Barangay Tanod',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Barangay Position',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: barangayPositions.map((position) {
            final isSelected = selectedPosition == position;
            return AudienceTag(
              label: position,
              isSelected: isSelected,
              onTap: () => onSelect(position),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDemographicSelector({
    required Set<String> selectedCategories,
    required ValueChanged<String> onToggle,
    Set<String> blockedCategories = const <String>{},
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Demographic Category',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _mainDemographicOptions.map((audience) {
            final isSelected = selectedCategories.contains(audience);
            final isBlocked = blockedCategories.contains(audience) &&
                !isSelected;
            return Opacity(
              opacity: isBlocked ? 0.45 : 1,
              child: IgnorePointer(
                ignoring: isBlocked,
                child: AudienceTag(
                  label: audience,
                  isSelected: isSelected,
                  onTap: () => onToggle(audience),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          '${selectedCategories.length} category(ies) selected',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: AppColors.lightGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscureText = false,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            enabled: enabled,
            validator: validator,
            style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogReadOnlyField({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogDropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T value) itemLabelBuilder,
    required ValueChanged<T?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<T>(
              value: value,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
              ),
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(itemLabelBuilder(item)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogPasswordField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?)? validator,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            validator: validator,
            style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 12,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.darkGrey,
                  size: 22,
                ),
                onPressed: onToggle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTable() {
    final canViewFullData = _currentUserRole == 'super_admin';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBackground, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    canViewFullData ? 'Phone Number' : 'Status',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Purok',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Demographic category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Sub-demography',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),
          ...List.generate(_paginatedList.length, (index) {
            return _buildUserRow(
              _paginatedList[index],
              index == _paginatedList.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAdminsTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBackground, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Email',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Position',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                SizedBox(width: 60),
              ],
            ),
          ),
          ...List.generate(_paginatedList.length, (index) {
            return _buildAdminRow(
              _paginatedList[index],
              index == _paginatedList.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAwaitingApprovalTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBackground, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value:
                        _selectedIndices.length == _currentList.length &&
                        _currentList.isNotEmpty,
                    onChanged: _handleSelectAll,
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Email / Phone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Demographic category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Sub-demography',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _selectedIndices.isNotEmpty
                        ? AcceptDeclineButtons(
                            onAccept: _approveSelectedAwaiting,
                            onDecline: _declineSelectedAwaiting,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(_paginatedList.length, (index) {
            return _buildAwaitingApprovalRow(
              _paginatedList[index],
              _paginatedStartIndex + index,
              index == _paginatedList.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInactiveTable() {
    final canEdit = _currentUserRole == 'super_admin';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBackground, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Email / Phone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                SizedBox(width: 180),
              ],
            ),
          ),
          ...List.generate(_paginatedList.length, (index) {
            return _buildInactiveRow(
              _paginatedList[index],
              index == _paginatedList.length - 1,
              canEdit,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInactiveRow(
    Map<String, String> item,
    bool isLast,
    bool canEdit,
  ) {
    final status = item['status'] ?? 'declined';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              item['name'] ?? '—',
              style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item['phone'] ?? '—',
              style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item['category'] ?? '—',
              style: const TextStyle(fontSize: 14, color: AppColors.darkGrey),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'suspended'
                        ? Colors.red.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status == 'suspended' ? 'Suspended' : 'Declined',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: status == 'suspended'
                          ? Colors.red.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (canEdit)
            SizedBox(
              width: 180,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 100,
                    height: 36,
                    child: OutlineButton(
                      text: 'Reactivate',
                      onPressed: () => _reactivateUser(item),
                      isFullWidth: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActionIcon(
                    icon: Icons.edit,
                    onTap: () => _showEditUserDialog(item),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 180),
        ],
      ),
    );
  }

  Future<void> _reactivateUser(Map<String, String> item) async {
    final docId = item['id'] ?? '';
    if (docId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate account'),
        content: Text(
          'Set ${item['name']} to active? They will be able to sign in again.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlineButton(
                text: 'Cancel',
                onPressed: () => Navigator.pop(ctx, false),
                isFullWidth: false,
              ),
              const SizedBox(width: 12),
              CustomButton(
                text: 'Reactivate',
                isFullWidth: false,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'accountStatus': 'active',
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        await _loadAccounts();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Account reactivated.')));
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to reactivate: $e');
    }
  }

  Widget _buildUserRow(Map<String, String> user, bool isLast) {
    // OFFICIAL role: hide contact field and edit/delete buttons
    final canViewFullData = _currentUserRole == 'super_admin';
    final canEditDelete = _currentUserRole == 'super_admin';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              user['name']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              canViewFullData ? (user['phone'] ?? '—') : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (user['purok'] ?? '').trim().isNotEmpty
                  ? user['purok']!
                  : 'No Purok',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: (user['purok'] ?? '').trim().isNotEmpty
                    ? AppColors.darkGrey
                    : AppColors.mediumGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (user['mainCategory'] ?? user['category'] ?? '').trim().isNotEmpty
                  ? (user['mainCategory'] ?? user['category'])!
                  : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (user['subDemographies'] ?? '').trim().isNotEmpty
                  ? user['subDemographies']!
                  : '—',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: (user['subDemographies'] ?? '').trim().isNotEmpty
                    ? AppColors.darkGrey
                    : AppColors.mediumGrey,
              ),
            ),
          ),
          if (canEditDelete)
            SizedBox(
              width: 60,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(
                    icon: Icons.edit,
                    onTap: () => _showEditUserDialog(user),
                  ),
                  const SizedBox(width: 12),
                  _ActionIcon(
                    icon: Icons.delete,
                    onTap: () => _deleteUser(user),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 60),
        ],
      ),
    );
  }

  Widget _buildAdminRow(Map<String, String> admin, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              admin['name']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              admin['phone']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              admin['position']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: Icons.edit,
                  onTap: () => _showEditAdminDialog(admin),
                ),
                const SizedBox(width: 12),
                _ActionIcon(
                  icon: Icons.delete,
                  onTap: () => _deleteAdmin(admin),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingApprovalRow(
    Map<String, String> user,
    int index,
    bool isLast,
  ) {
    final docId = user['id'] ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _selectedIndices.contains(index),
              onChanged: (value) => _handleSelectItem(index, value),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    user['name']!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppColors.darkGrey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (user['reapplication'] == 'true') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Re-application',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (user['userType'] == 'admin')
                        ? Colors.blue.withOpacity(0.14)
                        : Colors.orange.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    user['userType'] == 'admin' ? 'Admin Account' : 'Resident',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: (user['userType'] == 'admin')
                          ? Colors.blue.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user['phone']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (user['mainCategory'] ?? user['category'] ?? '').trim().isNotEmpty
                  ? (user['mainCategory'] ?? user['category'])!
                  : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (user['subDemographies'] ?? '').trim().isNotEmpty
                  ? user['subDemographies']!
                  : '—',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: (user['subDemographies'] ?? '').trim().isNotEmpty
                    ? AppColors.darkGrey
                    : AppColors.mediumGrey,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            height: 36,
            child: OutlineButton(
              text: 'View',
              onPressed: () => _showVerificationDetailModal(docId, user),
              isFullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVerificationDetailModal(
    String docId,
    Map<String, String> user,
  ) async {
    final isReapplication = user['source'] == 'users';
    final doc = isReapplication
        ? await FirebaseFirestore.instance.collection('users').doc(docId).get()
        : await FirebaseFirestore.instance
              .collection('awaitingApproval')
              .doc(docId)
              .get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() ?? {};
    final fullName = (data['fullName'] ?? user['name'] ?? '') as String;
    final email = (data['email'] ?? user['email'] ?? '') as String;
    final phone = (data['phoneNumber'] ?? user['phone'] ?? '') as String;
    String purok = (data['purok'] ?? user['purok'] ?? '').toString().trim();
    final userTypeRaw = ((data['userType'] ?? user['userType'] ?? '') as String)
        .toLowerCase();
    final userType = userTypeRaw.isNotEmpty
        ? userTypeRaw
        : ((((data['role'] ?? user['role'] ?? '') as String).toLowerCase() ==
                      'admin' ||
                  ((data['role'] ?? user['role'] ?? '') as String)
                          .toLowerCase() ==
                      'super_admin')
              ? 'admin'
              : 'resident');
    final category =
        (data['category'] ??
                data['demographicCategory'] ??
                user['category'] ??
                '')
            as String;
    final role = ((data['role'] ?? user['role'] ?? '') as String).toLowerCase();
    final subDemographyEnabled = data['subDemographyEnabled'] == true;
    final subDemographies =
        (data['subDemographies'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    String? proofOfResidenceUrl = data['proofOfResidenceUrl'] as String?;
    if ((proofOfResidenceUrl == null || proofOfResidenceUrl.isEmpty) &&
        !isReapplication) {
      final candidateUid =
          ((data['uid'] as String?)?.trim().isNotEmpty ?? false)
          ? (data['uid'] as String).trim()
          : docId.trim();
      if (candidateUid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(candidateUid)
            .get();
        if (userDoc.exists) {
          final fallback = userDoc.data()?['proofOfResidenceUrl'] as String?;
          if (fallback != null && fallback.isNotEmpty) {
            proofOfResidenceUrl = fallback;
          }
          if (purok.isEmpty) {
            final purokFallback = (userDoc.data()?['purok'] ?? '')
                .toString()
                .trim();
            if (purokFallback.isNotEmpty) {
              purok = purokFallback;
            }
          }
        }
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => DialogContainer(
        title: isReapplication
            ? 'Review re-application'
            : 'Review verification request',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReapplication)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Re-application',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                    fontSize: 14,
                  ),
                ),
              ),
            _detailRow('Full Name', fullName),
            _detailRow('Email', email),
            _detailRow('Phone Number', phone),
            _detailRow('Purok', purok),
            _detailRow(
              'Account Type',
              userType == 'admin' ? 'Admin Account' : 'Resident',
            ),
            _detailRow(
              'Demography',
              category.isNotEmpty
                  ? category
                  : (role == 'admin' ? 'Admin' : role),
            ),
            if (subDemographyEnabled) ...[
              _detailRow(
                'Sub-demographies',
                subDemographies.isNotEmpty
                    ? subDemographies.join(', ')
                    : ((user['subDemographies'] ?? '').isNotEmpty
                          ? user['subDemographies']!
                          : '—'),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Proof of residence',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              width: double.infinity,
              child:
                  proofOfResidenceUrl != null && proofOfResidenceUrl.isNotEmpty
                  ? GestureDetector(
                      onTap: () =>
                          openFullScreenImage(ctx, proofOfResidenceUrl!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          proofOfResidenceUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          cacheHeight: 300,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppColors.inputBackground,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => _proofPlaceholder(),
                        ),
                      ),
                    )
                  : _proofPlaceholder(),
            ),
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!isReapplication)
              DialogActionButton(
                label: 'Edit',
                onPressed: () {
                  Navigator.pop(ctx);
                  _showEditAwaitingDialog(user);
                },
              ),
            if (!isReapplication) const SizedBox(width: 12),
            DialogActionButton(
              label: 'Decline',
              isDestructive: true,
              onPressed: () {
                Navigator.pop(ctx);
                _showDeclineDialog(docId, user);
              },
            ),
            const SizedBox(width: 12),
            DialogActionButton(
              label: 'Approve',
              isPrimary: true,
              onPressed: () async {
                Navigator.pop(ctx);
                if (isReapplication) {
                  await _confirmThenApproveReapplication(docId);
                } else {
                  await _confirmThenApprove(docId, user);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.lightGrey),
          ),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _proofPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.lightGrey,
          size: 32,
        ),
      ),
    );
  }

  Future<void> _confirmThenApprove(
    String docId,
    Map<String, String> user,
  ) async {
    String? approvedRole;
    final userType = (user['userType'] ?? '').toLowerCase();
    if (userType == 'admin') {
      final selectedRole = await _showAdminRolePicker();
      if (selectedRole == null) return;
      approvedRole = selectedRole;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve request'),
        content: const Text(
          'This will create the user\'s account. You will stay logged in. Continue?',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          StatefulBuilder(
            builder: (context, setButtonState) {
              bool isLoading = false;
              return SizedBox(
                width: 270,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomButton(
                      text: 'Approve',
                      isFullWidth: false,
                      isLoading: isLoading,
                      onPressed: isLoading
                          ? null
                          : () {
                              setButtonState(() => isLoading = true);
                              Navigator.pop(context, true);
                            },
                    ),
                    const SizedBox(height: 12),
                    OutlineButton(
                      text: 'Cancel',
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _approveAwaiting(docId, user, approvedRole: approvedRole);
    }
  }

  Future<String?> _showAdminRolePicker() {
    String selected = 'admin';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assign role for admin account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'admin',
                    groupValue: selected,
                    title: const Text('Admin'),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    value: 'super_admin',
                    groupValue: selected,
                    title: const Text('Super Admin'),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmThenApproveReapplication(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve re-application'),
        content: const Text(
          'This will set the account to active. The resident can use the app again. Continue?',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          StatefulBuilder(
            builder: (context, setButtonState) {
              bool isLoading = false;
              return SizedBox(
                width: 270,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomButton(
                      text: 'Approve',
                      isFullWidth: false,
                      isLoading: isLoading,
                      onPressed: isLoading
                          ? null
                          : () {
                              setButtonState(() => isLoading = true);
                              Navigator.pop(context, true);
                            },
                    ),
                    const SizedBox(height: 12),
                    OutlineButton(
                      text: 'Cancel',
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _approveReapplication(uid);
    }
  }

  Future<void> _approveReapplication(String uid) async {
    if (uid.isEmpty) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final reapplicationName =
          (userDoc.data()?['fullName'] as String?)?.trim() ?? '';
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'accountStatus': 'active',
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send account-approved push notification to the user
      try {
        await sendAccountApprovalPush(
          requestId: uid,
          userId: uid,
          title: 'Account Approved',
          body: 'Your re-application has been approved. You can now login.',
        );
      } catch (e) {
        // Non-blocking: approval succeeded; only push failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message:
                    'Re-application approved. Push notification could not be sent: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      if (mounted) {
        await _loadAccounts();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Re-application approved. Account is now active.'),
          ),
        );
      }

      await _logAdminActivity(
        'user_approved',
        'approved a re-application for ${reapplicationName.isNotEmpty ? reapplicationName : 'a user'}',
        fullName: reapplicationName,
      );
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = 'Failed to approve re-application: $e');
    }
  }

  Future<void> _approveAwaiting(
    String docId,
    Map<String, String> user, {
    String? approvedRole,
  }) async {
    if (docId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final fullName = (data['fullName'] ?? user['name'] ?? '') as String;
      final phone = (data['phoneNumber'] ?? user['phone'] ?? '')
          .toString()
          .trim();
      final requestedEmail = (data['email'] ?? user['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final password = (data['password'] ?? '') as String?;
      final existingUid = data['uid'] as String?;
      final role = ((data['role'] ?? user['role'] ?? 'user') as String)
          .toLowerCase();
      final requestUserType =
          ((data['userType'] ?? user['userType'] ?? '') as String)
              .toLowerCase();
      var purok = (data['purok'] ?? user['purok'] ?? '').toString().trim();
      final userType = requestUserType.isNotEmpty
          ? requestUserType
          : ((role == 'admin' || role == 'super_admin') ? 'admin' : 'resident');
      final position = (data['position'] ?? user['position'] ?? '') as String;
      final category =
          (data['category'] ??
                  data['demographicCategory'] ??
                  user['category'] ??
                  '')
              as String;
      final subDemographyEnabled = data['subDemographyEnabled'] == true;
      final subDemographies =
          (data['subDemographies'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
      final proofOfResidenceUrl = data['proofOfResidenceUrl'] as String?;

      if (purok.isEmpty &&
          existingUid != null &&
          existingUid.toString().trim().isNotEmpty) {
        try {
          final existingUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(existingUid.toString().trim())
              .get();
          if (existingUserDoc.exists) {
            purok = (existingUserDoc.data()?['purok'] ?? '').toString().trim();
          }
        } catch (_) {
          // Approval should not fail if fallback purok lookup is unavailable.
        }
      }

      if (phone.isEmpty && requestedEmail.isEmpty) {
        if (mounted)
          setState(
            () =>
                _errorMessage = 'Email or phone number is required to approve.',
          );
        return;
      }

      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final email = requestedEmail.isNotEmpty
          ? requestedEmail
          : '$phone@linkod.com';
      final now = FieldValue.serverTimestamp();
      String uid;
      FirebaseAuth? authHelperUsed;

      // Mobile now creates Auth at registration and sends uid in awaitingApproval; then we only create users doc
      if (existingUid != null && existingUid.toString().trim().isNotEmpty) {
        uid = existingUid.toString().trim();
        // Mark request as approved; no Auth creation needed
        await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .doc(docId)
            .update({
              'status': 'approved',
              'reviewedBy': adminUid,
              'reviewedAt': now,
            });
      } else {
        // Legacy: no uid in request — create Firebase Auth account using secondary app
        if (password == null || password.isEmpty || password.length < 6) {
          if (mounted)
            setState(
              () => _errorMessage =
                  'Valid password (6+ chars) required in request to approve.',
            );
          return;
        }
        await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .doc(docId)
            .update({
              'status': 'approved',
              'reviewedBy': adminUid,
              'reviewedAt': now,
            });
        FirebaseApp secondaryApp;
        try {
          secondaryApp = Firebase.app('AuthHelper');
        } catch (_) {
          secondaryApp = await Firebase.initializeApp(
            name: 'AuthHelper',
            options: Firebase.app().options,
          );
        }
        final authHelper = FirebaseAuth.instanceFor(app: secondaryApp);
        authHelperUsed = authHelper;
        UserCredential? userCredential;
        try {
          userCredential = await authHelper.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            userCredential = await authHelper.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
          } else {
            rethrow;
          }
        }
        final newUser = userCredential?.user;
        if (newUser == null) {
          if (mounted)
            setState(
              () => _errorMessage = 'Failed to create or sign in to account.',
            );
          return;
        }
        uid = newUser.uid;
      }

      // Official account roles: super_admin and admin only for admin userType.
      final normalizedApprovedRole = (approvedRole ?? '').toLowerCase();
      final firestoreRole = userType == 'admin'
          ? ((normalizedApprovedRole == 'super_admin' ||
                    normalizedApprovedRole == 'admin')
                ? normalizedApprovedRole
                : 'admin')
          : 'resident';
      final categoriesList = (category)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (subDemographyEnabled && subDemographies.isNotEmpty) {
        categoriesList.addAll(
          subDemographies.where((entry) => !categoriesList.contains(entry)),
        );
      }

      // 3) As admin (primary Auth unchanged): create/update users/{uid}
      // Also copy FCM tokens from awaitingApproval to users doc to ensure push notification can find them
      final fcmTokens =
          (data['fcmTokens'] as List<dynamic>?)
              ?.whereType<String>()
              .map((t) => (t as String).trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          <String>[];

      final userDocData = <String, dynamic>{
        'userId': uid,
        'fullName': fullName,
        'phoneNumber': phone,
        'email': email,
        'userType': userType,
        'role': firestoreRole,
        'createdAt': now,
        'updatedAt': now,
        'isActive': true,
        'isApproved': true,
        'verificationStatus': 'Verified',
        'accountStatus': 'active',
        if (proofOfResidenceUrl != null && proofOfResidenceUrl.isNotEmpty)
          'proofOfResidenceUrl': proofOfResidenceUrl,
        if (fcmTokens.isNotEmpty) 'fcmTokens': fcmTokens,
        if (firestoreRole == 'admin')
          'position': position.isNotEmpty ? position : 'Admin',
        if (firestoreRole == 'resident') ...{
          if (purok.isNotEmpty) 'purok': purok,
          // Keep `category` (string) for existing UI and documents.
          'category': categoriesList.isNotEmpty
              ? categoriesList.join(', ')
              : (category.isNotEmpty ? category : 'User'),
          // Add `categories` (array) so we can query audience targeting efficiently.
          'categories': categoriesList,
          'subDemographyEnabled': subDemographyEnabled,
          'subDemographies': subDemographies,
        },
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userDocData, SetOptions(merge: true));

      await _logAdminActivity(
        'user_approved',
        'approved $fullName',
        fullName: fullName,
      );

      // 4) Send account-approved push (human-in-the-loop; backend fetches fcmTokens from awaitingApproval or users doc)
      try {
        await sendAccountApprovalPush(
          requestId: docId,
          userId: uid,
          title: 'Account Approved',
          body: 'Your account has been approved. You can now login.',
        );
      } catch (e) {
        // Non-blocking: approval succeeded; only push failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message:
                    'Account created. Push notification could not be sent: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .delete();

      // Sign out from secondary app only when we used it (legacy flow)
      if (authHelperUsed != null) {
        await authHelperUsed.signOut();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
            message: 'Account created successfully.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadAccounts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to approve request: $e';
        });
      }
    }
  }

  Future<void> _showDeclineDialog(
    String docId, [
    Map<String, String>? item,
  ]) async {
    if (docId.isEmpty) return;
    final result = await showDialog<DeclineReasonResult>(
      context: context,
      builder: (context) => DeclineReasonDialog(
        title: 'Reason for decline',
        submitLabel: 'Decline',
        showStatusDropdown: false,
      ),
    );
    if (result != null && mounted) {
      await _declineAwaiting(docId, result.reason, item, result.reapplyType);
    }
  }

  /// Persistence & governance: decline with reason. No Auth deletion (Spark plan).
  /// - Re-application (item.source == 'users'): update users doc to accountStatus declined.
  /// - New request (awaitingApproval): create Auth + users doc with accountStatus declined, then delete awaitingApproval.
  Future<void> _declineAwaiting(
    String docId,
    String reason, [
    Map<String, String>? item,
    String? reapplyType,
  ]) async {
    if (docId.isEmpty) return;
    if (mounted) setState(() => _errorMessage = null);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      String fullName = 'Applicant';
      String? declinedUserId;

      if (item != null && item['source'] == 'users') {
        // Re-application: user already has Auth and users doc; just set status to declined
        await FirebaseFirestore.instance.collection('users').doc(docId).update({
          'accountStatus': 'declined',
          'adminNote': reason,
          'reapplyType': reapplyType ?? 'full',
          'lastUpdated': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        fullName = item['name'] ?? fullName;
        declinedUserId = docId;
      } else {
        // New registration: if mobile sent uid (Auth already created), just create users doc; else create Auth + users
        final doc = await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .doc(docId)
            .get();
        if (!doc.exists) {
          if (mounted)
            setState(() => _errorMessage = 'Request no longer found.');
          return;
        }
        final data = doc.data() ?? {};
        fullName = (data['fullName'] as String? ?? 'Applicant').toString();
        final phone =
            ((data['phoneNumber'] ??
                        data['phone'] ??
                        data['contactNumber'] ??
                        data['mobileNumber'])
                    as String?)
                ?.toString()
                .trim() ??
            '';
        final requestEmail =
            (data['email'] as String?)?.toString().trim() ?? '';
        final existingUid = data['uid'] as String?;
        final category =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;
        final role = ((data['role'] ?? 'user') as String).toLowerCase();

        // Prefer request email when present; otherwise derive one from phone.
        final email = requestEmail.isNotEmpty
            ? requestEmail
            : (phone.isNotEmpty ? '$phone@linkod.com' : '');
        final now = FieldValue.serverTimestamp();
        // Official account roles: super_admin and admin only (stored as-is)
        final firestoreRole = (role == 'super_admin' || role == 'admin')
            ? role
            : 'resident';

        if (existingUid != null && existingUid.toString().trim().isNotEmpty) {
          // Mobile created Auth at registration — just create users doc with declined
          final uid = existingUid.toString().trim();
          declinedUserId = uid;
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'userId': uid,
            'fullName': fullName,
            'phoneNumber': phone,
            'email': email,
            'role': firestoreRole,
            'accountStatus': 'declined',
            'adminNote': reason,
            'reapplyType': reapplyType ?? 'full',
            'reapplicationCount': 0,
            'lastUpdated': now,
            'createdAt': now,
            'updatedAt': now,
            'isActive': false,
            'isApproved': false,
            if (firestoreRole == 'resident')
              'category': category.isNotEmpty ? category : 'User',
          }, SetOptions(merge: true));
        } else {
          // Legacy: no uid — create Auth + users doc
          final password = data['password'] as String?;
          if (email.isEmpty) {
            if (mounted) {
              setState(
                () => _errorMessage =
                    'Missing uid/email in request; cannot decline safely.',
              );
            }
            return;
          }
          if (password == null || password.isEmpty || password.length < 6) {
            if (mounted)
              setState(
                () => _errorMessage =
                    'Valid password (6+ chars) required in request.',
              );
            return;
          }
          FirebaseApp secondaryApp;
          try {
            secondaryApp = Firebase.app('AuthHelper');
          } catch (_) {
            secondaryApp = await Firebase.initializeApp(
              name: 'AuthHelper',
              options: Firebase.app().options,
            );
          }
          final authHelper = FirebaseAuth.instanceFor(app: secondaryApp);
          UserCredential? userCredential;
          try {
            userCredential = await authHelper.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
          } on FirebaseAuthException catch (e) {
            if (e.code == 'email-already-in-use') {
              userCredential = await authHelper.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
            } else {
              rethrow;
            }
          }
          final newUser = userCredential?.user;
          if (newUser == null) {
            if (mounted)
              setState(
                () => _errorMessage =
                    'Could not create account for declined user.',
              );
            return;
          }
          final uid = newUser.uid;
          declinedUserId = uid;
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'userId': uid,
            'fullName': fullName,
            'phoneNumber': phone,
            'email': email,
            'role': firestoreRole,
            'accountStatus': 'declined',
            'adminNote': reason,
            'reapplyType': reapplyType ?? 'full',
            'reapplicationCount': 0,
            'lastUpdated': now,
            'createdAt': now,
            'updatedAt': now,
            'isActive': false,
            'isApproved': false,
            if (firestoreRole == 'resident')
              'category': category.isNotEmpty ? category : 'User',
          }, SetOptions(merge: true));
          await authHelper.signOut();
        }

        await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .doc(docId)
            .delete();
      }

      String adminName = 'Barangay Official';
      if (adminUid != null) {
        final adminDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(adminUid)
            .get();
        if (adminDoc.exists) {
          adminName = (adminDoc.data()?['fullName'] as String?) ?? adminName;
        }
      }
      await FirebaseFirestore.instance.collection('adminActivities').add({
        'type': 'user_declined',
        'description': '$adminName declined $fullName',
        'fullName': fullName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Send decline push notification to the user
      try {
        final bool isReapplication = item != null && item['source'] == 'users';
        if (declinedUserId != null && declinedUserId.isNotEmpty) {
          await sendUserPush(
            userId: declinedUserId,
            title: 'Account Declined',
            body: reason.isNotEmpty
                ? 'Your ${isReapplication ? 're-application' : 'account request'} was declined. Reason: $reason'
                : 'Your ${isReapplication ? 're-application' : 'account request'} was declined.',
            data: {'type': 'account_declined', 'reason': reason},
          );
        }
      } catch (pushError) {
        // Non-blocking: decline succeeded; only push failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message: 'Declined; push notification failed: $pushError',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      if (mounted) await _loadAccounts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to decline request: $e';
        });
      }
    }
  }

  Future<void> _showEditAwaitingDialog(Map<String, String> user) async {
    final nameController = TextEditingController(text: user['name'] ?? '');
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    final purok = (user['purok'] ?? '').trim();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    final docId = user['id'] ?? '';
    final isAdmin =
        ((user['role'] ?? '').toLowerCase() == 'admin' ||
        (user['role'] ?? '').toLowerCase() == 'super_admin');
    final existingCategory = user['category'] ?? '';
    final existingPosition = user['position'] ?? '';
    final existingRole = (user['role'] ?? '').toLowerCase();
    String? selectedRole = (existingRole == 'super_admin')
        ? 'super_admin'
        : 'admin';
    String? selectedPosition = existingPosition.isNotEmpty
        ? existingPosition
        : null;
    Set<String> selectedCategories = existingCategory.isEmpty
        ? <String>{}
        : existingCategory
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet();
    final awaitingDoc = docId.isNotEmpty
      ? await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .get()
      : null;
    final awaitingData = awaitingDoc?.data() ?? const <String, dynamic>{};
    final firestoreSubDemographies =
      (awaitingData['subDemographies'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final fallbackSubDemographies = (user['subDemographies'] ?? '')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
    Set<String> selectedSubCategories =
      (firestoreSubDemographies.isNotEmpty
          ? firestoreSubDemographies
          : fallbackSubDemographies)
        .toSet();
    selectedSubCategories.removeWhere(
      (value) => selectedCategories.contains(value),
    );

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxDialogHeight,
                    ),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Edit Approval Request',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.loginGreen,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildDialogTextField(
                            label: 'Full Name',
                            controller: nameController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Email / Phone',
                            controller: phoneController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Email or phone is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogReadOnlyField(
                            label: 'Purok',
                            value: purok,
                          ),
                          const SizedBox(height: 16),
                          if (isAdmin) ...[
                            // Role for official account: SUPER ADMIN or ADMIN (editable before approval)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Role',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: AppColors.darkGrey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedRole,
                                      isExpanded: true,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 15,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.darkGrey,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'super_admin',
                                          child: Text('SUPER ADMIN'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'admin',
                                          child: Text('ADMIN'),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        setState(() => selectedRole = value);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildPositionSelector(
                              selectedPosition: selectedPosition,
                              onSelect: (value) =>
                                  setState(() => selectedPosition = value),
                            ),
                          ] else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDemographicSelector(
                                  selectedCategories: selectedCategories,
                                  blockedCategories: selectedSubCategories,
                                  onToggle: (value) {
                                    setState(() {
                                      if (selectedCategories.contains(value)) {
                                        selectedCategories.remove(value);
                                      } else if (selectedSubCategories
                                          .contains(value)) {
                                        return;
                                      } else {
                                        selectedCategories.add(value);
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Sub-demography',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: AppColors.darkGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _usersDemographicOptions.map((
                                        audience,
                                      ) {
                                        final isSelected = selectedSubCategories
                                            .contains(audience);
                                        final isBlocked =
                                            selectedCategories
                                                .contains(audience) &&
                                            !isSelected;
                                        return Opacity(
                                          opacity: isBlocked ? 0.45 : 1,
                                          child: IgnorePointer(
                                            ignoring: isBlocked,
                                            child: AudienceTag(
                                              label: audience,
                                              isSelected: isSelected,
                                              onTap: () => setState(() {
                                                if (selectedSubCategories
                                                    .contains(audience)) {
                                                  selectedSubCategories.remove(
                                                    audience,
                                                  );
                                                } else if (selectedCategories
                                                    .contains(audience)) {
                                                  return;
                                                } else {
                                                  selectedSubCategories.add(
                                                    audience,
                                                  );
                                                }
                                              }),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${selectedSubCategories.length} sub-demography(ies) selected',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.normal,
                                        color: AppColors.lightGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          if (dialogError != null) ...[
                            ErrorNotification(message: dialogError!),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 110,
                                height: 40,
                                child: OutlineButton(
                                  text: 'Cancel',
                                  onPressed: isSubmitting
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  isFullWidth: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 110,
                                height: 40,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.loginGreen,
                                    foregroundColor: AppColors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: isSubmitting
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!.validate())
                                            return;
                                          if (isAdmin &&
                                              selectedPosition == null) {
                                            setState(
                                              () => dialogError =
                                                  'Please select a position.',
                                            );
                                            return;
                                          }
                                          if (!isAdmin &&
                                              selectedCategories.isEmpty) {
                                            setState(
                                              () => dialogError =
                                                  'Please select at least one category.',
                                            );
                                            return;
                                          }
                                          setState(() {
                                            isSubmitting = true;
                                            dialogError = null;
                                          });

                                          try {
                                            final updates = <String, dynamic>{
                                              'fullName': nameController.text
                                                  .trim(),
                                              'phoneNumber': phoneController
                                                  .text
                                                  .trim(),
                                            };
                                            if (isAdmin) {
                                              updates['role'] =
                                                  selectedRole ?? 'admin';
                                              updates['position'] =
                                                  selectedPosition
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? selectedPosition!
                                                  : 'Admin';
                                            } else {
                                              updates['category'] =
                                                  selectedCategories.isEmpty
                                                  ? 'User'
                                                  : selectedCategories.join(
                                                      ', ',
                                                    );
                                              updates['categories'] =
                                                selectedCategories.toList();
                                              updates['subDemographies'] =
                                                selectedSubCategories
                                                  .toList();
                                              updates['subDemographyEnabled'] =
                                                selectedSubCategories
                                                  .isNotEmpty;
                                            }
                                            await FirebaseFirestore.instance
                                                .collection('awaitingApproval')
                                                .doc(docId)
                                                .update(updates);
                                            await _logAdminActivity(
                                              'request_updated',
                                              'updated approval request for ${nameController.text.trim()}',
                                              fullName: nameController.text
                                                  .trim(),
                                            );
                                            if (mounted) {
                                              await _loadAccounts();
                                              Navigator.of(context).pop();
                                            }
                                          } catch (e) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to update request: $e';
                                              isSubmitting = false;
                                            });
                                          }
                                        },
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  AppColors.white,
                                                ),
                                          ),
                                        )
                                      : const Text('Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditUserDialog(Map<String, String> user) async {
    final docId = user['id'] ?? '';
    if (docId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(docId)
        .get();
    final currentStatus =
        (doc.data()?['accountStatus'] as String?)?.toLowerCase() ?? 'active';
    final currentNote = (doc.data()?['adminNote'] as String?) ?? '';
    final currentPurok =
        ((doc.data()?['purok'] ?? user['purok'] ?? '').toString()).trim();
    final normalizedCurrentPurok = _normalizePurokSelection(currentPurok);
    final resolvedCurrentPurok = _mainPurokOptions.firstWhere(
      (option) => _normalizePurokSelection(option) == normalizedCurrentPurok,
      orElse: () =>
          currentPurok.isNotEmpty ? currentPurok : _mainPurokOptions.first,
    );

    final nameController = TextEditingController(text: user['name'] ?? '');
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    final adminNoteController = TextEditingController(text: currentNote);
    String selectedPurok = resolvedCurrentPurok;

    final firestoreSubDemographies =
        (doc.data()?['subDemographies'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    final mainOnlyDemographics = _extractMainDemographics(doc.data() ?? {});
    final Set<String> selectedCategories = mainOnlyDemographics.toSet();
    final Set<String> selectedSubCategories = firestoreSubDemographies.toSet();
    selectedSubCategories.removeWhere(
      (value) => selectedCategories.contains(value),
    );

    String selectedStatus = currentStatus;
    if (selectedStatus != 'active' &&
        selectedStatus != 'declined' &&
        selectedStatus != 'suspended') {
      selectedStatus = 'active';
    }
    String selectedDeclineReason = kDeclineReasonPresets.first;
    for (final preset in kDeclineReasonPresets) {
      if (currentNote.toLowerCase().startsWith(preset.toLowerCase())) {
        selectedDeclineReason = preset;
        break;
      }
    }
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxDialogHeight,
                    ),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Edit User',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.loginGreen,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildDialogTextField(
                            label: 'Full Name',
                            controller: nameController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Email / Phone',
                            controller: phoneController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Email or phone is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogDropdownField<String>(
                            label: 'Purok',
                            value: selectedPurok,
                            items: _mainPurokOptions,
                            itemLabelBuilder: (value) => value,
                            onChanged: isSubmitting
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      selectedPurok = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Account status',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.darkGrey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: selectedStatus,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('Active'),
                              ),
                              DropdownMenuItem(
                                value: 'declined',
                                child: Text('Declined'),
                              ),
                              DropdownMenuItem(
                                value: 'suspended',
                                child: Text('Suspended'),
                              ),
                            ],
                            onChanged: isSubmitting
                                ? null
                                : (v) => setState(
                                    () => selectedStatus = v ?? 'active',
                                  ),
                          ),
                          if (selectedStatus == 'declined') ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Reason for disapproval',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.darkGrey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: selectedDeclineReason,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: kDeclineReasonPresets
                                  .map(
                                    (reason) => DropdownMenuItem(
                                      value: reason,
                                      child: Text(reason),
                                    ),
                                  )
                                  .toList(),
                              onChanged: isSubmitting
                                  ? null
                                  : (v) => setState(
                                      () => selectedDeclineReason =
                                          v ?? kDeclineReasonPresets.first,
                                    ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Admin note (optional)',
                            controller: adminNoteController,
                            validator: (_) => null,
                          ),
                          const SizedBox(height: 16),
                          _buildDemographicSelector(
                            selectedCategories: selectedCategories,
                            blockedCategories: selectedSubCategories,
                            onToggle: (value) {
                              setState(() {
                                if (selectedCategories.contains(value)) {
                                  selectedCategories.remove(value);
                                } else if (selectedSubCategories.contains(
                                  value,
                                )) {
                                  return;
                                } else {
                                  selectedCategories.add(value);
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sub-demography',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  color: AppColors.darkGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _usersDemographicOptions.map((
                                  audience,
                                ) {
                                  final isSelected = selectedSubCategories
                                      .contains(audience);
                                  final isBlocked =
                                      selectedCategories.contains(audience) &&
                                      !isSelected;
                                  return Opacity(
                                    opacity: isBlocked ? 0.45 : 1,
                                    child: IgnorePointer(
                                      ignoring: isBlocked,
                                      child: AudienceTag(
                                        label: audience,
                                        isSelected: isSelected,
                                        onTap: () => setState(() {
                                          if (selectedSubCategories.contains(
                                            audience,
                                          )) {
                                            selectedSubCategories.remove(
                                              audience,
                                            );
                                          } else if (selectedCategories
                                              .contains(audience)) {
                                            return;
                                          } else {
                                            selectedSubCategories.add(audience);
                                          }
                                        }),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${selectedSubCategories.length} sub-demography(ies) selected',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: AppColors.lightGrey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (dialogError != null) ...[
                            ErrorNotification(message: dialogError!),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 110,
                                height: 40,
                                child: OutlineButton(
                                  text: 'Cancel',
                                  onPressed: isSubmitting
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  isFullWidth: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                height: 40,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.loginGreen,
                                    foregroundColor: AppColors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: isSubmitting
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!.validate())
                                            return;
                                          setState(() {
                                            isSubmitting = true;
                                            dialogError = null;
                                          });

                                          try {
                                            final adminNoteText =
                                                adminNoteController.text.trim();
                                            final combinedDeclineNote =
                                                adminNoteText.isEmpty
                                                ? selectedDeclineReason
                                                : '$selectedDeclineReason. $adminNoteText';
                                            final updates = <String, dynamic>{
                                              'fullName': nameController.text
                                                  .trim(),
                                              'phoneNumber': phoneController
                                                  .text
                                                  .trim(),
                                              'purok': _normalizePurokSelection(
                                                selectedPurok,
                                              ),
                                              'category':
                                                  selectedCategories.isEmpty
                                                  ? 'User'
                                                  : selectedCategories.join(
                                                      ', ',
                                                    ),
                                              'categories': selectedCategories
                                                  .toList(),
                                              'subDemographies':
                                                  selectedSubCategories
                                                      .toList(),
                                              'subDemographyEnabled':
                                                  selectedSubCategories
                                                      .isNotEmpty,
                                              'accountStatus': selectedStatus,
                                              'adminNote':
                                                  selectedStatus == 'declined'
                                                  ? combinedDeclineNote
                                                  : adminNoteText,
                                              'lastUpdated':
                                                  FieldValue.serverTimestamp(),
                                              'updatedAt':
                                                  FieldValue.serverTimestamp(),
                                            };
                                            if (selectedStatus == 'declined') {
                                              updates['reapplyType'] =
                                                  kProofOnlyPresets.contains(
                                                    selectedDeclineReason,
                                                  )
                                                  ? 'proof_only'
                                                  : 'full';
                                            }
                                            await FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(docId)
                                                .update(updates);
                                            await _logAdminActivity(
                                              'user_updated',
                                              'edited user ${nameController.text.trim()}',
                                              fullName: nameController.text
                                                  .trim(),
                                            );
                                            if (mounted) {
                                              await _loadAccounts();
                                              Navigator.of(context).pop();
                                            }
                                          } catch (e) {
                                            setState(() {
                                              dialogError =
                                                  'Failed to update user: $e';
                                              isSubmitting = false;
                                            });
                                          }
                                        },
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  AppColors.white,
                                                ),
                                          ),
                                        )
                                      : const Text('Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditAdminDialog(Map<String, String> admin) async {
    final nameController = TextEditingController(text: admin['name'] ?? '');
    final phoneController = TextEditingController(text: admin['phone'] ?? '');
    final purok = (admin['purok'] ?? '').trim();
    String? selectedPosition = admin['position'];
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    final docId = admin['id'] ?? '';

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit Admin',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.loginGreen,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDialogTextField(
                          label: 'Full Name',
                          controller: nameController,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDialogTextField(
                          label: 'Email / Phone',
                          controller: phoneController,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Email or phone is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDialogReadOnlyField(label: 'Purok', value: purok),
                        const SizedBox(height: 16),
                        _buildPositionSelector(
                          selectedPosition: selectedPosition,
                          onSelect: (value) {
                            setState(() {
                              selectedPosition = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (dialogError != null) ...[
                          ErrorNotification(message: dialogError!),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 110,
                              height: 40,
                              child: OutlineButton(
                                text: 'Cancel',
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                isFullWidth: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 110,
                              height: 40,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.loginGreen,
                                  foregroundColor: AppColors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate())
                                          return;
                                        setState(() {
                                          isSubmitting = true;
                                          dialogError = null;
                                        });

                                        try {
                                          final positionValue =
                                              (selectedPosition ??
                                                      admin['position'] ??
                                                      '')
                                                  .trim();
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(docId)
                                              .update({
                                                'fullName': nameController.text
                                                    .trim(),
                                                'phoneNumber': phoneController
                                                    .text
                                                    .trim(),
                                                'position':
                                                    positionValue.isNotEmpty
                                                    ? positionValue
                                                    : 'Admin',
                                                'updatedAt':
                                                    FieldValue.serverTimestamp(),
                                                'role': 'admin',
                                              });
                                          await _logAdminActivity(
                                            'admin_updated',
                                            'edited admin ${nameController.text.trim()}',
                                            fullName: nameController.text
                                                .trim(),
                                          );
                                          if (mounted) {
                                            await _loadAccounts();
                                            Navigator.of(context).pop();
                                          }
                                        } catch (e) {
                                          setState(() {
                                            dialogError =
                                                'Failed to update admin: $e';
                                            isSubmitting = false;
                                          });
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppColors.white,
                                              ),
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _logAdminActivity(
    String type,
    String description, {
    String? fullName,
  }) async {
    try {
      var adminName = 'Barangay Official';
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      if (adminUid != null && adminUid.isNotEmpty) {
        final adminDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(adminUid)
            .get();
        if (adminDoc.exists) {
          final resolvedName =
              (adminDoc.data()?['fullName'] as String?)?.trim() ?? '';
          if (resolvedName.isNotEmpty) {
            adminName = resolvedName;
          }
        }
      }

      final payload = <String, dynamic>{
        'type': type,
        'description': '$adminName $description',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final trimmedFullName = fullName?.trim() ?? '';
      if (trimmedFullName.isNotEmpty) {
        payload['fullName'] = trimmedFullName;
      }

      await FirebaseFirestore.instance
          .collection('adminActivities')
          .add(payload);
    } catch (_) {
      // Activity logging should never block the user management flow.
    }
  }

  /// Persistence & governance: change status to Declined or Suspended (no Auth deletion).
  Future<void> _deleteUser(Map<String, String> user) async {
    final docId = user['id'] ?? '';
    if (docId.isEmpty) return;

    final result = await showDialog<DeclineReasonResult>(
      context: context,
      builder: (context) => DeclineReasonDialog(
        title: 'Change account status',
        submitLabel: 'Update status',
        showStatusDropdown: true,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final updates = <String, dynamic>{
        'accountStatus': result.status ?? 'declined',
        'adminNote': result.reason,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (result.status == 'declined' && result.reapplyType != null) {
        updates['reapplyType'] = result.reapplyType!;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .update(updates);
      if (mounted) {
        await _loadAccounts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${user['name']} status set to ${result.status ?? 'declined'}. They can log in to see the reason.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = 'Failed to update status: $e');
    }
  }

  Future<void> _deleteAdmin(Map<String, String> admin) async {
    final docId = admin['id'] ?? '';
    if (docId.isEmpty) return;

    final result = await showDialog<DeclineReasonResult>(
      context: context,
      builder: (context) => DeclineReasonDialog(
        title: 'Change account status',
        submitLabel: 'Update status',
        showStatusDropdown: true,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final updates = <String, dynamic>{
        'accountStatus': result.status ?? 'declined',
        'adminNote': result.reason,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (result.status == 'declined' && result.reapplyType != null) {
        updates['reapplyType'] = result.reapplyType!;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .update(updates);
      if (mounted) {
        await _loadAccounts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${admin['name']} status set to ${result.status ?? 'declined'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = 'Failed to update status: $e');
    }
  }

  Widget _buildTableFooter() {
    final recordText = _activeTabIndex == 2
        ? '$_totalRecords Awaiting Approval'
        : _activeTabIndex == 3
        ? '$_totalRecords Inactive'
        : '$_totalRecords Records';

    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            recordText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          Row(
            children: [
              const Text(
                'Show',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 60,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _itemsPerPage.toString(),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.darkGrey,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.darkGrey,
                      ),
                      items: ['10', '20', '50', '100'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: _handleItemsPerPageChange,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _PaginationButton(
                icon: Icons.chevron_left,
                onTap: _handlePreviousPage,
                isEnabled: _currentPage > 1,
              ),
              const SizedBox(width: 16),
              Text(
                'Page $_effectiveCurrentPage of $_totalPages',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(width: 16),
              _PaginationButton(
                icon: Icons.chevron_right,
                onTap: _handleNextPage,
                isEnabled: _currentPage < _totalPages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIcon({required this.icon, required this.onTap});

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          widget.icon,
          size: 20,
          color: _isHovered ? AppColors.primaryGreen : AppColors.darkGrey,
        ),
      ),
    );
  }
}

class _PaginationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isEnabled;

  const _PaginationButton({
    required this.icon,
    required this.onTap,
    required this.isEnabled,
  });

  @override
  State<_PaginationButton> createState() => _PaginationButtonState();
}

class _PaginationButtonState extends State<_PaginationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (widget.isEnabled) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (widget.isEnabled) {
          setState(() => _isHovered = false);
        }
      },
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.isEnabled ? widget.onTap : null,
        child: Icon(
          widget.icon,
          size: 20,
          color: widget.isEnabled
              ? (_isHovered ? AppColors.primaryGreen : AppColors.darkGrey)
              : AppColors.lightGrey,
        ),
      ),
    );
  }
}
