import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/features/ai/data/ai_policy.dart';
import 'package:ani_dash/features/ai/data/ai_router.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';

void main() {
  group('AniDash AI policy', () {
    final policy = AiPolicy();

    test('lets the backend semantically classify title-only requests', () {
      final result = policy.evaluate(
        'tell me about Black Clover',
        const AiContext(),
      );
      expect(result.allowed, isTrue);
    });

    test('allows contextual anime questions', () {
      final result = policy.evaluate(
        'What happens next?',
        const AiContext(animeId: '21', animeTitle: 'One Piece'),
      );
      expect(result.allowed, isTrue);
    });

    test('write action requires edit authorization', () {
      const action = AiAction(
        type: 'markEpisodeWatched',
        capability: AiCapability.write,
      );
      expect(policy.canExecute(action, editAuthorized: false), isFalse);
      expect(policy.canExecute(action, editAuthorized: true), isTrue);
    });

    test('destructive model action never executes directly', () {
      const action = AiAction(
        type: 'delete',
        capability: AiCapability.destructive,
      );
      expect(policy.canExecute(action, editAuthorized: true), isFalse);
    });
  });

  group('AniDash AI router', () {
    const router = AiModelRouter();

    test('routes screenshots to visual specialist', () {
      final result = router.route('Which anime?', const [
        AiAttachment(
          type: AiAttachmentType.screenshot,
          value: 'data:image/png;base64,x',
        ),
      ]);
      expect(result.assistantId, 'vision');
    });

    test('routes edits to action specialist', () {
      expect(
        router.route('/edit mark episode 3 watched', const []).assistantId,
        'action',
      );
    });

    test('routes watch orders to anime specialist', () {
      expect(
        router.route('One Piece watch order', const []).assistantId,
        'anime_text',
      );
    });

    test('routes identity question to the user-facing anime specialist', () {
      expect(
        router.route('What is your name?', const []).assistantId,
        'anime_text',
      );
    });

    test('routes greetings and normal conversation to Nia', () {
      expect(router.route('Hi', const []).assistantId, 'anime_text');
      expect(
        router.route('Tell me about One Piece', const []).assistantId,
        'anime_text',
      );
    });

    test('routes explicit planning to Mira', () {
      expect(
        router.route('/plan my next anime month', const []).assistantId,
        'coordinator',
      );
    });
  });
}
