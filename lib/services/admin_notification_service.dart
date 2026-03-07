import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Service for notifying admins of new account registrations/resubmissions.
/// Uses Firestore real-time listener to detect new documents in awaitingApproval.
/// Only shows notifications for NEWLY ADDED documents (not existing ones on app start).
class AdminNotificationService {
  static final AdminNotificationService _instance = AdminNotificationService._internal();
  factory AdminNotificationService() => _instance;
  AdminNotificationService._internal();

  StreamSubscription<QuerySnapshot>? _subscription;
  bool _isInitialized = false;

  /// Initialize the notification service and start listening
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifier for Windows
    await localNotifier.setup(
      appName: 'LINKod Admin',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );

    _startListening();
    _isInitialized = true;
  }

  /// Dispose and stop listening
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }

  void _startListening() {
    _subscription = FirebaseFirestore.instance
        .collection('awaitingApproval')
        .snapshots()
        .listen(_handleSnapshot);
  }

  void _handleSnapshot(QuerySnapshot snapshot) {
    // Only process document CHANGES, not the initial snapshot
    // This prevents 100 notifications on app startup
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        _showNotification(change.doc);
      }
    }
  }

  void _showNotification(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final fullName = data['fullName'] as String? ?? 'Someone';
    final phoneNumber = data['phoneNumber'] as String? ?? '';
    final isResubmission = data['reapplicationCount'] != null &&
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
