/// API client for the LINKod Admin backend (FastAPI).
///
/// - POST /refine: AI text refinement (Ollama llama3.2:3b)
/// - POST /recommend-audiences: rule-based audience recommendation
///
/// Base URL: local backend, e.g. http://localhost:8000
/// Push endpoints can use [kPushApiBaseUrl] (Cloud Function) so you don't need to run the local backend.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Optional override for the FastAPI backend base URL.
///
/// Set with:
/// flutter run --dart-define=ANNOUNCEMENT_API_BASE_URL=http://<host>:8000
const String _kAnnouncementBackendBaseUrlOverride = String.fromEnvironment(
  'ANNOUNCEMENT_API_BASE_URL',
  defaultValue: '',
);

/// Base URL for the FastAPI backend (refine, recommend-audiences).
///
/// Defaults:
/// - Android emulator: http://10.0.2.2:8000
/// - Other platforms (Windows/macOS/Linux/iOS/Web): http://localhost:8000
String get kAnnouncementBackendBaseUrl {
  final override = _kAnnouncementBackendBaseUrlOverride.trim();
  if (override.isNotEmpty) {
    return _normalizeBaseUrl(override);
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }

  return 'http://localhost:8000';
}

/// Base URL for push/scheduling endpoints
/// (send-announcement-push, send-account-approval, send-user-push,
/// schedule-announcement-reminder, cancel-announcement-reminder).
/// When set, the admin app calls this URL for push so you don't need to run the Python backend.
/// Currently deployed to: https://us-central1-linkod-db.cloudfunctions.net/api
const String? kPushApiBaseUrl =
    'https://us-central1-linkod-db.cloudfunctions.net/api';

String get _pushBaseUrl =>
    (kPushApiBaseUrl != null && kPushApiBaseUrl!.trim().isNotEmpty)
    ? _normalizePushBaseUrl(kPushApiBaseUrl!.trim())
    : kAnnouncementBackendBaseUrl;

String _normalizePushBaseUrl(String baseUrl) {
  var normalized = _normalizeBaseUrl(baseUrl);

  // Guard against missing /api when using the Express HTTP function URL.
  if (normalized.contains('cloudfunctions.net') &&
      !normalized.endsWith('/api')) {
    normalized = '$normalized/api';
  }
  return normalized;
}

