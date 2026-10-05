import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/main.dart';

class AssistantRegistry {
  static const defaults = <AssistantProfile>[
    AssistantProfile(
      id: 'coordinator',
      defaultName: 'Mira',
      role: AssistantRole.coordinator,
    ),
    AssistantProfile(
      id: 'anime_text',
      defaultName: 'Nia',
      role: AssistantRole.animeText,
    ),
    AssistantProfile(
      id: 'vision',
      defaultName: 'Aira',
      role: AssistantRole.vision,
    ),
    AssistantProfile(
      id: 'action',
      defaultName: 'Kiro',
      role: AssistantRole.action,
    ),
  ];

  List<AssistantProfile> load() => defaults
      .map(
        (profile) => profile.copyWith(
          userName: sharedPrefs.getString('ai_name_${profile.id}'),
          customInstructions:
              sharedPrefs.getString('ai_instructions_${profile.id}') ?? '',
        ),
      )
      .toList(growable: false);

  AssistantProfile byId(String id) => load().firstWhere(
    (profile) => profile.id == id,
    orElse: () => load().first,
  );

  Future<void> rename(String id, String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      await sharedPrefs.remove('ai_name_$id');
    } else {
      await sharedPrefs.setString(
        'ai_name_$id',
        cleaned.substring(0, cleaned.length.clamp(0, 24)),
      );
    }
  }

  Future<void> setInstructions(String id, String value) =>
      sharedPrefs.setString('ai_instructions_$id', value.trim());

  String get globalInstructions =>
      sharedPrefs.getString('ai_global_instructions') ?? '';
  Future<void> setGlobalInstructions(String value) =>
      sharedPrefs.setString('ai_global_instructions', value.trim());
}
