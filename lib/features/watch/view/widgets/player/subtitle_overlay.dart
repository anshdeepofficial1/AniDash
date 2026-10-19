import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/features/settings/utils/subtitle_utils.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/shared/providers/settings/subtitle_notifier.dart';

class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleStyle = ref.watch(subtitleAppearanceProvider);
    final subtitleText = ref.watch(
      playerStateProvider.select(
        (s) => s.subtitle.isEmpty ? null : s.subtitle.join('\n'),
      ),
    );
    final margin = subtitleStyle.bottomMargin;
    if (subtitleText == null || subtitleText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 8.0,
        right: 8.0,
        bottom: subtitleStyle.position == 1 ? margin : 10.0,
        top: subtitleStyle.position == 3 ? margin : 10.0,
      ),
      child: Align(
        alignment: subtitleStyle.position == 1
            ? Alignment.bottomCenter
            : subtitleStyle.position == 2
            ? Alignment.center
            : Alignment.topCenter,
        child: Container(
          decoration: BoxDecoration(
            color: Color(
              subtitleStyle.backgroundColor,
            ).withValues(alpha: subtitleStyle.backgroundOpacity),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              if (subtitleStyle.outlineWidth > 0)
                Text(
                  subtitleStyle.forceUppercase
                      ? subtitleText.toUpperCase()
                      : subtitleText,
                  textAlign: TextAlign.center,
                  style: SubtitleUtils.getSubtitleTextStyle(
                    subtitleStyle,
                    stroke: true,
                  ),
                ),
              Text(
                subtitleStyle.forceUppercase
                    ? subtitleText.toUpperCase()
                    : subtitleText,
                textAlign: TextAlign.center,
                style: SubtitleUtils.getSubtitleTextStyle(subtitleStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
