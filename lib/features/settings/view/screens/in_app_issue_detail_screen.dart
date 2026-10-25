import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ani_dash/core/services/feedback_service.dart';

class InAppIssueDetailScreen extends StatefulWidget {
  final GitHubIssueItem issue;

  const InAppIssueDetailScreen({
    super.key,
    required this.issue,
  });

  @override
  State<InAppIssueDetailScreen> createState() => _InAppIssueDetailScreenState();
}

class _InAppIssueDetailScreenState extends State<InAppIssueDetailScreen> {
  final FeedbackService _feedbackService = FeedbackService();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<GitHubIssueComment> _comments = [];
  bool _loadingComments = true;
  bool _sendingReply = false;
  late String _currentState;

  @override
  void initState() {
    super.initState();
    _currentState = widget.issue.state;
    _loadComments();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    final comments = await _feedbackService.fetchIssueComments(widget.issue.number);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _loadingComments = false;
    });
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    final token = await _feedbackService.getGitHubToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      _promptForToken(onSaved: _sendReply);
      return;
    }

    setState(() => _sendingReply = true);
    final success = await _feedbackService.postIssueComment(widget.issue.number, text, token: token);
    if (!mounted) return;
    setState(() => _sendingReply = false);

    if (success) {
      _replyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply posted successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadComments();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to post reply. Check your GitHub Token in settings.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleIssueState() async {
    final token = await _feedbackService.getGitHubToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      _promptForToken(onSaved: _toggleIssueState);
      return;
    }

    final willClose = _currentState == 'open';
    final success = await _feedbackService.updateIssueState(
      widget.issue.number,
      close: willClose,
      token: token,
    );

    if (!mounted) return;
    if (success) {
      setState(() => _currentState = willClose ? 'closed' : 'open');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(willClose ? 'Issue #${widget.issue.number} closed.' : 'Issue #${widget.issue.number} reopened.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update issue status. Verify GitHub Token permissions.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _promptForToken({VoidCallback? onSaved}) {
    final tokenController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Iconsax.key, size: 20),
            SizedBox(width: 8),
            Text('GitHub Access Token'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a GitHub Personal Access Token (repo scope) to reply and manage issues directly within AniDash:',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(
                hintText: 'ghp_xxxxxxxxxxxx',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final token = tokenController.text.trim();
              if (token.isNotEmpty) {
                await _feedbackService.saveGitHubToken(token);
                if (ctx.mounted) Navigator.pop(ctx);
                onSaved?.call();
              }
            },
            child: const Text('Save Token'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOpen = _currentState == 'open';
    final stateColor = isOpen ? Colors.greenAccent : Colors.purpleAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.issue.number}'),
        actions: [
          IconButton(
            tooltip: isOpen ? 'Close Issue' : 'Reopen Issue',
            icon: Icon(isOpen ? Icons.check_circle_outline_rounded : Icons.replay_rounded),
            onPressed: _toggleIssueState,
          ),
          IconButton(
            tooltip: 'Configure GitHub Token',
            icon: const Icon(Iconsax.key),
            onPressed: () => _promptForToken(),
          ),
          IconButton(
            tooltip: 'Open on GitHub Website',
            icon: const Icon(Iconsax.export_1),
            onPressed: () {
              launchUrl(
                Uri.parse(widget.issue.htmlUrl),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Issue Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: stateColor.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOpen ? Icons.adjust_rounded : Icons.check_circle_outline_rounded,
                                  color: stateColor,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _currentState.toUpperCase(),
                                  style: TextStyle(
                                    color: stateColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('MMM d, y • h:mm a').format(widget.issue.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.issue.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (widget.issue.authorAvatar != null)
                            ClipOval(
                              child: Image.network(
                                widget.issue.authorAvatar!,
                                width: 22,
                                height: 22,
                                errorBuilder: (_, _, _) => const Icon(Icons.person, size: 22),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            'Opened by @${widget.issue.author}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (widget.issue.labels.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.issue.labels.map((l) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      Text(
                        widget.issue.body.isNotEmpty
                            ? widget.issue.body
                            : 'No description provided.',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Comments Header
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Discussion (${_comments.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (_loadingComments)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        tooltip: 'Refresh Comments',
                        onPressed: _loadComments,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Comments List
                if (_comments.isEmpty && !_loadingComments)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      'No comments yet. Write the first response below!',
                      style: TextStyle(color: colorScheme.outline, fontSize: 13),
                    ),
                  )
                else
                  ..._comments.map((comment) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (comment.authorAvatar != null)
                                ClipOval(
                                  child: Image.network(
                                    comment.authorAvatar!,
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, _, _) => const Icon(Icons.person, size: 20),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                '@${comment.author}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                DateFormat('MMM d, h:mm a').format(comment.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            comment.body,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          // Bottom Reply Input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Reply to #${widget.issue.number}...',
                        hintStyle: TextStyle(fontSize: 14, color: colorScheme.outline),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sendingReply
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          onPressed: _sendReply,
                          icon: const Icon(Icons.send_rounded, size: 18),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
