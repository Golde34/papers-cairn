import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/settings/settings_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _Heading('Appearance'),
          // The group owns the selection and the callback now; the tiles only
          // say which value they stand for.
          RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (selected) {
              if (selected == null) return;
              ref.read(settingsRepositoryProvider).setThemeMode(selected);
            },
            child: Column(
              children: [
                for (final option in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: option,
                    title: Text(switch (option) {
                      ThemeMode.system => 'Follow the device',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                  ),
              ],
            ),
          ),
          const Divider(),
          _Heading('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: Text(
              appRepositoryUrl,
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => launchUrl(
              Uri.parse(appRepositoryUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
