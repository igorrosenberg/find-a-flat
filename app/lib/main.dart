import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'app_router.dart';
import 'flat_page.dart';
import 'map_page.dart';
import 'top_bar.dart';

void main() {
  usePathUrlStrategy();
  runApp(const FindAFlatApp());
}

class FindAFlatApp extends StatefulWidget {
  const FindAFlatApp({
    super.key,
    this.client,
    this.navigatorObservers = const [],
  });

  /// Injected in tests; the real app uses a default client.
  final http.Client? client;
  final List<NavigatorObserver> navigatorObservers;

  static final _flatPath = RegExp(r'^/flats/(\d+)$');

  Widget _page(String path) {
    final c = client ?? http.Client();
    final flat = _flatPath.firstMatch(path);
    // Unknown paths show the list until their pages land.
    return switch (path) {
      '/flats/new' => FlatPage(client: c),
      '/map' => MapPage(client: c),
      _ when flat != null => FlatPage(id: int.parse(flat[1]!), client: c),
      _ => HomePage(client: c),
    };
  }

  @override
  State<FindAFlatApp> createState() => _FindAFlatAppState();
}

class _FindAFlatAppState extends State<FindAFlatApp> {
  late final _delegate = AppRouterDelegate(
    buildPage: widget._page,
    navigatorObservers: widget.navigatorObservers,
  );

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flats',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      routeInformationParser: const AppRouteParser(),
      routerDelegate: _delegate,
    );
  }
}

class Flat {
  Flat.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      name = json['name'] as String,
      price = json['price'] as int?,
      sizeSqft = json['size_sqft'] as int?,
      bedrooms = json['bedrooms'] as int?,
      bathrooms = json['bathrooms'] as int?,
      distanceM = json['distance_m'] as int?,
      lat = (json['lat'] as num?)?.toDouble(),
      lng = (json['lng'] as num?)?.toDouble(),
      discarded = (json['discarded'] as int? ?? 0) == 1;

  final int id;
  final String name;
  final int? price;
  final int? sizeSqft;
  final int? bedrooms;
  final int? bathrooms;
  final int? distanceM;
  final double? lat;
  final double? lng;
  final bool discarded;

  /// Where to pin the flat on a map, or null if it has no coordinates.
  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);
}

/// Price is always shown in crore with two decimals, never lakh.
String formatCrore(int? rupees) =>
    rupees == null ? '–' : '₹${(rupees / 1e7).toStringAsFixed(2)} Cr';

/// Bedrooms(bathrooms), e.g. "3(2)"; a dash for whichever is unknown, and a
/// single dash when both are.
String formatBb(int? bedrooms, int? bathrooms) =>
    bedrooms == null && bathrooms == null
    ? '–'
    : '${bedrooms ?? '–'}(${bathrooms ?? '–'})';

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

/// Bumped when a flat is saved or deleted, so the list and map reload.
final flatsChanged = ValueNotifier<int>(0);

/// Columns the list can be sorted by, in table order.
enum SortColumn {
  name('Name'),
  price('Price'),
  size('Size'),
  bb('B(B)'),
  distance('Distance');

  const SortColumn(this.label);

  /// Short label for the sort menu on narrow screens.
  final String label;
}

