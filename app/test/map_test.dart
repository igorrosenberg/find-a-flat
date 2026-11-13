import 'dart:convert';

import 'package:find_a_flat/map_page.dart';
import 'package:find_a_flat/main.dart' show hideDiscarded;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Draws every tile as a transparent pixel, so tests make no tile requests.
class _BlankTiles extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

const _flats =
    '['
    '{"id":1,"name":"Lake view","price":9500000,"size_sqft":1100,'
    '"bedrooms":3,"bathrooms":2,'
    '"distance_m":1800,"lat":22.51,"lng":88.36,"discarded":0},'
    '{"id":2,"name":"Old block","price":10500000,"size_sqft":900,'
    '"distance_m":2500,"lat":22.54,"lng":88.37,"discarded":1},'
    '{"id":3,"name":"No address yet","price":null,"size_sqft":null,'
    '"distance_m":null,"lat":null,"lng":null,"discarded":0}'
    ']';

Future<void> _pumpMap(WidgetTester tester) async {
  final client = MockClient(
    (_) async => http.Response(
      _flats,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        '/flats/1': (_) => const Text('flat page 1'),
        '/flats/new': (_) => const Text('add page'),
      },
      home: MapPage(client: client, tileProvider: _BlankTiles()),
    ),
  );
  await tester.pumpAndSettle();
}

Icon _icon(WidgetTester tester, String key) =>
    tester.widget<Icon>(find.byKey(Key(key)));

void main() {
  tearDown(() => hideDiscarded.value = false);

  testWidgets('pins every flat with coordinates, plus Deodar St', (
    tester,
  ) async {
    await _pumpMap(tester);
    expect(find.byKey(const Key('deodar-marker')), findsOneWidget);
    expect(find.byKey(const Key('pin-1')), findsOneWidget);
    expect(find.byKey(const Key('pin-2')), findsOneWidget);
    expect(find.byKey(const Key('pin-3')), findsNothing);
    expect(_icon(tester, 'pin-1').color, Colors.teal);
    expect(_icon(tester, 'pin-2').color, Colors.grey);
  });

  testWidgets('a pin opens a popup that links to the property page', (
    tester,
  ) async {
    await _pumpMap(tester);
    await tester.tap(find.byKey(const Key('pin-1')));
    await tester.pumpAndSettle();
    expect(find.text('Lake view'), findsOneWidget);
    expect(find.text('₹0.95 Cr'), findsOneWidget);
    expect(find.text('1100 sq ft'), findsOneWidget);
    expect(find.text('B(B) 3(2)'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('flat page 1'), findsOneWidget);
  });

  testWidgets('hide discarded removes grey pins', (tester) async {
    await _pumpMap(tester);
    hideDiscarded.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-1')), findsOneWidget);
    expect(find.byKey(const Key('pin-2')), findsNothing);
  });

  testWidgets('Add property button opens the add page', (tester) async {
    await _pumpMap(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add property'));
    await tester.pumpAndSettle();
    expect(find.text('add page'), findsOneWidget);
  });

  testWidgets('+ and − buttons zoom the map in and out', (tester) async {
    await _pumpMap(tester);
    double zoom() =>
        MapCamera.of(tester.element(find.byKey(const Key('zoom-in')))).zoom;
    final start = zoom();
    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.pumpAndSettle();
    expect(zoom(), closeTo(start + 1, 0.001));
    await tester.tap(find.byKey(const Key('zoom-out')));
    await tester.tap(find.byKey(const Key('zoom-out')));
    await tester.pumpAndSettle();
    expect(zoom(), closeTo(start - 1, 0.001));
  });
}
