import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:ani_dash/core/registery/anime_source_registery.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/main.dart';

// Hive (Depecrated)
const selectedProviderBox = 'selected_provider';
const selectedProviderKey = 'selected_key';
// SharedPreferences
const selectedProvider = 'selected_provider';

final animeSourceRegistryProvider = Provider<AnimeSourceRegistry>((ref) {
  return AnimeSourceRegistry();
});

final selectedProviderKeyProvider =
    NotifierProvider<SelectedProviderKeyNotifier, String?>(
      SelectedProviderKeyNotifier.new,
    );

class SelectedProviderKeyNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.keepAlive();
    // Safely check Hive migration only if box is open
    try {
      if (Hive.isBoxOpen(selectedProviderBox)) {
        final box = Hive.box<String>(selectedProviderBox);
        final key = box.get(selectedProviderKey);
        if (box.isNotEmpty && key != null && key.isNotEmpty) {
          sharedPrefs.setString(selectedProvider, key.trim().toLowerCase());
        }
        box.delete(selectedProviderKey);
      }
    } catch (_) {}

    // A user-selected extension must remain selected after app restart.
    if (sharedPrefs.getString('selected_playback_source_kind') == 'extension') {
      return null;
    }
    final selectedKey =
        sharedPrefs.getString(selectedProvider)?.trim().toLowerCase();
    AppLogger.w("[Registry] Selected $selectedKey");
    if (selectedKey == null || selectedKey.isEmpty) {
      sharedPrefs.setString(selectedProvider, 'justanime');
      return 'justanime';
    }
    return selectedKey;
  }

  void select(String key) {
    final lowerKey = key.trim().toLowerCase();
    sharedPrefs.setString(selectedProvider, lowerKey);
    sharedPrefs.setString('selected_playback_source_kind', 'native');
    state = lowerKey;
  }

  void clear() {
    sharedPrefs.remove(selectedProvider);
    sharedPrefs.setString('selected_playback_source_kind', 'extension');
    state = null;
  }
}

final selectedAnimeProvider = Provider<AnimeProvider?>((ref) {
  final registry = ref.watch(animeSourceRegistryProvider);
  final key = ref.watch(selectedProviderKeyProvider);
  if (key != null && key.isNotEmpty) {
    return registry.get(key.trim().toLowerCase());
  }
  return registry.get('justanime');
});
