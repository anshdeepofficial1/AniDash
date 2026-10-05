import 'package:ani_dash/features/ai/data/ai_cache.dart';
import 'package:ani_dash/features/ai/data/ai_policy.dart';
import 'package:ani_dash/features/ai/data/ai_provider_client.dart';
import 'package:ani_dash/features/ai/data/ai_router.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/features/ai/domain/assistant_registry.dart';

class AiOrchestrator {
  AiOrchestrator({
    AiProviderClient? client,
    AiPolicy? policy,
    AiResponseCache? cache,
    AssistantRegistry? registry,
  }) : _client = client ?? AniDashAiProxyClient(),
       _policy = policy ?? AiPolicy(),
       _cache = cache ?? AiResponseCache(),
       _registry = registry ?? AssistantRegistry();

  final AiProviderClient _client;
  final AiPolicy _policy;
  final AiResponseCache _cache;
  final AssistantRegistry _registry;
  final AiModelRouter _router = const AiModelRouter();

  Stream<AiStreamEvent> send({
    required String message,
    required AiContext context,
    List<AiAttachment> attachments = const [],
  }) async* {
    final policy = _policy.evaluate(message, context);
    if (!policy.allowed) {
      yield AiStreamEvent(AiStreamEventType.error, text: policy.reason);
      return;
    }

    final decision = _router.route(message, attachments);
    final profile = _registry.byId(decision.assistantId);
    final normalized = message.trim().toLowerCase();

    // Identity is app state, not an AI inference and costs no provider call.
    if (normalized == 'what is your name?' ||
        normalized == 'what is your name') {
      final response = AiResponse(
        text:
            'My name is ${profile.displayName}. I am your AniDash ${_roleLabel(profile.role)}.',
        assistantId: profile.id,
      );
      yield AiStreamEvent(AiStreamEventType.done, response: response);
      return;
    }

    final request = AiRequest(
      message: message,
      assistantId: profile.id,
      displayName: profile.displayName,
      globalInstructions: _registry.globalInstructions,
      specialistInstructions: profile.customInstructions,
      context: context,
      attachments: attachments,
      editAuthorized: policy.edit,
    );
    final cached = _cache.get(request);
    if (cached != null) {
      yield AiStreamEvent(AiStreamEventType.done, response: cached);
      return;
    }

    await for (final event in _client.send(request)) {
      if (event.type == AiStreamEventType.done && event.response != null) {
        final response = event.response!;
        final safeActions = response.actions
            .where(
              (action) =>
                  _policy.canExecute(action, editAuthorized: policy.edit),
            )
            .toList(growable: false);
        final safe = AiResponse(
          text: response.text,
          // The local router owns character selection. Providers may suggest
          // actions, but must not randomly replace the visible specialist.
          assistantId: decision.assistantId,
          actions: safeActions,
          handoffFrom: response.handoffFrom,
          handoffTo: response.handoffTo,
          cached: response.cached,
        );
        await _cache.put(request, safe);
        yield AiStreamEvent(AiStreamEventType.done, response: safe);
      } else {
        yield event;
      }
    }
  }

  String _roleLabel(AssistantRole role) => switch (role) {
    AssistantRole.coordinator => 'main assistant',
    AssistantRole.animeText => 'anime specialist',
    AssistantRole.vision => 'visual specialist',
    AssistantRole.action => 'action specialist',
  };
}
