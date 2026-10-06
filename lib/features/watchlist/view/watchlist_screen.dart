import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ani_dash/shared/ui/cards/anime/anime_card.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/ui/shonenx_gridview.dart';
import 'package:ani_dash/features/watchlist/view/widget/watchlist_states_widgets.dart';
import 'package:ani_dash/features/watchlist/view_model/watchlist_notifier.dart';
import 'package:ani_dash/features/watchlist/view_model/library_tabs_notifier.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:ani_dash/shared/providers/anime_repo_provider.dart';

import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/shared/providers/anilist_service_provider.dart';
import 'package:ani_dash/shared/providers/mal_service_provider.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/repositories/local_media_repository.dart';
import 'package:ani_dash/core/models/universal/universal_media_list_entry.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';

class WatchlistSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {...state}..remove(id);
    } else {
      state = {...state}..add(id);
    }
  }

  void clear() => state = {};

  void selectAll(List<String> ids) {
    state = {...state, ...ids};
  }
}

final watchlistSelectionProvider =
    NotifierProvider<WatchlistSelectionNotifier, Set<String>>(
      WatchlistSelectionNotifier.new,
    );

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen>
    with TickerProviderStateMixin {
  TabController? _controller;
  List<String> _statuses = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(animeRepositoryProvider);
    final baseStatuses = await repo.getSupportedStatuses();
    final allStatuses = [...baseStatuses, 'favorites'];

    await ref
        .read(libraryTabsProvider.notifier)
        .setAvailableStatuses(allStatuses);

    final visible = ref.read(libraryTabsProvider).visibleStatuses;
    _statuses = visible.isNotEmpty ? visible : List<String>.from(allStatuses);

    _controller = TabController(length: _statuses.length, vsync: this)
      ..addListener(() {
        if (_controller != null && _controller!.index != _index) {
          // Clear selection when changing tabs
          ref.read(watchlistSelectionProvider.notifier).clear();
          _index = _controller!.index;
          _fetch(_index);
        }
      });

    if (mounted) {
      setState(() {});
      _fetch(0);
    }
  }

  void _applyVisibleStatuses(List<String> visible) {
    if (visible.isEmpty || listEquals(_statuses, visible)) return;
    final prevIndex = _index;
    _controller?.dispose();
    _statuses = List<String>.from(visible);
    final newIndex =
        prevIndex >= _statuses.length
            ? (_statuses.length - 1).clamp(0, _statuses.length - 1)
            : prevIndex;
    _index = newIndex;
    _controller = TabController(
      length: _statuses.length,
      initialIndex: newIndex,
      vsync: this,
    )..addListener(() {
      if (_controller != null && _controller!.index != _index) {
        // Clear selection when changing tabs
        ref.read(watchlistSelectionProvider.notifier).clear();
        _index = _controller!.index;
        _fetch(_index);
      }
    });
    setState(() {});
    _fetch(_index);
  }

  Future<void> _fetch(int i, {bool force = false, int page = 1}) async {
    if (_statuses.isEmpty) return;
    if (_statuses.length <= i) return;

    await ref
        .read(watchlistProvider.notifier)
        .fetchListForStatus(_statuses[i], force: force, page: page);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _deleteSelected() async {
    final selectedIds = ref.read(watchlistSelectionProvider);
    if (selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Selected?'),
            content: Text(
              'Are you sure you want to delete ${selectedIds.length} items? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    final auth = ref.read(authProvider);
    final isLocal = ref.read(watchlistProvider).isLocal;

    try {
      final toDelete = List<String>.from(selectedIds);
      // Immediately remove from Watchlist UI state so it disappears instantly
      ref.read(watchlistProvider.notifier).removeEntries(toDelete);
      ref.read(watchlistSelectionProvider.notifier).clear();

      int successCount = 0;
      for (final idStr in toDelete) {
        final id = int.tryParse(idStr);

        // Delete from remote tracker if authenticated
        if (!isLocal && id != null) {
          try {
            if (auth.isAniListAuthenticated) {
              await ref.read(anilistServiceProvider).deleteUserAnimeList(id);
            } else if (auth.isMalAuthenticated) {
              await ref.read(malServiceProvider).deleteUserAnimeList(id);
            }
          } catch (e) {
            AppLogger.e('Remote delete failed for $idStr: $e');
          }
        }

        // Delete from local media repository
        try {
          await ref.read(localMediaRepoProvider).deleteEntry(idStr);
        } catch (_) {}

        // Delete from watch progress repository
        try {
          await ref.read(watchProgressRepositoryProvider).deleteProgress(idStr);
        } catch (_) {}

        // Dismiss from Continue Watching on Home Screen
        try {
          await ref
              .read(continueWatchingDismissedProvider.notifier)
              .commitDismiss(idStr, ref);
        } catch (_) {}

        successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted $successCount items')));
      }

      // Refresh current list with fresh network fetch
      _fetch(_index, force: true);
    } catch (e) {
      AppLogger.e('Failed to delete items: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LibraryTabsState>(libraryTabsProvider, (prev, next) {
      if (prev != null &&
          !listEquals(prev.visibleStatuses, next.visibleStatuses)) {
        _applyVisibleStatuses(next.visibleStatuses);
      }
    });

    if (_controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final isLocal = ref.watch(watchlistProvider.select((s) => s.isLocal));
    final selected = ref.watch(watchlistSelectionProvider);
    final isSelectionMode = selected.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading:
            isSelectionMode
                ? IconButton(
                  onPressed:
                      () =>
                          ref.read(watchlistSelectionProvider.notifier).clear(),
                  icon: const Icon(Icons.close),
                )
                : null,
        title:
            isSelectionMode
                ? Text('${selected.length} Selected')
                : const Text('Your Library'),
        actions: [
          if (isSelectionMode)
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Iconsax.trash, color: Colors.red),
            )
          else ...[
            const AskNiaButton(compact: true),
            if (auth.isAniListAuthenticated)
              Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: _ModeSwitch(isLocal: isLocal),
              ),
            IconButton(
              onPressed: () => _showCustomizeTabsSheet(context),
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Customize Tabs',
            ),
            const SizedBox(width: 8),
          ],
        ],
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          onTap: (i) => _fetch(i),
          tabs: _statuses.map((s) => Tab(text: _label(s))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: _statuses.map((s) => _WatchlistTabView(status: s)).toList(),
      ),
    );
  }

  void _showCustomizeTabsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final tabsState = ref.watch(libraryTabsProvider);
            final notifier = ref.read(libraryTabsProvider.notifier);
            final theme = Theme.of(context);
            final bottomPadding = MediaQuery.of(context).padding.bottom;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Customize Library Tabs',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => notifier.resetToDefault(),
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                    Text(
                      'Drag to reorder tabs or toggle switches to show/hide them.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: EdgeInsets.only(bottom: bottomPadding + 32),
                        itemCount: tabsState.allTabs.length,
                        onReorder:
                            (oldIdx, newIdx) =>
                                notifier.reorder(oldIdx, newIdx),
                        itemBuilder: (context, index) {
                          final tab = tabsState.allTabs[index];
                          final label = _label(tab.status);
                          final visibleCount =
                              tabsState.allTabs
                                  .where((t) => t.isVisible)
                                  .length;
                          final canHide = !tab.isVisible || visibleCount > 1;

                          return Container(
                            key: ValueKey(tab.status),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: Icon(
                                _tabIcon(tab.status),
                                color:
                                    tab.isVisible
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                              ),
                              title: Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      tab.isVisible
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.5),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: tab.isVisible,
                                    onChanged:
                                        canHide
                                            ? (_) => notifier.toggleVisibility(
                                              tab.status,
                                            )
                                            : null,
                                  ),
                                  const SizedBox(width: 8),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _tabIcon(String s) {
    switch (s.toLowerCase()) {
      case 'watching':
      case 'current':
        return Iconsax.play_circle;
      case 'completed':
        return Iconsax.tick_circle;
      case 'on_hold':
      case 'onhold':
      case 'paused':
        return Iconsax.pause_circle;
      case 'dropped':
        return Iconsax.close_circle;
      case 'plan_to_watch':
      case 'planning':
        return Iconsax.calendar;
      case 'favorites':
        return Iconsax.heart;
      default:
        return Iconsax.folder;
    }
  }

  String _label(String s) {
    switch (s.toLowerCase()) {
      case 'watching':
      case 'current':
        return 'Watching';
      case 'completed':
        return 'Completed';
      case 'on_hold':
      case 'onhold':
      case 'paused':
        return 'On Hold';
      case 'dropped':
        return 'Dropped';
      case 'plan_to_watch':
      case 'planning':
        return 'Plan to Watch';
      case 'favorites':
        return 'Favorites';
      default:
        return s.isNotEmpty
            ? s[0].toUpperCase() + s.substring(1).toLowerCase()
            : s;
    }
  }
}

