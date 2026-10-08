import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/manga/manga_reading_progress_model.dart';
import 'package:ani_dash/core/repositories/manga_reading_progress_repository.dart';
import 'package:ani_dash/features/manga/utils/manga_helpers.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/router/desktop/windows_caption_buttons.dart';

enum _ReaderMode { vertical, book }

class MangaReaderScreen extends ConsumerStatefulWidget {
  final DEpisode chapter;
  final String mangaTitle;
  final Source mangaSource;
  final DMedia? manga;
  final String? mangaCover;
  final String? mangaUrl;
  final int initialPage;
  final bool isAdult;

  const MangaReaderScreen({
    super.key,
    required this.chapter,
    required this.mangaTitle,
    required this.mangaSource,
    this.manga,
    this.mangaCover,
    this.mangaUrl,
    this.initialPage = 1,
    this.isAdult = false,
  });

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  late final PageController _pageController;
  List<PageUrl> _pages = [];
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  bool _showControls = true;
  late _ReaderMode _readerMode;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage > 0 ? widget.initialPage : 1;
    _readerMode =
        sharedPrefs.getString('manga_reader_mode') == 'book'
            ? _ReaderMode.book
            : _ReaderMode.vertical;
    _pageController = PageController(initialPage: _currentPage - 1);
    _scrollController.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _loadPages();
  }

  @override
  void dispose() {
    UIHelper.forcePortrait();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _saveProgress();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleOrientation() {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      UIHelper.forcePortrait();
    } else {
      UIHelper.forceLandscape();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_readerMode != _ReaderMode.book) return false;

    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      if (_pageController.hasClients) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
      return true;
    }
    return false;
  }

  void _onScroll() {
    if (_pages.isEmpty || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final current = _scrollController.position.pixels;
    final fraction = (current / max).clamp(0.0, 1.0);
    final page = (fraction * (_pages.length - 1)).round() + 1;
    if (page != _currentPage && page >= 1 && page <= _pages.length) {
      setState(() {
        _currentPage = page;
      });
      _saveProgress();
    }
  }

  Future<void> _saveProgress() async {
    if (_pages.isEmpty) return;
    try {
      final url = widget.manga?.url ?? widget.mangaUrl ?? widget.mangaTitle;
      final isAdultContent =
          widget.isAdult ||
          (widget.manga != null &&
              isMangaAdult(widget.manga!, source: widget.mangaSource));

      final entry = MangaReadingProgressEntry(
        mangaUrl: url,
        mangaTitle: widget.manga?.title ?? widget.mangaTitle,
        mangaCover: widget.manga?.cover ?? widget.mangaCover,
        sourceId: widget.mangaSource.id,
        sourceName: widget.mangaSource.name,
        chapterUrl: widget.chapter.url,
        chapterTitle:
            widget.chapter.name ?? 'Chapter ${widget.chapter.episodeNumber}',
        chapterNumber: widget.chapter.episodeNumber,
        pageIndex: _currentPage,
        totalPages: _pages.length,
        lastReadTime: DateTime.now(),
        isAdult: isAdultContent,
        isCompleted: _currentPage >= _pages.length,
        mangaJson: widget.manga?.toJson(),
        chapterJson: widget.chapter.toJson(),
      );

      await ref
          .read(mangaReadingProgressRepositoryProvider)
          .saveProgress(entry);
    } catch (_) {}
  }

  Future<void> _loadPages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pages = await widget.mangaSource.methods
          .getPageList(widget.chapter)
          .timeout(const Duration(seconds: 25));

      if (mounted) {
        setState(() {
          _pages = pages;
          _isLoading = false;
        });

        // If resuming a page, jump to it after layout
        if (_readerMode == _ReaderMode.vertical &&
            widget.initialPage > 1 &&
            pages.length > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0) {
              final targetFraction =
                  (widget.initialPage - 1) / (pages.length - 1);
              final targetOffset =
                  targetFraction * _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(
                targetOffset.clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                ),
              );
            }
          });
        }
        _saveProgress();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load chapter pages: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _setReaderMode(_ReaderMode mode) {
    if (_readerMode == mode) return;
    setState(() => _readerMode = mode);
    sharedPrefs.setString('manga_reader_mode', mode.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mode == _ReaderMode.book && _pageController.hasClients) {
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final targetPage =
            isLandscape ? ((_currentPage - 1) ~/ 2) : (_currentPage - 1);
        _pageController.jumpToPage(
          targetPage.clamp(0, _pages.isNotEmpty ? _pages.length - 1 : 0),
        );
      } else if (mode == _ReaderMode.vertical &&
          _scrollController.hasClients &&
          _pages.length > 1) {
        final targetFraction = (_currentPage - 1) / (_pages.length - 1);
        final targetOffset =
            targetFraction * _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          targetOffset.clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  Widget _pageImage(PageUrl page, int index) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4.5,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: page.url,
          httpHeaders: page.headers,
          fit: BoxFit.contain,
          placeholder:
              (_, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white60),
              ),
          errorWidget:
              (_, _, _) => Center(
                child: Text(
                  'Failed to load page ${index + 1}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
        ),
      ),
    );
  }

  Widget _bookReader(BuildContext context) {
    final twoPage = MediaQuery.orientationOf(context) == Orientation.landscape;
    final totalCount = twoPage ? ((_pages.length + 1) ~/ 2) : _pages.length;
    return PageView.builder(
      controller: _pageController,
      itemCount: totalCount,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        final calculatedPage = twoPage ? (index * 2 + 1) : index + 1;
        setState(() => _currentPage = calculatedPage.clamp(1, _pages.length));
        _saveProgress();
      },
      itemBuilder: (context, index) {
        final first = twoPage ? (index * 2) : index;
        final pageWidget = !twoPage
            ? _pageImage(_pages[first], first)
            : Row(
                children: [
                  Expanded(child: _pageImage(_pages[first], first)),
                  if (first + 1 < _pages.length)
                    Expanded(child: _pageImage(_pages[first + 1], first + 1))
                  else
                    const Spacer(),
                ],
              );

        return AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            double diff = 0.0;
            if (_pageController.position.haveDimensions) {
              diff = (_pageController.page ?? _pageController.initialPage.toDouble()) - index;
            }
            final normalized = diff.clamp(-1.0, 1.0);
            if (normalized.abs() < 0.001) {
              return child!;
            }
            final opacity = (1.0 - (normalized.abs() * 0.12)).clamp(0.0, 1.0);
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0006)
                ..rotateY(normalized * 0.08),
              alignment: normalized > 0 ? Alignment.centerRight : Alignment.centerLeft,
              child: Opacity(
                opacity: opacity,
                child: child,
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: pageWidget,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation != null && _lastOrientation != orientation) {
      final isLandscape = orientation == Orientation.landscape;
      _lastOrientation = orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_readerMode == _ReaderMode.book && _pageController.hasClients) {
          final targetPage =
              isLandscape ? ((_currentPage - 1) ~/ 2) : (_currentPage - 1);
          _pageController.jumpToPage(
            targetPage.clamp(0, _pages.isNotEmpty ? _pages.length - 1 : 0),
          );
        }
      });
    } else {
      _lastOrientation = orientation;
    }

    final isAdult =
        widget.isAdult ||
        (widget.manga != null &&
            isMangaAdult(widget.manga!, source: widget.mangaSource));

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _saveProgress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Manga Viewer
          GestureDetector(
            onTap: _toggleControls,
            child:
                _isLoading
                    ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Loading chapter...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    )
                    : _error != null
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadPages,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                    : _readerMode == _ReaderMode.book
                    ? _bookReader(context)
                    : InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 3.5,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _pages.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          return CachedNetworkImage(
                            imageUrl: page.url,
                            httpHeaders: page.headers,
                            fit: BoxFit.fitWidth,
                            placeholder:
                                (context, url) => Container(
                                  height: 400,
                                  color: Colors.grey[900],
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white60,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Page ${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            errorWidget:
                                (context, url, error) => Container(
                                  height: 280,
                                  color: Colors.grey[900],
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.broken_image,
                                          color: Colors.redAccent,
                                          size: 36,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Failed to load page ${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                        },
                      ),
                    ),
          ),

          // Top App Bar Controls
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                left: 8,
                right: 16,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.chapter.name ??
                                    'Chapter ${widget.chapter.episodeNumber}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isAdult) ...[
                              const SizedBox(width: 8),
                              build18PlusBadge(fontSize: 9),
                            ],
                          ],
                        ),
                        Text(
                          widget.mangaTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_pages.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_currentPage / ${_pages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Toggle 2-Page Landscape',
                    icon: Icon(
                      MediaQuery.orientationOf(context) == Orientation.landscape
                          ? Icons.stay_current_portrait_rounded
                          : Icons.stay_current_landscape_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _toggleOrientation,
                  ),
                  IconButton(
                    tooltip: 'Reader mode',
                    icon: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                    ),
                    onPressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          builder:
                              (sheetContext) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RadioListTile<_ReaderMode>(
                                      value: _ReaderMode.vertical,
                                      groupValue: _readerMode,
                                      title: const Text('Vertical scroll'),
                                      subtitle: const Text(
                                        'Continuous chapter reading',
                                      ),
                                      onChanged: (value) {
                                        Navigator.pop(sheetContext);
                                        if (value != null) {
                                          _setReaderMode(value);
                                        }
                                      },
                                    ),
                                    RadioListTile<_ReaderMode>(
                                      value: _ReaderMode.book,
                                      groupValue: _readerMode,
                                      title: const Text('Book mode'),
                                      subtitle: const Text(
                                        'Animated pages; two pages in landscape',
                                      ),
                                      onChanged: (value) {
                                        Navigator.pop(sheetContext);
                                        if (value != null) {
                                          _setReaderMode(value);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                        ),
                  ),
                  if (!Platform.isAndroid && !Platform.isIOS) ...[
                    const SizedBox(width: 8),
                    const WindowsCaptionButtons(height: 38, isDark: true),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Floating Page Pill
          if (_pages.isNotEmpty && !_isLoading)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Text(
                      'Page $_currentPage of ${_pages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}
