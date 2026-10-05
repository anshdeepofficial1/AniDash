import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/main.dart';

class AiResponseCache {
  static const _version = 'v1';
  String _key(AiRequest request) =>
      'ai_cache_${sha256.convert(utf8.encode('$_version|${request.assistantId}|${request.message}|${request.context.animeId ?? ''}'))}';

  AiResponse? get(AiRequest request) {
    if (request.context.librarySummary != null || request.editAuthorized) {
      return null;
    }
    final raw = sharedPrefs.getString(_key(request));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final storedAt = DateTime.tryParse(json['storedAt']?.toString() ?? '');
      if (storedAt == null || DateTime.now().difference(storedAt).inDays > 7) {
        return null;
      }
      return AiResponse(
        text: json['text']?.toString() ?? '',
        assistantId: json['assistantId']?.toString() ?? request.assistantId,
        cached: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> put(AiRequest request, AiResponse response) async {
    if (request.context.librarySummary != null ||
        request.editAuthorized ||
        response.actions.isNotEmpty) {
      return;
    }
    await sharedPrefs.setString(
      _key(request),
      jsonEncode({
        'storedAt': DateTime.now().toIso8601String(),
        'text': response.text,
        'assistantId': response.assistantId,
      }),
    );
  }
}
