import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ani_dash/core/models/settings/subtitle_appearance_model.dart';
import 'package:ani_dash/features/settings/utils/subtitle_utils.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/shared/providers/settings/subtitle_notifier.dart';

class SubtitleSelectionSheet extends ConsumerStatefulWidget {
  final VoidCallback onLocalFilePressed;

  const SubtitleSelectionSheet({super.key, required this.onLocalFilePressed});

  @override
  ConsumerState<SubtitleSelectionSheet> createState() =>
      _SubtitleSelectionSheetState();
}

class _SubtitleSelectionSheetState extends ConsumerState<SubtitleSelectionSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(episodeDataProvider);
    final existingSubtitles = data.subtitles;
    final selectedIndex = data.selectedSubtitleIdx;
    final delay = ref.watch(playerStateProvider.select((s) => s.subtitleDelay));
    final subtitleStyle = ref.watch(subtitleAppearanceProvider);
    final notifier = ref.read(subtitleAppearanceProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with TabBar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Subtitles',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: Colors.white60,
              indicatorColor: theme.colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(
                  icon: Icon(Iconsax.document_text, size: 18),
                  text: 'Tracks',
                ),
                Tab(
                  icon: Icon(Iconsax.text_block, size: 18),
                  text: 'Appearance & Size',
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // TAB 1: TRACKS & OFFSET
                  _buildTracksTab(
                    context,
                    existingSubtitles,
                    selectedIndex,
                    delay,
                  ),
                  // TAB 2: APPEARANCE & STYLING
                  _buildAppearanceTab(
                    context,
                    subtitleStyle,
                    notifier,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracksTab(
    BuildContext context,
    List<dynamic> existingSubtitles,
    int selectedIndex,
    double delay,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Subtitle Delay Offset
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Subtitle Delay Offset',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    delay == 0
                        ? 'Synced (0.0s)'
                        : '${delay > 0 ? "+" : ""}${delay.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          delay == 0
                              ? null
                              : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(44, 32),
                    ),
                    onPressed:
                        () => ref
                            .read(playerStateProvider.notifier)
                            .adjustSubtitleDelay(-0.5),
                    child: const Text('-0.5s', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(44, 32),
                    ),
                    onPressed:
                        () => ref
                            .read(playerStateProvider.notifier)
                            .adjustSubtitleDelay(-0.1),
                    child: const Text('-0.1s', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(44, 32),
                    ),
                    onPressed:
                        delay == 0
                            ? null
                            : () => ref
                                .read(playerStateProvider.notifier)
                                .setSubtitleDelay(0.0),
                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(44, 32),
                    ),
                    onPressed:
                        () => ref
                            .read(playerStateProvider.notifier)
                            .adjustSubtitleDelay(0.1),
                    child: const Text('+0.1s', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(44, 32),
                    ),
                    onPressed:
                        () => ref
                            .read(playerStateProvider.notifier)
                            .adjustSubtitleDelay(0.5),
                    child: const Text('+0.5s', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: const Icon(Iconsax.folder_open),
          title: const Text('Import Local Subtitle File'),
          subtitle: const Text('.srt, .vtt, .ass, .ssa'),
          onTap: widget.onLocalFilePressed,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'AVAILABLE TRACKS (${existingSubtitles.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Colors.white54,
            ),
          ),
        ),
        for (int index = 0; index < existingSubtitles.length; index++)
          _buildSubtitleTile(
            context,
            existingSubtitles[index],
            index,
            index == selectedIndex,
          ),
      ],
    );
  }

  Widget _buildSubtitleTile(
    BuildContext context,
    dynamic sub,
    int index,
    bool isSelected,
  ) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : null,
      leading: Icon(
        isSelected ? Iconsax.tick_circle : Iconsax.subtitle,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.white54,
        size: 20,
      ),
      title: Text(
        sub.lang ?? 'Unknown',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
        ),
      ),
      trailing: isSelected
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          : null,
      onTap: () {
        ref.read(episodeDataProvider.notifier).changeSubtitle(index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildAppearanceTab(
    BuildContext context,
    SubtitleAppearanceModel style,
    SubtitleAppearanceNotifier notifier,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Live Preview Banner
        _buildSubtitlePreview(style),

        // Quick Presets
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            'QUICK PRESETS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _presetChip(
                label: 'Standard',
                onTap: () => notifier.updateSettings(
                  (p) => p.copyWith(
                    fontSize: 18,
                    textColor: 0xFFFFFFFF,
                    outlineWidth: 2.0,
                    outlineColor: 0xFF000000,
                    backgroundOpacity: 0.0,
                    hasShadow: true,
                    boldText: true,
                  ),
                ),
              ),
              _presetChip(
                label: 'Boxed',
                onTap: () => notifier.updateSettings(
                  (p) => p.copyWith(
                    fontSize: 18,
                    textColor: 0xFFFFFFFF,
                    outlineWidth: 0.0,
                    backgroundOpacity: 0.55,
                    backgroundColor: 0xFF000000,
                    hasShadow: false,
                    boldText: true,
                  ),
                ),
              ),
              _presetChip(
                label: 'Classic Yellow',
                onTap: () => notifier.updateSettings(
                  (p) => p.copyWith(
                    fontSize: 18,
                    textColor: 0xFFFFD700,
                    outlineWidth: 2.0,
                    outlineColor: 0xFF000000,
                    backgroundOpacity: 0.0,
                    hasShadow: true,
                    boldText: true,
                  ),
                ),
              ),
              _presetChip(
                label: 'High Vis',
                onTap: () => notifier.updateSettings(
                  (p) => p.copyWith(
                    fontSize: 20,
                    textColor: 0xFFFFFF00,
                    outlineWidth: 0.0,
                    backgroundOpacity: 0.85,
                    backgroundColor: 0xFF000000,
                    hasShadow: false,
                    boldText: true,
                  ),
                ),
              ),
              _presetChip(
                label: 'Cyber Cyan',
                onTap: () => notifier.updateSettings(
                  (p) => p.copyWith(
                    fontSize: 18,
                    textColor: 0xFF00FFFF,
                    outlineWidth: 2.0,
                    outlineColor: 0xFF00008B,
                    backgroundOpacity: 0.0,
                    hasShadow: true,
                    boldText: true,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 24),

        // Font Size Slider with direct controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Font Size',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${style.fontSize.round()} px',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: style.fontSize > 10
                  ? () => notifier.updateSettings(
                        (p) => p.copyWith(fontSize: p.fontSize - 1),
                      )
                  : null,
            ),
            Expanded(
              child: Slider(
                value: style.fontSize.clamp(10.0, 38.0),
                min: 10.0,
                max: 38.0,
                divisions: 28,
                label: '${style.fontSize.round()} px',
                onChanged: (val) => notifier.updateSettings(
                  (p) => p.copyWith(fontSize: val),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: style.fontSize < 38
                  ? () => notifier.updateSettings(
                        (p) => p.copyWith(fontSize: p.fontSize + 1),
                      )
                  : null,
            ),
          ],
        ),

        // Font Family Selector
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Font Family'),
          subtitle: Text(style.fontFamily ?? 'Default'),
          trailing: DropdownButton<String>(
            value: SubtitleUtils.availableFonts.contains(style.fontFamily)
                ? style.fontFamily
                : 'Default',
            underline: const SizedBox(),
            items: SubtitleUtils.availableFonts.map((String font) {
              return DropdownMenuItem<String>(
                value: font,
                child: Text(font, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: (val) => notifier.updateSettings(
              (p) => p.copyWith(fontFamily: val),
            ),
          ),
        ),

        // Text Color Palette
        _buildColorPickerRow(
          title: 'Text Color',
          selectedColor: style.textColor,
          colors: const [
            0xFFFFFFFF, // White
            0xFFFFD700, // Yellow / Gold
            0xFF00E5FF, // Cyan
            0xFF76FF03, // Lime Green
            0xFFFF80AB, // Pink
            0xFFFF9100, // Orange
          ],
          onSelected: (col) => notifier.updateSettings(
            (p) => p.copyWith(textColor: col),
          ),
        ),

        const SizedBox(height: 12),

        // Background Opacity
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Background Opacity',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '${(style.backgroundOpacity * 100).round()}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        Slider(
          value: style.backgroundOpacity.clamp(0.0, 1.0),
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '${(style.backgroundOpacity * 100).round()}%',
          onChanged: (val) => notifier.updateSettings(
            (p) => p.copyWith(backgroundOpacity: val),
          ),
        ),

        // Border / Outline Width
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Outline / Stroke Width',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '${style.outlineWidth.toStringAsFixed(1)} px',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        Slider(
          value: style.outlineWidth.clamp(0.0, 5.0),
          min: 0.0,
          max: 5.0,
          divisions: 10,
          label: '${style.outlineWidth.toStringAsFixed(1)} px',
          onChanged: (val) => notifier.updateSettings(
            (p) => p.copyWith(outlineWidth: val),
          ),
        ),

        // Bold Text & Drop Shadow Switches
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Bold Text'),
          value: style.boldText,
          onChanged: (val) => notifier.updateSettings(
            (p) => p.copyWith(boldText: val),
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Drop Shadow'),
          value: style.hasShadow,
          onChanged: (val) => notifier.updateSettings(
            (p) => p.copyWith(hasShadow: val),
          ),
        ),

        // Subtitle Position
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Screen Position',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 1, label: Text('Bottom')),
                  ButtonSegment<int>(value: 2, label: Text('Center')),
                  ButtonSegment<int>(value: 3, label: Text('Top')),
                ],
                selected: {style.position},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) {
                    notifier.updateSettings(
                      (p) => p.copyWith(position: set.first),
                    );
                  }
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        // Reset to Defaults Button
        Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset Subtitle Settings'),
            onPressed: () => notifier.updateSettings(
              (_) => SubtitleAppearanceModel(
                fontSize: 16,
                textColor: 0xFFFFFFFF,
                backgroundOpacity: 0.5,
                hasShadow: true,
                shadowOpacity: 0.5,
                shadowBlur: 2,
                fontFamily: null,
                position: 1,
                boldText: true,
                forceUppercase: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _presetChip({required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildSubtitlePreview(SubtitleAppearanceModel style) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Text(
            'LIVE PREVIEW',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Color(style.backgroundColor)
                  .withValues(alpha: style.backgroundOpacity),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              children: [
                if (style.outlineWidth > 0)
                  Text(
                    'The quick brown fox jumps over the lazy dog',
                    textAlign: TextAlign.center,
                    style: SubtitleUtils.getSubtitleTextStyle(
                      style,
                      stroke: true,
                    ),
                  ),
                Text(
                  'The quick brown fox jumps over the lazy dog',
                  textAlign: TextAlign.center,
                  style: SubtitleUtils.getSubtitleTextStyle(style),
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: colors.map((col) {
              final isSelected = col == selectedColor;
              return GestureDetector(
                onTap: () => onSelected(col),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color(col),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.white24,
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Color(col).withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: (col == 0xFFFFFFFF || col == 0xFFFFD700)
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
}
