import 'dart:convert';
import 'package:flex_color_scheme/flex_color_scheme.dart';

class ThemeModel {
  final String themeMode;
  final bool amoled;
  final String? flexScheme;
  final int blendLevel;
  final bool swapColors;
  final bool useMaterial3;
  final bool useDynamicColors;
  final String logoMode;
  final int customPrimaryColor;
  final int customSecondaryColor;
  final int customTertiaryColor;
  final int customSurfaceColor;
  final bool navigationBlur;
  final bool compactNavigationOnScroll;

  ThemeModel({
    this.themeMode = 'system',
    this.amoled = false,
    this.flexScheme,
    this.blendLevel = 11,
    this.swapColors = false,
    this.useMaterial3 = true,
    this.useDynamicColors = false,
    this.logoMode = 'dynamic',
    this.customPrimaryColor = 0xFF6750A4,
    this.customSecondaryColor = 0xFF625B71,
    this.customTertiaryColor = 0xFF7D5260,
    this.customSurfaceColor = 0xFFFFF7FF,
    this.navigationBlur = true,
    this.compactNavigationOnScroll = true,
  });

  ThemeModel copyWith({
    String? themeMode,
    bool? amoled,
    String? flexScheme,
    int? blendLevel,
    bool? swapColors,
    bool? useMaterial3,
    bool? useDynamicColors,
    String? logoMode,
    int? customPrimaryColor,
    int? customSecondaryColor,
    int? customTertiaryColor,
    int? customSurfaceColor,
    bool? navigationBlur,
    bool? compactNavigationOnScroll,
  }) {
    return ThemeModel(
      themeMode: themeMode ?? this.themeMode,
      amoled: amoled ?? this.amoled,
      flexScheme: flexScheme ?? this.flexScheme,
      blendLevel: blendLevel ?? this.blendLevel,
      swapColors: swapColors ?? this.swapColors,
      useMaterial3: useMaterial3 ?? this.useMaterial3,
      useDynamicColors: useDynamicColors ?? this.useDynamicColors,
      logoMode: logoMode ?? this.logoMode,
      customPrimaryColor: customPrimaryColor ?? this.customPrimaryColor,
      customSecondaryColor: customSecondaryColor ?? this.customSecondaryColor,
      customTertiaryColor: customTertiaryColor ?? this.customTertiaryColor,
      customSurfaceColor: customSurfaceColor ?? this.customSurfaceColor,
      navigationBlur: navigationBlur ?? this.navigationBlur,
      compactNavigationOnScroll:
          compactNavigationOnScroll ?? this.compactNavigationOnScroll,
    );
  }

  FlexScheme get flexSchemeEnum => FlexScheme.values.firstWhere(
    (e) => e.name == flexScheme,
    orElse: () => FlexScheme.red,
  );
  Map<String, dynamic> toMap() {
    return {
      'themeMode': themeMode,
      'amoled': amoled,
      'flexScheme': flexScheme,
      'blendLevel': blendLevel,
      'swapColors': swapColors,
      'useMaterial3': useMaterial3,
      'useDynamicColors': useDynamicColors,
      'logoMode': logoMode,
      'customPrimaryColor': customPrimaryColor,
      'customSecondaryColor': customSecondaryColor,
      'customTertiaryColor': customTertiaryColor,
      'customSurfaceColor': customSurfaceColor,
      'navigationBlur': navigationBlur,
      'compactNavigationOnScroll': compactNavigationOnScroll,
    };
  }

  factory ThemeModel.fromMap(Map<String, dynamic> map) {
    return ThemeModel(
      themeMode: map['themeMode'] ?? 'system',
      amoled: map['amoled'] ?? false,
      flexScheme: map['flexScheme'],
      blendLevel: map['blendLevel']?.toInt() ?? 11,
      swapColors: map['swapColors'] ?? false,
      useMaterial3: map['useMaterial3'] ?? true,
      useDynamicColors: map['useDynamicColors'] ?? false,
      logoMode: map['logoMode'] ?? 'dynamic',
      customPrimaryColor: map['customPrimaryColor'] ?? 0xFF6750A4,
      customSecondaryColor: map['customSecondaryColor'] ?? 0xFF625B71,
      customTertiaryColor: map['customTertiaryColor'] ?? 0xFF7D5260,
      customSurfaceColor: map['customSurfaceColor'] ?? 0xFFFFF7FF,
      navigationBlur: map['navigationBlur'] ?? true,
      compactNavigationOnScroll: map['compactNavigationOnScroll'] ?? true,
    );
  }

  String toJson() => json.encode(toMap());

  factory ThemeModel.fromJson(String source) =>
      ThemeModel.fromMap(json.decode(source));
}
