import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ani_dash/router/router_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/shared/providers/settings/download_settings_notifier.dart';
import 'package:ani_dash/core/utils/extractors.dart' as extractor;
import 'package:ani_dash/core/utils/video_utils.dart';

class DownloadSourceSelector extends ConsumerStatefulWidget {
  final String animeTitle;
  final String? animeCover;
  final EpisodeDataModel? episode;
  final int episodeCount;
  final ServerData? server;
  final List<ServerData> availableServers;
  final Future<BaseSourcesModel?> Function()? fetchSources;
  final Future<BaseSourcesModel?> Function(ServerData server)?
  fetchSourcesForServer;
  final ScrollController? scrollController;
  final Future<void> Function(
    String language,
    String quality,
    bool doNotAskAgain,
  )?
  onConfirmBatchDownload;
  final bool isAdult;

  const DownloadSourceSelector({
    super.key,
    required this.animeTitle,
    this.animeCover,
    this.episode,
    this.episodeCount = 1,
    this.server,
    this.availableServers = const [],
    this.fetchSources,
    this.fetchSourcesForServer,
    this.scrollController,
    this.onConfirmBatchDownload,
    this.isAdult = false,
  });

  @override
  ConsumerState<DownloadSourceSelector> createState() =>
      _DownloadSourceSelectorState();
}

