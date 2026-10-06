import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/shared/providers/settings/theme_notifier.dart';

class MacDesktopTopBar extends ConsumerStatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onSearchTap;

  const MacDesktopTopBar({
    super.key,
    required this.title,
    required this.icon,
    this.onSearchTap,
  });

  @override
  ConsumerState<MacDesktopTopBar> createState() => _MacDesktopTopBarState();
}

class _MacDesktopTopBarState extends ConsumerState<MacDesktopTopBar> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _cycleTheme() {
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final current = ref.read(themeSettingsProvider);
    if (!current.amoled && current.themeMode == 'dark') {
      themeNotifier.updateSettings((s) => s.copyWith(amoled: true));
    } else if (current.amoled) {
      themeNotifier.updateSettings(
        (s) => s.copyWith(amoled: false, themeMode: 'light'),
      );
    } else {
      themeNotifier.updateSettings(
        (s) => s.copyWith(amoled: false, themeMode: 'dark'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();

    return GestureDetector(
      onPanStart: (_) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          windowManager.startDragging();
        }
      },
      onDoubleTap: () async {
        if (!Platform.isAndroid && !Platform.isIOS) {
          final isMax = await windowManager.isMaximized();
          if (isMax) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.9)
              : colorScheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // 1. Back & Forward navigation buttons
            _MacIconButton(
              tooltip: 'Go Back',
              icon: Iconsax.arrow_left_2,
              enabled: canPop,
              onPressed: () {
                if (canPop) Navigator.of(context).pop();
              },
            ),
            const SizedBox(width: 10),

            // 2. Current Page Breadcrumb & Title
            Icon(widget.icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: colorScheme.onSurface,
              ),
            ),

            const SizedBox(width: 24),

            // 3. Desktop Search Pill (Spotlight / Omnibox style)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.25,
                        ),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        hintText: 'Search anime, manga, genres...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        prefixIcon: Icon(
                          Iconsax.search_normal_1,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 28,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (query) {
                        if (query.trim().isNotEmpty) {
                          context.push(
                            '/browse?keyword=${Uri.encodeComponent(query.trim())}',
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // 4. Quick Action Controls
            _MacIconButton(
              tooltip: 'Ask AniAI',
              icon: Iconsax.magicpen,
              iconColor: colorScheme.primary,
              onPressed: () => context.push('/ai'),
            ),
            const SizedBox(width: 6),
            _MacIconButton(
              tooltip: 'Notifications',
              icon: Iconsax.notification,
              onPressed: () => context.push('/notifications'),
            ),
            const SizedBox(width: 6),
            _MacIconButton(
              tooltip: 'Toggle Theme (Dark / AMOLED / Light)',
              icon: Iconsax.moon,
              onPressed: _cycleTheme,
            ),
            const SizedBox(width: 6),
            _MacIconButton(
              tooltip: 'Fullscreen Toggle',
              icon: Iconsax.maximize_4,
              onPressed: () => UIHelper.handleToggleFullscreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? iconColor;

  const _MacIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.enabled = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? (iconColor ?? colorScheme.onSurfaceVariant)
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
