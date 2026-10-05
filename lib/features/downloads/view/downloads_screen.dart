import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';

import 'package:ani_dash/features/downloads/view/widgets/download_card.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/storage_provider.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';

class DownloadsScreen extends ConsumerWidget {
  final bool isAdult;

  const DownloadsScreen({super.key, this.isAdult = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allDownloads = ref.watch(
      downloadsProvider.select((d) => d.downloads),
    );
    final downloads =
        allDownloads.where((d) => isAdult ? d.isAdult : !d.isAdult).toList();
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isAdult ? '18+ Downloads' : 'Downloads'),
          actions: const [AskNiaButton(compact: true), SizedBox(width: 8)],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Downloading'),
              Tab(text: 'Completed'),
            ],
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        body: TabBarView(
          children: [
            _buildDownloadList(context, downloads, groupByAnime: true),
            _buildDownloadList(
              context,
              downloads
                  .where(
                    (d) =>
                        d.state == DownloadStatus.downloading ||
                        d.state == DownloadStatus.paused ||
                        d.state == DownloadStatus.queued,
                  )
                  .toList(),
              groupByAnime: true,
            ),
            _buildDownloadList(
              context,
              downloads
                  .where((d) => d.state == DownloadStatus.downloaded)
                  .toList(),
              groupByAnime: true,
            ),
          ],
        ),
        floatingActionButton:
            kDebugMode
                ? FloatingActionButton(
                  onPressed: () async {
                    final path =
                        (await StorageProvider.getDefaultDirectory())!.path;
                    AppLogger.d(
                      "$path/Offline/One piece/1 - I am gonna be king of the pirates/Auto",
                    );

                    ref
                        .read(downloadsProvider.notifier)
                        .addDownload(
                          DownloadItem(
                            animeTitle: 'One piece',
                            episodeTitle:
                                '1 - I am gonna be king of the pirates',
                            episodeNumber: 1,
                            thumbnail:
                                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSbUFgoWQMHU93hyXCzppyDfhPEcAf76WscJg&s',
                            state: DownloadStatus.downloading,
                            downloadUrl:
                                'https://proxy.animetsu.cc/oppai/pahe/Fw8cARFZQkZuChkMER0eWl4OHkYeEQYWFC1KX1BdSUdbSQNbWA8GEktNIVdXW0EaEUAfB1hQVQQWQEAiBw8HFEpHTElUCghYAEMRRnNVDFBLHUFMT1FbDQxTTBBCcwBbV10MBwEEDF0cVQ',
                            quality: 'Auto',
                            progress: 0,
                            filePath:
                                '$path/Anime Title/1 - Episode Title/Auto',
                            headers: {
                              'User-Agent':
                                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                              // 'Referer':
                              //     'https://megacloud.blog/embed-2/v3/e-1/j7cbMWEbkUys?k=1',
                              // 'Origin': 'https://megacloud.blog',
                            },
                          ),
                        );
                  },
                  child: const Icon(Iconsax.add),
                )
                : null,
      ),
    );
  }

  Widget _buildDownloadList(
    BuildContext context,
    List<DownloadItem> items, {
    bool groupByAnime = false,
  }) {
    if (items.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 72, 28, 120),
        child: Column(
          children: [
            Icon(
              Iconsax.receive_square,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Your offline library starts here',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Download episodes to watch without internet. AniDash keeps each anime together and orders episodes by number.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => context.go('/browse'),
              icon: const Icon(Iconsax.search_normal_1),
              label: const Text('Find anime to download'),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: const [
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.folder_copy_outlined),
                      title: Text('Organized automatically'),
                      subtitle: Text(
                        'Episodes are grouped into anime folders.',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.play_circle_outline_rounded),
                      title: Text('Same AniDash player'),
                      subtitle: Text(
                        'Offline and online playback use the same controls.',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.subtitles_outlined),
                      title: Text('Audio and subtitles'),
                      subtitle: Text(
                        'Choose language, quality, and subtitles before downloading.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (groupByAnime) {
      final grouped = <String, List<DownloadItem>>{};
      for (final item in items) {
        final key =
            (item.animeId?.isNotEmpty == true)
                ? 'id:${item.animeId}'
                : 'title:${item.animeTitle.trim().toLowerCase()}';
        grouped.putIfAbsent(key, () => []).add(item);
      }
      final groups =
          grouped.values.toList()..sort(
            (a, b) => a.first.animeTitle.toLowerCase().compareTo(
              b.first.animeTitle.toLowerCase(),
            ),
          );
      for (final group in groups) {
        group.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      }
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(
          10,
          10,
          10,
          MediaQuery.paddingOf(context).bottom + 110,
        ),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          final completed =
              group
                  .where((item) => item.state == DownloadStatus.downloaded)
                  .length;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: groups.length == 1,
              leading: const Icon(Icons.folder_rounded),
              title: Text(
                group.first.animeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${group.length} episode${group.length == 1 ? '' : 's'} • $completed ready',
              ),
              children: [for (final item in group) DownloadCard(item: item)],
            ),
          );
        },
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        10,
        MediaQuery.paddingOf(context).bottom + 110,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return DownloadCard(item: items[index]);
      },
    );
  }
}