class _DownloadSourceSelectorState
    extends ConsumerState<DownloadSourceSelector> {
  bool _loading = false;
  String? _error;
  List<Source> _sources = [];
  List<Subtitle> _subtitles = [];

  late String _selectedLanguage;
  late String _selectedQuality;
  bool _rememberChoice = false;
  bool _hasDub = true;
  late ServerData? _selectedServer;
  bool _downloadSubtitles = true;

  @override
  void initState() {
    super.initState();
    final downloadSettings = ref.read(downloadSettingsProvider);
    _selectedLanguage = downloadSettings.preferredLanguage;
    _selectedQuality = downloadSettings.preferredQuality;
    _rememberChoice = downloadSettings.rememberDownloadPreferences;
    _selectedServer = widget.server;

    if (widget.fetchSources != null) {
      _initSources();
    }
  }

  Future<void> _initSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data =
          widget.fetchSourcesForServer != null && _selectedServer != null
              ? await widget.fetchSourcesForServer!(_selectedServer!)
              : await widget.fetchSources!();
      if (!mounted) return;

      if (data != null && data.sources.isNotEmpty) {
        final hasDub =
            data.sources.any((s) => s.isDub) ||
            widget.availableServers.any((server) => server.isDub);

        setState(() {
          _sources = data.sources;
          _subtitles = data.tracks;
          _hasDub = hasDub;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectLanguage(String language) async {
    setState(() => _selectedLanguage = language);
    final wantsDub = language == 'dub';
    final matching =
        widget.availableServers
            .where((server) => server.isDub == wantsDub)
            .toList();
    if (matching.isNotEmpty && _selectedServer?.isDub != wantsDub) {
      setState(() => _selectedServer = matching.first);
      await _initSources();
    }
  }

  Future<void> _selectServer(ServerData server) async {
    if (_selectedServer == server) return;
    setState(() {
      _selectedServer = server;
      _selectedLanguage = server.isDub ? 'dub' : 'sub';
    });
    await _initSources();
  }

  String _formatSize(int mb) {
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~$mb MB';
  }

  int _getQualitySize(String quality) {
    switch (quality) {
      case '1080p':
        return 350;
      case '720p':
        return 200;
      case '480p':
        return 100;
      case '360p':
        return 60;
      default:
        return 200;
    }
  }

  Future<void> _startDownload() async {
    // 1. Save preferences if remember was checked
    if (_rememberChoice) {
      ref
          .read(downloadSettingsProvider.notifier)
          .saveDownloadPreferences(
            remember: true,
            language: _selectedLanguage,
            quality: _selectedQuality,
            serverId: _selectedServer?.id,
          );
    }

    // 2. Batch download callback
    if (widget.onConfirmBatchDownload != null) {
      Navigator.pop(context);
      await widget.onConfirmBatchDownload!(
        _selectedLanguage,
        _selectedQuality,
        _rememberChoice,
      );
      return;
    }

    // 3. Single episode direct download
    if (widget.episode == null) return;

    final epNum = widget.episode!.number ?? 0;
    Source? matchedSource;

    if (_sources.isNotEmpty) {
      if (_selectedLanguage == 'dub') {
        for (final source in _sources) {
          if (source.isDub) {
            matchedSource = source;
            break;
          }
        }
      } else {
        for (final source in _sources) {
          if (!source.isDub) {
            matchedSource = source;
            break;
          }
        }
      }
    }

    if (matchedSource == null ||
        !VideoUtils.isValidNetworkUrl(matchedSource.url) ||
        (_selectedLanguage == 'dub' &&
            !matchedSource.isDub &&
            _selectedServer?.isDub != true)) {
      if (!mounted) return;
      setState(() {
        _error =
            _selectedLanguage == 'dub'
                ? 'English DUB is unavailable from this server. Choose SUB or another server.'
                : 'This server did not provide a valid download. Choose another server.';
      });
      return;
    }

    String downloadUrl = matchedSource.url!;
    final isM3U8 = matchedSource.isM3U8 || downloadUrl.contains('.m3u8');

    // If source is M3U8, try to extract matching quality sub-playlist
    if (isM3U8) {
      try {
        final extracted = await extractor
            .extractQualities(
              matchedSource.url!,
              matchedSource.headers ?? {},
              true,
            )
            .timeout(const Duration(seconds: 8));

        final target = extracted.firstWhere(
          (q) => (q['quality'] as String).contains(_selectedQuality),
          orElse: () => extracted.first,
        );
        if (VideoUtils.isValidNetworkUrl(target['url']?.toString())) {
          downloadUrl = target['url'] as String;
        }
      } catch (_) {}
    }

    if (!VideoUtils.isValidNetworkUrl(downloadUrl)) {
      if (!mounted) return;
      setState(() {
        _error =
            'This server returned an invalid download link. Try another server.';
      });
      return;
    }

    final ext = isM3U8 ? 'ts' : 'mp4';
    final sanitizedTitle = widget.animeTitle.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final qualityName = _selectedQuality.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final fileName = '${sanitizedTitle}_EP${epNum}_$qualityName.$ext';

    final thumb =
        (widget.episode?.thumbnail != null &&
                widget.episode!.thumbnail!.isNotEmpty)
            ? widget.episode!.thumbnail!
            : (widget.animeCover ?? '');

    final item = DownloadItem(
      animeTitle: widget.animeTitle,
      episodeTitle: widget.episode!.title ?? 'Episode $epNum',
      episodeNumber: epNum,
      thumbnail: thumb,
      state: DownloadStatus.queued,
      progress: 0,
      downloadUrl: downloadUrl,
      quality: _selectedQuality,
      filePath: fileName,
      subtitles:
          _downloadSubtitles
              ? _subtitles.map((s) => jsonEncode(s.toJson())).toList()
              : const [],
      contentType: isM3U8 ? 'application/vnd.apple.mpegurl' : null,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        ...?matchedSource.headers,
      },
      isAdult: widget.isAdult,
      audioLanguage:
          _selectedLanguage == 'dub' ? 'English DUB' : 'Japanese SUB',
    );

    await ref.read(downloadsProvider.notifier).addDownload(item);

    if (mounted) {
      Navigator.pop(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              Expanded(
                child: Text(
                  'Download queued for Episode $epNum ($_selectedQuality)',
                ),
              ),
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  routerConfig.go('/downloads');
                },
                child: const Text('View Downloads'),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Cancel',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              ref.read(downloadsProvider.notifier).cancelDownload(item.id);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isBatch = widget.episodeCount > 1;

    final basePerEpSize = _getQualitySize(_selectedQuality);
    final totalSizeMB = basePerEpSize * widget.episodeCount;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child:
                          (widget.episode?.thumbnail?.isNotEmpty == true ||
                                  widget.animeCover?.isNotEmpty == true)
                              ? Image.network(
                                widget.episode?.thumbnail ?? widget.animeCover!,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, _, _) => ColoredBox(
                                      color: colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.download_rounded,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                              )
                              : ColoredBox(
                                color: colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.download_rounded,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBatch
                              ? 'Download ${widget.episodeCount} Episodes'
                              : 'Download Episode ${widget.episode?.number ?? 1}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (!isBatch && widget.episode?.title != null)
                          Text(
                            widget.episode!.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (widget.availableServers.isNotEmpty) ...[
                Text(
                  'Server',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                PopupMenuButton<ServerData>(
                  onSelected: _selectServer,
                  itemBuilder:
                      (context) =>
                          widget.availableServers
                              .map(
                                (server) => PopupMenuItem(
                                  value: server,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          server.name ??
                                              server.id?.toUpperCase() ??
                                              'Server',
                                        ),
                                      ),
                                      Badge(
                                        label: Text(
                                          server.isDub ? 'DUB' : 'SUB',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.dns_rounded),
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedServer?.name ??
                                _selectedServer?.id?.toUpperCase() ??
                                'Automatic',
                          ),
                        ),
                        Badge(
                          label: Text(
                            _selectedServer?.isDub == true ? 'DUB' : 'SUB',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                'Language / Audio',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_hasDub)
                    _LanguageChip(
                      label: 'English (Dub)',
                      icon: Iconsax.volume_high,
                      isSelected: _selectedLanguage == 'dub',
                      onTap: () => _selectLanguage('dub'),
                    ),
                  _LanguageChip(
                    label: 'Japanese (Sub)',
                    icon: Iconsax.translate,
                    isSelected: _selectedLanguage == 'sub',
                    onTap: () => _selectLanguage('sub'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.subtitles_rounded),
                title: const Text('Include subtitles'),
                subtitle: Text(
                  _subtitles.isEmpty
                      ? 'No subtitle tracks reported by this server'
                      : '${_subtitles.length} track${_subtitles.length == 1 ? '' : 's'} available',
                ),
                value: _downloadSubtitles && _subtitles.isNotEmpty,
                onChanged:
                    _subtitles.isEmpty
                        ? null
                        : (value) => setState(() => _downloadSubtitles = value),
              ),
              const SizedBox(height: 22),
              Text(
                'Quality',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              _QualityCard(
                quality: '1080p',
                title: '1080p (Full HD)',
                sizeDescription:
                    isBatch
                        ? '${_formatSize(350)} / ep • ${_formatSize(350 * widget.episodeCount)} Total'
                        : _formatSize(350),
                isSelected: _selectedQuality == '1080p',
                onTap: () => setState(() => _selectedQuality = '1080p'),
              ),
              const SizedBox(height: 8),
              _QualityCard(
                quality: '720p',
                title: '720p (High Definition)',
                sizeDescription:
                    isBatch
                        ? '${_formatSize(200)} / ep • ${_formatSize(200 * widget.episodeCount)} Total'
                        : _formatSize(200),
                isSelected: _selectedQuality == '720p',
                onTap: () => setState(() => _selectedQuality = '720p'),
              ),
              const SizedBox(height: 8),
              _QualityCard(
                quality: '480p',
                title: '480p (Standard)',
                sizeDescription:
                    isBatch
                        ? '${_formatSize(100)} / ep • ${_formatSize(100 * widget.episodeCount)} Total'
                        : _formatSize(100),
                isSelected: _selectedQuality == '480p',
                onTap: () => setState(() => _selectedQuality = '480p'),
              ),
              const SizedBox(height: 8),
              _QualityCard(
                quality: '360p',
                title: '360p (Data Saver)',
                sizeDescription:
                    isBatch
                        ? '${_formatSize(60)} / ep • ${_formatSize(60 * widget.episodeCount)} Total'
                        : _formatSize(60),
                isSelected: _selectedQuality == '360p',
                onTap: () => setState(() => _selectedQuality = '360p'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isBatch
                            ? 'Estimated download size: ${_formatSize(totalSizeMB)} for ${widget.episodeCount} episodes'
                            : 'Estimated file size: ${_formatSize(basePerEpSize)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _rememberChoice = !_rememberChoice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _rememberChoice,
                        onChanged:
                            (val) =>
                                setState(() => _rememberChoice = val ?? false),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remember choice (Do not ask again)',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Future downloads will use this language & quality automatically.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _startDownload,
                  icon:
                      _loading
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.download_rounded),
                  label: Text(
                    isBatch
                        ? 'Download ${widget.episodeCount} Episodes (${_formatSize(totalSizeMB)})'
                        : 'Download Episode (${_formatSize(basePerEpSize)})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

class _LanguageChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
            border: Border.all(
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color:
                      isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  final String quality;
  final String title;
  final String sizeDescription;
  final bool isSelected;
  final VoidCallback onTap;

  const _QualityCard({
    required this.quality,
    required this.title,
    required this.sizeDescription,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color:
                isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                      color:
                          isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sizeDescription,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isSelected
                              ? colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.8,
                              )
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                quality,
                style: TextStyle(
                  color:
                      isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
