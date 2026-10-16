String normalizeVideoQualityLabel(Object? rawValue) {
  final raw = rawValue?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Auto';

  final lower = raw.toLowerCase();
  if (lower == 'auto' ||
      lower == 'default' ||
      lower == 'master' ||
      lower == 'best') {
    return 'Auto';
  }

  final resolution = RegExp(
    r'(?<!\d)(2160|1440|1080|720|480|360|240)\s*p?',
    caseSensitive: false,
  ).firstMatch(lower)?.group(1);
  if (resolution != null) return '${resolution}p';

  if (RegExp(r'\b(uhd|4k)\b').hasMatch(lower)) return '2160p';
  if (RegExp(r'\bfhd\b').hasMatch(lower)) return '1080p';
  if (RegExp(r'\bhd\b').hasMatch(lower)) return '720p';
  if (RegExp(r'\bsd\b').hasMatch(lower)) return '480p';

  // Provider/server names are not video qualities. Keep the quality control
  // predictable instead of exposing labels such as "Mega Play Dub".
  return 'Auto';
}
