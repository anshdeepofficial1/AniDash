import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ani_dash/features/ai/domain/ai_models.dart';

abstract interface class AiProviderClient {
  Stream<AiStreamEvent> send(AiRequest request);
}

class AniDashAiProxyClient implements AiProviderClient {
  AniDashAiProxyClient({
    http.Client? client,
    this.endpoint = 'https://anidashweb.vercel.app/api/ai',
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final String endpoint;

  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final text = decoded['text']?.toString() ?? '';
        final actions = (decoded['actions'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => AiAction.fromJson(Map<String, Object?>.from(item)))
            .toList(growable: false);
        if (text.isNotEmpty) {
          for (var offset = 0; offset < text.length; offset += 28) {
            final end = (offset + 28).clamp(0, text.length);
            yield AiStreamEvent(
              AiStreamEventType.textDelta,
              text: text.substring(offset, end),
            );
          }
        }
        yield AiStreamEvent(
          AiStreamEventType.done,
          response: AiResponse(
            text: text,
            assistantId:
                decoded['assistantId']?.toString() ?? request.assistantId,
            actions: actions,
            handoffFrom: decoded['handoffFrom']?.toString(),
            handoffTo: decoded['handoffTo']?.toString(),
          ),
        );
        return;
      }
      // If Vercel returned 404, 503 or error, gracefully fall back to direct resilient AI
      yield* _fallbackDirectAi(request);
    } catch (_) {
      // Fallback on timeout or network exceptions
      yield* _fallbackDirectAi(request);
    }
  }

  Stream<AiStreamEvent> _fallbackDirectAi(AiRequest request) async* {
    try {
      final prompt = Uri.encodeComponent(request.message);
      final system = Uri.encodeComponent(
        'You are AniDash AI, a passionate anime and manga assistant. '
        'Answer questions about anime, manga, characters, episodes, arcs, watch order, and recommendations accurately with friendly, concise markdown. '
        'Never reject newly released episodes, continuations or upcoming sequels (like Black Clover continuation beyond ep 170) as non-existent; explain that sub is available or upcoming and provide expected dub timing on platforms like Crunchyroll. '
        'Never mention internal models or APIs. Keep tone engaging and helpful.',
      );
      final uri = Uri.parse('https://text.pollinations.ai/$prompt?system=$system');
      final res = await _client.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        final text = res.body.trim();
        for (var offset = 0; offset < text.length; offset += 28) {
          final end = (offset + 28).clamp(0, text.length);
          yield AiStreamEvent(
            AiStreamEventType.textDelta,
            text: text.substring(offset, end),
          );
        }
        yield AiStreamEvent(
          AiStreamEventType.done,
          response: AiResponse(
            text: text,
            assistantId: request.assistantId,
            actions: const [],
          ),
        );
        return;
      }
    } catch (_) {}
    yield const AiStreamEvent(
      AiStreamEventType.error,
      text: 'AniDash AI could not connect. Check your internet connection and try again.',
    );
  }
}
