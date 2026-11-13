import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'add_flat_page.dart';

void main() {
  usePathUrlStrategy();
  runApp(const FindAFlatApp());
}

class FindAFlatApp extends StatelessWidget {
  const FindAFlatApp({super.key, this.client});

  /// Injected in tests; the real app uses a default client.
  final http.Client? client;

  Route<void> _route(RouteSettings settings) {
    final c = client ?? http.Client();
    final Widget page = switch (settings.name) {
      '/flats/new' => AddFlatPage(client: c),
      _ => HomePage(client: c),
    };
    // Unknown paths show the list, so the URL bar always matches the page.
    final name = settings.name == '/flats/new' ? '/flats/new' : '/home';
    return MaterialPageRoute(
      settings: RouteSettings(name: name),
      builder: (_) => page,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Find a flat',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      // Open the page for the URL directly, with no back stack under it.
      onGenerateInitialRoutes: (initial) =>
          [_route(RouteSettings(name: initial))],
      onGenerateRoute: _route,
    );
  }
}

class Flat {
  Flat.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        price = json['price'] as int?,
        sizeSqft = json['size_sqft'] as int?,
        distanceM = json['distance_m'] as int?,
        discarded = (json['discarded'] as int? ?? 0) == 1;

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

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client});

  final http.Client client;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List<Flat>> _flats = fetchFlats(widget.client);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a flat'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/flats/new'),
            child: const Text('Add property'),
          ),
        ],
      ),
      body: FutureBuilder<List<Flat>>(
        future: _flats,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load flats: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final flats = snapshot.data!;
          if (flats.isEmpty) {
            return const Center(child: Text('No flats yet.'));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Price')),
                DataColumn(label: Text('Size (sq ft)'), numeric: true),
                DataColumn(label: Text('Distance to Deodar Street')),
              ],
              rows: [
                for (final f in flats)
                  DataRow(cells: [
                    _cell(f.name, f.discarded),
                    _cell(formatCrore(f.price), f.discarded),
                    _cell(f.sizeSqft?.toString() ?? '–', f.discarded),
                    _cell(formatKm(f.distanceM), f.discarded),
                  ]),
              ],
            ),
          );
        },
      ),
    );
  }

  DataCell _cell(String text, bool discarded) => DataCell(Text(
        text,
        style: discarded
            ? const TextStyle(
                decoration: TextDecoration.lineThrough, color: Colors.grey)
            : null,
      ));
}
