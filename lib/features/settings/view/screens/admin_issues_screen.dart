import 'package:ani_dash/core/services/developer_access_service.dart';
import 'package:ani_dash/core/services/feedback_service.dart';
import 'package:ani_dash/core/utils/env_loader.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:ani_dash/features/settings/view/screens/in_app_issue_detail_screen.dart';
import 'package:ani_dash/features/settings/view/widgets/feedback_issue_sheet.dart';

class AdminIssuesScreen extends ConsumerStatefulWidget {
  const AdminIssuesScreen({super.key});

  @override
  ConsumerState<AdminIssuesScreen> createState() => _AdminIssuesScreenState();
}

class _AdminIssuesScreenState extends ConsumerState<AdminIssuesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _accessService = const DeveloperAccessService();
  final _feedbackService = FeedbackService();
  final _pinController = TextEditingController();

  bool _checkingAccess = true;
  bool _unlocked = false;
  bool _blocked = false;
  int _remainingAttempts = 3;
  bool _loadingPin = false;

  // In-app reports
  List<FeedbackReport> _inAppReports = [];
  bool _loadingInApp = false;

  // GitHub issues
  List<GitHubIssueItem> _githubIssues = [];
  bool _loadingGitHub = false;
  String _githubFilter = 'all'; // all, open, closed

  bool _isInAppIssue(GitHubIssueItem item) {
    final title = item.title.toLowerCase();
    final hasInAppTitle = title.startsWith('[in-app') || title.contains('in-app');
    final hasInAppLabel = item.labels.any((l) => l.toLowerCase().contains('in-app'));
    final hasInAppBody = item.body.toLowerCase().contains('[anidash in-app report]');
    return hasInAppTitle || hasInAppLabel || hasInAppBody;
  }

  List<GitHubIssueItem> get _inAppGitHubIssues =>
      _githubIssues.where(_isInAppIssue).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAccess());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String? get _token => ref.read(authProvider).anilistAccessToken;

  bool get _isDeveloper =>
      ref.read(authProvider).anilistUser?.id.toString() == ADMIN_ANILIST_ID;

  Future<void> _initializeAccess() async {
    final blocked = await _accessService.isBlocked();
    final unlocked = await _accessService.isUnlocked();
    final remaining = await _accessService.remainingAttempts();
    if (!mounted) return;
    setState(() {
      _blocked = blocked;
      _unlocked = unlocked && !blocked;
      _remainingAttempts = remaining;
      _checkingAccess = false;
    });

    _loadAllData();
  }

  void _showPinDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Developer Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your 4-digit developer PIN to unlock remote server database sync:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(letterSpacing: 16, fontSize: 24),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••',
              ),
            ),
            if (_remainingAttempts < 3) ...[
              const SizedBox(height: 8),
              Text(
                '$_remainingAttempts attempts remaining',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _loadingPin
                ? null
                : () {
                    Navigator.pop(ctx);
                    _unlock();
                  },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlock() async {
    final token = _token;
    if (token == null || _pinController.text.length != 4) return;
    setState(() => _loadingPin = true);
    try {
      final success = await _accessService.verify(
        accessToken: token,
        pin: _pinController.text,
      );
      if (!mounted) return;
      setState(() => _unlocked = success);
      if (success) {
        _loadAllData();
      }
    } catch (_) {
      final remaining = await _accessService.remainingAttempts();
      final blocked = await _accessService.isBlocked();
      if (!mounted) return;
      setState(() {
        _remainingAttempts = remaining;
        _blocked = blocked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'Developer access temporarily locked.'
                : 'Invalid PIN. $remaining attempts remaining.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingPin = false);
    }
  }

  Future<void> _loadAllData() async {
    _loadInAppReports();
    _loadGitHubIssues();
  }

  Future<void> _loadInAppReports() async {
    if (!mounted) return;
    setState(() => _loadingInApp = true);
    try {
      final local = await _feedbackService.getLocalReports();
      final token = _token;
      List<FeedbackReport> remote = [];
      if (_unlocked && token != null) {
        remote = await _feedbackService.getRemoteReports(
          accessToken: token,
          developerPin: _pinController.text,
        );
      }

      // Merge and deduplicate by ID
      final map = <String, FeedbackReport>{};
      for (final r in local) {
        map[r.id] = r;
      }
      for (final r in remote) {
        map[r.id] = r;
      }

      final merged = map.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() => _inAppReports = merged);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load in-app reports: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingInApp = false);
    }
  }

  Future<void> _loadGitHubIssues() async {
    if (!mounted) return;
    setState(() => _loadingGitHub = true);
    try {
      final issues = await _feedbackService.fetchGitHubIssues(
        state: _githubFilter,
      );
      if (!mounted) return;
      setState(() => _githubIssues = issues);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load GitHub issues: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGitHub = false);
    }
  }

  Color _categoryColor(String type) {
    switch (type.toLowerCase()) {
      case 'bug':
        return Colors.redAccent;
      case 'playback':
        return Colors.orangeAccent;
      case 'request':
        return Colors.greenAccent;
      default:
        return Colors.blueAccent;
    }
  }

  IconData _categoryIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bug':
        return Iconsax.danger;
      case 'playback':
        return Iconsax.video_play;
      case 'request':
        return Iconsax.lamp_on;
      default:
        return Iconsax.message_question;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_checkingAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Community Feedback & Issues')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback & Issues'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Iconsax.message_text),
              text: 'In-App Reports (${_inAppGitHubIssues.length + _inAppReports.length})',
            ),
            Tab(
              icon: const Icon(Iconsax.code),
              text: 'GitHub Issues (${_githubIssues.length})',
            ),
          ],
        ),
        actions: [
          if (_isDeveloper && !_unlocked && !_blocked)
            IconButton(
              icon: const Icon(Iconsax.key),
              tooltip: 'Unlock Developer Sync',
              onPressed: _showPinDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildInAppTab(colorScheme), _buildGitHubTab(colorScheme)],
      ),
    );
  }

  Widget _buildInAppTab(ColorScheme colorScheme) {
    if (_loadingInApp && _loadingGitHub) {
      return const Center(child: CircularProgressIndicator());
    }

    final inAppIssues = _inAppGitHubIssues;
    // Deduplicate local reports that already have a GitHub issue URL matching one of the inAppIssues
    final unlinkedLocalReports = _inAppReports.where((local) {
      if (local.githubIssueUrl == null) return true;
      return !inAppIssues.any((gh) => gh.htmlUrl == local.githubIssueUrl);
    }).toList();

    final totalCount = inAppIssues.length + unlinkedLocalReports.length;

    if (totalCount == 0) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 60),
            Icon(
              Iconsax.message_tick,
              size: 56,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'No in-app reports yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'When users submit feedback or bug reports inside AniDash, they will appear right here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: inAppIssues.length + unlinkedLocalReports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index < inAppIssues.length) {
            final item = inAppIssues[index];
            final isOpen = item.state == 'open';
            final stateColor = isOpen ? Colors.greenAccent : Colors.purpleAccent;

            // Clean title: remove [In-App Feedback]: prefix
            final cleanTitle = item.title
                .replaceAll(
                  RegExp(r'^\[In-App[^\]]*\]:\s*', caseSensitive: false),
                  '',
                )
                .trim();

            // Category from title or labels
            String category = 'Bug / Error';
            if (item.title.toLowerCase().contains('subtitles') ||
                item.title.toLowerCase().contains('playback')) {
              category = 'Video / Subtitles';
            } else if (item.title.toLowerCase().contains('feature') ||
                item.title.toLowerCase().contains('request')) {
              category = 'Feature Request';
            }

            final color = _categoryColor(category);
            final icon = _categoryIcon(category);
            final formattedDate = DateFormat(
              'MMM d, y • h:mm a',
            ).format(item.createdAt);

            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: color.withValues(alpha: 0.3), width: 1.2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InAppIssueDetailScreen(issue: item),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 14, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  category.toUpperCase(),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOpen ? 'OPEN' : 'RESOLVED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: stateColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        cleanTitle.isEmpty ? item.title : cleanTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.body
                              .replaceAll(RegExp(r'\[AniDash In-App Report\]'), '')
                              .replaceAll(RegExp(r'Type:.*'), '')
                              .replaceAll(RegExp(r'Title:.*'), '')
                              .replaceAll(RegExp(r'Details:'), '')
                              .trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(
                            Iconsax.user,
                            'by ${item.author}',
                            colorScheme,
                          ),
                          _chip(
                            Iconsax.code,
                            'Issue #${item.number}',
                            colorScheme,
                          ),
                          if (item.commentsCount > 0)
                            _chip(
                              Icons.chat_bubble_outline_rounded,
                              '${item.commentsCount} comments',
                              colorScheme,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Iconsax.message, size: 16),
                            label: const Text('View & Reply in App'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => InAppIssueDetailScreen(issue: item),
                                ),
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

          // Local reports
          final localIndex = index - inAppIssues.length;
          final item = unlinkedLocalReports[localIndex];
          final color = _categoryColor(item.type);
          final icon = _categoryIcon(item.type);
          final formattedDate = DateFormat(
            'MMM d, y • h:mm a',
          ).format(item.createdAt);

          return Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: 0.3), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 4),
                            Text(
                              item.type.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.outline.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'LOCAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(
                        Iconsax.mobile,
                        '${item.platform} • ${item.appVersion}',
                        colorScheme,
                      ),
                      if (item.animeTitle != null &&
                          item.animeTitle!.isNotEmpty)
                        _chip(
                          Iconsax.video,
                          'Anime: ${item.animeTitle}',
                          colorScheme,
                        ),
                      if (item.contact.isNotEmpty)
                        _chip(
                          Iconsax.sms,
                          'Contact: ${item.contact}',
                          colorScheme,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy Details'),
                        onPressed: () {
                          final text = '''
[AniDash In-App Report]
Type: ${item.type}
Title: ${item.title}
Details: ${item.description}
Anime: ${item.animeTitle ?? 'None'}
Version: ${item.appVersion}
Platform: ${item.platform}
Contact: ${item.contact}
Date: ${item.createdAt}
'''.trim();
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report copied to clipboard!'),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete Local Report',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: const Text('Delete Report?'),
                                  content: const Text(
                                    'Are you sure you want to remove this local report?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                      ),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm == true) {
                            await _feedbackService.deleteReport(
                              id: item.id,
                              accessToken: _token,
                              developerPin: _pinController.text,
                            );
                            _loadInAppReports();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGitHubTab(ColorScheme colorScheme) {
    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _githubFilter == 'all',
                onSelected: (_) {
                  setState(() => _githubFilter = 'all');
                  _loadGitHubIssues();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Open'),
                selected: _githubFilter == 'open',
                onSelected: (_) {
                  setState(() => _githubFilter = 'open');
                  _loadGitHubIssues();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Closed'),
                selected: _githubFilter == 'closed',
                onSelected: (_) {
                  setState(() => _githubFilter = 'closed');
                  _loadGitHubIssues();
                },
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Issue'),
                onPressed: () => FeedbackIssueSheet.show(context),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child:
              _loadingGitHub
                  ? const Center(child: CircularProgressIndicator())
                  : _githubIssues.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Iconsax.code_1,
                          size: 48,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No ${_githubFilter != 'all' ? _githubFilter : ''} GitHub issues found',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                  : RefreshIndicator(
                    onRefresh: _loadGitHubIssues,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _githubIssues.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _githubIssues[index];
                        final isOpen = item.state == 'open';
                        final stateColor =
                            isOpen ? Colors.greenAccent : Colors.purpleAccent;

                        return Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: stateColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isOpen
                                    ? Icons.adjust_rounded
                                    : Icons.check_circle_outline_rounded,
                                color: stateColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '#${item.number}: ${item.title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'by ${item.author} • ${DateFormat('MMM d, y').format(item.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.outline,
                                  ),
                                ),
                                if (item.labels.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children:
                                        item.labels.map((l) {
                                          return Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              l,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.commentsCount > 0) ...[
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 14,
                                    color: colorScheme.outline,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item.commentsCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => InAppIssueDetailScreen(issue: item),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String text, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
