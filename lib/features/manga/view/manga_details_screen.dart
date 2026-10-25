import 'package:ani_dash/shared/providers/settings/source_notifier.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/core/repositories/manga_reading_progress_repository.dart';
import 'package:ani_dash/features/manga/utils/manga_helpers.dart';
import 'manga_reader_screen.dart';

class MangaDetailsScreen extends ConsumerStatefulWidget {
  final DMedia manga;
  final Source mangaSource;

  const MangaDetailsScreen({
    super.key,
    required this.manga,
    required this.mangaSource,
  });

  @override
  ConsumerState<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  DMedia? _detailedManga;
  bool _isLoading = true;
  String? _error;
  bool _isReversed = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await widget.mangaSource.methods
          .getDetail(widget.manga)
          .timeout(const Duration(seconds: 20));

      if (details.episodes != null && details.episodes!.isNotEmpty) {
        final cacheKey = widget.manga.url ?? widget.manga.title;
        if (cacheKey != null && cacheKey.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('manga_ch_count_$cacheKey', details.episodes!.length);
        }
      }

      if (mounted) {
        setState(() {
          _detailedManga = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailedManga = widget.manga;
          _error = 'Could not load full chapter list: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showSourceSwitcher(BuildContext context) async {
    final sources = ref.read(sourceProvider).installedMangaExtensions;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other manga extensions installed.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Switch Manga Source',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sources.length,
                itemBuilder: (_, i) {
                  final src = sources[i];
                  final isCurrent = src.id == widget.mangaSource.id;
                  return ListTile(
                    leading: const Icon(Iconsax.book),
                    title: Text(src.name ?? 'Unknown Source'),
                    trailing: isCurrent ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      if (isCurrent) return;
                      // Search manga on new source
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      try {
                        final title = widget.manga.title ?? '';
                        final searchRes = await src.methods.search(title, 1, []);
                        final matches = searchRes.list;
                        if (matches.isNotEmpty) {
                          final match = matches.first;
                          final details = await src.methods.getDetail(match).timeout(const Duration(seconds: 20));
                          if (mounted) {
                            setState(() {
                              _detailedManga = details;
                              _isLoading = false;
                            });
                          }
                        } else {
                          if (mounted) {
                            setState(() {
                              _error = 'No match found for "$title" on ${src.name}';
                              _isLoading = false;
                            });
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _error = 'Error searching ${src.name}: $e';
                            _isLoading = false;
                          });
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final manga = _detailedManga ?? widget.manga;
    final chapters = manga.episodes ?? [];
    final displayedChapters =
        _isReversed ? chapters.reversed.toList() : chapters;
    final isAdult = isMangaAdult(manga, source: widget.mangaSource);

    final progressList = ref.watch(mangaReadingProgressProvider);
    final mangaKey = manga.url ?? manga.title ?? '';
    final currentProgress = progressList
        .where((p) => p.mangaUrl == mangaKey || p.mangaTitle == manga.title)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          manga.title ?? 'Manga Details',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: _loadDetails,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: manga.cover ?? '',
                                    width: 110,
                                    height: 160,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 110,
                                      height: 160,
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      child: const Icon(Iconsax.book, size: 40),
                                    ),
                                  ),
                                ),
                                if (isAdult)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: build18PlusBadge(fontSize: 9),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    manga.title ?? 'Untitled',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (manga.author?.isNotEmpty == true) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Author: ${manga.author}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          widget.mangaSource.name ??
                                              'Manga Source',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color:
                                                colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (isAdult) build18PlusBadge(fontSize: 9),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${chapters.length} Chapters',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Resume Reading Button if progress exists
                        if (currentProgress != null &&
                            chapters.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                // Find the chapter matching progress
                                final targetChapter = chapters.firstWhere(
                                  (ch) =>
                                      (ch.url != null &&
                                          ch.url == currentProgress.chapterUrl) ||
                                      ch.name == currentProgress.chapterTitle ||
                                      ch.episodeNumber ==
                                          currentProgress.chapterNumber,
                                  orElse: () => chapters.first,
                                );

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MangaReaderScreen(
                                      chapter: targetChapter,
                                      mangaTitle: manga.title ?? 'Manga',
                                      mangaSource: widget.mangaSource,
                                      manga: manga,
                                      mangaCover: manga.cover,
                                      initialPage: currentProgress.pageIndex,
                                      isAdult: isAdult,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Iconsax.book_1),
                              label: Text(
                                'Resume ${currentProgress.chapterTitle} (Page ${currentProgress.pageIndex}/${currentProgress.totalPages})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],

                        if (manga.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 16),
                          Text(
                            manga.description!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.8),
                              height: 1.4,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Chapters (${chapters.length})',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _isReversed
                                    ? Iconsax.arrow_up_3
                                    : Iconsax.arrow_down_1,
                                size: 20,
                              ),
                              tooltip: _isReversed
                                  ? 'Show First to Last'
                                  : 'Show Last to First',
                              onPressed: () =>
                                  setState(() => _isReversed = !_isReversed),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (displayedChapters.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Iconsax.book_1,
                              size: 48,
                              color: colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error ?? 'No chapters found on ${widget.mangaSource.name ?? "current source"}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              icon: const Icon(Iconsax.refresh, size: 18),
                              label: const Text('Try Another Source (MangaSee, Mangakakalot)'),
                              onPressed: () => _showSourceSwitcher(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chapter = displayedChapters[index];
                        final isRead = currentProgress != null &&
                            (currentProgress.chapterUrl == chapter.url ||
                                currentProgress.chapterTitle == chapter.name);

                        return ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isRead
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : colorScheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isRead
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                      size: 18,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            chapter.name ?? 'Chapter ${index + 1}',
                            style: TextStyle(
                              fontWeight:
                                  isRead ? FontWeight.bold : FontWeight.w600,
                              color: isRead ? colorScheme.primary : null,
                            ),
                          ),
                          subtitle: chapter.dateUpload?.isNotEmpty == true
                              ? Text(chapter.dateUpload!)
                              : null,
                          trailing: const Icon(Iconsax.arrow_right_3, size: 18),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MangaReaderScreen(
                                  chapter: chapter,
                                  mangaTitle: manga.title ?? 'Manga',
                                  mangaSource: widget.mangaSource,
                                  manga: manga,
                                  mangaCover: manga.cover,
                                  isAdult: isAdult,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: displayedChapters.length,
                    ),
                  ),
              ],
            ),
    );
  }
}
