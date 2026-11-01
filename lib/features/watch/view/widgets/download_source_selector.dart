import 'package:collection/collection.dart';
import 'dart:async';
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
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/core/utils/extractors.dart' as extractor;
import 'package:ani_dash/core/utils/video_utils.dart';
import 'package:ani_dash/core/utils/language_utils.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';
import 'package:ani_dash/helpers/ui.dart';

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
  final List<String>? genres;

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
    this.genres,
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
  Source? _selectedSource;
  bool _downloadSubtitles = true;
  final Map<String, int> _probedQualityBytes = {};

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

  bool _isSourceDub(Source s) {
    if (s.isDub) return true;
    if (_selectedServer?.isDub == true) return true;
    final q = (s.quality ?? '').toLowerCase();
    if (q.contains('dub')) return true;
    final url = (s.url ?? '').toLowerCase();
    if (url.contains('dub')) return true;
    return false;
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
            data.sources.any((s) => _isSourceDub(s)) ||
            widget.availableServers.any((server) => server.isDub);

        setState(() {
          _sources = data.sources;
          _subtitles = data.tracks;
          _hasDub = hasDub;
          _loading = false;
          if (!hasDub && _selectedLanguage == 'dub') {
            _selectedLanguage = 'sub';
          }
          _selectedSource = _findMatchingSource(data.sources, _selectedLanguage, _selectedQuality);
        });
        unawaited(_probeSizes());
      } else {
        setState(() {
          _loading = false;
          _error = 'No streaming links found from this server. Try another server.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Source? _findMatchingSource(List<Source> sources, String language, String quality) {
    if (sources.isEmpty) return null;
    final isDubTarget = language == 'dub';
    final langSources = sources.where((s) => isDubTarget ? _isSourceDub(s) : !_isSourceDub(s)).toList();
    final candidates = langSources.isNotEmpty ? langSources : sources;

    // 1. Direct quality match in candidate sources (e.g. 1080p, 720p, 360p)
    final directMatch = candidates.firstWhereOrNull(
      (s) => s.quality != null && s.quality!.toLowerCase().contains(quality.toLowerCase()),
    );
    if (directMatch != null) return directMatch;

    // 2. Fallback to M3U8 source for variant playlist extraction
    final m3u8 = candidates.firstWhereOrNull((s) => s.isM3U8 || (s.url?.contains('.m3u8') ?? false));
    return m3u8 ?? candidates.firstOrNull;
  }

  Future<void> _selectLanguage(String language) async {
    setState(() {
      _selectedLanguage = language;
      _selectedSource = _findMatchingSource(_sources, language, _selectedQuality);
    });
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

  void _selectQuality(String quality) {
    setState(() {
      _selectedQuality = quality;
      _selectedSource = _findMatchingSource(_sources, _selectedLanguage, quality);
    });
  }

  Source? _getMatchedSource() {
    if (_selectedSource != null) return _selectedSource;
    return _findMatchingSource(_sources, _selectedLanguage, _selectedQuality);
  }

  Future<void> _probeSizes() async {
    final matched = _getMatchedSource();
    if (matched == null || !VideoUtils.isValidNetworkUrl(matched.url)) return;
    if (matched.isM3U8 || matched.url!.contains('.m3u8')) {
      try {
        final extracted = await extractor
            .extractQualities(matched.url!, matched.headers ?? {}, true)
            .timeout(const Duration(seconds: 6));
        for (final q in extracted) {
          final qName = q['quality'] as String?;
          final bw = q['bandwidth'] as int?;
          if (qName != null && bw != null && bw > 0) {
            final bytes = (bw * 1440) ~/ 8;
            _probedQualityBytes[qName] = bytes;
          }
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  String _formatSize(int mb) {
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~$mb MB';
  }

  int _getQualitySize(String quality) {
    for (final entry in _probedQualityBytes.entries) {
      if (entry.key.contains(quality)) {
        return (entry.value / (1024 * 1024)).round();
      }
    }
    switch (quality) {
      case '1080p':
        return 950;
      case '720p':
        return 500;
      case '480p':
        return 250;
      case '360p':
        return 120;
      default:
        return 500;
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
    Source? matchedSource = _selectedSource ?? _findMatchingSource(_sources, _selectedLanguage, _selectedQuality);

    if (matchedSource == null || !VideoUtils.isValidNetworkUrl(matchedSource.url)) {
      if (!mounted) return;
      setState(() {
        _error = 'This server did not provide a valid streaming link. Choose another server.';
      });
      return;
    }

    final isDubSource = _isSourceDub(matchedSource);
    if (_selectedLanguage == 'dub' && !isDubSource && !_sources.any((s) => _isSourceDub(s)) && _selectedServer?.isDub != true) {
      if (!mounted) return;
      setState(() {
        _error = 'English DUB is unavailable from this server. Choose SUB or another server.';
      });
      return;
    }

    String downloadUrl = matchedSource.url!;
    final isM3U8 = matchedSource.isM3U8 || downloadUrl.contains('.m3u8');
    String finalQuality = matchedSource.quality?.trim() ?? _selectedQuality;

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

        final target = extracted.firstWhereOrNull(
          (q) => (q['quality'] as String).toLowerCase().contains(_selectedQuality.toLowerCase()),
        );
        if (target != null && VideoUtils.isValidNetworkUrl(target['url']?.toString())) {
          downloadUrl = target['url'] as String;
          finalQuality = _selectedQuality;
        } else if (extracted.isNotEmpty) {
          final first = extracted.first;
          if (VideoUtils.isValidNetworkUrl(first['url']?.toString())) {
            downloadUrl = first['url'] as String;
            finalQuality = (first['quality'] as String?) ?? _selectedQuality;
          }
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
    final qualityName = finalQuality.replaceAll(
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
      quality: finalQuality,
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
      audioLanguage: LanguageUtils.formatAudioLanguage(
        _selectedLanguage,
        ref.read(experimentalProvider).useExtensions
            ? LanguageUtils.detectLanguage(
                sourceLang: ref.read(sourceProvider).activeAnimeSource?.lang,
                genres: widget.genres,
                title: widget.animeTitle,
              )
            : 'ja',
      ),
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
                  UIHelper.exitImmersiveMode();
                  UIHelper.forcePortrait();
                  routerConfig.push('/downloads');
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
    final useExt = ref.watch(experimentalProvider).useExtensions;
    final activeSource = ref.watch(sourceProvider).activeAnimeSource;
    final activeSourceLang = useExt
        ? LanguageUtils.detectLanguage(
            sourceLang: activeSource?.lang,
            genres: widget.genres,
            title: widget.animeTitle,
          )
        : 'ja';
    final subLabel = LanguageUtils.getSubLabel(activeSourceLang);
    final dubLabel = LanguageUtils.getDubLabel(activeSourceLang);

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
                      label: dubLabel,
                      icon: Iconsax.volume_high,
                      isSelected: _selectedLanguage == 'dub',
                      onTap: () => _selectLanguage('dub'),
                    ),
                  _LanguageChip(
                    label: subLabel,
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
              Builder(
                builder: (context) {
                  final langSources = _sources.where((s) => _selectedLanguage == 'dub' ? _isSourceDub(s) : !_isSourceDub(s)).toList();
                  final availableStreams = langSources.isNotEmpty ? langSources : _sources;
                  final hasSpecificStreams = !isBatch && availableStreams.length > 1;

                  if (hasSpecificStreams) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Streams',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: availableStreams.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final src = availableStreams[index];
                            final isSelected = _selectedSource == src;
                            final qText = src.quality?.trim();
                            final displayName = (qText != null && qText.isNotEmpty) ? qText : 'Stream ${index + 1}';
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedSource = src;
                                  final lower = displayName.toLowerCase();
                                  if (lower.contains('1080')) {
                                    _selectedQuality = '1080p';
                                  } else if (lower.contains('720')) {
                                    _selectedQuality = '720p';
                                  } else if (lower.contains('480')) {
                                    _selectedQuality = '480p';
                                  } else if (lower.contains('360')) {
                                    _selectedQuality = '360p';
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary.withValues(alpha: 0.12)
                                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        src.isM3U8 || (src.url?.contains('.m3u8') ?? false) ? 'HLS' : 'MP4',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  }

                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.2,
                    children: [
                      _QualityCard(
                        quality: '1080p',
                        title: '1080p (FHD)',
                        sizeDescription: isBatch
                            ? '${_formatSize(_getQualitySize('1080p'))} • Total ${_formatSize(_getQualitySize('1080p') * widget.episodeCount)}'
                            : _formatSize(_getQualitySize('1080p')),
                        isSelected: _selectedQuality == '1080p',
                        onTap: () => _selectQuality('1080p'),
                      ),
                      _QualityCard(
                        quality: '720p',
                        title: '720p (HD)',
                        sizeDescription: isBatch
                            ? '${_formatSize(_getQualitySize('720p'))} • Total ${_formatSize(_getQualitySize('720p') * widget.episodeCount)}'
                            : _formatSize(_getQualitySize('720p')),
                        isSelected: _selectedQuality == '720p',
                        onTap: () => _selectQuality('720p'),
                      ),
                      _QualityCard(
                        quality: '480p',
                        title: '480p (SD)',
                        sizeDescription: isBatch
                            ? '${_formatSize(_getQualitySize('480p'))} • Total ${_formatSize(_getQualitySize('480p') * widget.episodeCount)}'
                            : _formatSize(_getQualitySize('480p')),
                        isSelected: _selectedQuality == '480p',
                        onTap: () => _selectQuality('480p'),
                      ),
                      _QualityCard(
                        quality: '360p',
                        title: '360p (Data Saver)',
                        sizeDescription: isBatch
                            ? '${_formatSize(_getQualitySize('360p'))} • Total ${_formatSize(_getQualitySize('360p') * widget.episodeCount)}'
                            : _formatSize(_getQualitySize('360p')),
                        isSelected: _selectedQuality == '360p',
                        onTap: () => _selectQuality('360p'),
                      ),
                    ],
                  );
                },
              ),              const SizedBox(height: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
