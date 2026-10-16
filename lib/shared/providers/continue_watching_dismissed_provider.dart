import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/main.dart';

const _kDismissedContinueWatchingKey = 'dismissed_continue_watching_ids';

final continueWatchingDismissedProvider =
    NotifierProvider<ContinueWatchingDismissedNotifier, Set<String>>(
      ContinueWatchingDismissedNotifier.new,
    );

class ContinueWatchingDismissedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final list =
        sharedPrefs.getStringList(_kDismissedContinueWatchingKey) ?? [];
    return list.toSet();
  }

  void stageDismiss(String animeId) {
    state = {...state, animeId};
  }

  void undoDismiss(String animeId) {
    state = Set<String>.from(state)..remove(animeId);
  }

  Future<void> commitDismiss(String animeId, WidgetRef ref) async {
    state = {...state, animeId};
    await sharedPrefs.setStringList(
      _kDismissedContinueWatchingKey,
      state.toList(),
    );
    await ref.read(watchProgressRepositoryProvider).deleteProgress(animeId);
  }

  Future<void> restoreIfWatched(String animeId) async {
    if (state.contains(animeId)) {
      state = Set<String>.from(state)..remove(animeId);
      await sharedPrefs.setStringList(
        _kDismissedContinueWatchingKey,
        state.toList(),
      );
    }
  }
}

/// Displays a bottom snackbar with a 5-second countdown timer, Undo, and Skip options.
void showContinueWatchingUndoSnackBar({
  required BuildContext context,
  required WidgetRef ref,
  required String animeId,
  required String animeTitle,
}) {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  scaffoldMessenger.removeCurrentSnackBar();

  // Stage removal in state immediately
  ref.read(continueWatchingDismissedProvider.notifier).stageDismiss(animeId);

  int remainingSeconds = 5;
  Timer? timer;
  bool isActionTaken = false;

  final controller = scaffoldMessenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: StatefulBuilder(
        builder: (context, setSnackBarState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remainingSeconds > 1) {
              setSnackBarState(() {
                remainingSeconds--;
              });
            } else {
              t.cancel();
            }
          });

          return Row(
            children: [
              Expanded(
                child: Text(
                  'Removed from Continue (${remainingSeconds}s)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  if (isActionTaken) return;
                  isActionTaken = true;
                  timer?.cancel();
                  ref
                      .read(continueWatchingDismissedProvider.notifier)
                      .undoDismiss(animeId);
                  scaffoldMessenger.hideCurrentSnackBar();
                },
                child: const Text(
                  'Undo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (isActionTaken) return;
                  isActionTaken = true;
                  timer?.cancel();
                  ref
                      .read(continueWatchingDismissedProvider.notifier)
                      .commitDismiss(animeId, ref);
                  scaffoldMessenger.hideCurrentSnackBar();
                },
                child: const Text('Skip'),
              ),
            ],
          );
        },
      ),
    ),
  );

  controller.closed.then((reason) {
    timer?.cancel();
    // A route change or an unrelated snackbar can hide/replace this snackbar.
    // That must never silently delete Continue Watching history. Commit only
    // when the countdown really expires or the user explicitly swipes it away.
    final shouldCommit =
        reason == SnackBarClosedReason.timeout ||
        reason == SnackBarClosedReason.swipe;
    if (!isActionTaken && shouldCommit) {
      isActionTaken = true;
      ref
          .read(continueWatchingDismissedProvider.notifier)
          .commitDismiss(animeId, ref);
    } else if (!isActionTaken) {
      isActionTaken = true;
      ref.read(continueWatchingDismissedProvider.notifier).undoDismiss(animeId);
    }
  });
}
