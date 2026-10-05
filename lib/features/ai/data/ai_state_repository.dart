import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/main.dart';

class AnimeWatchPlan {
  const AnimeWatchPlan({
    required this.id,
    required this.title,
    required this.animeId,
    required this.groups,
    required this.createdAt,
  });
  final String id;
  final String title;
  final String animeId;
  final List<Map<String, Object?>> groups;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'animeId': animeId,
    'groups': groups,
    'createdAt': createdAt.toIso8601String(),
  };
}

class AiStateRepository {
  static const _shareEndpoint = 'https://anidashweb.vercel.app/api/shared-chat';
  static const _plansKey = 'ai_watch_plans_v1';
  static const _jobsKey = 'ai_action_jobs_v1';
  static const _chatHistoryKey = 'ai_chat_history_v1';
  static const _conversationsKey = 'ai_conversations_v2';
  static const _activeConversationKey = 'ai_active_conversation_v2';

  List<Map<String, Object?>> get plans => _readList(_plansKey);
  List<Map<String, Object?>> get jobs => _readList(_jobsKey);
  List<Map<String, Object?>> get chatHistory => _readList(_chatHistoryKey);
  List<Map<String, Object?>> get conversations =>
      _readList(_conversationsKey)..sort(
        (a, b) => (b['updatedAt']?.toString() ?? '').compareTo(
          a['updatedAt']?.toString() ?? '',
        ),
      );
  String? get activeConversationId =>
      sharedPrefs.getString(_activeConversationKey);

  List<Map<String, Object?>> messagesFor(String id) {
    final match = conversations.where((item) => item['id'] == id);
    if (match.isEmpty) return const [];
    return (match.first['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }

  Future<void> saveConversation({
    required String id,
    required String title,
    required List<Map<String, Object?>> messages,
  }) async {
    final record = <String, Object?>{
      'id': id,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages':
          messages.length > 100
              ? messages.sublist(messages.length - 100)
              : messages,
    };
    final next =
        [
          record,
          ...conversations.where((item) => item['id'] != id),
        ].take(30).toList();
    await sharedPrefs.setString(_conversationsKey, jsonEncode(next));
    await sharedPrefs.setString(_activeConversationKey, id);
  }

  Future<void> setActiveConversation(String id) =>
      sharedPrefs.setString(_activeConversationKey, id);

  Future<String> createShareLink(
    List<Map<String, Object?>> messages, {
    String title = 'AnyCore chat',
  }) async {
    final random = Random.secure();
    for (var attempt = 0; attempt < 4; attempt++) {
      final id =
          List.generate(
            12,
            (_) =>
                'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[random
                    .nextInt(62)],
          ).join();
      final response = await http.post(
        Uri.parse(_shareEndpoint),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'title': title.trim().isEmpty ? 'AnyCore chat' : title.trim(),
          'messages': messages,
        }),
      );
      if (response.statusCode == 201) {
        return 'https://anidashweb.vercel.app/c/$id';
      }
      if (response.statusCode != 409) break;
    }
    throw StateError('Unable to create share link');
  }

  Future<List<Map<String, Object?>>> loadSharedChat(String id) async {
    final response = await http.get(Uri.parse('$_shareEndpoint?id=$id'));
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }

  Future<void> saveChatHistory(List<Map<String, Object?>> messages) async {
    await sharedPrefs.setString(
      _chatHistoryKey,
      jsonEncode(
        messages.length > 100
            ? messages.sublist(messages.length - 100)
            : messages,
      ),
    );
  }

  Future<void> clearChatHistory() => sharedPrefs.remove(_chatHistoryKey);

  Future<void> savePlan(AnimeWatchPlan plan) async {
    final next = [
      ...plans.where((item) => item['id'] != plan.id),
      plan.toJson(),
    ];
    await sharedPrefs.setString(_plansKey, jsonEncode(next));
  }

  Future<void> saveJob({
    required String jobId,
    required String state,
    required int completed,
    required int total,
    List<AiAction> undoActions = const [],
  }) async {
    final record = <String, Object?>{
      'jobId': jobId,
      'state': state,
      'completed': completed,
      'total': total,
      'updatedAt': DateTime.now().toIso8601String(),
      'undoActions':
          undoActions
              .map(
                (item) => {
                  'type': item.type,
                  'capability': item.capability.name,
                  'arguments': item.arguments,
                  'label': item.label,
                },
              )
              .toList(),
    };
    final next = [...jobs.where((item) => item['jobId'] != jobId), record];
    await sharedPrefs.setString(_jobsKey, jsonEncode(next.take(50).toList()));
  }

  List<Map<String, Object?>> _readList(String key) {
    try {
      final decoded = jsonDecode(sharedPrefs.getString(key) ?? '[]') as List;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
