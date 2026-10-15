import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:ani_dash/main.dart';

const voiceInputLocaleKey = 'voice_input_locale';

class VoiceTextController {
  Future<void> Function()? _stop;

  Future<void> stop() async => _stop?.call();
}

class VoiceTextButton extends StatefulWidget {
  const VoiceTextButton({
    super.key,
    required this.controller,
    this.voiceController,
    this.onChanged,
    this.tooltip = 'Type with your voice',
  });
  final TextEditingController controller;
  final VoiceTextController? voiceController;
  final ValueChanged<String>? onChanged;
  final String tooltip;
  @override
  State<VoiceTextButton> createState() => _VoiceTextButtonState();
}

class _VoiceTextButtonState extends State<VoiceTextButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _prefix = '';
  int _speechGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.voiceController?._stop = _stopListening;
  }

  Future<void> _stopListening() async {
    _speechGeneration++;
    _listening = false;
    await _speech.stop();
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stopListening();
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
    final selectedLocale = sharedPrefs.getString(voiceInputLocaleKey);
    await _speech.listen(
      onResult: (result) {
        final spoken = _normalizeAnimeNames(result.recognizedWords.trim());
        if (!mounted ||
            !_listening ||
            generation != _speechGeneration ||
            spoken.isEmpty) {
          return;
        }
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
        localeId:
            selectedLocale == null || selectedLocale.isEmpty
                ? null
                : selectedLocale,
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

  Future<void> _chooseLanguage() async {
    final available = await _speech.initialize();
    if (!available || !mounted) return;
    final locales = await _speech.locales();
    locales.sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                children: [
                  const ListTile(
                    title: Text('Voice input language'),
                    subtitle: Text(
                      'Choose any language installed on this device.',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: const Text('Automatic (device language)'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: locales.length,
                      itemBuilder: (context, index) {
                        final locale = locales[index];
                        return ListTile(
                          title: Text(locale.name),
                          subtitle: Text(locale.localeId),
                          onTap: () => Navigator.pop(context, locale.localeId),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (selected == null) return;
    if (selected.isEmpty) {
      await sharedPrefs.remove(voiceInputLocaleKey);
    } else {
      await sharedPrefs.setString(voiceInputLocaleKey, selected);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected.isEmpty
                ? 'Voice input will use the device language.'
                : 'Voice input language updated.',
          ),
        ),
      );
    }
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
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'\b(tell me(?: the)?|exact)\s+watch\s+(?:of\s+)?(One Piece|Black Clover|Re:Zero|Mushoku Tensei|SPY x FAMILY)\b',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)} watch order of ${match.group(2)}',
    );
    return normalized;
  }

  @override
  void dispose() {
    _speechGeneration++;
    widget.voiceController?._stop = null;
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
