import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/features/ai/application/ai_action_executor.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';

void main() {
  test('executor reports real completion for allowlisted write', () async {
    final executor = AiActionExecutor();
    var invoked = false;
    executor.register('markEpisodeWatched', (_) async {
      invoked = true;
      return null;
    });
    const action = AiAction(
      type: 'markEpisodeWatched',
      capability: AiCapability.write,
      label: 'Episode 3',
    );
    final events =
        await executor
            .execute(
              const [action],
              editAuthorized: true,
              destructiveConfirmed: false,
            )
            .toList();
    expect(invoked, isTrue);
    expect(events.last.state, 'completed');
    expect(events.last.completed, 1);
  });

  test('executor refuses writes without edit permission', () async {
    final executor = AiActionExecutor();
    var invoked = false;
    executor.register('markEpisodeWatched', (_) async => invoked = true);
    final events =
        await executor
            .execute(
              const [
                AiAction(
                  type: 'markEpisodeWatched',
                  capability: AiCapability.write,
                ),
              ],
              editAuthorized: false,
              destructiveConfirmed: false,
            )
            .toList();
    expect(invoked, isFalse);
    expect(events.last.total, 0);
  });
}
