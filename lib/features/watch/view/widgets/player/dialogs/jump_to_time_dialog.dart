import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

/// Formatter that automatically inserts colon separators from raw digits
/// as the user types without requiring manual ':' entry.
class TimeDigitInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // If user is manually typing colons, units, or dots, preserve directly
    if (newValue.text.contains(':') ||
        newValue.text.contains('m') ||
        newValue.text.contains('s') ||
        newValue.text.contains('h') ||
        newValue.text.contains('.')) {
      return newValue;
    }

    // Extract only digits from new value
    final rawDigits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (rawDigits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Limit to max 6 digits (hhmmss)
    final digits = rawDigits.length > 6 ? rawDigits.substring(0, 6) : rawDigits;

    String formattedText;
    if (digits.length == 1) {
      formattedText = digits;
    } else if (digits.length == 2) {
      formattedText = digits;
    } else if (digits.length == 3) {
      if (digits.startsWith('0')) {
        // e.g. 060 -> "06:0"
        formattedText = '${digits.substring(0, 2)}:${digits[2]}';
      } else {
        // e.g. 607 -> "6:07"
        formattedText = '${digits[0]}:${digits.substring(1)}';
      }
    } else if (digits.length == 4) {
      // e.g. 0607 -> "06:07", 1234 -> "12:34", 0159 -> "01:59"
      formattedText = '${digits.substring(0, 2)}:${digits.substring(2)}';
    } else if (digits.length == 5) {
      // e.g. 10203 -> "1:02:03"
      formattedText = '${digits[0]}:${digits.substring(1, 3)}:${digits.substring(3)}';
    } else {
      // 6 digits: 010203 -> "01:02:03"
      formattedText = '${digits.substring(0, 2)}:${digits.substring(2, 4)}:${digits.substring(4)}';
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

/// Parses jump-to-time user input in both raw digit buffer formats (607, 0607, 1234)
/// and standard formatted/suffix formats (6:07, 06:07, 20m, etc.).
Duration? parseJumpTimeInput(
  String input, {
  Duration totalDuration = Duration.zero,
  void Function(String error)? onError,
}) {
  input = input.trim().toLowerCase();
  if (input.isEmpty) return null;

  // 1. Unit suffix format: e.g. "20m", "20min", "45s", "1h 30m"
  if (input.contains('m') || input.contains('s') || input.contains('h')) {
    int totalSec = 0;
    final hourMatch = RegExp(r'(\d+)\s*(?:h|hr|hrs)').firstMatch(input);
    final minMatch = RegExp(r'(\d+)\s*(?:m|min|mins)').firstMatch(input);
    final secMatch = RegExp(r'(\d+)\s*(?:s|sec|secs)').firstMatch(input);

    bool foundAny = false;
    if (hourMatch != null) {
      totalSec += int.parse(hourMatch.group(1)!) * 3600;
      foundAny = true;
    }
    if (minMatch != null) {
      totalSec += int.parse(minMatch.group(1)!) * 60;
      foundAny = true;
    }
    if (secMatch != null) {
      totalSec += int.parse(secMatch.group(1)!);
      foundAny = true;
    }

    if (foundAny) return Duration(seconds: totalSec);
  }

  // 2. Colon separated format: mm:ss or hh:mm:ss
  if (input.contains(':')) {
    final parts = input.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0].trim());
      final s = int.tryParse(parts[1].trim());
      if (m != null && s != null) {
        if (s < 0 || s > 59) {
          onError?.call('Seconds must be between 00 and 59');
          return null;
        }
        return Duration(minutes: m, seconds: s);
      }
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0].trim());
      final m = int.tryParse(parts[1].trim());
      final s = int.tryParse(parts[2].trim());
      if (h != null && m != null && s != null) {
        if (m < 0 || m > 59) {
          onError?.call('Minutes must be between 00 and 59');
          return null;
        }
        if (s < 0 || s > 59) {
          onError?.call('Seconds must be between 00 and 59');
          return null;
        }
        return Duration(hours: h, minutes: m, seconds: s);
      }
    }
    onError?.call('Invalid time format (e.g. 6:07, 12:34)');
    return null;
  }

  // 3. Raw digit buffer format (no colons entered by user or raw numeric input)
  final digits = input.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isNotEmpty) {
    if (digits.length == 3) {
      // e.g. 607 -> min 6, sec 07 (6 minutes, 7 seconds)
      final m = int.parse(digits[0]);
      final s = int.parse(digits.substring(1));
      if (s > 59) {
        onError?.call('Seconds must be between 00 and 59');
        return null;
      }
      return Duration(minutes: m, seconds: s);
    } else if (digits.length == 4) {
      // e.g. 0607 -> min 06, sec 07; 1234 -> min 12, sec 34; 0159 -> min 1, sec 59
      final m = int.parse(digits.substring(0, 2));
      final s = int.parse(digits.substring(2));
      if (s > 59) {
        onError?.call('Seconds must be between 00 and 59');
        return null;
      }
      return Duration(minutes: m, seconds: s);
    } else if (digits.length == 5) {
      final h = int.parse(digits[0]);
      final m = int.parse(digits.substring(1, 3));
      final s = int.parse(digits.substring(3));
      if (m > 59 || s > 59) {
        onError?.call('Minutes and seconds must be between 00 and 59');
        return null;
      }
      return Duration(hours: h, minutes: m, seconds: s);
    } else if (digits.length == 6) {
      final h = int.parse(digits.substring(0, 2));
      final m = int.parse(digits.substring(2, 4));
      final s = int.parse(digits.substring(4));
      if (m > 59 || s > 59) {
        onError?.call('Minutes and seconds must be between 00 and 59');
        return null;
      }
      return Duration(hours: h, minutes: m, seconds: s);
    } else {
      // 1 or 2 digits: treat as minutes
      final plainNumber = int.tryParse(digits);
      if (plainNumber != null) {
        if (totalDuration > Duration.zero) {
          final totalMinutes = totalDuration.inMinutes;
          if (plainNumber <= totalMinutes) {
            return Duration(minutes: plainNumber);
          }
          if (plainNumber <= totalDuration.inSeconds) {
            return Duration(seconds: plainNumber);
          }
        }
        return Duration(minutes: plainNumber);
      }
    }
  }

  onError?.call('Invalid format (e.g. 607, 06:07, 20 min)');
  return null;
}

