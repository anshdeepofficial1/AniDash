import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart'
    hide Extension;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';

class ExtensionScreen extends StatefulWidget {
  const ExtensionScreen({super.key});

  @override
  State<ExtensionScreen> createState() => _ExtensionScreenState();
}

class _ExtensionScreenState extends ExtensionManagerScreen<ExtensionScreen> {
  String? _selectedRepository;

  String _repoLabel(String url) {
    final uri = Uri.tryParse(url);
    final name =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : url;
    return Uri.decodeComponent(name);
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
                'Extension repositories',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Choose a JSON file to browse its sources'),
            ),
            ListTile(
              selected: _selectedRepository == null,
              leading: const Icon(Icons.apps),
              title: const Text('All repositories'),
              onTap: () {
                setState(() => _selectedRepository = null);
                Navigator.of(context).pop();
              },
            ),
            group(
              'Mangayomi • Anime',
              _getSavedAnimeRepos(mangayomi),
              ExtensionType.mangayomi,
            ),
            group(
              'Mangayomi • Manga',
              _getSavedMangaRepos(mangayomi),
              ExtensionType.mangayomi,
            ),
            if (aniyomi != null) ...[
              group(
                'Aniyomi • Anime',
                _getSavedAnimeRepos(aniyomi),
                ExtensionType.aniyomi,
              ),
              group(
                'Aniyomi • Manga',
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
      repositoryFilter: _selectedRepository,
    );
  };

  List<String> _getSavedAnimeRepos(dynamic manager) {
    final isAniyomi =
        ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    final saved = sharedPrefs.getStringList('saved_anime_repos') ?? const [];
    if (isAniyomi) {
      return <String>{
        'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
        'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
        'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/refs/heads/repo/index.min.json',
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
        onPressed:
            () => _showAddRepoDialog(context, tabController, onRepoSaved),
        icon: const Icon(Iconsax.add),
        tooltip: 'Add Repository',
      ),
      IconButton(
        tooltip: 'Backup or restore extension JSON repositories',
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
                    title: const Text('Extension engines'),
                    content: const Text(
                      'AniDash uses MangaYomi-compatible source files that run inside AniDash.\n\n'
                      'On Android, AniYomi repositories are also supported. Their APK plug-ins use Android\'s secure package installer, so the system may ask you to approve the installation.\n\n'
                      'Adding a repository does not install every source inside it. After adding it, open Available Anime or Available Manga and install the source you want.',
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
            return PopupMenuItem(
              value: lang,
              child: Text(lang == 'All' ? 'All Languages' : lang),
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
                                  setState(() => _selectedRepository = url);
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
