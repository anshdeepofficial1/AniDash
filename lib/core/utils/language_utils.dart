class LanguageUtils {
  static const Map<String, String> _languageMap = {
    'en': 'English',
    'de': 'German (Deutsch)',
    'es': 'Spanish (Español)',
    'fr': 'French (Français)',
    'it': 'Italian (Italiano)',
    'pt': 'Portuguese (Português)',
    'ru': 'Russian (Русский)',
    'ja': 'Japanese (日本語)',
    'ko': 'Korean (한국어)',
    'zh': 'Chinese (中文)',
    'ar': 'Arabic (العربية)',
    'hi': 'Hindi (हिन्दी)',
    'id': 'Indonesian (Bahasa Indonesia)',
    'tr': 'Turkish (Türkçe)',
    'pl': 'Polish (Polski)',
    'nl': 'Dutch (Nederlands)',
    'vi': 'Vietnamese (Tiếng Việt)',
    'th': 'Thai (ไทย)',
    'all': 'All Languages',
  };

  static const Map<String, String> _shortNames = {
    'en': 'English',
    'de': 'German',
    'es': 'Spanish',
    'fr': 'French',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'id': 'Indonesian',
    'tr': 'Turkish',
    'pl': 'Polish',
    'nl': 'Dutch',
    'vi': 'Vietnamese',
    'th': 'Thai',
  };

  /// Returns full localized display name (e.g. 'German (Deutsch)')
  static String getDisplayName(String? code, {String fallback = 'English'}) {
    if (code == null || code.trim().isEmpty) return fallback;
    final clean = code.trim().toLowerCase();
    return _languageMap[clean] ?? code.toUpperCase();
  }

  /// Returns short common English name (e.g. 'German')
  static String getShortName(String? code, {String fallback = 'English'}) {
    if (code == null || code.trim().isEmpty) return fallback;
    final clean = code.trim().toLowerCase();
    return _shortNames[clean] ?? _languageMap[clean]?.split(' ').first ?? code.toUpperCase();
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
