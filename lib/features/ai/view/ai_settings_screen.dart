import 'package:flutter/material.dart';
import 'package:ani_dash/features/ai/domain/assistant_registry.dart';
import 'package:ani_dash/features/ai/view/widgets/assistant_avatar.dart';
import 'package:ani_dash/features/ai/view/widgets/anidash_ai_emblem.dart';
import 'package:ani_dash/main.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _registry = AssistantRegistry();
  late bool _animateLogo = sharedPrefs.getBool(anyCoreLogoAnimationKey) ?? true;

  Future<String?> _editText(
    String title,
    String initial, {
    bool singleLine = false,
  }) => showDialog<String>(
    context: context,
    builder: (context) {
      final controller = TextEditingController(text: initial);
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: singleLine ? 24 : 1000,
          maxLines: singleLine ? 1 : 7,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final profiles = _registry.load();
    return Scaffold(
      appBar: AppBar(title: const Text('AnyCore')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: SwitchListTile(
              secondary: AniDashAiEmblem(
                key: ValueKey(_animateLogo),
                size: 38,
                animate: _animateLogo,
              ),
              title: const Text('Logo animation'),
              subtitle: const Text('Keep the AnyCore logo gently rotating'),
              value: _animateLogo,
              onChanged: (value) async {
                await sharedPrefs.setBool(anyCoreLogoAnimationKey, value);
                if (mounted) setState(() => _animateLogo = value);
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Global Instructions'),
              subtitle: Text(
                _registry.globalInstructions.isEmpty
                    ? 'Not set'
                    : _registry.globalInstructions,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                final value = await _editText(
                  'Global Instructions',
                  _registry.globalInstructions,
                );
                if (value != null) {
                  await _registry.setGlobalInstructions(value);
                  setState(() {});
                }
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(
              'AI Team',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...profiles.map(
            (profile) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: AssistantAvatar(
                      assistantId: profile.id,
                      size: 48,
                      showStatus: true,
                    ),
                    title: Text(profile.displayName),
                    subtitle: Text(AssistantVisual.forId(profile.id).role),
                    trailing: TextButton(
                      onPressed: () async {
                        final value = await _editText(
                          'Rename ${profile.displayName}',
                          profile.displayName,
                          singleLine: true,
                        );
                        if (value != null) {
                          await _registry.rename(profile.id, value);
                          setState(() {});
                        }
                      },
                      child: const Text('Rename'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notes_rounded),
                    title: const Text('Custom Instructions'),
                    subtitle: Text(
                      profile.customInstructions.isEmpty
                          ? 'Not set'
                          : profile.customInstructions,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      final value = await _editText(
                        '${profile.displayName} Instructions',
                        profile.customInstructions,
                      );
                      if (value != null) {
                        await _registry.setInstructions(profile.id, value);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personalization Sources',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'AniDash History • Ratings • Activity • MyAnimeList • AniList',
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Only relevant summaries are shared. Login tokens, passwords and API keys are never sent.',
                    style: TextStyle(fontSize: 12),
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
