import 'dart:convert';

import 'package:find_a_flat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A browser history in miniature: it records what the app writes to the
/// browser, and replays entries the way Back and Forward do.
class _History {
  _History(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method != 'routeInformationUpdated') return null;
        final args = call.arguments as Map;
        final entry = (args['uri'] as String, args['state']);
        if (args['replace'] == true && entries.isNotEmpty) {
          entries[pos] = entry;
        } else {
          entries
            ..removeRange(pos + 1, entries.length)
            ..add(entry);
          pos = entries.length - 1;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
  }

  final WidgetTester tester;
  final entries = <(String, Object?)>[];
  var pos = -1;

  List<String> get urls => [for (final e in entries) e.$1];
  String get current => entries[pos].$1;

  Future<void> show() async {
    final (uri, state) = entries[pos];
    final message = const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': uri, 'state': state}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> back() async {
    pos--;
    await show();
  }

  Future<void> forward() async {
    pos++;
    await show();
  }
}

const _flats =
    '['
    '{"id":2,"name":"Zed flat","price":8000000,"size_sqft":900,"distance_m":5000,"discarded":0},'
    '{"id":1,"name":"Alpha flat","price":9500000,"size_sqft":1100,"distance_m":1800,"discarded":0}'
    ']';

Map<String, Object?> _flat(int id, String name) => {
  'id': id,
  'name': name,
  'price': 9500000,
  'size_sqft': 1100,
  'distance_m': 1800,
  'address': '1 Park St, Kolkata',
  'bedrooms': null,
  'bathrooms': null,
  'listing_url': null,
  'lat': null,
  'lng': null,
  'notes': '',
  'discarded': 0,
  'created_at': '2026-11-13T00:00:00Z',
  'updated_at': '2026-11-13T00:00:00Z',
};

http.Client _api() => MockClient((req) async {
  final json = switch ((req.method, req.url.path)) {
    ('GET', '/api/flats') => _flats,
    ('GET', '/api/flats/1') => jsonEncode(_flat(1, 'Alpha flat')),
    ('GET', '/api/flats/2') => jsonEncode(_flat(2, 'Zed flat')),
    ('POST', '/api/flats') => jsonEncode(_flat(7, 'New flat')),
    ('GET', '/api/flats/7') => jsonEncode(_flat(7, 'New flat')),
    _ => '[]',
  };
  return http.Response(
    json,
    req.method == 'POST' ? 201 : 200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Future<_History> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final history = _History(tester);
  await tester.pumpWidget(FindAFlatApp(client: _api()));
  await tester.pumpAndSettle();
  return history;
}

List<String> _rowNames(WidgetTester tester) => tester
    .widget<DataTable>(find.byType(DataTable))
    .rows
    .map((r) => ((r.cells.first.child as Text).data!))
    .toList();

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => hideDiscarded.value = false);

  testWidgets('each page is its own entry, and Back and Forward walk them', (
    tester,
  ) async {
    final h = await _start(tester);
    expect(h.urls, ['/home']);

    // List, sorted by name, then a flat's detail page.
    await _tapText(tester, 'Name');
    expect(_rowNames(tester), ['Alpha flat', 'Zed flat']);
    await _tapText(tester, 'Zed flat');
    expect(h.urls, ['/home', '/flats/2']);
    expect(find.byType(DataTable), findsNothing);

    // Back returns to the list as it was left.
    await h.back();
    expect(find.byType(DataTable), findsOneWidget);
    expect(_rowNames(tester), ['Alpha flat', 'Zed flat']);

    // Forward reopens the detail page.
    await h.forward();
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Zed flat'), findsWidgets);

    // Map, then Add property from the map.
    await _tapText(tester, 'Map');
    await _tapText(tester, 'Add property');
    expect(h.urls, ['/home', '/flats/2', '/map', '/flats/new']);
    expect(find.text('Save'), findsOneWidget);

    // Back three times walks to the list, then Forward three to the form.
    await h.back();
    expect(h.current, '/map');
    expect(
      find.widgetWithText(FloatingActionButton, 'Add property'),
      findsOneWidget,
    );
    await h.back();
    expect(h.current, '/flats/2');
    expect(find.text('Zed flat'), findsWidgets);
    await h.back();
    expect(find.byType(DataTable), findsOneWidget);
    await h.forward();
    await h.forward();
    await h.forward();
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Back works from a detail page opened by its URL', (
    tester,
  ) async {
    final h = await _start(tester);
    // As if the user typed /flats/1, then went to the list from the top bar.
    h.entries
      ..clear()
      ..add(('/flats/1', null));
    h.pos = 0;
    await h.show();
    expect(find.byType(DataTable), findsNothing);
    await _tapText(tester, 'List');
    expect(h.urls, ['/flats/1', '/home']);
    await h.back();
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Alpha flat'), findsWidgets);
  });

  testWidgets('a saved form is replaced by the new flat, not kept in Back', (
    tester,
  ) async {
    final h = await _start(tester);
    final add = find.widgetWithText(FilledButton, 'Add property');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('name')), 'New flat');
    await tester.enterText(find.byKey(const ValueKey('address')), 'Park St');
    await tester.enterText(find.byKey(const ValueKey('price')), '1');
    await tester.enterText(find.byKey(const ValueKey('size_sqft')), '900');
    await _tapText(tester, 'Save');
    expect(h.urls, ['/home', '/flats/7']);
    await h.back();
    expect(find.byType(DataTable), findsOneWidget);
  });
}
