import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging (FCM) token registration.
///
/// Why store tokens in Firestore?
/// - The FCM token acts as a **device identifier** for push `delivery.
/// - Tokens can change (reinstall, refresh), so we store them in a list and de-duplicate.
/// - OTP is an authentication enhancement later; token storage stays tied to **Auth UID**.
///
/// Data model (non-breaking):
/// - `users/{uid}.fcmTokens`: array<string> (deduped via `arrayUnion`)
/// - `users/{uid}.fcmTokensUpdatedAt`: server timestamp
class FcmTokenService {
  FcmTokenService._();

  static final FcmTokenService instance = FcmTokenService._();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _started = false;

  bool get _isSupportedPlatform {
    if (kIsWeb) return true; // Web is supported via firebase_messaging_web.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false; // No push for the Windows admin app (by design).
    }
  }

  /// Starts listeners to register/store tokens on:
  /// - app startup (already-authenticated user)
  /// - successful login (auth state changes)
  /// - token refresh events
  ///
  /// Safe to call multiple times.
  void start() {
    if (_started) return;
    _started = true;

    // Important: do nothing on Windows/Linux so the admin app never crashes
    // due to missing plugin implementations.
    if (!_isSupportedPlatform) return;

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(registerCurrentTokenForUser(user.uid));
    });

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _saveToken(uid: uid, token: token);
    });
  }

  /// Fetches the current device token and stores it under `users/{uid}`.
  Future<void> registerCurrentTokenForUser(String uid) async {
    if (!_isSupportedPlatform) return;

    await _requestPermissionIfNeeded();

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) return;

    await _saveToken(uid: uid, token: token);
  }

  Future<void> _requestPermissionIfNeeded() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // On iOS/macOS, permission is required before a token is usable.
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _saveToken({required String uid, required String token}) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set({
      // Store as list to support multiple devices in the future.
      // arrayUnion prevents duplicates.
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokensUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Optional cleanup if you ever need to stop listeners (tests, etc.).
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
  }
}
