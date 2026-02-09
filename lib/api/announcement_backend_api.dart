/// API client for the LINKod Admin backend (FastAPI).
///
/// - POST /refine: AI text refinement (Ollama llama3.2:3b)
/// - POST /recommend-audiences: rule-based audience recommendation
///
/// Base URL: local backend, e.g. http://localhost:8000

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the local FastAPI backend. Change if backend runs elsewhere.
const String kAnnouncementBackendBaseUrl = 'http://localhost:8000';

/// Result of POST /refine: original and refined text.
class RefineResponse {
  const RefineResponse({
    required this.originalText,
    required this.refinedText,
  });

  factory RefineResponse.fromJson(Map<String, dynamic> json) {
    return RefineResponse(
      originalText: json['original_text'] as String? ?? '',
      refinedText: json['refined_text'] as String? ?? '',
    );
  }

  final String originalText;
  final String refinedText;
}

/// Result of POST /recommend-audiences: suggested audiences and matched rules.
class RecommendAudiencesResponse {
  const RecommendAudiencesResponse({
    required this.audiences,
    required this.matchedRules,
    required this.defaultUsed,
  });

  factory RecommendAudiencesResponse.fromJson(Map<String, dynamic> json) {
    final audiences = (json['audiences'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    final matchedRules = (json['matched_rules'] as List<dynamic>?)
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
        (json['keywords'] as List<dynamic>?)?.map((e) => e as String).toList() ??
            [];
    final audiences =
        (json['audiences'] as List<dynamic>?)?.map((e) => e as String).toList() ??
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
  String toString() => 'AnnouncementBackendException: $message (status: $statusCode)';
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
      errorCounts: (json['error_counts'] as Map<String, dynamic>?)?.map(
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
      errorCounts: (json['error_counts'] as Map<String, dynamic>?)?.map(
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

/// Calls POST /send-account-approval to notify the approved user (single-user push).
/// Fetches fcmTokens from awaitingApproval on the backend. Non-blocking: do not fail approval if this throws.
Future<SendAccountApprovalResponse> sendAccountApprovalPush({
  required String requestId,
  required String userId,
  required String title,
  required String body,
}) async {
  final uri = Uri.parse('$kAnnouncementBackendBaseUrl/send-account-approval');
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
    final body = response.body;
    throw AnnouncementBackendException(
      body.isNotEmpty ? body : 'Send account approval push failed (${response.statusCode})',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException('Empty response from send-account-approval');
  }
  return SendAccountApprovalResponse.fromJson(json);
}

/// Calls POST /refine with [rawText]. Returns original and refined text.
/// Throws [AnnouncementBackendException] on empty response, 4xx/5xx, or network error.
/// Uses 120s timeout; refine can be slow if Ollama is cold or under load.
Future<RefineResponse> refineAnnouncementText(String rawText) async {
  final uri = Uri.parse('$kAnnouncementBackendBaseUrl/refine');
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'raw_text': rawText}),
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
      body.isNotEmpty ? body : 'Recommend audiences failed (${response.statusCode})',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException('Empty response from recommend-audiences');
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
  final uri = Uri.parse('$kAnnouncementBackendBaseUrl/send-announcement-push');
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
          if (data != null) 'data': data,
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (response.statusCode != 200) {
    final body = response.body;
    throw AnnouncementBackendException(
      body.isNotEmpty ? body : 'Send push failed (${response.statusCode})',
      response.statusCode,
    );
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>?;
  if (json == null) {
    throw AnnouncementBackendException('Empty response from send-announcement-push');
  }
  return SendAnnouncementPushResponse.fromJson(json);
}
