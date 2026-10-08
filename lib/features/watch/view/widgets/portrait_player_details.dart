import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:commentum_client/commentum_client.dart';
import 'package:ani_dash/core/commentum/commentum_client.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/utils/html_parser.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/details/view_model/details_page_notifier.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';

enum DiscussionMode { episodeComments, worldChat }

class PortraitPlayerDetails extends ConsumerStatefulWidget {
  final String animeTitle;
  final String? animeFormat;
  final String? animeCover;
  final int episodeNumber;
  final String? episodeTitle;
  final String? episodeThumbnail;
  final String? episodeDescription;
  final List<EpisodeDataModel> episodes;
  final String mediaId;
  final VoidCallback onAllEpisodesPressed;
  final VoidCallback onMoreOptionsPressed;
  final VoidCallback onToggleFullscreen;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const PortraitPlayerDetails({
    super.key,
    required this.animeTitle,
    this.animeFormat,
    this.animeCover,
    required this.episodeNumber,
    this.episodeTitle,
    this.episodeThumbnail,
    this.episodeDescription,
    this.episodes = const [],
    required this.mediaId,
    required this.onAllEpisodesPressed,
    required this.onMoreOptionsPressed,
    required this.onToggleFullscreen,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  ConsumerState<PortraitPlayerDetails> createState() =>
      _PortraitPlayerDetailsState();
}

class _PortraitPlayerDetailsState extends ConsumerState<PortraitPlayerDetails> {
  bool _isLiked = false;
  bool _isDisliked = false;
  int _likeCount = 1920;
  int _dislikeCount = 18;
  bool _isDescriptionExpanded = false;
  bool _isAboutSectionExpanded = false;

  // Discussion / World Chat State
  DiscussionMode _activeDiscussionMode = DiscussionMode.episodeComments;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  List<Comment> _comments = [];
  bool _isLoadingComments = false;
  bool _isSubmittingComment = false;

  @override
  void initState() {
    super.initState();
    _loadLikesPreferences();
    _loadComments();
  }

  @override
  void didUpdateWidget(covariant PortraitPlayerDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeNumber != widget.episodeNumber ||
        oldWidget.mediaId != widget.mediaId) {
      _loadLikesPreferences();
      _loadComments();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  String get _currentDiscussionArticleId {
    if (_activeDiscussionMode == DiscussionMode.episodeComments) {
      return '${widget.mediaId}_ep_${widget.episodeNumber}';
    } else {
      return 'global_world_chat';
    }
  }

  Future<void> _loadLikesPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
      final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';
      final keyCount = 'likes_count_${widget.mediaId}_ep_${widget.episodeNumber}';

      final userLiked = prefs.getBool(keyLiked) ?? false;
      final userDisliked = prefs.getBool(keyDisliked) ?? false;

      // Realistic base likes seeded from anime ID and episode number
      final seed = (widget.mediaId.hashCode.abs() % 1500) + (widget.episodeNumber * 23);
      final storedCount = prefs.getInt(keyCount) ?? (500 + seed);

      if (!mounted) return;
      setState(() {
        _isLiked = userLiked;
        _isDisliked = userDisliked;
        _likeCount = storedCount + (userLiked ? 1 : 0);
        _dislikeCount = 8 + (widget.episodeNumber % 12) + (userDisliked ? 1 : 0);
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final prefs = await SharedPreferences.getInstance();
    final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyCount = 'likes_count_${widget.mediaId}_ep_${widget.episodeNumber}';

    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999);
      } else {
        _isLiked = true;
        _likeCount++;
        if (_isDisliked) {
          _isDisliked = false;
          _dislikeCount = (_dislikeCount - 1).clamp(0, 999999);
          prefs.setBool(keyDisliked, false);
        }
      }
    });
    await prefs.setBool(keyLiked, _isLiked);
    await prefs.setInt(keyCount, _likeCount);
  }

