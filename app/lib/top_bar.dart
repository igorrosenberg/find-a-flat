import 'package:flutter/material.dart';

/// The top bar shared by every page: the "Flats" title, then links to List
/// and Map.
/// Add property lives on the list and map pages, not here.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _go(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name == route) return;
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    // On a phone the links get icons and tighter padding, so the title and
    // both links fit on one line.
    final narrow = MediaQuery.sizeOf(context).width < 520;
    Widget link(String label, IconData icon, String route) {
      void go() => _go(context, route);
      if (!narrow) {
        return TextButton(onPressed: go, child: Text(label));
      }
      return TextButton.icon(
        onPressed: go,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    final links = [
      link('List', Icons.list, '/home'),
      link('Map', Icons.map_outlined, '/map'),
    ];
    if (narrow) {
      // Scaled down rather than cut off if a large font makes them too wide.
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Flats'),
              const SizedBox(width: 16),
              ...links,
            ],
          ),
        ),
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Flats'),
      actions: [...links, const SizedBox(width: 8)],
    );
  }
}
