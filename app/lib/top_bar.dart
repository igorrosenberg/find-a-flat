import 'package:flutter/material.dart';

/// The top bar shared by every page: links to List, Map and Add property.
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
    // On a phone the title is dropped and the links get icons and tighter
    // padding, so all three fit with room to spare.
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
      link('Add property', Icons.add, '/flats/new'),
    ];
    if (narrow) {
      // Scaled down rather than cut off if a large font makes them too wide.
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: links),
          ),
        ),
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Find a flat'),
      actions: [...links, const SizedBox(width: 8)],
    );
  }
}
