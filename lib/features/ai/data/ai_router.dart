import 'package:ani_dash/features/ai/domain/ai_models.dart';

class AiRouteDecision {
  const AiRouteDecision(this.assistantId, {this.reason});
  final String assistantId;
  final String? reason;
}

class AiModelRouter {
  const AiModelRouter();

  AiRouteDecision route(String text, List<AiAttachment> attachments) {
    if (attachments.any(
      (item) =>
          item.type == AiAttachmentType.image ||
          item.type == AiAttachmentType.screenshot,
    )) {
      return const AiRouteDecision('vision', reason: 'image');
    }
    final normalized = text.trim().toLowerCase();
    if (normalized == 'what is your name?' ||
        normalized == 'what is your name') {
      return const AiRouteDecision('anime_text', reason: 'identity');
    }
    if (normalized.startsWith('/edit ') || normalized == '/undo') {
      return const AiRouteDecision('action', reason: 'write-command');
    }
    if (normalized.startsWith('/plan ')) {
      return const AiRouteDecision('coordinator', reason: 'planning');
    }
    if (normalized.contains('watch order') ||
        normalized.contains('recommend') ||
        normalized.contains('filler') ||
        normalized.contains('arc')) {
      return const AiRouteDecision('anime_text', reason: 'anime-reasoning');
    }
    // Ask Nia is the user-facing conversation. Greetings and ordinary anime
    // questions stay with Nia; other specialists appear only for their job.
    return const AiRouteDecision('anime_text', reason: 'default-conversation');
  }
}