/// Below this width the list shows compact rows instead of a table.
const narrowWidth = 600.0;

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
    // By bedrooms, then bathrooms.
    SortColumn.bb =>
      f.bedrooms == null && f.bathrooms == null
          ? null
          : (f.bedrooms ?? 0) * 1000 + (f.bathrooms ?? 0),
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
  late Future<List<Flat>> _flats = fetchFlats(widget.client);

  // Reload when a flat is saved or deleted, keeping what is on screen
  // (sort order, scroll position, map view) until the new list arrives.
  void _reload() => setState(() {
    _flats = fetchFlats(widget.client);
  });

  @override
  void initState() {
    super.initState();
    flatsChanged.addListener(_reload);
  }

  @override
  void dispose() {
    flatsChanged.removeListener(_reload);
    super.dispose();
  }

  SortColumn? _sortColumn;
  bool _ascending = true;

  void _sort(SortColumn column, bool ascending) => setState(() {
    _sortColumn = column;
    _ascending = ascending;
  });

  Widget _addButton(BuildContext context) => FilledButton.icon(
    onPressed: () => goTo(context, '/flats/new'),
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
          return LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < narrowWidth;
              return ValueListenableBuilder<bool>(
                valueListenable: hideDiscarded,
                builder: (context, hide, _) {
                  final shown = sortFlats(
                    [
                      for (final f in flats)
                        if (!hide || !f.discarded) f,
                    ],
                    _sortColumn,
                    _ascending,
                  );
                  return ListView(
                    padding: EdgeInsets.all(narrow ? 12 : 16),
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [_hideSwitch(hide), if (narrow) _sortMenu()],
                      ),
                      const SizedBox(height: 8),
                      if (narrow)
                        ..._compactRows(context, shown)
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _table(context, shown),
                        ),
                      const SizedBox(height: 16),
                      // The one Add property button, below the last row.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _addButton(context),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _hideSwitch(bool hide) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: hide, onChanged: (v) => hideDiscarded.value = v),
      const SizedBox(width: 8),
      Text(hide ? 'Show discarded' : 'Hide discarded'),
    ],
  );

  /// Sort field and direction, standing in for the table headers on a phone.
  Widget _sortMenu() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Sort by'),
      const SizedBox(width: 8),
      DropdownButton<SortColumn?>(
        key: const Key('sort-by'),
        value: _sortColumn,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(value: null, child: Text('Newest')),
          for (final c in SortColumn.values)
            DropdownMenuItem(value: c, child: Text(c.label)),
        ],
        onChanged: (c) => setState(() {
          _sortColumn = c;
          _ascending = true;
        }),
      ),
      if (_sortColumn != null)
        IconButton(
          key: const Key('sort-direction'),
          tooltip: _ascending ? 'Ascending' : 'Descending',
          icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
          onPressed: () => setState(() => _ascending = !_ascending),
        ),
    ],
  );

  /// One tappable row per flat: name on top, price, size, B(B) and distance
  /// below.
  List<Widget> _compactRows(BuildContext context, List<Flat> shown) {
    final theme = Theme.of(context);
    return [
      for (final f in shown) ...[
        ListTile(
          key: Key('flat-row-${f.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(f.name, style: _style(f.discarded)),
          subtitle: Text(
            [
              formatCrore(f.price),
              f.sizeSqft == null ? '– sq ft' : '${f.sizeSqft} sq ft',
              formatBb(f.bedrooms, f.bathrooms),
              formatKm(f.distanceM),
            ].join('  ·  '),
            style: _style(f.discarded) ?? theme.textTheme.bodyMedium,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => goTo(context, '/flats/${f.id}'),
        ),
        const Divider(height: 1),
      ],
    ];
  }

  Widget _table(BuildContext context, List<Flat> shown) {
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
        column('B(B)', SortColumn.bb, numeric: true),
        column('Distance to Deodar Street', SortColumn.distance, numeric: true),
      ],
      rows: [
        for (final f in shown)
          DataRow(
            onSelectChanged: (_) => goTo(context, '/flats/${f.id}'),
            cells: [
              _cell(f.name, f.discarded),
              _cell(formatCrore(f.price), f.discarded),
              _cell(f.sizeSqft?.toString() ?? '–', f.discarded),
              _cell(formatBb(f.bedrooms, f.bathrooms), f.discarded),
              _cell(formatKm(f.distanceM), f.discarded),
            ],
          ),
      ],
    );
  }

  TextStyle? _style(bool discarded) => discarded
      ? const TextStyle(
          decoration: TextDecoration.lineThrough,
          color: Colors.grey,
        )
      : null;

  DataCell _cell(String text, bool discarded) =>
      DataCell(Text(text, style: _style(discarded)));
}
