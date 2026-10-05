import 'dart:async';
import 'package:ani_dash/features/ai/data/ai_policy.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/features/ai/data/ai_state_repository.dart';

typedef AiActionHandler =
    Future<Object?> Function(Map<String, Object?> arguments);

class AiActionExecutor {
  AiActionExecutor({AiPolicy? policy, AiStateRepository? stateRepository})
    : _policy = policy ?? AiPolicy(),
      _stateRepository = stateRepository;
  final AiPolicy _policy;
  final AiStateRepository? _stateRepository;
  final Map<String, AiActionHandler> _handlers = {};
  final Map<String, List<AiAction>> _undo = {};

  static const allowedTools = <String>{
    'searchAnime',
    'getAnime',
    'getEpisodes',
    'getNamedEpisodeGroups',
    'getFillerEpisodes',
    'getUserAnimeProgress',
    'getRecommendations',
    'openAnime',
    'openEpisode',
    'openArc',
    'markEpisodeWatched',
    'markEpisodesWatched',
    'setWatchStatus',
    'addToWatchlist',
    'removeFromWatchlist',
  };

  void register(String tool, AiActionHandler handler) {
    if (!allowedTools.contains(tool)) {
      throw ArgumentError('Tool is not allowlisted');
    }
    _handlers[tool] = handler;
  }

  Stream<AiActionProgress> execute(
    List<AiAction> actions, {
    required bool editAuthorized,
    required bool destructiveConfirmed,
  }) async* {
    final jobId = DateTime.now().microsecondsSinceEpoch.toString();
    final executable = actions
        .where((action) {
          if (!allowedTools.contains(action.type)) return false;
          if (!_policy.canExecute(action, editAuthorized: editAuthorized)) {
            return false;
          }
          if (action.capability == AiCapability.destructive &&
              !destructiveConfirmed) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    yield AiActionProgress(
      jobId: jobId,
      state: 'started',
      completed: 0,
      total: executable.length,
    );
    await _stateRepository?.saveJob(
      jobId: jobId,
      state: 'started',
      completed: 0,
      total: executable.length,
    );
    var completed = 0;
    for (final action in executable) {
      yield AiActionProgress(
        jobId: jobId,
        state: 'itemStarted',
        completed: completed,
        total: executable.length,
        item: action.label ?? action.type,
      );
      try {
        final handler = _handlers[action.type];
        if (handler == null) {
          throw StateError(
            'This action is not available in this AniDash build.',
          );
        }
        await handler(action.arguments);
        completed++;
        await _stateRepository?.saveJob(
          jobId: jobId,
          state: 'progress',
          completed: completed,
          total: executable.length,
        );
        yield AiActionProgress(
          jobId: jobId,
          state: 'itemCompleted',
          completed: completed,
          total: executable.length,
          item: action.label ?? action.type,
        );
      } catch (error) {
        yield AiActionProgress(
          jobId: jobId,
          state: 'itemFailed',
          completed: completed,
          total: executable.length,
          item: action.label ?? action.type,
          error: error.toString(),
        );
      }
    }
    yield AiActionProgress(
      jobId: jobId,
      state: 'completed',
      completed: completed,
      total: executable.length,
    );
    await _stateRepository?.saveJob(
      jobId: jobId,
      state: 'completed',
      completed: completed,
      total: executable.length,
    );
  }

  void saveUndo(String jobId, List<AiAction> inverseActions) {
    if (inverseActions.isNotEmpty) {
      _undo[jobId] = List.unmodifiable(inverseActions);
    }
  }

  List<AiAction>? takeUndo(String jobId) => _undo.remove(jobId);
}
