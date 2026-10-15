class CloudWatchProgressSync {
  static final RegExp _tagRegex = RegExp(
    r'shx:ep=(\d+)&sec=(\d+)(?:&dur=(\d+))?',
  );

  /// Parse episode progress and timestamp from tracker notes (AniList or MAL)
  static ({int episode, int seconds, int duration})? parseNotes(String? notes) {
    if (notes == null || notes.isEmpty) return null;
    final match = _tagRegex.firstMatch(notes);
    if (match == null) return null;
    final ep = int.tryParse(match.group(1) ?? '');
    final sec = int.tryParse(match.group(2) ?? '');
    final dur = match.group(3) != null ? int.tryParse(match.group(3)!) : null;
    if (ep != null && sec != null) {
      return (episode: ep, seconds: sec, duration: dur ?? 1440);
    }
    return null;
  }

  /// Format progress into notes tag, preserving any custom user notes
  static String formatNotes({
    String? existingNotes,
    required int episode,
    required int seconds,
    int? duration,
  }) {
    final durPart = (duration != null && duration > 0) ? '&dur=$duration' : '';
    final tag = 'shx:ep=$episode&sec=$seconds$durPart';
    if (existingNotes == null || existingNotes.trim().isEmpty) {
      return tag;
    }
    if (_tagRegex.hasMatch(existingNotes)) {
      return existingNotes.replaceFirst(_tagRegex, tag);
    }
    return '$tag\n$existingNotes';
  }

  /// Tracker progress is the number of fully watched episodes. A notes tag
  /// may point at a partially watched *next* episode, but an older tag must
  /// never pull Continue Watching backwards.
  static int resolveContinueEpisode({
    required int trackerProgress,
    int? notesEpisode,
    int notesSeconds = 0,
    int notesDuration = 0,
    int totalEpisodes = 0,
  }) {
    final next = trackerProgress > 0 ? trackerProgress + 1 : 1;
    final notesArePartial =
        notesEpisode != null &&
        notesEpisode >= next &&
        notesSeconds > 0 &&
        (notesDuration <= 0 || notesSeconds < notesDuration);
    final target = notesArePartial ? notesEpisode : next;
    if (totalEpisodes > 0 && target > totalEpisodes) return totalEpisodes;
    return target;
  }
}
