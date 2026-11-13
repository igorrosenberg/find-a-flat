import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// + and − buttons that zoom the enclosing [FlutterMap] by one level.
///
/// Put it in the map's `children`. It sits in the top-right corner, clear of
/// the attribution (bottom right) and the Add property button (bottom left).
class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MapController.of(context);
    void zoomBy(double delta) {
      // Read the camera now, so quick repeated taps each add a level.
      final camera = controller.camera;
      final zoom = (camera.zoom + delta).clamp(
        camera.minZoom ?? 0.0,
        camera.maxZoom ?? 19.0,
      );
      controller.move(camera.center, zoom);
    }

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('zoom-in'),
                tooltip: 'Zoom in',
                icon: const Icon(Icons.add),
                onPressed: () => zoomBy(1),
              ),
              const SizedBox(width: 32, child: Divider(height: 1)),
              IconButton(
                key: const Key('zoom-out'),
                tooltip: 'Zoom out',
                icon: const Icon(Icons.remove),
                onPressed: () => zoomBy(-1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
