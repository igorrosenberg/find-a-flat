import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'app_router.dart';
import 'flat_detail.dart' show deodarStreet;
import 'main.dart';
import 'top_bar.dart';
import 'zoom_buttons.dart';

/// Map of every flat with coordinates, plus the Deodar Street marker.
class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.client, this.tileProvider});

  final http.Client client;

  /// Injected in tests so they make no tile requests.
  final TileProvider? tileProvider;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final Future<List<Flat>> _flats = fetchFlats(widget.client);
  Flat? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopBar(),
      // Bottom left, clear of the OpenStreetMap attribution on the right.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => goTo(context, '/flats/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add property'),
      ),
      body: FutureBuilder<List<Flat>>(
        future: _flats,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load flats: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final placed = snapshot.data!.where((f) => f.point != null).toList();
          return ValueListenableBuilder<bool>(
            valueListenable: hideDiscarded,
            builder: (context, hide, _) =>
                _map(placed.where((f) => !(hide && f.discarded)).toList()),
          );
        },
      ),
    );
  }

  Widget _map(List<Flat> flats) {
    final points = [deodarStreet, for (final f in flats) f.point!];
    final selected = flats.contains(_selected) ? _selected : null;
    return FlutterMap(
      options: MapOptions(
        initialCenter: deodarStreet,
        initialZoom: 14,
        // Zoom to fit every pin (and Deodar St) on load.
        initialCameraFit: points.length < 2
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                // Extra room at the top for the pins, which stand above their point.
                padding: const EdgeInsets.fromLTRB(48, 80, 48, 48),
                maxZoom: 16,
              ),
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'find_a_flat',
          tileProvider: widget.tileProvider,
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: deodarStreet,
              width: 40,
              height: 40,
              child: const Tooltip(
                message: 'Deodar Street',
                child: Icon(
                  Icons.star,
                  key: Key('deodar-marker'),
                  size: 36,
                  color: Colors.deepOrange,
                ),
              ),
            ),
            for (final f in flats)
              Marker(
                point: f.point!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = f),
                  child: Icon(
                    Icons.location_on,
                    key: Key('pin-${f.id}'),
                    size: 40,
                    color: f.discarded ? Colors.grey : Colors.teal,
                  ),
                ),
              ),
            if (selected != null)
              Marker(
                point: selected.point!,
                width: 240,
                height: 170,
                // Sits above the pin, which is 40 px tall.
                alignment: const Alignment(0, -1.48),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _Popup(flat: selected),
                ),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
        const ZoomButtons(),
      ],
    );
  }
}

class _Popup extends StatelessWidget {
  const _Popup({required this.flat});

  final Flat flat;

  @override
  Widget build(BuildContext context) {
    final style = flat.discarded
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.merge(style),
            ),
            const SizedBox(height: 4),
            Text(formatCrore(flat.price)),
            Text(flat.sizeSqft == null ? '– sq ft' : '${flat.sizeSqft} sq ft'),
            Text('B(B) ${formatBb(flat.bedrooms, flat.bathrooms)}'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => goTo(context, '/flats/${flat.id}'),
                child: const Text('Open details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
