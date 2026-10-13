import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/shared/providers/settings/theme_notifier.dart';
import 'package:ani_dash/core/models/settings/theme_model.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/ui/brand_logo.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Theme Settings'),
        forceMaterialTransparency: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSection(
                title: 'Appearance',
                titleColor: colorScheme.primary,
                children: [
                  SegmentedToggleSettingsItem<dynamic>(
                    accent: colorScheme.primary,
                    iconColor: colorScheme.primary,
                    title: 'Adaptive App Logo',
                    description: 'Choose automatic, white, or black logo',
                    selectedValue:
                        theme.logoMode == 'light' || theme.logoMode == 'black'
                            ? 1
                            : theme.logoMode == 'dark' ||
                                theme.logoMode == 'white'
                            ? 2
                            : 0,
                    onValueChanged: (value) {
                      final index = value as int;
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(
                          logoMode:
                              index == 1
                                  ? 'light'
                                  : index == 2
                                  ? 'dark'
                                  : 'dynamic',
                        ),
                      );
                    },
                    children: const {
                      0: Icon(Icons.brightness_auto_rounded),
                      1: Icon(Icons.light_mode_rounded),
                      2: Icon(Icons.dark_mode_rounded),
                    },
                    labels: const {0: 'Dynamic', 1: 'Light', 2: 'Dark'},
                    icon: const Icon(Icons.apps_rounded),
                  ),
                  NormalSettingsItem(
                    leading: BrandLogo(
                      size: 36,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    title: 'Logo Preview',
                    description: 'Current logo selection',
                    trailingWidgets: const [Icon(Icons.check_circle_rounded)],
                  ),
                  SegmentedToggleSettingsItem<dynamic>(
                    accent: colorScheme.primary,
                    iconColor: colorScheme.primary,
                    title: 'Theme Mode',
                    description: 'Choose your preferred theme',
                    selectedValue:
                        theme.themeMode == 'light'
                            ? 1
                            : theme.themeMode == 'dark'
                            ? 2
                            : 0,
                    onValueChanged: (value) {
                      final index = value as int;
                      final newMode =
                          index == 0
                              ? 'system'
                              : index == 1
                              ? 'light'
                              : 'dark';
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(themeMode: newMode),
                      );
                    },
                    children: const {
                      0: Icon(Iconsax.monitor),
                      1: Icon(Iconsax.sun_1),
                      2: Icon(Iconsax.moon),
                    },
                    labels: const {0: 'System', 1: 'Light', 2: 'Dark'},
                    icon: const Icon(Iconsax.color_swatch),
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(
                      Icons.blur_on_rounded,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Navigation blur',
                    description: 'Turn off for a solid toolbar color',
                    value: theme.navigationBlur,
                    onChanged:
                        (value) => themeNotifier.updateSettings(
                          (prev) => prev.copyWith(navigationBlur: value),
                        ),
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(
                      Icons.compress_rounded,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Compact toolbar on scroll',
                    description:
                        'Shrink while scrolling down and expand upward',
                    value: theme.compactNavigationOnScroll,
                    onChanged:
                        (value) => themeNotifier.updateSettings(
                          (prev) =>
                              prev.copyWith(compactNavigationOnScroll: value),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: 'Colors',
                titleColor: colorScheme.primary,
                children: [
                  NormalSettingsItem(
                    icon: Icon(
                      Iconsax.colors_square,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Color Scheme',
                    description: _formatSchemeName(theme.flexScheme ?? ''),
                    onTap:
                        () =>
                            _showColorSchemeSheet(context, ref, themeNotifier),
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(Iconsax.colorfilter, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'AMOLED Pure Black',
                    description:
                        'Use pure pitch-black (#000000) in dark mode for OLED displays',
                    value: theme.amoled,
                    onChanged: (value) {
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(amoled: value),
                      );
                    },
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(Iconsax.arrow_swap, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Swap Colors',
                    description: 'Swap primary and secondary colors',
                    value: theme.swapColors,
                    onChanged: (value) {
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(swapColors: value),
                      );
                    },
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(
                      Iconsax.color_swatch,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title:
                        'System Colors ${Platform.isAndroid ? '(A12+)' : ''}',
                    description: 'Use colors from your wallpaper',
                    value: theme.useDynamicColors,
                    onChanged: (value) async {
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(useDynamicColors: value),
                      );
                    },
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(Iconsax.magicpen, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Material 3',
                    description: 'Use the latest Material 3 design system',
                    value: theme.useMaterial3,
                    onChanged: (value) {
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(useMaterial3: value),
                      );
                    },
                  ),
                  SliderSettingsItem(
                    icon: Icon(
                      Icons.blender_outlined,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    value: theme.blendLevel.toDouble(),
                    min: 0,
                    max: 40,
                    divisions: 40,
                    title: 'Blend Level',
                    description: 'Adjust the color blend intensity',
                    onChanged: (value) {
                      themeNotifier.updateSettings(
                        (prev) => prev.copyWith(blendLevel: value.toInt()),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorSchemeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeSettingsNotifier themeNotifier,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final theme = ref.watch(themeSettingsProvider);
            final currentScheme = FlexScheme.values.firstWhere(
              (s) => s.name == theme.flexScheme,
              orElse: () => FlexScheme.material,
            );

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final previewScheme =
                isDark
                    ? FlexThemeData.dark(scheme: currentScheme).colorScheme
                    : FlexThemeData.light(scheme: currentScheme).colorScheme;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients && scrollController.offset == 0) {
                final index = FlexScheme.values.indexWhere(
                  (s) => s.name == theme.flexScheme,
                );
                if (index > 0) {
                  scrollController.animateTo(
                    index * 56.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                }
              }
            });

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: _buildSimpleSkeleton(previewScheme),
                  ),

                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),

                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: FlexScheme.values.length,
                      itemBuilder: (context, index) {
                        final scheme = FlexScheme.values[index];
                        final isSelected = theme.flexScheme == scheme.name;

                        return ListTile(
                          onTap: () {
                            if (scheme == FlexScheme.custom) {
                              _showCustomColorEditor(
                                context,
                                themeNotifier,
                                theme,
                              );
                              return;
                            }
                            themeNotifier.updateSettings(
                              (prev) => prev.copyWith(flexScheme: scheme.name),
                            );
                          },
                          leading: _buildListIcon(scheme),
                          title: Text(_formatSchemeName(scheme.name)),
                          trailing:
                              isSelected
                                  ? Icon(
                                    Iconsax.tick_circle,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                  : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomColorEditor(
    BuildContext context,
    ThemeSettingsNotifier themeNotifier,
    ThemeModel current,
  ) async {
    var primary = Color(current.customPrimaryColor);
    var secondary = Color(current.customSecondaryColor);
    var tertiary = Color(current.customTertiaryColor);
    var surface = Color(current.customSurfaceColor);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              final preview = ColorScheme.fromSeed(
                seedColor: primary,
                brightness: Theme.of(context).brightness,
              ).copyWith(
                primary: primary,
                secondary: secondary,
                tertiary: tertiary,
                surface: surface,
              );

              Future<void> editColor(
                Color initial,
                ValueChanged<Color> update,
              ) async {
                final selected = await _pickCustomColor(context, initial);
                if (selected != null) setSheetState(() => update(selected));
              }

              return SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Custom Color Scheme',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildSimpleSkeleton(preview),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _customColorTile(
                              context,
                              'Primary',
                              'Buttons, active controls and highlights',
                              primary,
                              () => editColor(
                                primary,
                                (value) => primary = value,
                              ),
                            ),
                            _customColorTile(
                              context,
                              'Secondary',
                              'Supporting controls and containers',
                              secondary,
                              () => editColor(
                                secondary,
                                (value) => secondary = value,
                              ),
                            ),
                            _customColorTile(
                              context,
                              'Tertiary',
                              'Accents, badges and complementary elements',
                              tertiary,
                              () => editColor(
                                tertiary,
                                (value) => tertiary = value,
                              ),
                            ),
                            _customColorTile(
                              context,
                              'Surface',
                              'Pages, cards and background surfaces',
                              surface,
                              () => editColor(
                                surface,
                                (value) => surface = value,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  themeNotifier.updateSettings(
                                    (previous) => previous.copyWith(
                                      flexScheme: FlexScheme.custom.name,
                                      customPrimaryColor: primary.toARGB32(),
                                      customSecondaryColor:
                                          secondary.toARGB32(),
                                      customTertiaryColor: tertiary.toARGB32(),
                                      customSurfaceColor: surface.toARGB32(),
                                    ),
                                  );
                                  Navigator.pop(sheetContext);
                                },
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _customColorTile(
    BuildContext context,
    String title,
    String description,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      title: Text(title),
      subtitle: Text(description),
      trailing: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }

  Future<Color?> _pickCustomColor(BuildContext context, Color initial) async {
    var draft = initial;
    return showDialog<Color>(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            title: const Text('Choose Color'),
            content: ColorPicker(
              color: initial,
              onColorChanged: (value) => draft = value,
              showColorCode: true,
              showColorName: true,
              showMaterialName: true,
              pickersEnabled: const {
                ColorPickerType.both: true,
                ColorPickerType.primary: true,
                ColorPickerType.accent: true,
                ColorPickerType.bw: true,
                ColorPickerType.custom: false,
                ColorPickerType.wheel: true,
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, draft),
                child: const Text('Select'),
              ),
            ],
          ),
    );
  }

  Widget _buildSimpleSkeleton(ColorScheme colors) {
    const duration = Duration(milliseconds: 300);

    return AnimatedContainer(
      duration: duration,
      height: 80,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: AnimatedContainer(
              duration: duration,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: duration,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: duration,
                          decoration: BoxDecoration(
                            color: colors.tertiary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedContainer(
                          duration: duration,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListIcon(FlexScheme scheme) {
    final colors = FlexThemeData.light(scheme: scheme).colorScheme;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Row(
          children: [
            Expanded(flex: 2, child: Container(color: colors.primary)),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(child: Container(color: colors.secondary)),
                  Expanded(child: Container(color: colors.tertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSchemeName(String name) {
    return name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .split(' ')
        .map(
          (word) =>
              word.isNotEmpty
                  ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
                  : word,
        )
        .join(' ');
  }
}
