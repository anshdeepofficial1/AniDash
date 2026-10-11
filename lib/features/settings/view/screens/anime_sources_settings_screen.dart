import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';

final providerStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final registry = ref.read(animeSourceRegistryProvider);
  final providers = registry.keys;
  final statusMap = <String, dynamic>{};

  await Future.wait(
    providers.map((key) async {
      final provider = registry.get(key);
      if (provider == null) {
        statusMap[key] = {'status': 'offline'};
        return;
      }
      try {
        final timer = Stopwatch()..start();
        final result = await provider
            .getSearch('one piece', null, 1)
            .timeout(const Duration(seconds: 9));
        timer.stop();
        final working = result.results.isNotEmpty;
        statusMap[key] = {
          'status':
              !working
                  ? 'offline'
                  : timer.elapsedMilliseconds > 4000
                  ? 'degraded'
                  : 'online',
          'latencyMs': timer.elapsedMilliseconds,
        };
      } catch (_) {
        statusMap[key] = {'status': 'offline'};
      }
    }),
  );

  return statusMap;
});

class AnimeSourcesSettingsScreen extends ConsumerWidget {
  const AnimeSourcesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAnimeSource = ref.watch(selectedAnimeProvider);
    final animeSources = ref.read(animeSourceRegistryProvider).keys;
    final providerStatus = ref.watch(providerStatusProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Anime Sources'),
        forceMaterialTransparency: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Sources',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a source to fetch anime from. The status indicates if the source is currently working.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: providerStatus.when(
                data:
                    (statusData) => ListView.builder(
                      itemCount: animeSources.length,
                      itemBuilder: (context, index) {
                        final provider = animeSources[index];
                        final statusInfo = statusData[provider];
                        final status = statusInfo?['status'] as String?;
                        final latency = statusInfo?['latencyMs'] as int?;
                        final isSelected =
                            selectedAnimeSource?.providerName ==
                            provider.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: SelectableSettingsItem(
                            icon: Icon(_getStatusIcon(status)),
                            iconColor: _getStatusColor(status),
                            accent: _getStatusColor(status),
                            title: provider.toUpperCase(),
                            description:
                                'Status: ${_getFriendlyStatus(status)}${latency == null ? '' : ' (${latency}ms)'}\nAvailable: ${_getSubDub(provider)}',
                            isInSelectionMode: true,
                            isSelected: isSelected,
                            onTap: () {
                              ref
                                  .read(selectedProviderKeyProvider.notifier)
                                  .select(provider);
                              ref
                                  .read(experimentalProvider.notifier)
                                  .toggleExtensions(false);
                            },
                          ),
                        );
                      },
                    ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, stack) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          const Text('Failed to load provider status'),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed:
                                () => ref.refresh(providerStatusProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'degraded':
        return Colors.orange;
      case 'offline':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    if (status == null) return Iconsax.info_circle;
    switch (status.toLowerCase()) {
      case 'online':
        return Iconsax.health;
      case 'degraded':
        return Iconsax.warning_2;
      case 'offline':
        return Iconsax.danger;
      default:
        return Iconsax.info_circle;
    }
  }

  String _getFriendlyStatus(String? status) {
    if (status == null) return 'Checking...';
    switch (status.toLowerCase()) {
      case 'online':
        return 'Working smoothly';
      case 'degraded':
        return 'Experiencing issues';
      case 'offline':
        return 'Currently down/failed';
      default:
        return status.toUpperCase();
    }
  }

  String _getSubDub(String provider) {
    final name = provider.toLowerCase();
    if (name.contains('hianime') ||
        name.contains('aniwatch') ||
        name.contains('kaido')) {
      return 'Sub & Dub';
    } else if (name.contains('animepahe') || name.contains('animekai')) {
      return 'Sub & Dub';
    } else if (name.contains('anikoto')) {
      return 'Sub & Dub'; // Assuming Anikoto has both based on homepage
    } else if (name.contains('gojo') || name.contains('anizone')) {
      return 'Sub only (Mostly)';
    }
    return 'Sub (Dub unconfirmed)';
  }
}
