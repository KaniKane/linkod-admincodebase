import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailAuthService {
  EmailAuthService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static bool get _useHttpFallback {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static Uri _buildApiUri(String path) {
    final projectId = Firebase.app().options.projectId;
    return Uri.https('us-central1-$projectId.cloudfunctions.net', 'api/$path');
  }

  static Future<Map<String, dynamic>> _postJsonApi({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final response = await http
        .post(
          _buildApiUri(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic> data = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw FirebaseFunctionsException(
      code: (data['code'] ?? 'internal').toString(),
      message:
          (data['error'] ??
                  'Request failed with status ${response.statusCode}.')
              .toString(),
    );
  }

  static Future<void> sendOtp({required String email}) async {
    if (_useHttpFallback) {
      await _postJsonApi(
        path: 'auth/send-email-otp',
        body: <String, dynamic>{'email': email.trim()},
      );
      return;
    }

    final callable = _functions.httpsCallable('sendEmailOtp');
    await callable.call(<String, dynamic>{'email': email.trim()});
  }

  static Future<void> verifyOtp({
    required String email,
    required String otp,
  }) async {
    if (_useHttpFallback) {
      await _postJsonApi(
        path: 'auth/verify-email-otp',
        body: <String, dynamic>{'email': email.trim(), 'otp': otp.trim()},
      );
      return;
    }

    final callable = _functions.httpsCallable('verifyEmailOtp');
    await callable.call(<String, dynamic>{
      'email': email.trim(),
      'otp': otp.trim(),
    });
  }

  static Future<void> createPendingSignup({
    required String email,
    required String password,
    required String firstName,
    required String middleName,
    required String lastName,
    required String userType,
    required String requestedRole,
    required String position,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'firstName': firstName.trim(),
      'middleName': middleName.trim(),
      'lastName': lastName.trim(),
      'userType': userType.trim().toLowerCase(),
      'requestedRole': requestedRole.trim().toLowerCase(),
      'position': position.trim(),
    };

    if (_useHttpFallback) {
      await _postJsonApi(path: 'auth/create-pending-signup', body: payload);
      return;
    }

    final callable = _functions.httpsCallable('createPendingSignup');
    await callable.call(payload);
  }
}
