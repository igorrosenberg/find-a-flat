import 'dart:convert';

import 'package:find_a_flat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'browser_history.dart';

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
    ('PATCH', '/api/flats/2') => jsonEncode(_flat(2, 'Zed flat 2')),
    _ => '[]',
  };
  return http.Response(
    json,
    req.method == 'POST' ? 201 : 200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Future<BrowserHistory> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final history = BrowserHistory(tester);
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

  testWidgets('saving goes back to the list: Home > add > Home', (
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
    // The browser went Back to the list: no extra history entry.
    expect(h.urls, ['/home', '/flats/new']);
    expect(h.current, '/home');
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byKey(const ValueKey('name')), findsNothing);
  });

  testWidgets('saving an opened flat goes back to the list', (tester) async {
    final h = await _start(tester);
    await _tapText(tester, 'Zed flat');
    expect(h.current, '/flats/2');
    await tester.enterText(find.byKey(const ValueKey('name')), 'Zed flat 2');
    await _tapText(tester, 'Save');
    expect(h.urls, ['/home', '/flats/2']);
    expect(h.current, '/home');
    expect(find.byType(DataTable), findsOneWidget);
  });
}
