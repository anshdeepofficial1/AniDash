import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:commentum_client/commentum_client.dart';
import 'package:ani_dash/core/commentum/commentum_client.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';

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

  // Comments / World Chat
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

  Future<void> _loadLikesPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
      final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';
      if (!mounted) return;
      setState(() {
        _isLiked = prefs.getBool(keyLiked) ?? false;
        _isDisliked = prefs.getBool(keyDisliked) ?? false;
        _likeCount = 1900 + (widget.episodeNumber * 13) % 450 + (_isLiked ? 1 : 0);
        _dislikeCount = 15 + (widget.episodeNumber * 3) % 25 + (_isDisliked ? 1 : 0);
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final prefs = await SharedPreferences.getInstance();
    final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';

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
  }

  Future<void> _toggleDislike() async {
    final prefs = await SharedPreferences.getInstance();
    final keyLiked = 'like_${widget.mediaId}_ep_${widget.episodeNumber}';
    final keyDisliked = 'dislike_${widget.mediaId}_ep_${widget.episodeNumber}';

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
        }
      }
    });
    await prefs.setBool(keyDisliked, _isDisliked);
  }

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);
    try {
      final articleId = '${widget.mediaId}_ep_${widget.episodeNumber}';
      var res = await commentumClient.listComments(articleId, limit: 15);
      if (res.data.isEmpty) {
        // Fallback to anime root comments if episode has no comments yet
        res = await commentumClient.listComments(widget.mediaId, limit: 15);
      }
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
      final articleId = '${widget.mediaId}_ep_${widget.episodeNumber}';
      await commentumClient.createComment(
        articleId,
        "anilist",
        text,
      );
    } catch (_) {
      try {
        await commentumClient.createComment(
          widget.mediaId,
          "anilist",
          text,
        );
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
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

  String _cleanEpisodeTitle(String? raw) {
    final title = (raw ?? '').trim().replaceFirst(
      RegExp(r'^(?:(?:episode|ep)|e)\s*#?\s*\d+(?:\.\d+)?\s*(?:[-:—|/]+\s*)?', caseSensitive: false),
      '',
    ).trim();
    return title.isEmpty ? 'Episode ${widget.episodeNumber}' : title;
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(episodeDataProvider);
    final isDub = streamState.selectedServer?.isDub == true;
    final audioLabel = isDub ? 'Dub English | Sub' : 'Sub Japanese | Dub';

    final cleanTitle = _cleanEpisodeTitle(widget.episodeTitle);
    final nextEp = _nextEpisode;

    return Container(
      color: Colors.black,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Orange Anime Title (Matching Screenshot)
          Text(
            widget.animeTitle,
            style: const TextStyle(
              color: Color(0xFFFF7A00),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),

          // 2. Bold White Episode Title: E230 - Adventure in the City...
          Text(
            'E${widget.episodeNumber} - $cleanTitle',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),

          // 3. Badges: [ U/A 16+ ] • Dub English | Sub
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.animeFormat ?? 'U/A 16+',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '•',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                audioLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4. Interactive Action Row: Like, Dislike, Download, More
          Row(
            children: [
              // Like Button
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                        size: 20,
                        color: _isLiked ? const Color(0xFFFF7A00) : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_likeCount),
                        style: TextStyle(
                          color: _isLiked ? const Color(0xFFFF7A00) : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Dislike Button
              InkWell(
                onTap: _toggleDislike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDisliked ? Icons.thumb_down : Icons.thumb_down_alt_outlined,
                        size: 20,
                        color: _isDisliked ? Colors.redAccent : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_dislikeCount),
                        style: TextStyle(
                          color: _isDisliked ? Colors.redAccent : Colors.white,
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
              IconButton(
                onPressed: () {
                  ref.read(episodeDataProvider.notifier).downloadEpisode(
                    context,
                    widget.episodeNumber,
                  );
                },
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                tooltip: 'Download Episode',
              ),

              // More Options (Settings/Servers)
              IconButton(
                onPressed: widget.onMoreOptionsPressed,
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                tooltip: 'More options',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Episode Synopsis / Description
          if (widget.episodeDescription != null && widget.episodeDescription!.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
              child: Text(
                widget.episodeDescription!,
                maxLines: _isDescriptionExpanded ? 100 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 18),

          // 6. Content Advisory Section
          const Text(
            'Content Advisory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'U/A 16+',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Violence, Smoking, Drug/Alcohol Use, Action, Language',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),

          // 7. Next Episode Section
          if (nextEp != null) ...[
            const Text(
              'Next Episode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                ref.read(episodeDataProvider.notifier).changeEpisode(nextEp.number);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    // Next Thumbnail with 23m tag
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CachedNetworkImage(
                            imageUrl: nextEp.thumbnail ?? widget.animeCover ?? '',
                            width: 120,
                            height: 68,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(color: Colors.grey.shade900),
                            errorWidget: (_, _, _) => Container(
                              width: 120,
                              height: 68,
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.play_circle_outline, color: Colors.white38),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              '23m',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${nextEp.number}. ${_cleanEpisodeTitle(nextEp.title)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.white70, size: 20),
                      onPressed: () {
                        final epNum = nextEp.number;
                        if (epNum != null) {
                          ref.read(episodeDataProvider.notifier).downloadEpisode(
                            context,
                            epNum,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // 8. All Episodes Button (Centered Orange)
          Center(
            child: TextButton.icon(
              onPressed: widget.onAllEpisodesPressed,
              icon: const Icon(Iconsax.menu_1, color: Color(0xFFFF7A00), size: 18),
              label: const Text(
                'All Episodes',
                style: TextStyle(
                  color: Color(0xFFFF7A00),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // 9. Community World Chat & Episode Comments
          Row(
            children: [
              const Icon(Iconsax.messages_1, color: Color(0xFFFF7A00), size: 18),
              const SizedBox(width: 8),
              Text(
                'World Chat & Discussion (${_comments.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                onPressed: _loadComments,
                tooltip: 'Refresh comments',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Comment Composer
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Discuss Ep ${widget.episodeNumber} in World Chat...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
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
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF7A00)),
                      )
                    : const Icon(Icons.send_rounded, color: Color(0xFFFF7A00), size: 22),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Comments List
          if (_isLoadingComments)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFFFF7A00), strokeWidth: 2),
              ),
            )
          else if (_comments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                'Be the first to comment on this episode!',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ..._comments.take(20).map((comment) => _buildCommentTile(comment)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCommentTile(Comment comment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white12,
            backgroundImage: comment.avatarUrl != null && comment.avatarUrl!.isNotEmpty
                ? NetworkImage(comment.avatarUrl!)
                : null,
            child: comment.avatarUrl == null || comment.avatarUrl!.isEmpty
                ? const Icon(Icons.person, size: 18, color: Colors.white54)
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _timeAgo(comment.createdAt),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
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
