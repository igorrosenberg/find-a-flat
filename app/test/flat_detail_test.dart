import 'dart:convert';

import 'package:find_a_flat/app_router.dart';
import 'package:find_a_flat/flat_detail.dart';
import 'package:find_a_flat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> flatJson({bool discarded = false, double? lat = 22.55}) =>
    {
      'id': 3,
      'name': 'Park flat',
      'address': '1 Park St, Kolkata',
      'price': 10500000,
      'size_sqft': 1100,
      'bedrooms': 2,
      'bathrooms': null,
      'listing_url': null,
      'lat': lat,
      'lng': lat == null ? null : 88.35,
      'distance_m': lat == null ? null : 2800,
      'notes': 'Old note',
      'discarded': discarded ? 1 : 0,
      'created_at': '2026-11-13T00:00:00Z',
      'updated_at': '2026-11-13T00:00:00Z',
    };

http.Response ok(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> open(WidgetTester tester, http.Client client) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  await tester.pumpWidget(
    MaterialApp(
      routes: {'/home': (_) => const Text('LIST PAGE')},
      home: FlatDetailPage(id: 3, client: client),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every field and the distance', (tester) async {
    await open(tester, MockClient((_) async => ok(flatJson())));
    expect(find.text('Park flat'), findsOneWidget);
    expect(find.text('1 Park St, Kolkata'), findsOneWidget);
    expect(find.text('₹1.05 Cr'), findsOneWidget);
    expect(find.text('1100 sq ft'), findsOneWidget);
    expect(find.text('2.8 km'), findsOneWidget);
    expect(find.text('Old note'), findsOneWidget);
  });

  testWidgets('address is the last field on the page and in Edit', (
    tester,
  ) async {
    await open(tester, MockClient((_) async => ok(flatJson())));
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(
      top(find.text('Distance to Deodar Street')),
      lessThan(top(find.text('Address'))),
    );
    await tester.tap(find.byKey(const Key('edit')));
    await tester.pumpAndSettle();
    for (final key in [
      'name',
      'price',
      'size_sqft',
      'bedrooms',
      'bathrooms',
      'listing_url',
    ]) {
      expect(
        top(find.byKey(Key('edit-$key'))),
        lessThan(top(find.byKey(const Key('edit-address')))),
        reason: key,
      );
    }
  });

  testWidgets('unknown id shows not found', (tester) async {
    await open(
      tester,
      MockClient((_) async => ok({'error': 'Not found'}, 404)),
    );
    expect(find.text('Property not found.'), findsOneWidget);
  });

  testWidgets('no coordinates offers to drop a pin', (tester) async {
    await open(tester, MockClient((_) async => ok(flatJson(lat: null))));
    expect(find.byKey(const Key('pin-hint')), findsOneWidget);
    expect(find.text('Drop pin by hand'), findsOneWidget);
  });

  testWidgets('saving notes sends a PATCH', (tester) async {
    late http.Request patch;
    await open(
      tester,
      MockClient((req) async {
        if (req.method == 'PATCH') {
          patch = req;
          return ok({...flatJson(), 'notes': 'New note'});
        }
        return ok(flatJson());
      }),
    );
    await tester.enterText(find.byKey(const Key('notes')), 'New note');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-notes')));
    await tester.pumpAndSettle();
    expect(jsonDecode(patch.body), {'notes': 'New note'});
    expect(find.text('Notes saved'), findsOneWidget);
  });

  testWidgets('notes hide the counter but keep the 10,000 limit', (
    tester,
  ) async {
    await open(tester, MockClient((_) async => ok(flatJson())));
    expect(find.textContaining('/$notesMax'), findsNothing);
    expect(find.textContaining('10000'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('notes')),
      'x' * (notesMax + 5),
    );
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('notes')));
    expect(field.controller!.text.length, notesMax);
    expect(find.textContaining('/$notesMax'), findsNothing);
  });

  testWidgets('ticking discarded strikes the name through', (tester) async {
    await open(
      tester,
      MockClient(
        (req) async => req.method == 'PATCH'
            ? ok(flatJson(discarded: true))
            : ok(flatJson()),
      ),
    );
    await tester.tap(find.byKey(const Key('discarded')));
    await tester.pumpAndSettle();
    final name = tester.widget<Text>(find.byKey(const Key('flat-name')));
    expect(name.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('edit shows server field errors', (tester) async {
    await open(
      tester,
      MockClient(
        (req) async => req.method == 'PATCH'
            ? ok({
                'error': 'Invalid fields',
                'fields': {'address': 'Required'},
              }, 400)
            : ok(flatJson()),
      ),
    );
    await tester.tap(find.byKey(const Key('edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-price')), 'abc');
    await tester.tap(find.byKey(const Key('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Must be a positive number'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit-price')), '0.95');
    await tester.tap(find.byKey(const Key('edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('delete asks to confirm, then goes back to the list', (
    tester,
  ) async {
    var deleted = false;
    await open(
      tester,
      MockClient((req) async {
        if (req.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        return ok(flatJson());
      }),
    );
    await tester.tap(find.byKey(const Key('delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this property?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('LIST PAGE'), findsOneWidget);
  });

  testWidgets('the app routes /flats/:id to the detail page', (tester) async {
    final client = MockClient(
      (req) async => req.url.path == '/api/flats/3' ? ok(flatJson()) : ok([]),
    );
    await tester.pumpWidget(FindAFlatApp(client: client));
    await tester.pumpAndSettle();
    goTo(tester.element(find.byType(HomePage)), '/flats/3');
    await tester.pumpAndSettle();
    expect(find.text('Park flat'), findsOneWidget);
  });
}
