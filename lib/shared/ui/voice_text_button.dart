import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceTextButton extends StatefulWidget {
  const VoiceTextButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.tooltip = 'Type with your voice',
  });
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String tooltip;
  @override
  State<VoiceTextButton> createState() => _VoiceTextButtonState();
}

class _VoiceTextButtonState extends State<VoiceTextButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _prefix = '';

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _listening = false);
        }
      },
    );
    if (!available || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voice typing is unavailable. Check microphone access.',
            ),
          ),
        );
      }
      return;
    }
    _prefix = widget.controller.text.trimRight();
    setState(() => _listening = true);
    final locales = await _speech.locales();
    stt.LocaleName? preferredLocale;
    for (final locale in locales) {
      final id = locale.localeId.toLowerCase();
      if (id.startsWith('en_in') || id.startsWith('en_us')) {
        preferredLocale = locale;
        if (id.startsWith('en_in')) break;
      }
    }
    await _speech.listen(
      onResult: (result) {
        final spoken = _normalizeAnimeNames(result.recognizedWords.trim());
        if (!mounted || spoken.isEmpty) return;
        final value = _prefix.isEmpty ? spoken : '$_prefix $spoken';
        widget.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        widget.onChanged?.call(value);
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        localeId: preferredLocale?.localeId,
        contextualPhrases: const [
          'One Piece',
          'AniList',
          'MyAnimeList',
          'Re:Zero',
          'SPY x FAMILY',
          'Mushoku Tensei',
          'Black Clover',
          'AniDash',
        ],
      ),
    );
  }

  String _normalizeAnimeNames(String value) {
    var normalized = value;
    final replacements = <RegExp, String>{
      RegExp(r'\b(?:won|one)\s+peace\b', caseSensitive: false): 'One Piece',
      RegExp(r'\bmy\s+anime\s+list\b', caseSensitive: false): 'MyAnimeList',
      RegExp(r'\banne?\s*list\b', caseSensitive: false): 'AniList',
      RegExp(r'\bre\s*zero\b', caseSensitive: false): 'Re:Zero',
      RegExp(r'\bspy\s*(?:x|cross)\s*family\b', caseSensitive: false):
          'SPY x FAMILY',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: _listening ? 'Listening… tap to stop' : widget.tooltip,
      onPressed: _toggle,
      style: IconButton.styleFrom(
        backgroundColor:
            _listening ? scheme.primaryContainer : Colors.transparent,
        foregroundColor:
            _listening ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_none_rounded),
    );
  }
}
