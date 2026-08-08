import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The side menu.
///
/// The bottom bar holds the three things you switch between constantly; this
/// holds everything else. Search and settings were reachable only from icons in
/// the app bar, which is fine while there are two of them and unworkable the
/// moment there is a fourth.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.tab,
    required this.onTab,
  });

  /// Which of the bottom-bar tabs is showing, so the menu can mark it rather
  /// than pretending every destination is equally far away.
  final int tab;
  final void Function(int index) onTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.landscape_outlined,
                  size: 34,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text('Cairn', style: theme.textTheme.titleLarge),
                Text(
                  'Papers, projects, boards',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _TabTile(
            icon: Icons.library_books_outlined,
            selectedIcon: Icons.library_books,
            label: 'Library',
            index: 0,
            tab: tab,
            onTab: onTab,
          ),
          _TabTile(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder,
            label: 'Projects',
            index: 1,
            tab: tab,
            onTab: onTab,
          ),
          _TabTile(
            icon: Icons.gesture_outlined,
            selectedIcon: Icons.gesture,
            label: 'Boards',
            index: 2,
            tab: tab,
            onTab: onTab,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/search');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Files'),
            subtitle: const Text('Everything stored on this device'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/files');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/settings');
            },
          ),
        ],
      ),
    );
  }
}

class _TabTile extends StatelessWidget {
  const _TabTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.tab,
    required this.onTab,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int tab;
  final void Function(int index) onTab;

  @override
  Widget build(BuildContext context) {
    final selected = index == tab;
    return ListTile(
      leading: Icon(selected ? selectedIcon : icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.of(context).pop();
        onTab(index);
      },
    );
  }
}
