import 'dart:io';
import 'package:ani_dash/core/services/feedback_service.dart';
import 'package:ani_dash/features/settings/view/screens/admin_issues_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum FeedbackType {
  bug('Bug / Error', Iconsax.danger),
  playback('Video / Subtitles', Iconsax.video_play),
  request('Feature Request', Iconsax.lamp_on),
  other('General Feedback', Iconsax.message_question);

  final String label;
  final IconData icon;
  const FeedbackType(this.label, this.icon);
}

class FeedbackIssueSheet extends StatefulWidget {
  final String? initialAnimeTitle;
  const FeedbackIssueSheet({super.key, this.initialAnimeTitle});

  static Future<void> show(
    BuildContext context, {
    String? initialAnimeTitle,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => FeedbackIssueSheet(initialAnimeTitle: initialAnimeTitle),
    );
  }

  @override
  State<FeedbackIssueSheet> createState() => _FeedbackIssueSheetState();
}

class _FeedbackIssueSheetState extends State<FeedbackIssueSheet> {
  bool _showInAppForm = false;
  FeedbackType _selectedType = FeedbackType.bug;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _contactController = TextEditingController();

  PackageInfo? _packageInfo;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    if (widget.initialAnimeTitle != null) {
      _titleController.text = 'Issue with: ${widget.initialAnimeTitle}';
    }
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  String _buildFormattedReport() {
    final version = _packageInfo?.version ?? '2.1.2';
    final build = _packageInfo?.buildNumber ?? '147';
    final os = Platform.operatingSystem;

    return '''
[AniDash In-App Report]
Type: ${_selectedType.label}
Title: ${_titleController.text.trim()}
Details:
${_descController.text.trim()}

Contact: ${_contactController.text.trim().isEmpty ? 'None provided' : _contactController.text.trim()}
App Version: v$version (Build $build)
Platform: $os
Date: ${DateTime.now().toIso8601String()}
'''.trim();
  }

  Future<void> _submitInAppReport() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a brief title or summary.')),
      );
      return;
    }
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe what happened or what you need.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final version =
        'v${_packageInfo?.version ?? '2.1.2'} (Build ${_packageInfo?.buildNumber ?? '147'})';
    final submitted = await FeedbackService().submitFeedback(
      type: _selectedType.name,
      title: title,
      description: desc,
      contact: _contactController.text.trim(),
      appVersion: version,
      animeTitle: widget.initialAnimeTitle,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.pop(context);

    final githubUrl = submitted.githubIssueUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                githubUrl != null
                    ? 'Report submitted and tracked on GitHub!'
                    : 'Report submitted! Developer will review it for upcoming updates.',
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View Issues',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminIssuesScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child:
            !_showInAppForm
                ? _buildSelectionView(context, colorScheme, textTheme)
                : _buildFormView(context, colorScheme, textTheme),
      ),
    );
  }

  Widget _buildSelectionView(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Iconsax.message_question, color: colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            Text(
              'Report Issue / Feedback',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Select your preferred way to report an issue or request a new feature:',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // Option 1: In-App Feedback
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Iconsax.edit, color: colorScheme.primary),
            ),
            title: const Text(
              'In-App Feedback (No Account Needed)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Report bugs, request anime, or share feedback directly inside the app.',
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => setState(() => _showInAppForm = true),
          ),
        ),
        const SizedBox(height: 10),

        // Option: View Community Issues & Discussions In-App
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Iconsax.task, color: colorScheme.primary),
            ),
            title: const Text(
              'Community Feedback & Issues',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'View reported issues, dev responses, and status right inside the app.',
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminIssuesScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Option 2: GitHub Issue
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
              child: Icon(Iconsax.code, color: colorScheme.onSurface),
            ),
            title: const Text(
              'GitHub Issue Tracker',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'For users with a GitHub account. Track replies and discussions.',
            ),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16),
            onTap: () {
              Navigator.pop(context);
              launchUrl(
                Uri.parse(
                  'https://github.com/anshdeepofficial1/AniDash/issues/new/choose',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Quick Share Option
        ListTile(
          dense: true,
          leading: const Icon(Iconsax.share, size: 20),
          title: const Text('Share Diagnostic Template'),
          subtitle: const Text('Send details via Telegram, WhatsApp, or Email'),
          onTap: () async {
            final report = _buildFormattedReport();
            Navigator.pop(context);
            await SharePlus.instance.share(
              ShareParams(
                text: report,
                subject: 'AniDash Issue Report',
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFormView(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _showInAppForm = false),
            ),
            Text(
              'Submit In-App Report',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Category Choice Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                FeedbackType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        type.icon,
                        size: 16,
                        color:
                            isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                      ),
                      label: Text(type.label),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedType = type);
                      },
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Title Field
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Summary / Title *',
            hintText: 'e.g. Subtitles out of sync or Season missing',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Description Field
        TextField(
          controller: _descController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Details / Description *',
            hintText:
                'What happened, which anime or episode, and what you expected...',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Contact Field (Optional)
        TextField(
          controller: _contactController,
          decoration: InputDecoration(
            labelText: 'Contact Info (Optional)',
            hintText: 'Email or Telegram so we can follow up',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Device Diagnostic Chip
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              'AniDash v${_packageInfo?.version ?? '2.1.2'} • ${Platform.operatingSystem}',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Submit Button
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submitInAppReport,
          icon:
              _isSubmitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.send_rounded),
          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Report'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
