import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart'
    hide Extension;
import 'package:dartotsu_extension_bridge/Mangayomi/MangayomiExtensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';

class ExtensionScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialRepo;
  final String? initialLanguage;
  final String? initialEngine;

  const ExtensionScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialRepo,
    this.initialLanguage,
    this.initialEngine,
  });

  @override
  State<ExtensionScreen> createState() => _ExtensionScreenState();
}

class _ExtensionScreenState extends ExtensionManagerScreen<ExtensionScreen> {
  @override
  String? get repositoryFilter => _selectedRepository;
  String? _selectedRepository;
  bool _restoringDefaults = false;

  String _repoLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return url;
    final segments = uri.pathSegments;
    final filename = Uri.decodeComponent(segments.last);
    if (uri.host == 'raw.githubusercontent.com' && segments.length >= 2) {
      return '${segments[0]}/${segments[1]} · $filename';
    }
    if (segments.length >= 2) {
      return '${Uri.decodeComponent(segments[segments.length - 2])} · $filename';
    }
    return '${uri.host} · $filename';
  }

  @override
  Widget get repositoryDrawer {
    final theme = Theme.of(context);

    Widget group(String title, List<String> urls, ExtensionType engine) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 5),
              child: Text(title, style: theme.textTheme.labelLarge),
            ),
            for (final url in urls)
              ListTile(
                selected: _selectedRepository == url,
                leading: const Icon(Icons.data_object),
                title: Text(
                  _repoLabel(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  Uri.tryParse(url)?.host ?? url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final extensionManager = Get.find<ExtensionManager>();
                  if (ExtensionType.fromManager(
                        extensionManager.currentManager,
                      ) !=
                      engine) {
                    extensionManager.setCurrentManager(engine);
                    manager = extensionManager.currentManager;
                    await ProviderScope.containerOf(
                      context,
                    ).read(sourceProvider.notifier).initialize();
                  }
                  if (!mounted) return;
                  setState(() => _selectedRepository = url);
                  await _refreshRepositories();
                },
              ),
          ],
        );

    final mangayomi = ExtensionType.mangayomi.getManager();
    final aniyomi =
        Platform.isAndroid ? ExtensionType.aniyomi.getManager() : null;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text(
                'Source collections',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Choose a ready-made collection. No JSON knowledge is needed.',
              ),
            ),
            ListTile(
              selected: _selectedRepository == null,
              leading: const Icon(Icons.apps),
              title: const Text('All source collections'),
              onTap: () {
                setState(() => _selectedRepository = null);
                Navigator.of(context).pop();
              },
            ),
            group(
              'Built-in sources • Anime',
              _getSavedAnimeRepos(mangayomi),
              ExtensionType.mangayomi,
            ),
            group(
              'Built-in sources • Manga',
              _getSavedMangaRepos(mangayomi),
              ExtensionType.mangayomi,
            ),
            if (aniyomi != null) ...[
              group(
                'Android plug-in sources • Anime',
                _getSavedAnimeRepos(aniyomi),
                ExtensionType.aniyomi,
              ),
              group(
                'Android plug-in sources • Manga',
                _getSavedMangaRepos(aniyomi),
                ExtensionType.aniyomi,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final isAniyomiTarget = widget.initialEngine == 'aniyomi' ||
        (widget.initialLanguage != null &&
            (widget.initialLanguage!.toLowerCase() == 'hi' ||
                widget.initialLanguage!.toLowerCase() == 'hindi')) ||
        (widget.initialRepo != null && widget.initialRepo!.contains('index.min.json'));

    if (Platform.isAndroid && isAniyomiTarget) {
      try {
        final extensionManager = Get.find<ExtensionManager>();
        if (ExtensionType.fromManager(extensionManager.currentManager) != ExtensionType.aniyomi) {
          extensionManager.setCurrentManager(ExtensionType.aniyomi);
          manager = extensionManager.currentManager;
        }
      } catch (_) {}
    }

    if (widget.initialRepo != null && widget.initialRepo!.isNotEmpty) {
      _selectedRepository = widget.initialRepo;
    }
    if (widget.initialLanguage != null && widget.initialLanguage!.isNotEmpty) {
      setLanguageFilter(widget.initialLanguage!);
    }
    if (widget.initialTabIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          animateToTab(widget.initialTabIndex);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRepositories());
  }

  Future<void> _refreshRepositories() async {
    final manager = Get.find<ExtensionManager>().currentManager;
    await Future.wait([
      manager.fetchAvailableAnimeExtensions(_getSavedAnimeRepos(manager)),
      manager.fetchAvailableMangaExtensions(_getSavedMangaRepos(manager)),
    ]);
  }

  @override
  Text get title =>
      const Text('Extensions', style: TextStyle(fontWeight: FontWeight.bold));

  @override
  Widget emptyExtensionsState(
    BuildContext context,
    ItemType type,
    bool isInstalled,
    String message,
    ColorScheme theme,
  ) {
    if (!isInstalled || type != ItemType.anime) {
      return Center(child: Text(message));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Restore AniDash\'s verified anime sources whenever you need them.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _restoringDefaults ? null : _restoreDefaultSources,
              icon:
                  _restoringDefaults
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.restore),
              label: Text(
                _restoringDefaults ? 'Restoring…' : 'Restore Default Sources',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDefaultSources() async {
    if (_restoringDefaults) return;
    setState(() => _restoringDefaults = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final extensionManager = Get.find<ExtensionManager>();
      extensionManager.setCurrentManager(ExtensionType.mangayomi);
      final defaults = ExtensionType.mangayomi.getManager();
      manager = defaults;
      await defaults.fetchAvailableAnimeExtensions(
        _getSavedAnimeRepos(defaults),
      );
      final mangayomi = defaults as MangayomiExtensions;
      final restoredAnime = await mangayomi.restoreDefaultAnimeSources();
      final restoredManga = await mangayomi.restoreDefaultMangaSources();
      final restored = restoredAnime + restoredManga;
      if (!mounted) return;
      await ProviderScope.containerOf(
        context,
      ).read(sourceProvider.notifier).initialize();
      setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            restored == 0
                ? 'Default sources are already installed.'
                : '$restored default source${restored == 1 ? '' : 's'} restored.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not restore sources: $error')),
      );
    } finally {
      if (mounted) setState(() => _restoringDefaults = false);
    }
  }

  @override
  ExtensionScreenBuilder get extensionScreenBuilder => (
    itemType,
    isInstalled,
    searchQuery,
    selectedLanguage,
  ) {
    return ExtensionListWidget(
      itemType: itemType,
      isInstalled: isInstalled,
      searchQuery: searchQuery,
      selectedLanguage: selectedLanguage,
      repositoryFilter: isInstalled ? null : _selectedRepository,
    );
  };

  @override
  Widget get engineSelector {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extensionManager = Get.find<ExtensionManager>();
    final currentEngine = ExtensionType.fromManager(extensionManager.currentManager);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ExtensionType>(
                  segments: [
                    const ButtonSegment<ExtensionType>(
                      value: ExtensionType.mangayomi,
                      icon: Icon(Icons.bolt, size: 16),
                      label: Text('Built-in (Fast)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    if (Platform.isAndroid)
                      const ButtonSegment<ExtensionType>(
                        value: ExtensionType.aniyomi,
                        icon: Icon(Icons.android, size: 16),
                        label: Text('Android (AniYomi)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                  ],
                  selected: {currentEngine},
                  onSelectionChanged: (Set<ExtensionType> newSelection) async {
                    final selected = newSelection.first;
                    if (selected != currentEngine) {
                      extensionManager.setCurrentManager(selected);
                      manager = extensionManager.currentManager;
                      await ProviderScope.containerOf(
                        context,
                      ).read(sourceProvider.notifier).initialize();
                      setState(() {
                        _selectedRepository = null;
                      });
                      await _refreshRepositories();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Manage Repositories',
                icon: const Icon(Icons.folder_copy_outlined, size: 20),
                onPressed: _showManageReposSheet,
              ),
            ],
          ),
          if (_selectedRepository != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_alt, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Filtered: ${_repoLabel(_selectedRepository!)}',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _selectedRepository = null),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showManageReposSheet() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extensionManager = Get.find<ExtensionManager>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final mangayomi = ExtensionType.mangayomi.getManager();
            final aniyomi = Platform.isAndroid ? ExtensionType.aniyomi.getManager() : null;
            final currentEngine = ExtensionType.fromManager(extensionManager.currentManager);
            final savedAnime = sharedPrefs.getStringList('saved_anime_repos') ?? <String>[];

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.folder_special, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage Repositories',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Separated by Mangayomi & AniYomi categories',
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ACTIVE EXTENSION ENGINE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<ExtensionType>(
                              segments: [
                                const ButtonSegment(
                                  value: ExtensionType.mangayomi,
                                  icon: Icon(Icons.bolt, size: 16),
                                  label: Text('Built-in (Mangayomi)'),
                                ),
                                if (Platform.isAndroid)
                                  const ButtonSegment(
                                    value: ExtensionType.aniyomi,
                                    icon: Icon(Icons.android, size: 16),
                                    label: Text('Android (AniYomi)'),
                                  ),
                              ],
                              selected: {currentEngine},
                              onSelectionChanged: (set) async {
                                final sel = set.first;
                                extensionManager.setCurrentManager(sel);
                                manager = extensionManager.currentManager;
                                await ProviderScope.containerOf(context)
                                    .read(sourceProvider.notifier)
                                    .initialize();
                                setState(() => _selectedRepository = null);
                                setSheetState(() {});
                                await _refreshRepositories();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      '⚡ BUILT-IN / MANGAYOMI REPOSITORIES',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final repo in _getSavedAnimeRepos(mangayomi))
                      _buildRepoTile(
                        repo: repo,
                        isCustom: savedAnime.contains(repo),
                        engine: ExtensionType.mangayomi,
                        type: ItemType.anime,
                        onDeleted: () async {
                          final updated = savedAnime.where((r) => r != repo).toList();
                          await sharedPrefs.setStringList('saved_anime_repos', updated);
                          await _refreshRepositories();
                          setSheetState(() {});
                          setState(() {});
                        },
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Mangayomi Repository'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showAddRepoDialog(context, tabBarController, manager.onRepoSaved);
                      },
                    ),
                    const SizedBox(height: 20),

                    if (aniyomi != null) ...[
                      Text(
                        '🤖 ANDROID / ANIYOMI REPOSITORIES (HINDI + APKS)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final repo in _getSavedAnimeRepos(aniyomi))
                        _buildRepoTile(
                          repo: repo,
                          isCustom: savedAnime.contains(repo),
                          engine: ExtensionType.aniyomi,
                          type: ItemType.anime,
                          onDeleted: () async {
                            final updated = savedAnime.where((r) => r != repo).toList();
                            await sharedPrefs.setStringList('saved_anime_repos', updated);
                            await _refreshRepositories();
                            setSheetState(() {});
                            setState(() {});
                          },
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Quick Presets:',
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Text('🇮🇳'),
                            label: const Text('Hindi Anime Dub (MSR)'),
                            onPressed: () => _addQuickPreset(
                              'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
                              ExtensionType.aniyomi,
                              ItemType.anime,
                              sheetContext,
                            ),
                          ),
                          ActionChip(
                            avatar: const Text('📺'),
                            label: const Text('Kohi-den Repo'),
                            onPressed: () => _addQuickPreset(
                              'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
                              ExtensionType.aniyomi,
                              ItemType.anime,
                              sheetContext,
                            ),
                          ),
                          ActionChip(
                            avatar: const Text('📖'),
                            label: const Text('Keiyoushi Manga'),
                            onPressed: () => _addQuickPreset(
                              'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
                              ExtensionType.aniyomi,
                              ItemType.manga,
                              sheetContext,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add AniYomi Repository URL'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showAddRepoDialog(context, tabBarController, manager.onRepoSaved);
                        },
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRepoTile({
    required String repo,
    required bool isCustom,
    required ExtensionType engine,
    required ItemType type,
    required VoidCallback onDeleted,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedRepository == repo;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          engine == ExtensionType.aniyomi ? Icons.android : Icons.bolt,
          color: engine == ExtensionType.aniyomi ? Colors.orange : colorScheme.primary,
          size: 20,
        ),
        title: Text(
          _repoLabel(repo),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          repo,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isSelected ? Icons.check_circle : Icons.filter_alt_outlined,
                size: 18,
                color: isSelected ? colorScheme.primary : null,
              ),
              tooltip: isSelected ? 'Active filter (tap to clear)' : 'Filter by this repo',
              onPressed: () {
                setState(() {
                  _selectedRepository = isSelected ? null : repo;
                });
                Navigator.pop(context);
              },
            ),
            if (isCustom)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                tooltip: 'Remove repository',
                onPressed: onDeleted,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addQuickPreset(
    String url,
    ExtensionType engine,
    ItemType type,
    BuildContext sheetContext,
  ) async {
    final saved = sharedPrefs.getStringList(
      type == ItemType.manga ? 'saved_manga_repos' : 'saved_anime_repos',
    ) ?? <String>[];
    if (!saved.contains(url)) {
      await sharedPrefs.setStringList(
        type == ItemType.manga ? 'saved_manga_repos' : 'saved_anime_repos',
        [...saved, url],
      );
    }
    final extensionManager = Get.find<ExtensionManager>();
    extensionManager.setCurrentManager(engine);
    manager = extensionManager.currentManager;
    if (!mounted) return;
    await ProviderScope.containerOf(context)
        .read(sourceProvider.notifier)
        .initialize();
    setState(() => _selectedRepository = null);
    await _refreshRepositories();
    if (mounted && sheetContext.mounted) {
      Navigator.pop(sheetContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset added: ${_repoLabel(url)}')),
      );
    }
  }

  List<String> _getSavedAnimeRepos(dynamic manager) {
    final isAniyomi =
        ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    final saved = sharedPrefs.getStringList('saved_anime_repos') ?? const [];
    if (isAniyomi) {
      return <String>{
        'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
        'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
        ...saved.where((url) => url.contains('index.min.json')),
      }.toList();
    }
    final repos = <String>{
      'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
      'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
    };
    if (saved.isNotEmpty) {
      repos.addAll(saved.where((url) => !url.contains('index.min.json')));
    }
    return repos.toList();
  }

  List<String> _getSavedMangaRepos(dynamic manager) {
    final isAniyomi =
        ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    final saved = sharedPrefs.getStringList('saved_manga_repos') ?? const [];
    if (isAniyomi) {
      return <String>{
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
        ...saved.where((url) => url.contains('index.min.json')),
      }.toList();
    }
    final repos = <String>{
      'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
    };
    if (saved.isNotEmpty) {
      repos.addAll(saved.where((url) => !url.contains('index.min.json')));
    }
    return repos.toList();
  }

  @override
  List<Widget> extensionActions(
    BuildContext context,
    TabController tabController,
    String currentLanguage,
    Future<void> Function(List<String> repoUrl, ItemType type) onRepoSaved,
    void Function(String currentLanguage) onLanguageChanged,
  ) {
    return [
      IconButton(
        tooltip: 'Manage Repositories',
        icon: const Icon(Icons.folder_copy_outlined),
        onPressed: _showManageReposSheet,
      ),
      IconButton(
        onPressed:
            () => _showAddRepoDialog(context, tabController, onRepoSaved),
        icon: const Icon(Iconsax.add),
        tooltip: 'Add source link (advanced)',
      ),
      IconButton(
        tooltip: 'Backup or restore source collections',
        icon: const Icon(Icons.settings_backup_restore),
        onPressed: () => context.push('/settings/data'),
      ),
      IconButton(
        tooltip: 'Extension engines explained',
        icon: const Icon(Icons.info_outline),
        onPressed:
            () => showDialog<void>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('How sources work'),
                    content: const Text(
                      'For normal use, choose Built-in sources and install the source you want. You do not need a JSON link.\n\n'
                      'Android plug-in sources add compatibility with external source packs; Android may ask you to approve their installation.\n\n'
                      'Repository links are an advanced option for adding a source collection supplied by a trusted developer. If sources are missing, use Restore Default Sources.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
            ),
      ),
      PopupMenuButton<String>(
        icon: const Icon(Iconsax.translate),
        tooltip: 'Filter Language',
        onSelected: onLanguageChanged,
        itemBuilder: (context) {
          final languages = [
            'All',
            'hi',
            'en',
            'es',
            'fr',
            'pt',
            'it',
            'de',
            'ru',
            'ja',
            'ko',
            'zh',
            'ar',
            'id',
            'vi',
            'th',
            'tr',
          ];
          return languages.map((lang) {
            String label = lang;
            if (lang == 'All') {
              label = 'All Languages';
            } else if (lang == 'hi') {
              label = 'Hindi (हिन्दी)';
            } else if (lang == 'en') {
              label = 'English';
            } else if (lang == 'ja') {
              label = 'Japanese';
            }
            return PopupMenuItem(
              value: lang,
              child: Text(label),
            );
          }).toList();
        },
      ),
      IconButton(
        onPressed: _refreshRepositories,
        icon: const Icon(Iconsax.refresh),
        tooltip: 'Refresh',
      ),
    ];
  }

  @override
  Widget searchBar(
    BuildContext context,
    TextEditingController textEditingController,
    void Function() onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: textEditingController,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: 'Search extensions...',
          prefixIcon: const Icon(Iconsax.search_normal),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget tabWidget(BuildContext context, String label, int count) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddRepoDialog(
    BuildContext context,
    TabController tabController,
    Future<void> Function(List<String> repoUrl, ItemType type) onRepoSaved,
  ) {
    final controller = TextEditingController();
    final presets = [
      (
        name: 'Kohi-den (AniYomi Anime)',
        url:
            'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
        type: ItemType.anime,
        is18Plus: false,
      ),
    ];

    showDialog(
      context: context,
      builder: (context) {
        ItemType selectedType = ItemType.anime;
        bool isAdding = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            return AlertDialog(
              title: const Text('Add Repository'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<ItemType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Extension Type',
                        ),
                        items:
                            const [ItemType.anime, ItemType.manga]
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.name.toUpperCase()),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => selectedType = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Repository URL',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Community & 18+ Repositories:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...presets.map((preset) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color:
                                  preset.is18Plus
                                      ? Colors.redAccent.withValues(alpha: 0.6)
                                      : colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color:
                                preset.is18Plus
                                    ? Colors.redAccent.withValues(alpha: 0.05)
                                    : null,
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    preset.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (preset.is18Plus)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '18+',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              preset.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: () {
                                setState(() {
                                  controller.text = preset.url;
                                  selectedType = preset.type;
                                });
                              },
                              child: const Text('Select'),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isAdding ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed:
                      isAdding
                          ? null
                          : () async {
                            final url = controller.text.trim();
                            if (url.isNotEmpty) {
                              setState(() => isAdding = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final sourceContainer = ProviderScope.containerOf(
                                context,
                              );
                              try {
                                final uri = Uri.tryParse(url);
                                if (uri == null ||
                                    !uri.hasAuthority ||
                                    (uri.scheme != 'https' &&
                                        uri.scheme != 'http')) {
                                  throw FormatException(
                                    'Please enter a valid JSON repository URL.',
                                  );
                                }
                                final isManga = selectedType == ItemType.manga;
                                final isAniyomiRepository =
                                    url.contains('index.min.json') ||
                                    url.toLowerCase().contains('aniyomi');
                                if (isAniyomiRepository &&
                                    !Platform.isAndroid) {
                                  throw StateError(
                                    'AniYomi APK repositories require Android.',
                                  );
                                }
                                final targetType =
                                    isAniyomiRepository
                                        ? ExtensionType.aniyomi
                                        : ExtensionType.mangayomi;
                                final targetManager = targetType.getManager();
                                final currentRepos =
                                    isManga
                                        ? _getSavedMangaRepos(targetManager)
                                        : _getSavedAnimeRepos(targetManager);
                                final updated = {...currentRepos, url}.toList();
                                final previousRepositories =
                                    sharedPrefs.getStringList(
                                      isManga
                                          ? 'saved_manga_repos'
                                          : 'saved_anime_repos',
                                    ) ??
                                    <String>[];

                                // Do not announce a successful add because
                                // another repository returned some extensions.
                                await targetManager.onRepoSaved(
                                  updated,
                                  selectedType,
                                );
                                if (!_repositoryLoaded(
                                  targetManager,
                                  selectedType,
                                  url,
                                )) {
                                  // Failed JSON should not be kept in saved
                                  // repositories or the visible source list.
                                  await targetManager.onRepoSaved(
                                    currentRepos,
                                    selectedType,
                                  );
                                  throw StateError(
                                    'This JSON returned no usable sources. '
                                    'Check the repository URL and format.',
                                  );
                                }
                                if (!previousRepositories.contains(url)) {
                                  await sharedPrefs.setStringList(
                                    isManga
                                        ? 'saved_manga_repos'
                                        : 'saved_anime_repos',
                                    {...previousRepositories, url}.toList(),
                                  );
                                }
                                final extensionManager =
                                    Get.find<ExtensionManager>();
                                extensionManager.setCurrentManager(targetType);
                                manager = extensionManager.currentManager;
                                if (mounted) {
                                  setState(() => _selectedRepository = null);
                                }
                                await sourceContainer
                                    .read(sourceProvider.notifier)
                                    .initialize();
                                if (!mounted || !context.mounted) return;
                                Navigator.of(context).pop();
                                if (selectedType == ItemType.anime) {
                                  tabController.animateTo(1);
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${currentRepos.contains(url) ? 'Repository refreshed' : 'Repository added'}: '
                                      '${_repoLabel(url)}. Browse sources from the menu.',
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (context.mounted) {
                                  setState(() => isAdding = false);
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not add repository: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  child:
                      isAdding
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _repositoryLoaded(dynamic manager, ItemType type, String repositoryUrl) {
    final available =
        type == ItemType.anime
            ? manager.availableAnimeExtensions.value
            : manager.availableMangaExtensions.value;
    final installed =
        type == ItemType.anime
            ? manager.installedAnimeExtensions.value
            : manager.installedMangaExtensions.value;
    final sources = [...available, ...installed];
    return sources.any(
      (source) =>
          source.repo == repositoryUrl ||
          (source.id != null &&
              sharedPrefs.getString('extension_source_repo_${source.id}') ==
                  repositoryUrl),
    );
  }
}

class ExtensionListWidget extends StatefulWidget implements ExtensionConfig {
  @override
  final ItemType itemType;
  @override
  final bool isInstalled;
  @override
  final String? repositoryFilter;
  @override
  final String searchQuery;
  @override
  final String selectedLanguage;
  const ExtensionListWidget({
    super.key,
    required this.itemType,
    required this.isInstalled,
    this.repositoryFilter,
    required this.searchQuery,
    required this.selectedLanguage,
  });

  @override
  String? assignedRepoFor(String sourceId) =>
      sharedPrefs.getString('extension_source_repo_$sourceId');

  @override
  State<ExtensionListWidget> createState() => _ExtensionListWidgetState();
}

class _ExtensionListWidgetState extends ExtensionList<ExtensionListWidget> {
  @override
  Widget build(BuildContext context) {
    manager = Get.find<ExtensionManager>().currentManager;
    return super.build(context);
  }

  @override
  Widget extensionItem(bool isHeader, String lang, Source? source) {
    if (isHeader) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(
          lang.toUpperCase(), // Or map to full name
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (source == null) return const SizedBox.shrink();

    return ExtensionListItem(
      source: source,
      isInstalled: widget.isInstalled,
      onInstall: () async {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Installing source inside AniDash…')),
        );
        try {
          await manager.installSource(source);
          final sourceId = source.id;
          final sourceRepo = source.repo ?? widget.repositoryFilter;
          if (sourceId != null &&
              sourceId.isNotEmpty &&
              sourceRepo != null &&
              sourceRepo.isNotEmpty) {
            await sharedPrefs.setString(
              'extension_source_repo_$sourceId',
              sourceRepo,
            );
          }
          if (mounted) {
            await ProviderScope.containerOf(
              context,
            ).read(sourceProvider.notifier).initialize();
          }
          messenger.showSnackBar(
            SnackBar(content: Text('${source.name ?? 'Extension'} installed.')),
          );
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('Source installed'),
                    content: const Text(
                      'The source is installed inside AniDash. Open Installed Anime or Installed Manga to use it.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
            );
          }
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('Installation failed: $error')),
          );
        }
      },
      onUninstall: () async {
        await manager.uninstallSource(source);
        if (source.id != null) {
          await sharedPrefs.remove('extension_source_repo_${source.id}');
        }
        if (mounted) {
          await ProviderScope.containerOf(
            context,
          ).read(sourceProvider.notifier).initialize();
        }
      },
      onUpdate: () async {
        await manager.updateSource(source);
        if (mounted) {
          await ProviderScope.containerOf(
            context,
          ).read(sourceProvider.notifier).initialize();
        }
      },
      onTap: () async {
        // Open details or settings if installed
        if (widget.isInstalled) {
          context.push(
            '/settings/extensions/extension-preference',
            extra: source,
          );
        } else {
          try {
            await (source.extensionType?.getManager() ?? manager).installSource(
              source,
            );
            final repo = source.repo ?? widget.repositoryFilter;
            if (source.id != null && repo != null && repo.isNotEmpty) {
              await sharedPrefs.setString(
                'extension_source_repo_${source.id}',
                repo,
              );
            }
            if (mounted) {
              await ProviderScope.containerOf(
                context,
              ).read(sourceProvider.notifier).initialize();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Installation failed: $e')),
              );
            }
          }
        }
      },
    );
  }
}

class ExtensionListItem extends StatelessWidget {
  final Source source;
  final bool isInstalled;
  final Future<void> Function() onInstall;
  final VoidCallback onUninstall;
  final VoidCallback onUpdate;
  final VoidCallback onTap;

  const ExtensionListItem({
    super.key,
    required this.source,
    required this.isInstalled,
    required this.onInstall,
    required this.onUninstall,
    required this.onUpdate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = source.iconUrl?.toLowerCase() ?? '';
    final name = source.name?.toLowerCase() ?? '';
    String repoName = 'Community';
    Color repoColor = Theme.of(context).colorScheme.primaryContainer;
    Color repoTextColor = Theme.of(context).colorScheme.onPrimaryContainer;

    if (source.isNsfw == true ||
        icon.contains('yuzono') ||
        name.contains('yuzono')) {
      repoName = 'Yuzono (18+)';
      repoColor = Colors.red.shade900.withValues(alpha: 0.3);
      repoTextColor = Colors.redAccent;
    } else if (icon.contains('kohi-den') ||
        icon.contains('kohiden') ||
        name.contains('kohi')) {
      repoName = 'Kohi-den';
      repoColor = Colors.blue.shade900.withValues(alpha: 0.3);
      repoTextColor = Colors.lightBlueAccent;
    } else if (icon.contains('secozzi') || name.contains('secozzi')) {
      repoName = 'Secozzi';
      repoColor = Colors.purple.shade900.withValues(alpha: 0.3);
      repoTextColor = Colors.purpleAccent;
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              source.iconUrl != null && source.iconUrl!.isNotEmpty
                  ? CachedNetworkImage(
                    imageUrl: source.iconUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget:
                        (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.extension, size: 20),
                        ),
                  )
                  : Container(
                    width: 40,
                    height: 40,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.extension, size: 20),
                  ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                source.name ?? 'Unknown',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (source.isNsfw == true) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '18+',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            Text('v${source.version ?? "?"} • ${source.lang ?? "?"}'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: repoColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                repoName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: repoTextColor,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (source.hasUpdate == true && isInstalled)
              IconButton(
                icon: const Icon(Icons.update, color: Colors.orange),
                onPressed: onUpdate,
                tooltip: 'Update',
              ),
            if (isInstalled)
              IconButton(
                icon: const Icon(Iconsax.trash, color: Colors.red),
                onPressed: onUninstall,
                tooltip: 'Uninstall',
              )
            else
              IconButton(
                icon: const Icon(Iconsax.import),
                onPressed: onInstall,
                tooltip: 'Install',
              ),
            if (isInstalled)
              IconButton(
                icon: const Icon(Iconsax.setting_2),
                onPressed:
                    () => context.push(
                      '/settings/extensions/extension-preference',
                      extra: source,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
