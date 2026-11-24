/// Source-routing decisions shared by episode metadata and playback flows.
abstract final class EpisodeSourceRouting {
  /// An explicitly selected installed extension is authoritative regardless
  /// of the shape of its anime identifier. Some extensions (including
  /// Miruro) use a numeric AniList id as their own details id, so treating
  /// every numeric id as a native-provider id routes the request back to the
  /// built-in provider by mistake.
  static bool shouldUseSelectedExtension({
    required bool extensionsEnabled,
    required bool hasActiveExtension,
  }) {
    return extensionsEnabled && hasActiveExtension;
  }
}
