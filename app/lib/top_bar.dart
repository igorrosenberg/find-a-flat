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
    return AppBar(
      automaticallyImplyLeading: false,
      // On a phone the links need the room, so the title is dropped.
      title: MediaQuery.sizeOf(context).width < 520
          ? null
          : const Text('Find a flat'),
      actions: [
        TextButton(
          onPressed: () => _go(context, '/home'),
          child: const Text('List'),
        ),
        TextButton(
          onPressed: () => _go(context, '/map'),
          child: const Text('Map'),
        ),
        TextButton(
          onPressed: () => _go(context, '/flats/new'),
          child: const Text('Add property'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
