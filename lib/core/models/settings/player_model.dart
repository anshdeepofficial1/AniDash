import 'dart:convert';

class PlayerModel {
  final String defaultQuality;
  final bool enableAniSkip;
  final bool enableAutoSkip;
  final bool skipFillerEpisodes;
  final String preferredAudioLanguage; // 'sub', 'dub'
  final int seekDuration;
  final int autoHideDuration;
  final int lockAutoHideDuration;
  final bool showNextPrevButtons;
  final bool prefetchNextEpisode;
  final bool showNextEpisodePrompt;
  final double bufferSize;
  final bool stopAfterCurrentEpisode;
  final double defaultPlaybackSpeed;
  final Map<String, String> mpvSettings;
  final bool showManualSkip;
  final int manualSkipDuration;
  final bool autoEnableSubtitles;

  PlayerModel({
    this.defaultQuality = 'Auto',
    this.enableAniSkip = true,
    this.enableAutoSkip = true,
    this.skipFillerEpisodes = false,
    bool? preferDub,
    String? preferredAudioLanguage,
    double bufferSize = 100,
    this.seekDuration = 10,
    this.autoHideDuration = 5,
    this.lockAutoHideDuration = 3,
    this.showNextPrevButtons = true,
    this.prefetchNextEpisode = true,
    this.showNextEpisodePrompt = true,
    this.stopAfterCurrentEpisode = false,
    this.defaultPlaybackSpeed = 1.0,
    this.mpvSettings = const {},
    this.showManualSkip = true,
    this.manualSkipDuration = 85,
    this.autoEnableSubtitles = false,
  }) : bufferSize = bufferSize.clamp(100.0, 256.0).toDouble(),
       preferredAudioLanguage =
           preferredAudioLanguage == 'dub'
               ? 'dub'
               : (preferredAudioLanguage == 'sub' || preferDub == false
                   ? 'sub'
                   : 'dub');

  /// 100% backward-compatible getter for existing code paths
  bool get preferDub => preferredAudioLanguage == 'dub';

  PlayerModel copyWith({
    String? defaultQuality,
    bool? enableAniSkip,
    bool? enableAutoSkip,
    bool? skipFillerEpisodes,
    bool? preferDub,
    String? preferredAudioLanguage,
    int? seekDuration,
    int? autoHideDuration,
    int? lockAutoHideDuration,
    double? bufferSize,
    bool? showNextPrevButtons,
    bool? prefetchNextEpisode,
    bool? showNextEpisodePrompt,
    bool? stopAfterCurrentEpisode,
    double? defaultPlaybackSpeed,
    Map<String, String>? mpvSettings,
    bool? showManualSkip,
    int? manualSkipDuration,
    bool? autoEnableSubtitles,
  }) {
    final newAudioLang =
        preferredAudioLanguage ??
        (preferDub != null
            ? (preferDub ? 'dub' : 'sub')
            : this.preferredAudioLanguage);

    return PlayerModel(
      defaultQuality: defaultQuality ?? this.defaultQuality,
      enableAniSkip: enableAniSkip ?? this.enableAniSkip,
      enableAutoSkip: enableAutoSkip ?? this.enableAutoSkip,
      skipFillerEpisodes: skipFillerEpisodes ?? this.skipFillerEpisodes,
      preferredAudioLanguage: newAudioLang == 'dub' ? 'dub' : 'sub',
      seekDuration: seekDuration ?? this.seekDuration,
      autoHideDuration: autoHideDuration ?? this.autoHideDuration,
      lockAutoHideDuration: lockAutoHideDuration ?? this.lockAutoHideDuration,
      bufferSize: bufferSize ?? this.bufferSize,
      showNextPrevButtons: showNextPrevButtons ?? this.showNextPrevButtons,
      prefetchNextEpisode: prefetchNextEpisode ?? this.prefetchNextEpisode,
      showNextEpisodePrompt:
          showNextEpisodePrompt ?? this.showNextEpisodePrompt,
      stopAfterCurrentEpisode:
          stopAfterCurrentEpisode ?? this.stopAfterCurrentEpisode,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      mpvSettings: mpvSettings ?? this.mpvSettings,
      showManualSkip: showManualSkip ?? this.showManualSkip,
      manualSkipDuration: manualSkipDuration ?? this.manualSkipDuration,
      autoEnableSubtitles: autoEnableSubtitles ?? this.autoEnableSubtitles,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultQuality': defaultQuality,
      'enableAniSkip': enableAniSkip,
      'enableAutoSkip': enableAutoSkip,
      'skipFillerEpisodes': skipFillerEpisodes,
      'preferDub': preferDub,
      'preferredAudioLanguage': preferredAudioLanguage,
      'seekDuration': seekDuration,
      'bufferSize': bufferSize,
      'autoHideDuration': autoHideDuration,
      'lockAutoHideDuration': lockAutoHideDuration,
      'showNextPrevButtons': showNextPrevButtons,
      'prefetchNextEpisode': prefetchNextEpisode,
      'showNextEpisodePrompt': showNextEpisodePrompt,
      'stopAfterCurrentEpisode': stopAfterCurrentEpisode,
      'defaultPlaybackSpeed': defaultPlaybackSpeed,
      'mpvSettings': mpvSettings,
      'showManualSkip': showManualSkip,
      'manualSkipDuration': manualSkipDuration,
      'autoEnableSubtitles': autoEnableSubtitles,
    };
  }

  factory PlayerModel.fromMap(Map<String, dynamic> map) {
    final rawPrefLang = map['preferredAudioLanguage'] as String?;
    final rawPreferDub = map['preferDub'] as bool?;
    var audioLang =
        rawPrefLang ??
        (rawPreferDub != null ? (rawPreferDub ? 'dub' : 'sub') : 'dub');
    audioLang = audioLang == 'dub' ? 'dub' : 'sub';

    return PlayerModel(
      defaultQuality: map['defaultQuality'] ?? 'Auto',
      enableAniSkip: map['enableAniSkip'] ?? true,
      enableAutoSkip: map['enableAutoSkip'] ?? true,
      skipFillerEpisodes: map['skipFillerEpisodes'] ?? false,
      preferredAudioLanguage: audioLang,
      seekDuration: map['seekDuration'] ?? 10,
      autoHideDuration: map['autoHideDuration'] ?? 5,
      lockAutoHideDuration: map['lockAutoHideDuration'] ?? 3,
      // Older installations stored a 32 MB cache. Migrate those values to a
      // 100 MiB forward-cache capacity so online HLS playback does not drain
      // its buffer after only a few seconds.
      bufferSize:
          ((map['bufferSize'] as num?)?.toDouble() ?? 100.0)
              .clamp(100.0, 256.0)
              .toDouble(),
      showNextPrevButtons: map['showNextPrevButtons'] ?? true,
      prefetchNextEpisode: map['prefetchNextEpisode'] ?? true,
      showNextEpisodePrompt: map['showNextEpisodePrompt'] ?? true,
      stopAfterCurrentEpisode: map['stopAfterCurrentEpisode'] ?? false,
      defaultPlaybackSpeed:
          (map['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0,
      mpvSettings: Map<String, String>.from(map['mpvSettings'] ?? {}),
      showManualSkip: map['showManualSkip'] ?? true,
      manualSkipDuration: map['manualSkipDuration'] ?? 85,
      autoEnableSubtitles: map['autoEnableSubtitles'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory PlayerModel.fromJson(String source) =>
      PlayerModel.fromMap(json.decode(source));
}
