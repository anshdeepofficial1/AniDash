import 'dart:io';
import 'dart:ui';
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

class _MacDesktopTopBarState extends ConsumerState<MacDesktopTopBar>
    with WindowListener {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid && !Platform.isIOS) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  Future<void> _checkMaximized() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = max);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void dispose() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      windowManager.removeListener(this);
    }
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
    final isDark = theme.brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    final isMac = Platform.isMacOS;
    final mod = isMac ? '⌘' : 'Ctrl+';

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
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: 52,
            padding: EdgeInsets.only(
              left: 16,
              right: isMac ? 16 : 0,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF14161C).withValues(alpha: 0.75)
                  : const Color(0xFFFFFFFF).withValues(alpha: 0.85),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.07),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // 1. Back navigation button (macOS / Windows segmented chevron)
                _MacIconButton(
                  tooltip: 'Go Back (${isMac ? '⌘[' : 'Alt+←'})',
                  icon: Iconsax.arrow_left_2,
                  enabled: canPop,
                  isDark: isDark,
                  onPressed: () {
                    if (canPop) Navigator.of(context).pop();
                  },
                ),
                const SizedBox(width: 10),

                // 2. Current Page Breadcrumb & Title
                Icon(widget.icon, size: 17, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(width: 24),

                // 3. Apple / Windows Fluent Spotlight Search Field
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6.5,
                            ),
                            hintText: 'Search anime, manga, genres... (${mod}F)',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            prefixIcon: Icon(
                              Iconsax.search_normal_1,
                              size: 13,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 28,
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

                // 4. Quick Action Controls with tooltips & keyboard hints
                _MacIconButton(
                  tooltip: 'Ask AniAI (${mod}K)',
                  icon: Iconsax.magicpen,
                  iconColor: colorScheme.primary,
                  isDark: isDark,
                  onPressed: () => context.push('/ai'),
                ),
                const SizedBox(width: 6),
                _MacIconButton(
                  tooltip: 'Notifications (${mod}N)',
                  icon: Iconsax.notification,
                  isDark: isDark,
                  onPressed: () => context.push('/notifications'),
                ),
                const SizedBox(width: 6),
                _MacIconButton(
                  tooltip: 'Cycle Theme (Dark / AMOLED / Light)',
                  icon: Iconsax.moon,
                  isDark: isDark,
                  onPressed: _cycleTheme,
                ),
                const SizedBox(width: 6),
                _MacIconButton(
                  tooltip: 'Toggle Fullscreen (${isMac ? '⌃⌘F' : 'F11'})',
                  icon: Iconsax.maximize_4,
                  isDark: isDark,
                  onPressed: () => UIHelper.handleToggleFullscreen(),
                ),

                // 5. Native Windows Window Caption Buttons (Minimize, Maximize/Restore, Close)
                if (!isMac && !Platform.isAndroid && !Platform.isIOS) ...[
                  const SizedBox(width: 10),
                  _WindowsCaptionButtons(
                    isDark: isDark,
                    isMaximized: _isMaximized,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsCaptionButtons extends StatelessWidget {
  final bool isDark;
  final bool isMaximized;

  const _WindowsCaptionButtons({
    required this.isDark,
    required this.isMaximized,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WindowsCaptionButton(
          tooltip: 'Minimize',
          icon: Icons.remove,
          isDark: isDark,
          onPressed: () => windowManager.minimize(),
        ),
        _WindowsCaptionButton(
          tooltip: isMaximized ? 'Restore' : 'Maximize',
          icon: isMaximized ? Icons.filter_none : Icons.crop_square_sharp,
          iconSize: isMaximized ? 12 : 14,
          isDark: isDark,
          onPressed: () async {
            if (isMaximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowsCaptionButton(
          tooltip: 'Close',
          icon: Icons.close,
          iconSize: 15,
          isDark: isDark,
          isClose: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WindowsCaptionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool isDark;
  final bool isClose;
  final VoidCallback onPressed;

  const _WindowsCaptionButton({
    required this.tooltip,
    required this.icon,
    this.iconSize = 14,
    required this.isDark,
    this.isClose = false,
    required this.onPressed,
  });

  @override
  State<_WindowsCaptionButton> createState() => _WindowsCaptionButtonState();
}

class _WindowsCaptionButtonState extends State<_WindowsCaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHovered = _isHovered;
    final isClose = widget.isClose;
    final isDark = widget.isDark;

    final Color bgColor = isHovered
        ? (isClose
            ? const Color(0xFFE81123)
            : (isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08)))
        : Colors.transparent;

    final Color iconColor = (isHovered && isClose)
        ? Colors.white
        : (isDark ? Colors.white70 : Colors.black87);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 52,
            color: bgColor,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _MacIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? iconColor;
  final bool isDark;

  const _MacIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.enabled = true,
    this.iconColor,
    required this.isDark,
  });

  @override
  State<_MacIconButton> createState() => _MacIconButtonState();
}

class _MacIconButtonState extends State<_MacIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final isDark = widget.isDark;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: _isHovered && enabled
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.06))
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: enabled
                  ? (widget.iconColor ??
                      (isDark ? Colors.white70 : Colors.black54))
                  : (isDark ? Colors.white24 : Colors.black26),
            ),
          ),
        ),
      ),
    );
  }
}
