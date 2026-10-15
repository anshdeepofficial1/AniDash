import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceTextButton extends StatefulWidget {
  const VoiceTextButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.resetToken = 0,
    this.tooltip = 'Type with your voice',
  });
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int resetToken;
  final String tooltip;
  @override
  State<VoiceTextButton> createState() => _VoiceTextButtonState();
}

class _VoiceTextButtonState extends State<VoiceTextButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _prefix = '';
  String? _preferredLocaleId;
  int _speechGeneration = 0;

  @override
  void didUpdateWidget(covariant VoiceTextButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _speechGeneration++;
      _prefix = '';
      _speech.cancel();
      if (_listening) setState(() => _listening = false);
    }
  }

  Future<void> _chooseLanguage() async {
    final isAvailable = await _speech.initialize();
    if (!isAvailable || !mounted) return;
    final options = await _speech.locales();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * .58,
              child: ListView(
                children: [
                  const ListTile(title: Text('Voice input language')),
                  ListTile(
                    title: const Text('Phone default language'),
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  ...options.map(
                    (locale) => ListTile(
                      title: Text(locale.name),
                      subtitle: Text(locale.localeId),
                      onTap: () => Navigator.pop(ctx, locale.localeId),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (selected == null || !mounted) return;
    setState(() => _preferredLocaleId = selected.isEmpty ? null : selected);
  }

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
    final generation = ++_speechGeneration;
    _prefix = widget.controller.text.trimRight();
    setState(() => _listening = true);
    final locales = await _speech.locales();
    final systemLocale = await _speech.systemLocale();
    stt.LocaleName? preferredLocale;
    for (final locale in locales) {
      if (locale.localeId == (_preferredLocaleId ?? systemLocale?.localeId)) {
        preferredLocale = locale;
        break;
      }
    }
    await _speech.listen(
      onResult: (result) {
        final spoken = _normalizeAnimeNames(result.recognizedWords.trim());
        if (!mounted || generation != _speechGeneration || spoken.isEmpty)
          return;
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
    // Android dictation can omit small connective words in common anime
    // queries. Repair only narrow high-confidence phrases.
    normalized = normalized.replaceFirst(
      RegExp(r'\btell\s+me\s+watch\s+order\s+of\b', caseSensitive: false),
      'Tell me the watch order of',
    );
    return normalized;
  }

  @override
  void dispose() {
    _speechGeneration++;
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: _chooseLanguage,
      child: IconButton(
        tooltip:
            _listening
                ? 'Listening… tap to stop'
                : '${widget.tooltip} (hold to choose language)',
        onPressed: _toggle,
        style: IconButton.styleFrom(
          backgroundColor:
              _listening ? scheme.primaryContainer : Colors.transparent,
          foregroundColor:
              _listening ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
        icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_none_rounded),
      ),
    );
  }
}
