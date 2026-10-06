import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

class SponsorDialog extends StatelessWidget {
  const SponsorDialog({super.key});

  static const String upiId = 'anshdeep200618-3@oksbi';

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const SponsorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFDD00).withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFFFDD00).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Iconsax.coffee,
          color: Color(0xFFFFDD00),
          size: 34,
        ),
      ),
      title: const Text(
        'Sponsor AniDash 💖☕',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AniDash is crafted with love as a 100% free, open-source, and ad-free anime platform. 🎬✨\n\n'
              'Maintaining scrapers, fast streams, and continuous updates requires significant ongoing server resources and dedication. As an independent solo developer, keeping AniDash alive and ad-free relies directly on community sponsorships.\n\n'
              'Sponsor this project so that it can always be continued without any interference. If community sponsorships cannot cover ongoing operational costs, ads may unfortunately have to be introduced to sustain the project.\n\n'
              'Every contribution makes a world of difference! ❤️🚀',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.88),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),

            // Direct UPI
            Material(
              color: colorScheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final upiUri = Uri.parse(
                    'upi://pay?pa=$upiId&pn=Anshdeep%20Singh&cu=INR&tn=Sponsor%20AniDash',
                  );
                  bool launched = false;
                  try {
                    launched = await launchUrl(
                      upiUri,
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                  if (!launched && context.mounted) {
                    await Clipboard.setData(const ClipboardData(text: upiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'UPI ID copied! Open your UPI app (GPay/PhonePe/Paytm) to sponsor.',
                        ),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(Iconsax.card, color: colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'UPI Direct (GPay, PhonePe, Paytm)',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              upiId,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.touch_app_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Buy Me a Coffee
            Material(
              color: const Color(0xFFFFDD00).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final uri = Uri.parse(
                    'https://buymeacoffee.com/anshdeepofficial',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Iconsax.coffee,
                        color: Color(0xFFFFDD00),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Buy Me a Coffee',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // GitHub Sponsor
            Material(
              color: const Color(0xFFEA4AAA).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final uri = Uri.parse(
                    'https://github.com/sponsors/anshdeepofficial1',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Iconsax.heart,
                        color: Color(0xFFEA4AAA),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'GitHub Sponsor',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Sponsor Later',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            elevation: 2,
          ),
          onPressed: () async {
            final upiUri = Uri.parse(
              'upi://pay?pa=$upiId&pn=Anshdeep%20Singh&cu=INR&tn=Sponsor%20AniDash',
            );
            bool launched = false;
            try {
              launched = await launchUrl(
                upiUri,
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {}
            if (!launched && context.mounted) {
              await Clipboard.setData(const ClipboardData(text: upiId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'UPI ID copied! Open your UPI app (GPay/PhonePe/Paytm) to sponsor.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.favorite_rounded, size: 18),
          label: const Text(
            'Sponsor Now',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
