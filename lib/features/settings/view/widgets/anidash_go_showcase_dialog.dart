import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ani_dash/core/constants/anidash_go.dart';
import 'package:ani_dash/main.dart';

class AniDashGoShowcaseDialog extends StatelessWidget {
  const AniDashGoShowcaseDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    if (sharedPrefs.getBool(AniDashGo.showcasePreferenceKey) == true) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AniDashGoShowcaseDialog(),
    );
    await sharedPrefs.setBool(AniDashGo.showcasePreferenceKey, true);
  }

  Future<void> _openWebsite() => launchUrl(
    Uri.parse(AniDashGo.websiteUrl),
    mode: LaunchMode.externalApplication,
  );

  void _showMoreInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AniDash Go on the web',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use AniDash from a desktop, laptop, tablet, or any modern browser without installing the Android app.',
                      ),
                      const SizedBox(height: 20),
                      const _FeatureDetail(
                        icon: Icons.language_rounded,
                        title: 'Anime in your browser',
                        body:
                            'Browse, search, and watch the languages and audio options supplied by the selected source, including Hindi where that title and source support it.',
                      ),
                      const _FeatureDetail(
                        icon: Icons.sync_rounded,
                        title: 'Keep tracker progress aligned',
                        body:
                            'Connect the same AniList or MyAnimeList account on both devices so lists and watch progress stay aligned through that tracker.',
                      ),
                      const _FeatureDetail(
                        icon: Icons.qr_code_2_rounded,
                        title: 'Pair from the app',
                        body:
                            'Open Settings → Devices to scan a short-lived QR code from AniDash Go. This is useful when your tracker is connected in the app but not yet in the browser.',
                      ),
                      const _FeatureDetail(
                        icon: Icons.phonelink_erase_rounded,
                        title: 'What does not sync',
                        body:
                            'Downloaded videos, local cache, and device-only settings remain on the device. Sync covers data supported by your connected tracker account.',
                      ),
                      const _FeatureDetail(
                        icon: Icons.shield_outlined,
                        title: 'Secure by design',
                        body:
                            'Pairing codes are short-lived and single-use. A QR code never contains your password or tracker credential, and you must approve the connection in AniDash.',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openWebsite,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Go to the Website'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.language_rounded,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Introducing AniDash Go',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'AniDash, now available in your browser',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outlineVariant),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final color in const [
                              Color(0xFFFF5F57),
                              Color(0xFFFFBD2E),
                              Color(0xFF28C840),
                            ]) ...[
                              Container(
                                width: 9,
                                height: 9,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'anidashgo.vercel.app',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AspectRatio(
                        aspectRatio: 16 / 10,
                        child: Image.asset(
                          'assets/images/anidash_go_desktop.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  AniDashGo.websiteUrl,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Open the website on a PC and connect the same tracker account to keep supported watch progress and lists aligned.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Not now'),
                    ),
                    OutlinedButton(
                      onPressed: () => _showMoreInfo(context),
                      child: const Text('More Info'),
                    ),
                    FilledButton.icon(
                      onPressed: _openWebsite,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Go to the Website'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureDetail extends StatelessWidget {
  const _FeatureDetail({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );
}
