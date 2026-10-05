import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/features/ai/view/widgets/anidash_ai_emblem.dart';

class AskNiaButton extends StatelessWidget {
  const AskNiaButton({
    super.key,
    this.animeId,
    this.animeTitle,
    this.currentEpisode,
    this.compact = false,
  });
  final String? animeId;
  final String? animeTitle;
  final int? currentEpisode;
  final bool compact;

  void _open(BuildContext context) => context.push(
    '/ai',
    extra: AiContext(
      animeId: animeId,
      animeTitle: animeTitle,
      currentEpisode: currentEpisode,
      sourceRoute: GoRouterState.of(context).uri.toString(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return compact
        ? IconButton(
            tooltip: 'Ask AniDash AI',
            icon: const AniDashAiEmblem(size: 22),
            onPressed: () => _open(context),
          )
        : FilledButton.tonalIcon(
            onPressed: () => _open(context),
            icon: const AniDashAiEmblem(size: 20),
            label: const Text('Ask AniDash AI'),
          );
  }
}