class _ModeSwitch extends ConsumerWidget {
  final bool isLocal;
  const _ModeSwitch({required this.isLocal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwitchOption(
            label: 'Cloud',
            isSelected: !isLocal,
            onTap: () => ref.read(watchlistProvider.notifier).setMode(false),
          ),
          _SwitchOption(
            label: 'Local',
            isSelected: isLocal,
            onTap: () => ref.read(watchlistProvider.notifier).setMode(true),
          ),
        ],
      ),
    );
  }
}

class _SwitchOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SwitchOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color:
                isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _WatchlistTabView extends ConsumerWidget {
  final String status;
  const _WatchlistTabView({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watchlistProvider);
    final notifier = ref.read(watchlistProvider.notifier);
    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final dim = mode.getDimensions(context);

    // Listen to selection changes to rebuild
    final selectedIds = ref.watch(watchlistSelectionProvider);
    final isSelectionMode = selectedIds.isNotEmpty;

    final rawEntries = status == 'favorites' ? null : state.listFor(status);
    final progressRepo = ref.watch(watchProgressRepositoryProvider);
    final sortedEntries =
        rawEntries == null
            ? null
            : (List<UniversalMediaListEntry>.from(rawEntries)
              ..sort((a, b) {
                final progA = progressRepo.getProgress(a.media.id.toString());
                final progB = progressRepo.getProgress(b.media.id.toString());
                final timeA =
                    progA?.lastPlayedAt ??
                    progA?.lastUpdated ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final timeB =
                    progB?.lastPlayedAt ??
                    progB?.lastUpdated ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return timeB.compareTo(timeA);
              }));

    final entries = sortedEntries;
    final media =
        status == 'favorites'
            ? state.favorites
            : entries!.map((e) => e.media).toList();

    final isLoading = state.loadingStatuses.contains(status);

    Widget refreshableState(Widget child) {
      return RefreshIndicator(
        onRefresh:
            () => notifier.fetchListForStatus(status, force: true, page: 1),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
        ),
      );
    }

    if (isLoading && media.isEmpty) {
      return refreshableState(const Center(child: CircularProgressIndicator()));
    }

    if (state.errors.containsKey(status) && media.isEmpty) {
      return refreshableState(
        WatchlistErrorView(
          message: state.errors[status]!,
          onRetry: () => notifier.fetchListForStatus(status, force: true),
        ),
      );
    }

    if (media.isEmpty) {
      return refreshableState(const WatchlistEmptyState());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!state.isLocal) {
          final info = state.pageInfo[status];
          if (info != null &&
              info.hasNextPage &&
              !isLoading &&
              n.metrics.pixels >= n.metrics.maxScrollExtent * 0.9) {
            notifier.fetchListForStatus(status, page: info.currentPage + 1);
          }
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh:
            () => notifier.fetchListForStatus(status, force: true, page: 1),
        child: AniDashGridView(
          itemCount: media.length + (isLoading ? 1 : 0),
          crossAxisExtent: dim.width,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          padding: EdgeInsets.fromLTRB(10, 10, 10, 100),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          childAspectRatio: dim.width / dim.height,
          itemBuilder: (context, index) {
            if (index == media.length) {
              return const WatchlistLoadingIndicator();
            }
            final anime = media[index];
            final tag = 'watchlist-$status-${anime.id}';
            final isSelected = selectedIds.contains(anime.id);
            final entry =
                (entries != null && index < entries.length)
                    ? entries[index]
                    : null;
            final progress =
                entry?.progress ??
                ref
                    .read(watchProgressRepositoryProvider)
                    .getProgress(anime.id.toString())
                    ?.currentEpisode;

            return GestureDetector(
              onLongPress: () {
                ref.read(watchlistSelectionProvider.notifier).toggle(anime.id);
              },
              onTap: () {
                if (isSelectionMode) {
                  ref
                      .read(watchlistSelectionProvider.notifier)
                      .toggle(anime.id);
                } else {
                  navigateToDetail(context, anime, tag);
                }
              },
              child: Stack(
                children: [
                  AnimeCard(
                    anime: anime,
                    tag: tag,
                    mode: mode,
                    progress: progress,
                  ),
                  if (isSelected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 4,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
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
    );
  }
}
