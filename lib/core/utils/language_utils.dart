class LanguageUtils {
  static const Map<String, String> _languageMap = {
    'en': 'English',
    'eng': 'English',
    'english': 'English',
    'de': 'German (Deutsch)',
    'ger': 'German (Deutsch)',
    'german': 'German (Deutsch)',
    'es': 'Spanish (Español)',
    'spa': 'Spanish (Español)',
    'spanish': 'Spanish (Español)',
    'fr': 'French (Français)',
    'fra': 'French (Français)',
    'french': 'French (Français)',
    'it': 'Italian (Italiano)',
    'ita': 'Italian (Italiano)',
    'italian': 'Italian (Italiano)',
    'pt': 'Portuguese (Português)',
    'por': 'Portuguese (Português)',
    'portuguese': 'Portuguese (Português)',
    'ru': 'Russian (Русский)',
    'rus': 'Russian (Русский)',
    'russian': 'Russian (Русский)',
    'ja': 'Japanese (日本語)',
    'jpn': 'Japanese (日本語)',
    'japanese': 'Japanese (日本語)',
    'ko': 'Korean (한국어)',
    'kor': 'Korean (한국어)',
    'korean': 'Korean (한국어)',
    'zh': 'Chinese (中文)',
    'chi': 'Chinese (中文)',
    'chinese': 'Chinese (中文)',
    'ar': 'Arabic (العربية)',
    'ara': 'Arabic (العربية)',
    'arabic': 'Arabic (العربية)',
    'hi': 'Hindi (हिन्दी)',
    'hin': 'Hindi (हिन्दी)',
    'hindi': 'Hindi (हिन्दी)',
    'ta': 'Tamil (தமிழ்)',
    'tam': 'Tamil (தமிழ்)',
    'tamil': 'Tamil (தமிழ்)',
    'te': 'Telugu (తెలుగు)',
    'tel': 'Telugu (తెలుగు)',
    'telugu': 'Telugu (తెలుగు)',
    'id': 'Indonesian (Bahasa Indonesia)',
    'ind': 'Indonesian (Bahasa Indonesia)',
    'indonesian': 'Indonesian (Bahasa Indonesia)',
    'tr': 'Turkish (Türkçe)',
    'tur': 'Turkish (Türkçe)',
    'turkish': 'Turkish (Türkçe)',
    'pl': 'Polish (Polski)',
    'pol': 'Polish (Polski)',
    'polish': 'Polish (Polski)',
    'nl': 'Dutch (Nederlands)',
    'dut': 'Dutch (Nederlands)',
    'dutch': 'Dutch (Nederlands)',
    'vi': 'Vietnamese (Tiếng Việt)',
    'vie': 'Vietnamese (Tiếng Việt)',
    'vietnamese': 'Vietnamese (Tiếng Việt)',
    'th': 'Thai (ไทย)',
    'tha': 'Thai (ไทย)',
    'thai': 'Thai (ไทย)',
    'all': 'All Languages',
  };

  static const Map<String, String> _shortNames = {
    'en': 'English',
    'eng': 'English',
    'english': 'English',
    'de': 'German',
    'ger': 'German',
    'german': 'German',
    'es': 'Spanish',
    'spa': 'Spanish',
    'spanish': 'Spanish',
    'fr': 'French',
    'fra': 'French',
    'french': 'French',
    'it': 'Italian',
    'ita': 'Italian',
    'italian': 'Italian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'portuguese': 'Portuguese',
    'ru': 'Russian',
    'rus': 'Russian',
    'russian': 'Russian',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'japanese': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'korean': 'Korean',
    'zh': 'Chinese',
    'chi': 'Chinese',
    'chinese': 'Chinese',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'arabic': 'Arabic',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'hindi': 'Hindi',
    'ta': 'Tamil',
    'tam': 'Tamil',
    'tamil': 'Tamil',
    'te': 'Telugu',
    'tel': 'Telugu',
    'telugu': 'Telugu',
    'id': 'Indonesian',
    'ind': 'Indonesian',
    'indonesian': 'Indonesian',
    'tr': 'Turkish',
    'tur': 'Turkish',
    'turkish': 'Turkish',
    'pl': 'Polish',
    'pol': 'Polish',
    'polish': 'Polish',
    'nl': 'Dutch',
    'dut': 'Dutch',
    'dutch': 'Dutch',
    'vi': 'Vietnamese',
    'vie': 'Vietnamese',
    'vietnamese': 'Vietnamese',
    'th': 'Thai',
    'tha': 'Thai',
    'thai': 'Thai',
  };

  /// Returns full localized display name (e.g. 'German (Deutsch)')
  static String getDisplayName(String? code, {String fallback = 'English'}) {
    if (code == null || code.trim().isEmpty) return fallback;
    final clean = code.trim().toLowerCase();
    return _languageMap[clean] ?? _shortNames[clean] ?? code.toUpperCase();
  }

  /// Returns short common English name (e.g. 'German')
  static String getShortName(String? code, {String fallback = 'English'}) {
    if (code == null || code.trim().isEmpty) return fallback;
    final clean = code.trim().toLowerCase();
    return _shortNames[clean] ?? _languageMap[clean]?.split(' ').first ?? code.toUpperCase();
  }

  /// Detects the target language from source configuration, anime genres, or anime title
  static String? detectLanguage({
    String? sourceLang,
    List<String>? genres,
    String? title,
  }) {
    if (sourceLang != null && sourceLang.trim().isNotEmpty && sourceLang.trim().toLowerCase() != 'all') {
      return getShortName(sourceLang);
    }

    if (genres != null && genres.isNotEmpty) {
      for (final g in genres) {
        final gl = g.trim().toLowerCase();
        for (final entry in _shortNames.entries) {
          if (entry.key.length >= 2 && (gl == entry.key || gl.contains(entry.key))) {
            return entry.value;
          }
        }
      }
    }

    if (title != null && title.trim().isNotEmpty) {
      final tl = title.toLowerCase();
      for (final entry in _shortNames.entries) {
        if (entry.key.length >= 3 && RegExp('\\b${entry.key}\\b', caseSensitive: false).hasMatch(tl)) {
          return entry.value;
        }
      }
    }

    return sourceLang;
  }

  /// Formats SUB audio/subtitle label given the active source's language code
  static String getSubLabel(String? sourceLang) {
    final lang = getShortName(sourceLang, fallback: 'Japanese');
    if (lang.toLowerCase() == 'japanese' || lang.toLowerCase() == 'ja') {
      return 'Japanese (SUB)';
    }
    return '$lang (SUB)';
  }

  /// Formats DUB audio label given the active source's language code
  static String getDubLabel(String? sourceLang) {
    final lang = getShortName(sourceLang, fallback: 'English');
    if (lang.toLowerCase() == 'japanese' || lang.toLowerCase() == 'ja') {
      return 'English (DUB)';
    }
    return '$lang (DUB)';
  }

  /// Normalized audio language description (e.g. 'German DUB' or 'English DUB')
  static String formatAudioLanguage(String? langOption, String? sourceLang) {
    final isDub = langOption == 'dub';
    if (isDub) {
      final lang = getShortName(sourceLang, fallback: 'English');
      final dubName = (lang.toLowerCase() == 'japanese' || lang.toLowerCase() == 'ja') ? 'English' : lang;
      return '$dubName DUB';
    } else {
      final lang = getShortName(sourceLang, fallback: 'Japanese');
      return '$lang SUB';
    }
  }
}