/// A dialog allowing users to seek or jump directly to a specific timestamp.
/// Supports both in-player seeking and jumping into playback from Continue Watching.
class JumpToTimeDialog extends StatefulWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final String title;
  final String actionLabel;
  final ValueChanged<Duration> onJump;

  const JumpToTimeDialog({
    super.key,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.title = 'Jump to Time',
    this.actionLabel = 'Jump',
    required this.onJump,
  });

  @override
  State<JumpToTimeDialog> createState() => _JumpToTimeDialogState();
}

class _JumpToTimeDialogState extends State<JumpToTimeDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  Duration? _parsedDuration;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initialText = widget.currentPosition > Duration.zero
        ? _formatDuration(widget.currentPosition)
        : '';
    _controller = TextEditingController(text: initialText);
    _parsedDuration = widget.currentPosition > Duration.zero ? widget.currentPosition : null;

    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedDuration = null;
        _errorMessage = null;
      });
      return;
    }

    String? customError;
    final parsed = parseJumpTimeInput(
      text,
      totalDuration: widget.totalDuration,
      onError: (err) => customError = err,
    );

    setState(() {
      if (parsed == null) {
        _parsedDuration = null;
        _errorMessage = customError ?? 'Invalid format (e.g. 607, 06:07, 20 min)';
      } else {
        if (widget.totalDuration > Duration.zero &&
            parsed > widget.totalDuration) {
          _parsedDuration = widget.totalDuration;
          _errorMessage =
              'Exceeds duration (${_formatDuration(widget.totalDuration)})';
        } else {
          _parsedDuration = parsed;
          _errorMessage = null;
        }
      }
    });
  }

  Duration? _fallbackParseDuration(String input) {
    input = input.trim().toLowerCase();
    // Handle mm:ss carryover e.g. 1:60 -> 2m, 0:90 -> 90s
    if (input.contains(':')) {
      final parts = input.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0].trim());
        final s = int.tryParse(parts[1].trim());
        if (m != null && s != null) {
          return Duration(seconds: (m * 60) + s);
        }
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0].trim());
        final m = int.tryParse(parts[1].trim());
        final s = int.tryParse(parts[2].trim());
        if (h != null && m != null && s != null) {
          return Duration(seconds: (h * 3600) + (m * 60) + s);
        }
      }
    }
    // Handle decimals e.g. 15.5 -> 15m 30s
    final decimal = double.tryParse(input);
    if (decimal != null && decimal > 0) {
      final totalSec = (decimal * 60).round();
      return Duration(seconds: totalSec);
    }
    return null;
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final target = _parsedDuration ??
        parseJumpTimeInput(text, totalDuration: widget.totalDuration) ??
        _fallbackParseDuration(text);

    if (target != null) {
      final clamped = widget.totalDuration > Duration.zero
          ? (target > widget.totalDuration ? widget.totalDuration : target)
          : target;
      widget.onJump(clamped);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _errorMessage = 'Please enter a valid time (e.g. 15:00 or 15m)';
      });
    }
  }

  void _setPreset(Duration d) {
    final target = widget.totalDuration > Duration.zero && d > widget.totalDuration
        ? widget.totalDuration
        : (d < Duration.zero ? Duration.zero : d);
    _controller.text = _formatDuration(target);
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  void _adjustRelative(Duration delta) {
    final base = _parsedDuration ?? widget.currentPosition;
    final target = base + delta;
    _setPreset(target);
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    final totalMins = widget.totalDuration > Duration.zero
        ? widget.totalDuration.inMinutes
        : 30;
    final minutePresets = <int>[5, 10, 15, 20];
    if (totalMins > 25) minutePresets.add(25);
    if (totalMins > 45) minutePresets.add(45);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? mediaQuery.size.width * 0.2 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Iconsax.timer_1,
                      color: colorScheme.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.totalDuration > Duration.zero)
                          Text(
                            'Current: ${_formatDuration(widget.currentPosition)} / ${_formatDuration(widget.totalDuration)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Time Input Field
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                keyboardType: TextInputType.datetime,
                inputFormatters: [TimeDigitInputFormatter()],
                textInputAction: TextInputAction.done,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '20:00 or 20 min',
                  hintStyle: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.access_time_rounded),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () => _controller.clear(),
                        )
                      : null,
                ),
                onSubmitted: (_) => _submit(),
              ),

              // Live Parsed Timestamp Feedback / Error
              const SizedBox(height: 8),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (_parsedDuration != null)
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Target: ${_formatDuration(_parsedDuration!)}${widget.totalDuration > Duration.zero ? " / ${_formatDuration(widget.totalDuration)}" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Quick Presets Label
              Text(
                'Quick Time Options',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Preset Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.first_page_rounded, size: 16),
                    label: const Text('Start (0:00)'),
                    onPressed: () => _setPreset(Duration.zero),
                  ),
                  for (final min in minutePresets)
                    if (widget.totalDuration == Duration.zero ||
                        min < totalMins)
                      ActionChip(
                        label: Text('$min min'),
                        onPressed: () => _setPreset(Duration(minutes: min)),
                      ),
                  if (widget.totalDuration > Duration.zero && totalMins > 2)
                    ActionChip(
                      avatar: const Icon(Icons.last_page_rounded, size: 16),
                      label: const Text('End - 2m'),
                      onPressed: () => _setPreset(
                        widget.totalDuration - const Duration(minutes: 2),
                      ),
                    ),
                ],
              ),

              // Relative Adjustment Chips (if inside player with known position)
              if (widget.currentPosition > Duration.zero) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('-5 min'),
                      onPressed: () =>
                          _adjustRelative(const Duration(minutes: -5)),
                    ),
                    ActionChip(
                      label: const Text('-1 min'),
                      onPressed: () =>
                          _adjustRelative(const Duration(minutes: -1)),
                    ),
                    ActionChip(
                      label: const Text('+1 min'),
                      onPressed: () =>
                          _adjustRelative(const Duration(minutes: 1)),
                    ),
                    ActionChip(
                      label: const Text('+5 min'),
                      onPressed: () =>
                          _adjustRelative(const Duration(minutes: 5)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _controller.text.trim().isNotEmpty ? _submit : null,
                    icon: const Icon(Iconsax.play5, size: 18),
                    label: Text(widget.actionLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