  Future<void> _toggleDislike() async {
    final prefs = await SharedPreferences.getInstance();
    final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyCount = 'likes_count_${widget.mediaId}_ep_${widget.episodeNumber}';

    setState(() {
      if (_isDisliked) {
        _isDisliked = false;
        _dislikeCount = (_dislikeCount - 1).clamp(0, 999999);
      } else {
        _isDisliked = true;
        _dislikeCount++;
        if (_isLiked) {
          _isLiked = false;
          _likeCount = (_likeCount - 1).clamp(0, 999999);
          prefs.setBool(keyLiked, false);
          prefs.setInt(keyCount, _likeCount);
        }
      }
    });
    await prefs.setBool(keyDisliked, _isDisliked);
  }

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);
    try {
      final articleId = _currentDiscussionArticleId;
      var res = await commentumClient.listComments(articleId, limit: 20);
      if (mounted) {
        setState(() {
          _comments = res.data;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final auth = ref.read(authProvider);
    final user = auth.userFor(auth.activePlatform);
    final authorName = user?.name ?? 'AniDash Fan';
    final avatar = user?.avatarUrl;

    _commentController.clear();
    _commentFocusNode.unfocus();

    final localComment = Comment(
      id: (-DateTime.now().millisecondsSinceEpoch).toString(),
      content: text,
      score: 0,
      status: CommentStatus.active,
      username: authorName,
      avatarUrl: avatar,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      hasMoreReplies: false,
      replies: [],
      repliesCount: 0,
      userVote: 0,
    );

    setState(() {
      _comments.insert(0, localComment);
      _isSubmittingComment = true;
    });

    try {
      final targetId = _currentDiscussionArticleId;
      await commentumClient.createComment(
        targetId,
        "anilist",
        text,
      );
      await _loadComments();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _voteComment(Comment comment, int newVote) async {
    try {
      final vote = comment.userVote == newVote ? 0 : newVote;
      await commentumClient.voteComment(comment.id, vote);
      await _loadComments();
    } catch (_) {}
  }

  EpisodeDataModel? get _nextEpisode {
    final nextNumber = widget.episodeNumber + 1;
    for (final ep in widget.episodes) {
      if (ep.number == nextNumber) return ep;
    }
    return null;
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  String _cleanEpisodeTitle(String? raw, {bool isMovie = false}) {
    final title = (raw ?? '').trim().replaceFirst(
      RegExp(r'^(?:(?:episode|ep)|e)\s*#?\s*\d+(?:\.\d+)?\s*(?:[-:—|/]+\s*)?', caseSensitive: false),
      '',
    ).trim();
    if (isMovie) {
      if (title.isEmpty || title.toLowerCase().startsWith('episode')) {
        return widget.animeTitle;
      }
      return title;
    }
    return title.isEmpty ? 'Episode ${widget.episodeNumber}' : title;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final streamState = ref.watch(episodeDataProvider);
    final isDub = streamState.selectedServer?.isDub == true;
    final audioLabel = isDub ? 'Dub English | Sub' : 'Sub Japanese | Dub';

    final detailsFormat = ref.watch(detailsPageProvider(widget.mediaId)).details.value?.format;
    final progressFormat = ref.watch(watchProgressRepositoryProvider).getProgress(widget.mediaId)?.animeFormat;
    final epListState = ref.watch(episodeListProvider);
    final titleLower = widget.animeTitle.toLowerCase();
    final isMovie = (widget.animeFormat?.trim().toUpperCase() == 'MOVIE') ||
        (detailsFormat?.trim().toUpperCase() == 'MOVIE') ||
        (progressFormat?.trim().toUpperCase() == 'MOVIE') ||
        epListState.isMovie ||
        titleLower.contains('the very final') ||
        titleLower.contains('movie') ||
        titleLower.contains('film') ||
        (widget.episodes.length <= 1 &&
            (widget.animeFormat?.trim().toUpperCase() == 'MOVIE' ||
                detailsFormat?.trim().toUpperCase() == 'MOVIE'));

    final cleanTitle = _cleanEpisodeTitle(widget.episodeTitle, isMovie: isMovie);
    final nextEp = _nextEpisode;

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Clickable Anime Title (Navigates to Full Anime Details Screen)
          InkWell(
            onTap: () {
              context.push('/details/${widget.mediaId}');
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.animeTitle,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Iconsax.arrow_right_3,
                    size: 14,
                    color: colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // 2. Bold Title (Adapts to Movie vs Series)
          Text(
            isMovie
                ? (cleanTitle.isNotEmpty && !cleanTitle.toLowerCase().startsWith('episode')
                    ? cleanTitle
                    : widget.animeTitle)
                : 'E${widget.episodeNumber} - $cleanTitle',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),

          // 3. Badges: [ MOVIE / Format ] • Dub English | Sub
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  isMovie
                      ? 'MOVIE'
                      : ((widget.animeFormat != null && widget.animeFormat!.trim().isNotEmpty)
                          ? widget.animeFormat!
                          : 'U/A 16+'),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '•',
                style: TextStyle(color: colorScheme.outline, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                audioLabel,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4. Interactive Action Row: Like, Dislike, Download, More Options
          Row(
            children: [
              // Like Button
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isLiked
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                        size: 19,
                        color: _isLiked ? colorScheme.primary : colorScheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_likeCount),
                        style: TextStyle(
                          color: _isLiked ? colorScheme.primary : colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Dislike Button
              InkWell(
                onTap: _toggleDislike,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isDisliked
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDisliked ? Icons.thumb_down : Icons.thumb_down_alt_outlined,
                        size: 19,
                        color: _isDisliked ? Colors.redAccent : colorScheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_dislikeCount),
                        style: TextStyle(
                          color: _isDisliked ? Colors.redAccent : colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Download Button
              IconButton.filledTonal(
                onPressed: () {
                  ref.read(episodeDataProvider.notifier).downloadEpisode(
                    context,
                    widget.episodeNumber,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isMovie
                          ? 'Starting download for ${widget.animeTitle}...'
                          : 'Starting download for Episode ${widget.episodeNumber}...'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 20),
                tooltip: isMovie ? 'Download Movie' : 'Download Episode',
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),

              // More Options (Episode Settings & Server Switcher)
              IconButton.filledTonal(
                onPressed: widget.onMoreOptionsPressed,
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                tooltip: isMovie ? 'Movie Options' : 'Episode Options',
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Episode Synopsis / Description (Collapsible)
          if (widget.episodeDescription != null && widget.episodeDescription!.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.episodeDescription!,
                      maxLines: _isDescriptionExpanded ? 100 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isDescriptionExpanded ? 'Show less' : 'Read more',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 6. Content Advisory Section (Click to reveal About / Synopsis)
          InkWell(
            onTap: () {
              setState(() {
                _isAboutSectionExpanded = !_isAboutSectionExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isAboutSectionExpanded
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Content Advisory',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        _isAboutSectionExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'U/A 16+',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Violence, Action, Strong Language, Drama',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),

                  // About / Synopsis accordion expanded right below
                  if (_isAboutSectionExpanded) ...[
                    const SizedBox(height: 10),
                    Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 1),
                    const SizedBox(height: 10),
                    Consumer(
                      builder: (context, ref, _) {
                        final detailsState = ref.watch(detailsPageProvider(widget.mediaId));
                        final media = detailsState.details.value;
                        final desc = media?.description ?? widget.episodeDescription ?? '';
                        final cleanDesc = desc.isNotEmpty ? parseHtmlToString(desc) : 'No description available.';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'About this ${isMovie ? "Movie" : "Anime"}',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cleanDesc,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 7. Next Episode Section (Hidden for Movies)
          if (!isMovie && nextEp != null) ...[
            Text(
              'Next Episode',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                ref.read(episodeDataProvider.notifier).changeEpisode(nextEp.number);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    // 16:9 Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,
                        height: 68,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (nextEp.thumbnail != null && nextEp.thumbnail!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: nextEp.thumbnail!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                errorWidget: (_, _, _) => Container(
                                  color: colorScheme.surfaceContainerHigh,
                                  child: const Icon(Icons.movie_creation_outlined),
                                ),
                              )
                            else
                              Container(
                                color: colorScheme.surfaceContainerHigh,
                                child: const Icon(Icons.movie_creation_outlined),
                              ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '23m',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EPISODE ${nextEp.number}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _cleanEpisodeTitle(nextEp.title),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.download_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                      onPressed: () {
                        final epNum = nextEp.number;
                        if (epNum == null) return;
                        ref.read(episodeDataProvider.notifier).downloadEpisode(
                          context,
                          epNum,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading Episode $epNum...'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // 8. All Episodes Button (Hidden for movies)
          if (!isMovie) ...[
            Center(
              child: OutlinedButton.icon(
                onPressed: widget.onAllEpisodesPressed,
                icon: Icon(Iconsax.menu_1, color: colorScheme.primary, size: 18),
                label: Text(
                  'All Episodes',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Divider(color: theme.dividerColor, height: 1),
          const SizedBox(height: 18),

          // 9. Community World Chat & Episode / Movie Comments
          Row(
            children: [
              // Segmented Tab Selector: [ Movie/Episode Comments ] / [ World Chat ]
              Expanded(
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (_activeDiscussionMode != DiscussionMode.episodeComments) {
                          setState(() => _activeDiscussionMode = DiscussionMode.episodeComments);
                          _loadComments();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _activeDiscussionMode == DiscussionMode.episodeComments
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isMovie
                              ? 'Comments on ${widget.animeTitle}'
                              : 'Episode ${widget.episodeNumber} Comments',
                          style: TextStyle(
                            color: _activeDiscussionMode == DiscussionMode.episodeComments
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        if (_activeDiscussionMode != DiscussionMode.worldChat) {
                          setState(() => _activeDiscussionMode = DiscussionMode.worldChat);
                          _loadComments();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _activeDiscussionMode == DiscussionMode.worldChat
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🌐', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              'World Chat',
                              style: TextStyle(
                                color: _activeDiscussionMode == DiscussionMode.worldChat
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3-Dot Discussion Menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                tooltip: 'Discussion Options',
                onSelected: (val) {
                  if (val == 'new_world_chat') {
                    setState(() => _activeDiscussionMode = DiscussionMode.worldChat);
                    _commentFocusNode.requestFocus();
                  } else if (val == 'switch_ep') {
                    setState(() => _activeDiscussionMode = DiscussionMode.episodeComments);
                    _loadComments();
                  } else if (val == 'refresh') {
                    _loadComments();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'new_world_chat',
                    child: Row(
                      children: [
                        Icon(Iconsax.global, size: 18),
                        SizedBox(width: 10),
                        Text('Create / Join World Chat'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'switch_ep',
                    child: Row(
                      children: [
                        const Icon(Iconsax.messages_1, size: 18),
                        const SizedBox(width: 10),
                        Text(isMovie ? 'Comments on Movie' : 'Ep ${widget.episodeNumber} Comments'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Refresh Comments'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Comment Composer
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _activeDiscussionMode == DiscussionMode.episodeComments
                        ? (isMovie
                            ? 'Comment on ${widget.animeTitle}...'
                            : 'Comment on Episode ${widget.episodeNumber}...')
                        : 'Chat with community in World Chat...',
                    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _postComment(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSubmittingComment ? null : _postComment,
                icon: _isSubmittingComment
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                      )
                    : Icon(Icons.send_rounded, color: colorScheme.primary, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Comments List
          if (_isLoadingComments)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
              ),
            )
          else if (_comments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                _activeDiscussionMode == DiscussionMode.episodeComments
                    ? (isMovie
                        ? 'No comments on this movie yet. Be the first!'
                        : 'No comments on this episode yet. Be the first!')
                    : 'World Chat is empty. Start the conversation!',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            )
          else
            ..._comments.take(30).map((comment) => _buildCommentTile(comment, colorScheme)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCommentTile(Comment comment, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: comment.avatarUrl != null && comment.avatarUrl!.isNotEmpty
                ? CachedNetworkImageProvider(comment.avatarUrl!)
                : null,
            child: comment.avatarUrl == null || comment.avatarUrl!.isEmpty
                ? Text(
                    comment.username.isNotEmpty ? comment.username[0].toUpperCase() : 'U',
                    style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.username.isEmpty ? 'Fan' : comment.username,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _timeAgo(comment.createdAt),
                      style: TextStyle(color: colorScheme.outline, fontSize: 11),
                    ),
                    const Spacer(),
                    // Upvote Button
                    InkWell(
                      onTap: () => _voteComment(comment, 1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.userVote == 1 ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                              size: 14,
                              color: comment.userVote == 1 ? colorScheme.primary : colorScheme.outline,
                            ),
                            if (comment.score > 0) ...[
                              const SizedBox(width: 2),
                              Text(
                                '${comment.score}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: comment.userVote == 1 ? colorScheme.primary : colorScheme.outline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
