import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowsCaptionButtons extends StatefulWidget {
  final bool? isDark;
  final double height;

  const WindowsCaptionButtons({
    super.key,
    this.isDark,
    this.height = 36,
  });

  @override
  State<WindowsCaptionButtons> createState() => _WindowsCaptionButtonsState();
}

class _WindowsCaptionButtonsState extends State<WindowsCaptionButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid && !Platform.isIOS) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
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
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) return const SizedBox.shrink();

    final isDark =
        widget.isDark ?? (Theme.of(context).brightness == Brightness.dark);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WindowsCaptionButton(
          tooltip: 'Minimize',
          icon: Icons.remove,
          isDark: isDark,
          height: widget.height,
          onPressed: () => windowManager.minimize(),
        ),
        _WindowsCaptionButton(
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square_sharp,
          iconSize: _isMaximized ? 12 : 14,
          isDark: isDark,
          height: widget.height,
          onPressed: () async {
            if (_isMaximized) {
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
          height: widget.height,
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
  final double height;
  final VoidCallback onPressed;

  const _WindowsCaptionButton({
    required this.tooltip,
    required this.icon,
    this.iconSize = 14,
    required this.isDark,
    this.isClose = false,
    required this.height,
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
            height: widget.height,
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
