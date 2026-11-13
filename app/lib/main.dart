import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'add_flat_page.dart';
import 'flat_detail.dart';
import 'top_bar.dart';

void main() {
  usePathUrlStrategy();
  runApp(const FindAFlatApp());
}

class FindAFlatApp extends StatelessWidget {
  const FindAFlatApp({
    super.key,
    this.client,
    this.navigatorObservers = const [],
  });

  /// Injected in tests; the real app uses a default client.
  final http.Client? client;
  final List<NavigatorObserver> navigatorObservers;

  static final _detailPath = RegExp(r'^/flats/(\d+)$');

  Route<void> _route(RouteSettings settings) {
    final c = client ?? http.Client();
    final detail = _detailPath.firstMatch(Uri.parse(settings.name ?? '').path);
    // Unknown paths show the list until their pages land.
    final Widget page = switch (settings.name) {
      '/flats/new' => AddFlatPage(client: c),
      _ when detail != null => FlatDetailPage(
        id: int.parse(detail[1]!),
        client: c,
      ),
      _ => HomePage(client: c),
    };
    return MaterialPageRoute(
      settings: settings.name == null || settings.name == '/'
          ? const RouteSettings(name: '/home')
          : settings,
      builder: (_) => page,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Find a flat',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      navigatorObservers: navigatorObservers,
      // Open the page for the URL directly, with no back stack under it.
      onGenerateInitialRoutes: (initial) => [
        _route(RouteSettings(name: initial)),
      ],
      onGenerateRoute: _route,
    );
  }
}

class Flat {
  Flat.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      name = json['name'] as String,
      price = json['price'] as int?,
      sizeSqft = json['size_sqft'] as int?,
      distanceM = json['distance_m'] as int?,
      discarded = (json['discarded'] as int? ?? 0) == 1;

  final int id;
  final String name;
  final int? price;
  final int? sizeSqft;
  final int? distanceM;
  final bool discarded;
}

/// Price is always shown in crore with two decimals, never lakh.
String formatCrore(int? rupees) =>
    rupees == null ? '–' : '₹${(rupees / 1e7).toStringAsFixed(2)} Cr';

String formatKm(int? metres) =>
    metres == null ? '–' : '${(metres / 1000).toStringAsFixed(1)} km';

Future<List<Flat>> fetchFlats(http.Client client) async {
  final res = await client.get(Uri.base.resolve('/api/flats'));
  if (res.statusCode != 200) {
    throw Exception('GET /api/flats returned ${res.statusCode}');
  }
  final body = jsonDecode(res.body) as List<dynamic>;
  return body.map((e) => Flat.fromJson(e as Map<String, dynamic>)).toList();
}

/// Whether the list hides discarded flats. Off by default; kept for the
/// session so the map can follow the same setting.
final hideDiscarded = ValueNotifier<bool>(false);

/// Columns the list can be sorted by, in table order.
enum SortColumn { name, price, size, distance }

/// Sorts [flats] by [column]; a null [column] means newest first. Missing
/// values always go last, whichever the direction.
List<Flat> sortFlats(List<Flat> flats, SortColumn? column, bool ascending) {
  final sorted = [...flats];
  if (column == null) {
    sorted.sort((a, b) => b.id.compareTo(a.id));
    return sorted;
  }
  Comparable<Object>? key(Flat f) => switch (column) {
    SortColumn.name => f.name.toLowerCase(),
    SortColumn.price => f.price,
    SortColumn.size => f.sizeSqft,
    SortColumn.distance => f.distanceM,
  } as Comparable<Object>?;
  sorted.sort((a, b) {
    final ka = key(a), kb = key(b);
    if (ka == null || kb == null) {
      if (ka == kb) return b.id.compareTo(a.id);
      return ka == null ? 1 : -1;
    }
    final c = ka.compareTo(kb);
    return c != 0 ? (ascending ? c : -c) : b.id.compareTo(a.id);
  });
  return sorted;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client});

  final http.Client client;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List<Flat>> _flats = fetchFlats(widget.client);
  SortColumn? _sortColumn;
  bool _ascending = true;

  void _sort(SortColumn column, bool ascending) => setState(() {
    _sortColumn = column;
    _ascending = ascending;
  });

  Widget _addButton(BuildContext context) => FilledButton.icon(
    onPressed: () => Navigator.of(context).pushNamed('/flats/new'),
    icon: const Icon(Icons.add),
    label: const Text('Add property'),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopBar(),
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
          final flats = snapshot.data!;
          if (flats.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No flats yet.'),
                  const SizedBox(height: 16),
                  _addButton(context),
                ],
              ),
            );
          }
          return ValueListenableBuilder<bool>(
            valueListenable: hideDiscarded,
            builder: (context, hide, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _addButton(context),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: hide,
                          onChanged: (v) => hideDiscarded.value = v,
                        ),
                        const SizedBox(width: 8),
                        const Text('Hide discarded'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _table(context, flats, hide),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _table(BuildContext context, List<Flat> flats, bool hide) {
    final shown = sortFlats(
      [
        for (final f in flats)
          if (!hide || !f.discarded) f,
      ],
      _sortColumn,
      _ascending,
    );
    DataColumn column(String label, SortColumn c, {bool numeric = false}) =>
        DataColumn(
          label: Text(label),
          numeric: numeric,
          onSort: (_, asc) =>
              // First click on a column sorts ascending, then it toggles.
              _sort(c, _sortColumn == c ? asc : true),
        );
    return DataTable(
      showCheckboxColumn: false,
      sortColumnIndex: _sortColumn?.index,
      sortAscending: _ascending,
      columns: [
        column('Name', SortColumn.name),
        column('Price', SortColumn.price, numeric: true),
        column('Size (sq ft)', SortColumn.size, numeric: true),
        column('Distance to Deodar Street', SortColumn.distance, numeric: true),
      ],
      rows: [
        for (final f in shown)
          DataRow(
            onSelectChanged: (_) =>
                Navigator.of(context).pushNamed('/flats/${f.id}'),
            cells: [
              _cell(f.name, f.discarded),
              _cell(formatCrore(f.price), f.discarded),
              _cell(f.sizeSqft?.toString() ?? '–', f.discarded),
              _cell(formatKm(f.distanceM), f.discarded),
            ],
          ),
      ],
    );
  }

  DataCell _cell(String text, bool discarded) => DataCell(
    Text(
      text,
      style: discarded
          ? const TextStyle(
              decoration: TextDecoration.lineThrough,
              color: Colors.grey,
            )
          : null,
    ),
  );
}
