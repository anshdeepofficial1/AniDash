import 'dart:convert';
import 'dart:io';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/env_loader.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum FeedbackCategory {
  bug('Bug / Error', 'bug'),
  playback('Video / Playback', 'playback'),
  request('Feature Request', 'request'),
  other('General Feedback', 'other');

  final String label;
  final String key;
  const FeedbackCategory(this.label, this.key);

  static FeedbackCategory fromKey(String key) {
    return FeedbackCategory.values.firstWhere(
      (c) => c.key == key,
      orElse: () => FeedbackCategory.other,
    );
  }
}

class FeedbackReport {
  final String id;
  final String type;
  final String title;
  final String description;
  final String contact;
  final String appVersion;
  final String platform;
  final String? animeTitle;
  final DateTime createdAt;
  final bool isResolved;
  final String? githubIssueUrl;

  const FeedbackReport({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.contact,
    required this.appVersion,
    required this.platform,
    this.animeTitle,
    required this.createdAt,
    this.isResolved = false,
    this.githubIssueUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'contact': contact,
        'appVersion': appVersion,
        'platform': platform,
        'animeTitle': animeTitle,
        'createdAt': createdAt.toIso8601String(),
        'isResolved': isResolved,
        'githubIssueUrl': githubIssueUrl,
      };

  factory FeedbackReport.fromJson(Map<String, dynamic> json) {
    return FeedbackReport(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'other',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      contact: json['contact']?.toString() ?? '',
      appVersion: json['appVersion']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      animeTitle: json['animeTitle']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isResolved: json['isResolved'] == true,
      githubIssueUrl: json['githubIssueUrl']?.toString(),
    );
  }
}

class GitHubIssueItem {
  final int number;
  final String title;
  final String state;
  final String author;
  final String? authorAvatar;
  final List<String> labels;
  final int commentsCount;
  final DateTime createdAt;
  final String htmlUrl;
  final String body;

  const GitHubIssueItem({
    required this.number,
    required this.title,
    required this.state,
    required this.author,
    this.authorAvatar,
    required this.labels,
    required this.commentsCount,
    required this.createdAt,
    required this.htmlUrl,
    required this.body,
  });

  factory GitHubIssueItem.fromJson(Map<String, dynamic> json) {
    final labelsList = (json['labels'] as List?)
            ?.map((e) => (e is Map ? e['name'] : e).toString())
            .toList() ??
        <String>[];
    return GitHubIssueItem(
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'No title',
      state: json['state']?.toString() ?? 'open',
      author: (json['user'] as Map?)?['login']?.toString() ?? 'anonymous',
      authorAvatar: (json['user'] as Map?)?['avatar_url']?.toString(),
      labels: labelsList,
      commentsCount: (json['comments'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      htmlUrl: json['html_url']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
    );
  }
}

class FeedbackService {
  static const FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  const FeedbackService._internal();

  static const String _localPrefsKey = 'anidash_user_feedback_reports_v1';

  /// Submit a feedback report: saves locally and forwards to backend API / GitHub
  Future<FeedbackReport> submitFeedback({
    required String type,
    required String title,
    required String description,
    required String contact,
    required String appVersion,
    String? animeTitle,
  }) async {
    final id = 'fb_${DateTime.now().millisecondsSinceEpoch}';
    final report = FeedbackReport(
      id: id,
      type: type,
      title: title.trim(),
      description: description.trim(),
      contact: contact.trim(),
      appVersion: appVersion.trim(),
      platform: Platform.operatingSystem,
      animeTitle: animeTitle?.trim(),
      createdAt: DateTime.now(),
    );

    // 1. Save locally in device storage so reports are never lost
    await _saveLocalReport(report);

    // 2. Post to AniDash backend (Vercel API)
    try {
      final uri = Uri.parse('$ANIDASH_ADMIN_API_URL/feedback');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(report.toJson()),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final githubUrl = data['githubIssueUrl']?.toString();
        if (githubUrl != null && githubUrl.isNotEmpty) {
          final updatedReport = FeedbackReport(
            id: report.id,
            type: report.type,
            title: report.title,
            description: report.description,
            contact: report.contact,
            appVersion: report.appVersion,
            platform: report.platform,
            animeTitle: report.animeTitle,
            createdAt: report.createdAt,
            githubIssueUrl: githubUrl,
          );
          await _saveLocalReport(updatedReport);
          return updatedReport;
        }
      }
    } catch (e) {
      AppLogger.d('Remote feedback submission skipped: $e');
    }

    return report;
  }

  /// Get locally stored reports on this device
  Future<List<FeedbackReport>> getLocalReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((e) => FeedbackReport.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.d('Error reading local feedback: $e');
    }
    return [];
  }

  Future<void> _saveLocalReport(FeedbackReport report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getLocalReports();
      final filtered = current.where((r) => r.id != report.id).toList();
      filtered.insert(0, report);
      final jsonStr = jsonEncode(filtered.map((e) => e.toJson()).toList());
      await prefs.setString(_localPrefsKey, jsonStr);
    } catch (e) {
      AppLogger.d('Error saving local feedback report: $e');
    }
  }

  /// Get remote reports from Vercel backend (requires admin token / pin)
  Future<List<FeedbackReport>> getRemoteReports({
    required String accessToken,
    required String developerPin,
  }) async {
    try {
      final uri = Uri.parse('$ANIDASH_ADMIN_API_URL/feedback');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'X-Admin-Pin': developerPin,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reports = data['reports'] as List? ?? [];
        return reports
            .map((e) => FeedbackReport.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.d('Error fetching remote feedback: $e');
    }
    return [];
  }

  /// Delete a report locally and remotely
  Future<void> deleteReport({
    required String id,
    String? accessToken,
    String? developerPin,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getLocalReports();
      final filtered = current.where((r) => r.id != id).toList();
      await prefs.setString(
        _localPrefsKey,
        jsonEncode(filtered.map((e) => e.toJson()).toList()),
      );

      if (accessToken != null && developerPin != null) {
        final uri = Uri.parse('$ANIDASH_ADMIN_API_URL/feedback?id=$id');
        await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'X-Admin-Pin': developerPin,
          },
        ).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      AppLogger.d('Error deleting feedback report: $e');
    }
  }

  /// Live query GitHub issues for anshdeepofficial1/AniDash
  Future<List<GitHubIssueItem>> fetchGitHubIssues({
    String state = 'all',
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/anshdeepofficial1/AniDash/issues?state=$state&per_page=50',
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'AniDash-Admin-Viewer',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list
            .map((e) => GitHubIssueItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.d('Error fetching GitHub issues: $e');
    }
    return [];
  }
}