String _normalizeBaseUrl(String baseUrl) {
  var normalized = baseUrl.trim();
  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Result of POST /refine: original and refined text.
class RefineResponse {
  const RefineResponse({
    required this.originalText,
    required this.refinedText,
    this.suggestedTitle,
  });

  factory RefineResponse.fromJson(Map<String, dynamic> json) {
    return RefineResponse(
      originalText: json['original_text'] as String? ?? '',
      refinedText: json['refined_text'] as String? ?? '',
      suggestedTitle: (json['suggested_title'] as String?)?.trim(),
    );
  }

  final String originalText;
  final String refinedText;
  final String? suggestedTitle;
}

/// Result of POST /recommend-audiences: suggested audiences and matched rules.
class RecommendAudiencesResponse {
  const RecommendAudiencesResponse({
    required this.audiences,
    required this.matchedRules,
    required this.defaultUsed,
  });

  factory RecommendAudiencesResponse.fromJson(Map<String, dynamic> json) {
    final audiences =
        (json['audiences'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    final matchedRules =
        (json['matched_rules'] as List<dynamic>?)
            ?.map((e) => _MatchedRule.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return RecommendAudiencesResponse(
      audiences: audiences,
      matchedRules: matchedRules,
      defaultUsed: json['default_used'] as bool? ?? false,
    );
  }

  final List<String> audiences;
  final List<_MatchedRule> matchedRules;
  final bool defaultUsed;
}

class _MatchedRule {
  const _MatchedRule({required this.keywords, required this.audiences});

  factory _MatchedRule.fromJson(Map<String, dynamic> json) {
    final keywords =
        (json['keywords'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    final audiences =
        (json['audiences'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    return _MatchedRule(keywords: keywords, audiences: audiences);
  }

  final List<String> keywords;
  final List<String> audiences;
}

/// Thrown when the backend returns an error (4xx/5xx) or network fails.
class AnnouncementBackendException implements Exception {
  AnnouncementBackendException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'AnnouncementBackendException: $message (status: $statusCode)';
}

/// Result of POST /send-announcement-push: counts for evaluation/UX feedback.
class SendAnnouncementPushResponse {
  const SendAnnouncementPushResponse({
    required this.userCount,
    required this.tokenCount,
    required this.successCount,
    required this.failureCount,
    required this.errorCounts,
  });

  factory SendAnnouncementPushResponse.fromJson(Map<String, dynamic> json) {
    return SendAnnouncementPushResponse(
      userCount: json['user_count'] as int? ?? 0,
      tokenCount: json['token_count'] as int? ?? 0,
      successCount: json['success_count'] as int? ?? 0,
      failureCount: json['failure_count'] as int? ?? 0,
      errorCounts:
          (json['error_counts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
    );
  }

  final int userCount;
  final int tokenCount;
  final int successCount;
  final int failureCount;
  final Map<String, int> errorCounts;
}

/// Result of POST /send-account-approval: counts for single-user approval push.
class SendAccountApprovalResponse {
  const SendAccountApprovalResponse({
    required this.tokenCount,
    required this.successCount,
    required this.failureCount,
    required this.errorCounts,
  });

  factory SendAccountApprovalResponse.fromJson(Map<String, dynamic> json) {
    return SendAccountApprovalResponse(
      tokenCount: json['token_count'] as int? ?? 0,
      successCount: json['success_count'] as int? ?? 0,
      failureCount: json['failure_count'] as int? ?? 0,
      errorCounts:
          (json['error_counts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
    );
  }

  final int tokenCount;
  final int successCount;
  final int failureCount;
  final Map<String, int> errorCounts;
}

/// Result of POST /send-user-push (single-user push, e.g. product/task approved).
class SendUserPushResponse {
  const SendUserPushResponse({
    required this.tokenCount,
    required this.successCount,
    required this.failureCount,
    required this.errorCounts,
  });

  factory SendUserPushResponse.fromJson(Map<String, dynamic> json) {
    return SendUserPushResponse(
      tokenCount: json['token_count'] as int? ?? 0,
      successCount: json['success_count'] as int? ?? 0,
      failureCount: json['failure_count'] as int? ?? 0,
      errorCounts:
          (json['error_counts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
    );
  }

  final int tokenCount;
  final int successCount;
  final int failureCount;
  final Map<String, int> errorCounts;
}

/// Result of POST /schedule-announcement-reminder.
class ScheduleAnnouncementReminderResponse {
  const ScheduleAnnouncementReminderResponse({
    required this.enabled,
    required this.status,
    this.taskName,
    this.scheduledForMs,
    this.reason,
  });

  factory ScheduleAnnouncementReminderResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return ScheduleAnnouncementReminderResponse(
      enabled: json['enabled'] as bool? ?? true,
      status: json['status'] as String? ?? 'unknown',
      taskName: json['task_name'] as String?,
      scheduledForMs: (json['scheduled_for_ms'] as num?)?.toInt(),
      reason: json['reason'] as String?,
    );
  }

  final bool enabled;
  final String status;
  final String? taskName;
  final int? scheduledForMs;
  final String? reason;
}

/// Result of POST /cancel-announcement-reminder.
class CancelAnnouncementReminderResponse {
  const CancelAnnouncementReminderResponse({
    required this.enabled,
    required this.status,
    required this.hadTask,
  });

  factory CancelAnnouncementReminderResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return CancelAnnouncementReminderResponse(
      enabled: json['enabled'] as bool? ?? true,
      status: json['status'] as String? ?? 'unknown',
      hadTask: json['had_task'] as bool? ?? false,
    );
  }

  final bool enabled;
  final String status;
  final bool hadTask;
}

/// Calls POST /send-account-approval to notify the approved user (single-user push).
/// Fetches fcmTokens from awaitingApproval on the backend. Non-blocking: do not fail approval if this throws.
Future<SendAccountApprovalResponse> sendAccountApprovalPush({
  required String requestId,
  required String userId,
  required String title,
  required String body,
}) async {
  final uri = Uri.parse('$_pushBaseUrl/send-account-approval');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'request_id': requestId,
          'user_id': userId,
          'title': title,
          'body': body,
        }),
      )
      .timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    final responseBody = response.body;
    throw AnnouncementBackendException(
      responseBody.isNotEmpty
          ? '$responseBody\n(request: $uri)'
          : 'Send account approval push failed (${response.statusCode}) (request: $uri)',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException(
      'Empty response from send-account-approval',
    );
  }
  return SendAccountApprovalResponse.fromJson(json);
}

/// Calls POST /send-user-push to notify a single user (e.g. product approved, task approved).
Future<SendUserPushResponse> sendUserPush({
  required String userId,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  final uri = Uri.parse('$_pushBaseUrl/send-user-push');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'title': title,
          'body': body,
          if (data != null && data.isNotEmpty) 'data': data,
        }),
      )
      .timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    final responseBody = response.body;
    throw AnnouncementBackendException(
      responseBody.isNotEmpty
          ? '$responseBody\n(request: $uri)'
          : 'Send user push failed (${response.statusCode}) (request: $uri)',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException('Empty response from send-user-push');
  }
  return SendUserPushResponse.fromJson(json);
}

/// Calls POST /schedule-announcement-reminder.
Future<ScheduleAnnouncementReminderResponse> scheduleAnnouncementReminder({
  required String announcementId,
  required String requestedByUserId,
}) async {
  final uri = Uri.parse('$_pushBaseUrl/schedule-announcement-reminder');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'announcement_id': announcementId,
          'requested_by_user_id': requestedByUserId,
        }),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    final responseBody = response.body;
    throw AnnouncementBackendException(
      responseBody.isNotEmpty
          ? '$responseBody\n(request: $uri)'
          : 'Schedule reminder failed (${response.statusCode}) (request: $uri)',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException(
      'Empty response from schedule-announcement-reminder',
    );
  }
  return ScheduleAnnouncementReminderResponse.fromJson(json);
}

/// Calls POST /cancel-announcement-reminder.
Future<CancelAnnouncementReminderResponse> cancelAnnouncementReminder({
  required String announcementId,
  required String requestedByUserId,
}) async {
  final uri = Uri.parse('$_pushBaseUrl/cancel-announcement-reminder');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'announcement_id': announcementId,
          'requested_by_user_id': requestedByUserId,
        }),
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    final responseBody = response.body;
    throw AnnouncementBackendException(
      responseBody.isNotEmpty
          ? '$responseBody\n(request: $uri)'
          : 'Cancel reminder failed (${response.statusCode}) (request: $uri)',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException(
      'Empty response from cancel-announcement-reminder',
    );
  }
  return CancelAnnouncementReminderResponse.fromJson(json);
}

/// Calls POST /refine with [rawText]. Returns original and refined text.
/// Throws [AnnouncementBackendException] on empty response, 4xx/5xx, or network error.
/// Uses 120s timeout; refine can be slow if Ollama is cold or under load.
Future<RefineResponse> refineAnnouncementText(
  String rawText, {
  String? signerName,
  String? signerTitle,
}) async {
  final uri = Uri.parse('$kAnnouncementBackendBaseUrl/refine');
  final payload = <String, dynamic>{'raw_text': rawText};
  final cleanSignerName = signerName?.trim() ?? '';
  final cleanSignerTitle = signerTitle?.trim() ?? '';
  if (cleanSignerName.isNotEmpty) {
    payload['signer_name'] = cleanSignerName;
  }
  if (cleanSignerTitle.isNotEmpty) {
    payload['signer_title'] = cleanSignerTitle;
  }

  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 120));

  if (response.statusCode != 200) {
    final body = response.body;
    throw AnnouncementBackendException(
      body.isNotEmpty ? body : 'Refine failed (${response.statusCode})',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException('Empty response from refine');
  }
  return RefineResponse.fromJson(json);
}

/// Calls POST /recommend-audiences with [text] (e.g. refined announcement).
/// Returns suggested audiences and matched rules (rule-based, no AI).
Future<RecommendAudiencesResponse> recommendAudiences(String text) async {
  final uri = Uri.parse('$kAnnouncementBackendBaseUrl/recommend-audiences');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      )
      .timeout(const Duration(seconds: 10));

  if (response.statusCode != 200) {
    final body = response.body;
    throw AnnouncementBackendException(
      body.isNotEmpty
          ? body
          : 'Recommend audiences failed (${response.statusCode})',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException(
      'Empty response from recommend-audiences',
    );
  }
  return RecommendAudiencesResponse.fromJson(json);
}

/// Calls POST /send-announcement-push to deliver targeted push notifications.
///
/// Human-in-the-loop:
/// - The Admin app must call this only after the admin confirms sending.
Future<SendAnnouncementPushResponse> sendAnnouncementPush({
  required String announcementId,
  required String title,
  required String body,
  required List<String> audiences,
  String? requestedByUserId,
  Map<String, String>? data,
}) async {
  final payloadData = <String, String>{
    if (data != null) ...data,
    'type': 'announcement',
    'announcementId': announcementId,
    'title': title,
    'body': body,
    'priority': 'high',
    'alertStyle': 'announcement_priority',
    'attemptFullScreen': 'true',
  };
  final uri = Uri.parse('$_pushBaseUrl/send-announcement-push');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'announcement_id': announcementId,
          'title': title,
          'body': body,
          'audiences': audiences,
          if (requestedByUserId != null)
            'requested_by_user_id': requestedByUserId,
          'data': payloadData,
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (response.statusCode != 200) {
    final responseBody = response.body;
    throw AnnouncementBackendException(
      responseBody.isNotEmpty
          ? '$responseBody\n(request: $uri)'
          : 'Send push failed (${response.statusCode}) (request: $uri)',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException(
      'Empty response from send-announcement-push',
    );
  }
  return SendAnnouncementPushResponse.fromJson(json);
}
