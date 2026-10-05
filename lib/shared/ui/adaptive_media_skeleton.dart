import 'package:flutter/material.dart';

/// A data-free placeholder that follows the dimensions of the selected card
/// mode without rendering card labels such as "Unknown Title".
class AdaptiveMediaSkeleton extends StatelessWidget {
  const AdaptiveMediaSkeleton({super.key, required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fill = colors.surfaceContainerHighest.withValues(alpha: 0.72);
    final soft = colors.surfaceContainerHighest.withValues(alpha: 0.46);
    final isLandscape = size.width / size.height > 1.15;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

    if (isLandscape) {
      return Container(
        width: size.width,
        height: size.height,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: size.height * .72,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(double.infinity, 12),
                  const SizedBox(height: 9),
                  bar(size.width * .28, 9),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final textHeight = (size.height * .18).clamp(24.0, 48.0);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          SizedBox(height: textHeight > 32 ? 9 : 6),
          bar(size.width * .84, 10),
          const SizedBox(height: 6),
          bar(size.width * .52, 8),
        ],
      ),
    );
  }
}
