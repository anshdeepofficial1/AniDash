import 'package:ani_dash/features/ai/domain/ai_models.dart';

class AiPolicyResult {
  const AiPolicyResult({required this.allowed, this.reason, this.edit = false});
  final bool allowed;
  final bool edit;
  final String? reason;
}

class AiPolicy {
  AiPolicyResult evaluate(String input, AiContext context) {
    final text = input.trim().toLowerCase();
    if (text.isEmpty) {
      return const AiPolicyResult(
        allowed: false,
        reason: 'Type an anime or manga question first.',
      );
    }
    final edit = text.startsWith('/edit ');
    // Anime titles are open-ended (for example "Black Clover") and cannot be
    // reliably recognized with a small keyword list. Let the AI read the full
    // question and apply the server-side scope instructions instead of falsely
    // rejecting valid title-only questions on the device.
    return AiPolicyResult(allowed: true, edit: edit);
  }

  bool canExecute(AiAction action, {required bool editAuthorized}) {
    switch (action.capability) {
      case AiCapability.read:
      case AiCapability.navigation:
        return true;
      case AiCapability.write:
        return editAuthorized;
      case AiCapability.destructive:
        return false;
    }
  }
}
