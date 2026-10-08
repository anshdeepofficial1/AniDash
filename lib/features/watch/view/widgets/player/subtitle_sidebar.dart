import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/settings/subtitle_appearance_model.dart';
import 'package:ani_dash/features/settings/utils/subtitle_utils.dart';
import 'package:ani_dash/shared/providers/settings/subtitle_notifier.dart';

class SubtitleSettingsSidebar extends ConsumerWidget {
  final VoidCallback onClose;

  const SubtitleSettingsSidebar({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleStyle = ref.watch(subtitleAppearanceProvider);
    final notifier = ref.read(subtitleAppearanceProvider.notifier);

    final isWide = MediaQuery.of(context).size.width > 600;

    return Container(
      width: isWide ? 400 : double.infinity,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              title: const Text('Subtitle Settings'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              color: Colors.black87,
              child: _buildSubtitlePreview(subtitleStyle),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildSectionHeader(context, 'Text Appearance'),

                  ListTile(
                    title: const Text('Font Family'),
                    subtitle: Text(subtitleStyle.fontFamily ?? 'Default'),
                    trailing: DropdownButton<String>(
                      value:
                          SubtitleUtils.availableFonts.contains(
                            subtitleStyle.fontFamily,
                          )
                          ? subtitleStyle.fontFamily
                          : 'Default',
                      underline: const SizedBox(),
                      items: SubtitleUtils.availableFonts.map((String font) {
                        return DropdownMenuItem<String>(
                          value: font,
                          child: Text(font),
                        );
                      }).toList(),
                      onChanged: (val) => notifier.updateSettings(
                        (p) => p.copyWith(fontFamily: val),
                      ),
                    ),
                  ),

                  _buildSliderTile(
                    title: 'Text Size',
                    value: (subtitleStyle.fontSize / 20.0).clamp(0.5, 3.0),
                    min: 0.5,
                    max: 3.0,
                    divisions: 25,
                    label:
                        '${(subtitleStyle.fontSize / 20.0).toStringAsFixed(1)}x',
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(fontSize: val * 20.0),
                    ),
                  ),

                  _buildColorPickerRow(
                    title: 'Text Color',
                    selectedColor: subtitleStyle.textColor,
                    colors: const [
                      0xFFFFFFFF, // White
                      0xFFFFEB3B, // Yellow
                      0xFF00E5FF, // Cyan
                      0xFF76FF03, // Green
                      0xFFFF80AB, // Pink
                      0xFFFF9100, // Orange
                    ],
                    onSelected: (col) => notifier.updateSettings(
                      (p) => p.copyWith(textColor: col),
                    ),
                  ),

                  SwitchListTile(
                    title: const Text('Bold Text'),
                    value: subtitleStyle.boldText,
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(boldText: val),
                    ),
                  ),

                  const Divider(),
                  _buildSectionHeader(context, 'Background & Border'),

                  _buildColorPickerRow(
                    title: 'Background Color',
                    selectedColor: subtitleStyle.backgroundColor,
                    colors: const [
                      0xFF000000, // Black
                      0xFF212121, // Charcoal
                      0xFF0D1B2A, // Navy
                      0xFF2B0000, // Crimson
                    ],
                    onSelected: (col) => notifier.updateSettings(
                      (p) => p.copyWith(backgroundColor: col),
                    ),
                  ),

                  _buildSliderTile(
                    title: 'Background Opacity',
                    value: subtitleStyle.backgroundOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label:
                        '${(subtitleStyle.backgroundOpacity * 100).round()}%',
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(backgroundOpacity: val),
                    ),
                  ),

                  _buildSliderTile(
                    title: 'Border Width',
                    value: subtitleStyle.outlineWidth,
                    min: 0.0,
                    max: 5.0,
                    divisions: 10,
                    label: '${subtitleStyle.outlineWidth.toStringAsFixed(1)}px',
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(outlineWidth: val),
                    ),
                  ),

                  const Divider(),
                  _buildSectionHeader(context, 'Advanced'),

                  SwitchListTile(
                    title: const Text('Drop Shadow'),
                    value: subtitleStyle.hasShadow,
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(hasShadow: val),
                    ),
                  ),

                  if (subtitleStyle.hasShadow)
                    _buildSliderTile(
                      title: 'Shadow Blur',
                      value: subtitleStyle.shadowBlur,
                      min: 1.0,
                      max: 10.0,
                      divisions: 9,
                      label: '${subtitleStyle.shadowBlur.toStringAsFixed(1)}px',
                      onChanged: (val) => notifier.updateSettings(
                        (p) => p.copyWith(shadowBlur: val),
                      ),
                    ),

                  _buildSliderTile(
                    title: 'Bottom Margin',
                    value: subtitleStyle.bottomMargin,
                    min: 0.0,
                    max: 100.0,
                    divisions: 20,
                    label: '${subtitleStyle.bottomMargin.round()}px',
                    onChanged: (val) => notifier.updateSettings(
                      (p) => p.copyWith(bottomMargin: val),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow({
    required String title,
    required int selectedColor,
    required List<int> colors,
    required ValueChanged<int> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(
            children: colors.map((c) {
              final isSelected = c == selectedColor;
              return GestureDetector(
                onTap: () => onSelected(c),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.white24,
                      width: isSelected ? 2.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Color(c).withValues(alpha: 0.6),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: (c == 0xFFFFFFFF || c == 0xFFFFEB3B || c == 0xFF76FF03)
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlePreview(SubtitleAppearanceModel style) {
    const sampleText = "Preview Subtitles";

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Color(
            style.backgroundColor,
          ).withValues(alpha: style.backgroundOpacity),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            if (style.outlineWidth > 0)
              Text(
                style.forceUppercase ? sampleText.toUpperCase() : sampleText,
                textAlign: TextAlign.center,
                style: SubtitleUtils.getSubtitleTextStyle(style, stroke: true),
              ),
            Text(
              style.forceUppercase ? sampleText.toUpperCase() : sampleText,
              textAlign: TextAlign.center,
              style: SubtitleUtils.getSubtitleTextStyle(style),
            ),
          ],
        ),
      ),
    );
  }
}
