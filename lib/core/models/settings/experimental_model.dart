import 'dart:convert';

class ExperimentalFeaturesModel {
  bool episodeTitleSync;
  bool useExtensions;
  bool useTestReleases;
  bool newUI;
  bool debugMode;
  bool useEpisodeBannerStyle;

  ExperimentalFeaturesModel({
    this.episodeTitleSync = true,
    this.useExtensions = false,
    this.useTestReleases = false,
    this.newUI = true,
    this.debugMode = false,
    this.useEpisodeBannerStyle = false,
  });

  ExperimentalFeaturesModel copyWith({
    bool? episodeTitleSync,
    bool? useExtensions,
    bool? useTestReleases,
    bool? newUI,
    bool? debugMode,
    bool? useEpisodeBannerStyle,
  }) {
    return ExperimentalFeaturesModel(
      episodeTitleSync: episodeTitleSync ?? this.episodeTitleSync,
      useExtensions: useExtensions ?? this.useExtensions,
      useTestReleases: useTestReleases ?? this.useTestReleases,
      newUI: newUI ?? this.newUI,
      debugMode: debugMode ?? this.debugMode,
      useEpisodeBannerStyle:
          useEpisodeBannerStyle ?? this.useEpisodeBannerStyle,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'episodeTitleSync': episodeTitleSync,
      'useMangayomiExtensions': useExtensions,
      'useTestReleases': useTestReleases,
      'newUI': newUI,
      'debugMode': debugMode,
      'useEpisodeBannerStyle': useEpisodeBannerStyle,
    };
  }

  factory ExperimentalFeaturesModel.fromMap(Map<String, dynamic> map) {
    return ExperimentalFeaturesModel(
      episodeTitleSync: map['episodeTitleSync'] ?? true,
      useExtensions: map['useMangayomiExtensions'] ?? false,
      useTestReleases: map['useTestReleases'] ?? false,
      newUI: map['newUI'] ?? true,
      debugMode: false,
      useEpisodeBannerStyle: map['useEpisodeBannerStyle'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory ExperimentalFeaturesModel.fromJson(String source) =>
      ExperimentalFeaturesModel.fromMap(json.decode(source));
}
