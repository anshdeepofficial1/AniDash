import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ani_dash/features/ai/application/ai_orchestrator.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/features/ai/domain/assistant_registry.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/ai/data/ai_state_repository.dart';
import 'package:ani_dash/features/ai/application/ai_action_executor.dart';
import 'package:ani_dash/features/ai/view/widgets/assistant_avatar.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/ui/voice_text_button.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({
    super.key,
    this.contextData = const AiContext(),
    this.sharedChatId,
  });
  final AiContext contextData;
  final String? sharedChatId;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMessage {
  _ChatMessage({
    required this.text,
    required this.fromUser,
    this.assistantId,
    this.actions = const [],
  });
  String text;
  final bool fromUser;
  final String? assistantId;
  final List<AiAction> actions;

  Map<String, Object?> toJson() => {
    'text': text,
    'fromUser': fromUser,
    'assistantId': assistantId,
    'actions':
        actions
            .map(
              (action) => {
                'type': action.type,
                'capability': action.capability.name,
                'arguments': action.arguments,
                'label': action.label,
              },
            )
            .toList(),
  };

  factory _ChatMessage.fromJson(Map<String, Object?> json) => _ChatMessage(
    text: json['text']?.toString() ?? '',
    fromUser: json['fromUser'] == true,
    assistantId: json['assistantId']?.toString(),
    actions: (json['actions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AiAction.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false),
  );
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _orchestrator = AiOrchestrator();
  final _registry = AssistantRegistry();
  final _stateRepository = AiStateRepository();
  final List<_ChatMessage> _messages = [];
  final List<AiAttachment> _attachments = [];
  StreamSubscription<AiStreamEvent>? _subscription;
  bool _busy = false;
  AnimeWatchProgressEntry? _undoProgress;
  final Set<String> _completedActionKeys = <String>{};
  final FlutterTts _tts = FlutterTts();
  int? _speakingMessage;
  late String _conversationId;

  @override
  void initState() {
    super.initState();
    _conversationId =
        _stateRepository.activeConversationId ??
        'chat_${DateTime.now().millisecondsSinceEpoch}';
    final conversation = _stateRepository.messagesFor(_conversationId);
    final saved =
        conversation.isNotEmpty ? conversation : _stateRepository.chatHistory;
    if (saved.isNotEmpty) {
      _messages.addAll(saved.map(_ChatMessage.fromJson));
    } else {
      _messages.add(
        _ChatMessage(
          text:
              widget.contextData.animeTitle == null
                  ? 'Ask me about anime, manga, your library, watch orders, or AniDash.'
                  : 'Ask me anything about ${widget.contextData.animeTitle}.',
          fromUser: false,
          assistantId: 'anime_text',
        ),
      );
    }
    _controller.addListener(_composerChanged);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingMessage = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speakingMessage = null);
    });
    unawaited(_tts.setLanguage('en-IN'));
    unawaited(_tts.setSpeechRate(.46));
    unawaited(_tts.setPitch(1.0));
    if (widget.sharedChatId != null) unawaited(_loadSharedChat());
  }

  Future<void> _loadSharedChat() async {
    final shared = await _stateRepository.loadSharedChat(widget.sharedChatId!);
    if (!mounted || shared.isEmpty) return;
    setState(() {
      _conversationId = 'shared_${widget.sharedChatId}';
      _messages
        ..clear()
        ..addAll(shared.map(_ChatMessage.fromJson));
    });
    await _persistHistory();
  }

  String get _conversationTitle {
    _ChatMessage? first;
    for (final message in _messages) {
      if (message.fromUser) {
        first = message;
        break;
      }
    }
    if (first == null) return 'New chat';
    return first.text.length > 42
        ? '${first.text.substring(0, 42)}…'
        : first.text;
  }

  Future<void> _persistHistory() async {
    final messages =
        _messages
            .where((message) => message.text.isNotEmpty)
            .map((message) => message.toJson())
            .toList();
    await _stateRepository.saveChatHistory(messages);
    await _stateRepository.saveConversation(
      id: _conversationId,
      title: _conversationTitle,
      messages: messages,
    );
  }

  Future<void> _newConversation() async {
    await _persistHistory();
    if (!mounted) return;
    setState(() {
      _conversationId = 'chat_${DateTime.now().millisecondsSinceEpoch}';
      _messages
        ..clear()
        ..add(_welcomeMessage());
    });
    await _persistHistory();
  }

  _ChatMessage _welcomeMessage() => _ChatMessage(
    text:
        widget.contextData.animeTitle == null
            ? 'Ask me about anime, manga, your library, watch orders, or AnyCore.'
            : 'Ask me anything about ${widget.contextData.animeTitle}.',
    fromUser: false,
    assistantId: 'anime_text',
  );

  Future<void> _openConversation(String id) async {
    await _persistHistory();
    final saved = _stateRepository.messagesFor(id);
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _conversationId = id;
      _messages
        ..clear()
        ..addAll(saved.map(_ChatMessage.fromJson));
    });
    await _stateRepository.setActiveConversation(id);
  }

  Future<void> _shareMessages(List<_ChatMessage> messages) async {
    try {
      final link = await _stateRepository.createShareLink(
        messages.map((message) => message.toJson()).toList(),
        title:
            messages.length == 1 ? 'Shared AnyCore reply' : _conversationTitle,
      );
      await SharePlus.instance.share(
        ShareParams(text: link, subject: 'Shared from AnyCore'),
      );
    } catch (_) {
      final textContent = messages.map((message) {
        final prefix = message.fromUser ? 'You: ' : 'AniDash AI: ';
        return '$prefix${message.text}';
      }).join('\n\n');
      if (textContent.trim().isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            text: textContent,
            subject:
                messages.length == 1
                    ? 'Shared AnyCore reply'
                    : _conversationTitle,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the share link.')),
        );
      }
    }
  }

  Future<void> _showMessageActions(_ChatMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy message'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share message'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _shareMessages([message]);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _clearHistory() async {
    await _stateRepository.clearChatHistory();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(
          _ChatMessage(
            text: 'Chat cleared. What would you like to explore next?',
            fromUser: false,
            assistantId: 'anime_text',
          ),
        );
    });
  }

  void _composerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_persistHistory());
    _subscription?.cancel();
    _controller.removeListener(_composerChanged);
    _controller.dispose();
    _scroll.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleSpeech(int index, String markdown) async {
    if (_speakingMessage == index) {
      await _tts.stop();
      if (mounted) setState(() => _speakingMessage = null);
      return;
    }
    await _tts.stop();
    final plainText =
        markdown
            .replaceAll(RegExp(r'[`*_>#\[\]]'), '')
            .replaceAll(RegExp(r'\((https?://[^)]+)\)'), '')
            .trim();
    if (plainText.isEmpty) return;
    if (mounted) setState(() => _speakingMessage = index);
    await _tts.speak(plainText);
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    if (text.startsWith('/') &&
        !text.toLowerCase().startsWith('/edit ') &&
        !(sharedPrefs.getBool('ai_command_education_seen') ?? false)) {
      final proceed = await _showCommandEducation(text.split(' ').first);
      if (!proceed) return;
      await sharedPrefs.setBool('ai_command_education_seen', true);
    }
    if (text.toLowerCase() == '/undo' && _undoProgress != null) {
      await ref
          .read(watchProgressRepositoryProvider)
          .saveProgress(_undoProgress!);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: text, fromUser: true));
        _messages.add(
          _ChatMessage(
            text: 'The last supported AnyCore change was restored.',
            fromUser: false,
            assistantId: 'action',
          ),
        );
        _undoProgress = null;
        _controller.clear();
      });
      unawaited(_persistHistory());
      return;
    }
    final localEdit = _parseLocalEdit(text);
    if (localEdit != null) {
      setState(() {
        _messages.add(_ChatMessage(text: text, fromUser: true));
        _messages.add(
          _ChatMessage(
            text: localEdit.text,
            fromUser: false,
            assistantId: localEdit.assistantId,
            actions: localEdit.actions,
          ),
        );
        _controller.clear();
      });
      unawaited(_persistHistory());
      _scrollToEnd();
      return;
    }
    final localRead = _localReadResponse(text);
    if (localRead != null) {
      setState(() {
        _messages.add(_ChatMessage(text: text, fromUser: true));
        _messages.add(localRead);
        _controller.clear();
      });
      unawaited(_persistHistory());
      _scrollToEnd();
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(text: text, fromUser: true));
      _messages.add(_ChatMessage(text: '', fromUser: false));
      _controller.clear();
      _busy = true;
    });
    var accumulated = '';
    final attachments = List<AiAttachment>.from(_attachments);
    _attachments.clear();
    await _subscription?.cancel();
    _subscription = _orchestrator
        .send(
          message: text,
          context: _contextFor(text),
          attachments: attachments,
        )
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              if (event.type == AiStreamEventType.textDelta) {
                accumulated += event.text ?? '';
                _messages.last.text = accumulated;
              } else if (event.type == AiStreamEventType.error) {
                _messages.last.text = event.text ?? 'Something went wrong.';
                _busy = false;
                unawaited(_persistHistory());
              } else if (event.type == AiStreamEventType.done &&
                  event.response != null) {
                final response = event.response!;
                if (text.toLowerCase().startsWith('/plan ') &&
                    response.actions.any(
                      (action) => action.type == 'openArc',
                    )) {
                  final actionAnimeIds =
                      response.actions
                          .map((action) => action.arguments['animeId'])
                          .whereType<Object>()
                          .map((value) => value.toString())
                          .toList();
                  final animeId =
                      widget.contextData.animeId ??
                      (actionAnimeIds.isEmpty ? null : actionAnimeIds.first);
                  if (animeId != null) {
                    unawaited(
                      _stateRepository.savePlan(
                        AnimeWatchPlan(
                          id: 'plan-$animeId',
                          title: text.substring('/plan'.length).trim(),
                          animeId: animeId,
                          groups:
                              response.actions
                                  .where((action) => action.type == 'openArc')
                                  .map(
                                    (action) => Map<String, Object?>.from(
                                      action.arguments,
                                    ),
                                  )
                                  .toList(),
                          createdAt: DateTime.now(),
                        ),
                      ),
                    );
                  }
                }
                _messages.removeLast();
                if (response.handoffFrom != null &&
                    response.handoffTo != null) {
                  final from =
                      _registry.byId(response.handoffFrom!).displayName;
                  final to = _registry.byId(response.handoffTo!).displayName;
                  _messages.add(
                    _ChatMessage(
                      text: '$from handed this to $to',
                      fromUser: false,
                    ),
                  );
                }
                _messages.add(
                  _ChatMessage(
                    text:
                        response.text.trim().isEmpty
                            ? 'I could not complete that response. Please try once more.'
                            : response.text,
                    fromUser: false,
                    assistantId: response.assistantId,
                    actions: response.actions,
                  ),
                );
                _busy = false;
                unawaited(_persistHistory());
              }
            });
            _scrollToEnd();
          },
          onDone: () {
            if (mounted && _busy) {
              setState(() {
                if (_messages.isNotEmpty && _messages.last.text.isEmpty) {
                  _messages.last.text =
                      'I could not complete that response. Please try once more.';
                }
                _busy = false;
              });
              unawaited(_persistHistory());
            }
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              if (_messages.isNotEmpty && _messages.last.text.isEmpty) {
                _messages.last.text =
                    'AnyCore could not connect. Check your internet and retry.';
              }
              _busy = false;
            });
            unawaited(_persistHistory());
          },
        );
  }

  AiResponse? _parseLocalEdit(String input) {
    final normalized = input.trim().toLowerCase();
    if (!normalized.startsWith('/edit ')) return null;
    final animeId = widget.contextData.animeId;
    if (animeId == null) return null;
    final range = RegExp(
      r'(?:till|until|through|up to|upto)\s*(?:ep(?:isode)?\s*)?(\d+)',
    ).firstMatch(normalized);
    final asksWatched = normalized.contains('watch');
    if (range == null || !asksWatched) return null;
    final endEpisode = int.tryParse(range.group(1) ?? '');
    if (endEpisode == null || endEpisode < 1 || endEpisode > 10000) return null;
    return AiResponse(
      text:
          'I can mark episodes 1–$endEpisode as watched. Review and confirm this change below.',
      assistantId: 'action',
      actions: [
        AiAction(
          type: 'markEpisodesWatched',
          capability: AiCapability.write,
          arguments: {
            'animeId': animeId,
            'startEpisode': 1,
            'endEpisode': endEpisode,
          },
          label: 'Mark episodes 1–$endEpisode watched',
        ),
      ],
    );
  }

  _ChatMessage? _localReadResponse(String input) {
    final normalized = input.trim().toLowerCase();
    if (RegExp(
      r'^(hi|hey|hello|hiya|yo|namaste|good morning|good afternoon|good evening)[!. ]*$',
    ).hasMatch(normalized)) {
      return _ChatMessage(
        text:
            'Hi! I’m Nia. Ask me about anime, your watch progress, episode order, arcs, fillers, or anything inside AniDash.',
        fromUser: false,
        assistantId: 'anime_text',
      );
    }
    final asksProgress =
        normalized.contains('how many') &&
            (normalized.contains('watched') ||
                normalized.contains('episode')) ||
        normalized.contains('where am i') ||
        normalized.contains('my progress');
    if (!asksProgress) return null;
    final entries = ref.read(watchProgressRepositoryProvider).getAllProgress();
    if (entries.isEmpty) {
      return _ChatMessage(
        text:
            'You do not have any saved watch progress on this device yet. Play an episode or mark one as watched, then I can report it here.',
        fromUser: false,
        assistantId: 'anime_text',
      );
    }
    AnimeWatchProgressEntry? match;
    for (final entry in entries) {
      final title = entry.animeTitle.toLowerCase();
      if (normalized.contains(title) ||
          title
              .split(RegExp(r'\s+'))
              .where((word) => word.length > 3)
              .any(normalized.contains)) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      final sorted =
          entries.toList()..sort(AnimeWatchProgressEntry.compareByRecency);
      match = sorted.first;
    }
    final resolved = match;
    final completed =
        resolved.episodesProgress.values
            .where((episode) => episode.isCompleted)
            .length;
    final totalText =
        resolved.totalEpisodes > 0 ? ' of ${resolved.totalEpisodes}' : '';
    return _ChatMessage(
      text:
          '**${resolved.animeTitle}**\n\n- Current episode: **${resolved.currentEpisode}**\n- Completed locally: **$completed$totalText episodes**\n- Status: **${resolved.status}**',
      fromUser: false,
      assistantId: 'anime_text',
    );
  }

  AiContext _contextFor(String message) {
    final entries = ref.read(watchProgressRepositoryProvider).getAllProgress();
    final statusCounts = <String, int>{};
    for (final entry in entries) {
      statusCounts.update(
        entry.status,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final recent =
        entries.toList()..sort(
          (a, b) =>
              b.effectiveLastPlayedTime.compareTo(a.effectiveLastPlayedTime),
        );
    return AiContext(
      animeId: widget.contextData.animeId,
      animeTitle: widget.contextData.animeTitle,
      currentEpisode: widget.contextData.currentEpisode,
      sourceRoute: widget.contextData.sourceRoute,
      conversationHistory:
          _messages
              .where((item) => item.text.trim().isNotEmpty)
              .take(_messages.length)
              .toList()
              .reversed
              .take(12)
              .toList()
              .reversed
              .map(
                (item) => <String, Object?>{
                  'role': item.fromUser ? 'user' : 'assistant',
                  'content': item.text,
                },
              )
              .toList(),
      librarySummary: {
        'statusCounts': statusCounts,
        'recentTitles':
            recent.take(10).map((entry) => entry.animeTitle).toList(),
        'progress': recent
            .take(30)
            .map(
              (entry) => {
                'animeId': entry.animeId,
                'title': entry.animeTitle,
                'currentEpisode': entry.currentEpisode,
                'completedEpisodes':
                    entry.episodesProgress.values
                        .where((episode) => episode.isCompleted)
                        .length,
                'totalEpisodes': entry.totalEpisodes,
                'status': entry.status,
              },
            )
            .toList(growable: false),
      },
    );
  }

  Future<bool> _showCommandEducation(String command) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                command == '/edit' ? 'Make changes with AI' : 'AniDash command',
              ),
              content: Text(
                command == '/edit'
                    ? '/edit can change watch status, episode progress, and your library. Large changes always ask for confirmation.'
                    : '$command is a special AnyCore command. Normal anime questions do not need commands.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Got it'),
                ),
              ],
            ),
      ) ??
      false;

  Future<void> _pickImage(bool screenshot) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    if (bytes.length > 8 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an image smaller than 8 MB.')),
      );
      return;
    }
    final extension = (file.extension ?? 'jpg').toLowerCase();
    final mime = extension == 'png' ? 'image/png' : 'image/jpeg';
    setState(
      () => _attachments.add(
        AiAttachment(
          type:
              screenshot ? AiAttachmentType.screenshot : AiAttachmentType.image,
          value: 'data:$mime;base64,${base64Encode(bytes)}',
          label: file.name,
        ),
      ),
    );
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  });

  Future<void> _runAction(
    AiAction action, {
    bool alreadyConfirmed = false,
    bool silent = false,
  }) async {
    final actionKey = '${action.type}:${jsonEncode(action.arguments)}';
    if (_completedActionKeys.contains(actionKey)) return;
    final id = action.arguments['animeId']?.toString();
    switch (action.type) {
      case 'openAnime':
        if (id != null) context.push('/details/$id');
        return;
      case 'openEpisode':
      case 'openArc':
        if (id != null) context.push('/details/$id?tab=episodes');
        return;
      case 'markEpisodeWatched':
      case 'markEpisodesWatched':
      case 'setWatchStatus':
        final animeId = id ?? widget.contextData.animeId;
        if (animeId == null) return;
        final confirmed =
            alreadyConfirmed
                ? true
                : await showDialog<bool>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('Confirm change'),
                            content: Text(
                              action.label ??
                                  'AniDash will update your watch progress.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Confirm Changes'),
                              ),
                            ],
                          ),
                    ) ??
                    false;
        if (!confirmed || !mounted) return;
        _ChatMessage? progressMessage;
        if (!silent) {
          progressMessage = _ChatMessage(
            text: 'Checking your current AniDash progress…',
            fromUser: false,
            assistantId: 'action',
          );
          setState(() => _messages.add(progressMessage!));
          _scrollToEnd();
        }
        void report(String value) {
          if (!mounted || progressMessage == null) return;
          setState(() => progressMessage!.text = value);
          _scrollToEnd();
        }
        final repo = ref.read(watchProgressRepositoryProvider);
        final executor = AiActionExecutor(stateRepository: _stateRepository);
        executor.register(action.type, (arguments) async {
          final existing = repo.getProgress(animeId);
          _undoProgress = existing;
          final episode =
              int.tryParse(arguments['episode']?.toString() ?? '') ??
              widget.contextData.currentEpisode ??
              1;
          final progress = Map<int, EpisodeProgress>.from(
            existing?.episodesProgress ?? const {},
          );
          if (action.type == 'markEpisodeWatched' ||
              action.type == 'markEpisodesWatched') {
            final start =
                action.type == 'markEpisodesWatched'
                    ? int.tryParse(
                          arguments['startEpisode']?.toString() ?? '',
                        ) ??
                        1
                    : episode;
            final end =
                action.type == 'markEpisodesWatched'
                    ? int.tryParse(arguments['endEpisode']?.toString() ?? '') ??
                        episode
                    : episode;
            report(
              start == end
                  ? 'Marking episode $start as watched…'
                  : 'Updating episodes $start–$end…',
            );
            for (var current = start; current <= end; current++) {
              final old = progress[current];
              progress[current] = EpisodeProgress(
                episodeNumber: current,
                episodeTitle: old?.episodeTitle ?? 'Episode $current',
                episodeThumbnail: old?.episodeThumbnail,
                progressInSeconds: old?.durationInSeconds ?? 1440,
                durationInSeconds: old?.durationInSeconds ?? 1440,
                isCompleted: true,
                watchedAt: DateTime.now(),
              );
              if (!silent &&
                  (current == end || (current - start + 1) % 25 == 0)) {
                report('Updated $current of $end episodes…');
                await Future<void>.delayed(Duration.zero);
              }
            }
          }
          final resultingEpisode =
              action.type == 'markEpisodesWatched'
                  ? int.tryParse(arguments['endEpisode']?.toString() ?? '') ??
                      episode
                  : episode;
          final updated = (existing ??
                  AnimeWatchProgressEntry(
                    animeId: animeId,
                    animeTitle: widget.contextData.animeTitle ?? 'Anime',
                    animeCover: '',
                    totalEpisodes: 0,
                    currentEpisode: resultingEpisode,
                    episodesProgress: progress,
                  ))
              .copyWith(
                currentEpisode: resultingEpisode,
                episodesProgress: progress,
                status:
                    action.type == 'setWatchStatus'
                        ? arguments['status']?.toString()
                        : existing?.status,
                lastUpdated: DateTime.now(),
              );
          report('Saving the updated progress to your library…');
          await repo.saveProgress(updated);
          return updated;
        });
        var completed = false;
        await for (final progress in executor.execute(
          [action],
          editAuthorized: true,
          destructiveConfirmed: false,
        )) {
          if (progress.state == 'completed') {
            completed = progress.completed == 1;
          }
        }
        if (!completed) {
          if (mounted && !silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('The change could not be completed.'),
              ),
            );
          }
          return;
        }
        if (mounted && !silent) {
          final auth = ref.read(authProvider);
          final destination = switch ((
            auth.isAniListAuthenticated,
            auth.isMalAuthenticated,
          )) {
            (true, true) =>
              'locally; AniList and MyAnimeList are connected for app sync',
            (true, false) => 'locally; AniList is connected for app sync',
            (false, true) => 'locally; MyAnimeList is connected for app sync',
            _ => 'locally on this device',
          };
          report('Done — your progress was saved $destination.');
          _completedActionKeys.add(actionKey);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('AniDash updated your progress.'),
              action:
                  _undoProgress == null
                      ? null
                      : SnackBarAction(
                        label: 'UNDO',
                        onPressed: () => repo.saveProgress(_undoProgress!),
                      ),
            ),
          );
        }
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This action is not available in this build. No changes were made.',
            ),
          ),
        );
        return;
    }
  }

  Future<void> _runBulkActions(List<AiAction> actions) async {
    final writes = actions
        .where((action) => action.capability == AiCapability.write)
        .toList(growable: false);
    if (writes.isEmpty) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Confirm changes'),
                content: Text(
                  '${writes.length} AniDash items will be updated. You can cancel without changing anything.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm Changes'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final completed = ValueNotifier<int>(0);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Updating library'),
              content: ValueListenableBuilder<int>(
                valueListenable: completed,
                builder:
                    (_, value, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: writes.isEmpty ? 0 : value / writes.length,
                        ),
                        const SizedBox(height: 12),
                        Text('$value / ${writes.length} completed'),
                      ],
                    ),
              ),
            ),
      ),
    );
    for (final action in writes) {
      await _runAction(action, alreadyConfirmed: true, silent: true);
      completed.value++;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    completed.dispose();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${writes.length} changes completed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AssistantAvatar(
              assistantId: 'anime_text',
              size: 42,
              showStatus: true,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask ${_registry.byId('anime_text').displayName}'),
                const Text(
                  '4 specialists, one conversation',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: (value) async {
              if (value == 'clear') _clearHistory();
              if (value == 'new') await _newConversation();
              if (value == 'chats') {
                if (!context.mounted) return;
                await showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder:
                      (sheetContext) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            const ListTile(
                              title: Text('Your chats'),
                              subtitle: Text(
                                'Choose a conversation to continue',
                              ),
                            ),
                            ..._stateRepository.conversations.map(
                              (chat) => ListTile(
                                leading: const Icon(Icons.chat_bubble_outline),
                                title: Text(
                                  chat['title']?.toString() ?? 'Chat',
                                ),
                                selected: chat['id'] == _conversationId,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openConversation(chat['id'].toString());
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                );
              }
              if (value == 'share') {
                await _shareMessages(
                  _messages
                      .where((message) => message.text.isNotEmpty)
                      .toList(),
                );
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'new',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_comment_outlined),
                      title: Text('New chat'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'chats',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.forum_outlined),
                      title: Text('Your chats'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share_outlined),
                      title: Text('Share chat'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Clear chat history'),
                    ),
                  ),
                ],
          ),
          IconButton(
            tooltip: 'AI settings',
            onPressed: () => context.push('/settings/ai'),
            icon: const Icon(Iconsax.setting_2),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final item = _messages[index];
                final profile =
                    item.assistantId == null
                        ? null
                        : _registry.byId(item.assistantId!);
                final visual = AssistantVisual.forId(item.assistantId);
                final motion =
                    item.text.isEmpty
                        ? AssistantMotion.thinking
                        : item.assistantId == 'action' &&
                            (item.text.contains('…') ||
                                item.text.contains('â€¦'))
                        ? AssistantMotion.working
                        : item.assistantId == 'action' &&
                            item.text.toLowerCase().startsWith('done')
                        ? AssistantMotion.success
                        : AssistantMotion.idle;
                return Align(
                  alignment:
                      item.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!item.fromUser) ...[
                        AssistantAvatar(
                          assistantId: item.assistantId,
                          size: 38,
                          motion: motion,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: GestureDetector(
                          onLongPress:
                              item.text.isEmpty
                                  ? null
                                  : () => _showMessageActions(item),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 560),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  item.fromUser
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerHigh,
                              border:
                                  item.fromUser
                                      ? null
                                      : Border.all(
                                        color: visual.color.withValues(
                                          alpha: .22,
                                        ),
                                      ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(
                                  item.fromUser ? 18 : 6,
                                ),
                                topRight: Radius.circular(
                                  item.fromUser ? 6 : 18,
                                ),
                                bottomLeft: const Radius.circular(18),
                                bottomRight: const Radius.circular(18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (profile != null)
                                  Text(
                                    profile.displayName,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: visual.color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (item.text.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      '${profile?.displayName ?? 'Nia'} is thinking…',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: visual.color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  )
                                else
                                  item.fromUser
                                      ? SelectableText(item.text)
                                      : MarkdownBody(
                                        data: item.text,
                                        selectable: true,
                                        shrinkWrap: true,
                                      ),
                                if (item.text.isNotEmpty && !item.fromUser) ...[
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!item.fromUser)
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip:
                                                _speakingMessage == index
                                                    ? 'Stop speaking'
                                                    : 'Read aloud',
                                            iconSize: 17,
                                            onPressed:
                                                () => _toggleSpeech(
                                                  index,
                                                  item.text,
                                                ),
                                            icon: Icon(
                                              _speakingMessage == index
                                                  ? Icons.stop_circle_outlined
                                                  : Icons.volume_up_outlined,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (item.actions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (item.actions
                                              .where(
                                                (action) =>
                                                    action.capability ==
                                                    AiCapability.write,
                                              )
                                              .length >
                                          1)
                                        ActionChip(
                                          avatar: const Icon(
                                            Icons.checklist_rounded,
                                          ),
                                          label: Text(
                                            'Review ${item.actions.where((action) => action.capability == AiCapability.write).length} changes',
                                          ),
                                          onPressed:
                                              () =>
                                                  _runBulkActions(item.actions),
                                        ),
                                      ...item.actions.map(
                                        (action) => ActionChip(
                                          label: Text(
                                            action.label ?? action.type,
                                          ),
                                          onPressed:
                                              _completedActionKeys.contains(
                                                    '${action.type}:${jsonEncode(action.arguments)}',
                                                  )
                                                  ? null
                                                  : () => _runAction(action),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children:
                    _attachments
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(item.label ?? 'Image'),
                              onDeleted:
                                  () =>
                                      setState(() => _attachments.remove(item)),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          if (_controller.text.startsWith('/') &&
              !_controller.text.contains(' '))
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children:
                    ['/edit', '/plan', '/undo']
                        .map(
                          (command) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(command),
                              onPressed: () => _controller.text = '$command ',
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Add',
                    icon: const Icon(Icons.add_circle_outline),
                    onSelected: (value) {
                      if (value == 'image') _pickImage(false);
                      if (value == 'anime' &&
                          widget.contextData.animeId != null) {
                        setState(
                          () => _attachments.add(
                            AiAttachment(
                              type: AiAttachmentType.anime,
                              value: widget.contextData.animeId!,
                              label:
                                  widget.contextData.animeTitle ??
                                  'Selected anime',
                            ),
                          ),
                        );
                      }
                      if (value == 'episode' &&
                          widget.contextData.currentEpisode != null) {
                        setState(
                          () => _attachments.add(
                            AiAttachment(
                              type: AiAttachmentType.episode,
                              value:
                                  widget.contextData.currentEpisode!.toString(),
                              label:
                                  'Episode ${widget.contextData.currentEpisode}',
                            ),
                          ),
                        );
                      }
                      if (value.startsWith('/')) _controller.text = '$value ';
                    },
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem(
                            value: '/edit',
                            child: Text('/edit  Make changes'),
                          ),
                          const PopupMenuItem(
                            value: '/plan',
                            child: Text('/plan  Create watch plan'),
                          ),
                          const PopupMenuItem(
                            value: '/undo',
                            child: Text('/undo  Undo last supported change'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'image',
                            child: Text('Add image or screenshot'),
                          ),
                          PopupMenuItem(
                            value: 'anime',
                            enabled: widget.contextData.animeId != null,
                            child: const Text('Select current anime'),
                          ),
                          PopupMenuItem(
                            value: 'episode',
                            enabled: widget.contextData.currentEpisode != null,
                            child: const Text('Select current episode'),
                          ),
                        ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about anime…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  VoiceTextButton(
                    controller: _controller,
                    tooltip: 'Speak your message',
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Iconsax.send_1),
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
