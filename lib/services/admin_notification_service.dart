import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../utils/admin_navigation.dart';

/// Service for notifying admins of new account registrations/resubmissions.
/// Uses Firestore real-time listener to detect new documents in awaitingApproval.
/// Only shows notifications for NEWLY ADDED documents (not existing ones on app start).
class AdminNotificationService {
  static final AdminNotificationService _instance =
      AdminNotificationService._internal();
  factory AdminNotificationService() => _instance;
  AdminNotificationService._internal();

  StreamSubscription<QuerySnapshot>? _subscription;
  StreamSubscription<User?>? _authSubscription;
  bool _isInitialized = false;
  bool _localNotifierReady = false;
  bool _hasSeenInitialSnapshot = false;
  DateTime? _listenerStartedAt;
  DateTime? _lastUserRefreshSignalAt;

  /// Initialize the notification service and start listening
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifier for Windows.
    // Some locked-down machines can block shortcut creation/notification APIs.
    try {
      await localNotifier.setup(
        appName: 'LINKod Admin',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _localNotifierReady = true;
    } catch (e) {
      _localNotifierReady = false;
      if (kDebugMode) {
        debugPrint('AdminNotificationService setup failed: $e');
      }
      // Keep app functional even when desktop notifications are unavailable.
      // The Firestore listener must still run so UI badges can auto-refresh.
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) => _handleAuthStateChanged(user),
    );

    // Handle currently signed-in user immediately.
    await _handleAuthStateChanged(FirebaseAuth.instance.currentUser);
    _isInitialized = true;
  }

  /// Dispose and stop listening
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _isInitialized = false;
    _localNotifierReady = false;
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    await _subscription?.cancel();
    _subscription = null;
    _hasSeenInitialSnapshot = false;
    _listenerStartedAt = null;

    if (user == null) {
      return;
    }

    final isAdminPanelUser = await _isAdminPanelUser(user.uid);
    if (!isAdminPanelUser) {
      if (kDebugMode) {
        debugPrint(
          'AdminNotificationService: disabled for non-admin-panel account.',
        );
      }
      return;
    }

    _startListening();
  }

  Future<bool> _isAdminPanelUser(String uid) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) return false;

      final role = (userDoc.data()?['role'] as String? ?? '').toLowerCase();
      final userType =
          (userDoc.data()?['userType'] as String? ?? '').toLowerCase();
      return role == 'super_admin' ||
          role == 'admin' ||
          role == 'official' ||
          role == 'staff' ||
          userType == 'admin';
    } catch (_) {
      return false;
    }
  }

  void _startListening() {
    _listenerStartedAt = DateTime.now();
    _subscription = FirebaseFirestore.instance
        .collection('awaitingApproval')
        .snapshots()
        .listen(
          _handleSnapshot,
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              debugPrint('AdminNotificationService listener error: $error');
            }
          },
        );
  }

  void _handleSnapshot(QuerySnapshot snapshot) {
    // Keep the global pending-users badge in sync across screens.
    AdminRefreshBus.publishPendingUsersCount(snapshot.docs.length);

    // Skip the first snapshot to avoid replaying existing pending docs.
    if (!_hasSeenInitialSnapshot) {
      _hasSeenInitialSnapshot = true;

      // Handle race condition: if a request is created while listener is booting,
      // it can appear in the first snapshot and would otherwise be missed.
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added &&
            _isRecentRequest(change.doc)) {
          _handleNewRegistration(change.doc);
        }
      }
      return;
    }

    // Process only newly added docs after initialization.
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        _handleNewRegistration(change.doc);
      }
    }
  }

  void _handleNewRegistration(DocumentSnapshot doc) {
    _signalUserManagementRefresh();
    _showNotification(doc);
  }

  void _signalUserManagementRefresh() {
    final now = DateTime.now();
    final last = _lastUserRefreshSignalAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }

    _lastUserRefreshSignalAt = now;
    AdminRefreshBus.requestUserManagementRefresh();
  }

  bool _isRecentRequest(DocumentSnapshot doc) {
    final startedAt = _listenerStartedAt;
    if (startedAt == null) return false;

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return false;
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) return false;

    // Small grace window covers clock skew/server timestamp delays.
    return createdAt.toDate().isAfter(startedAt.subtract(const Duration(seconds: 5)));
  }

  void _showNotification(DocumentSnapshot doc) {
    if (!_localNotifierReady) {
      return;
    }

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final fullName = data['fullName'] as String? ?? 'Someone';
    final isResubmission =
        data['reapplicationCount'] != null &&
        (data['reapplicationCount'] as int) > 0;

    final title = isResubmission
        ? 'Account Resubmission'
        : 'New Account Request';

    final body = isResubmission
        ? '$fullName resubmitted their application'
        : '$fullName requested a new account';

    final notification = LocalNotification(
      title: title,
      body: body,
      identifier: doc.id,
    );

    notification.onClick = () {
      // TODO: Navigate to User Management screen when notification clicked
      if (kDebugMode) {
        debugPrint('Notification clicked for user: ${doc.id}');
      }
    };

    notification.show();
  }
}
