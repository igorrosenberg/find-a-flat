import 'dart:convert';

import 'package:find_a_flat/flat_page.dart';
import 'package:find_a_flat/main.dart';
import 'package:find_a_flat/passphrase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'browser_history.dart';

/// Opens the add page from the list's Add property button.
Future<void> openAddPage(WidgetTester tester, http.Client client) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  BrowserHistory(tester);
  await tester.pumpWidget(FindAFlatApp(client: client));
  await tester.pumpAndSettle();
  final add = find.widgetWithText(FilledButton, 'Add property');
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  expect(find.text('Save'), findsOneWidget);
}

Future<void> fill(WidgetTester tester, Map<String, String> values) async {
  for (final e in values.entries) {
    await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
  }
}

Map<String, Object?> flatJson({bool discarded = false, double? lat = 22.55}) =>
    {
      'id': 3,
      'name': 'Park flat',
      'address': '1 Park St, Kolkata',
      'price': 10500000,
      'size_sqft': 1100,
      'bedrooms': 2,
      'bathrooms': null,
      'listing_url': 'https://example.com/ad',
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

/// Opens flat 3 on its own, with a stand-in list page to go back to.
Future<void> openFlat(WidgetTester tester, http.Client client) async {
  await tester.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      routes: {'/home': (_) => const Text('LIST PAGE')},
      home: FlatPage(id: 3, client: client),
    ),
  );
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

void main() {
  group('add', addTests);
  group('edit', editTests);
}

void editTests() {
  testWidgets('loads every field into the form, address last', (tester) async {
    await openFlat(tester, MockClient((_) async => ok(flatJson())));
    expect(fieldText(tester, 'name'), 'Park flat');
    expect(fieldText(tester, 'price'), '1.05');
    expect(fieldText(tester, 'size_sqft'), '1100');
    expect(fieldText(tester, 'bedrooms'), '2');
    expect(fieldText(tester, 'bathrooms'), '');
    expect(fieldText(tester, 'listing_url'), 'https://example.com/ad');
    expect(fieldText(tester, 'notes'), 'Old note');
    expect(fieldText(tester, 'address'), '1 Park St, Kolkata');
    expect(find.text('Distance to Deodar Street: 2.8 km'), findsOneWidget);
    expect(find.byKey(const Key('open-listing')), findsOneWidget);
    expect(find.byKey(const Key('zoom-in')), findsOneWidget);
    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    for (final key in formFields.take(formFields.length - 1)) {
      expect(top(key), lessThan(top('address')), reason: key);
    }
  });

  testWidgets('unknown id shows not found', (tester) async {
    await openFlat(
      tester,
      MockClient((_) async => ok({'error': 'Not found'}, 404)),
    );
    expect(find.text('Property not found.'), findsOneWidget);
  });

  testWidgets('no coordinates offers to drop a pin', (tester) async {
    await openFlat(tester, MockClient((_) async => ok(flatJson(lat: null))));
    expect(find.byKey(const Key('pin-hint')), findsOneWidget);
    expect(find.text('Drop pin by hand'), findsOneWidget);
  });

  testWidgets('Save sends every field in one PATCH, then shows the list', (
    tester,
  ) async {
    final patches = <http.Request>[];
    await openFlat(
      tester,
      MockClient((req) async {
        if (req.method != 'PATCH') return ok(flatJson());
        patches.add(req);
        return ok(flatJson(discarded: true));
      }),
    );
    await tester.enterText(find.byKey(const ValueKey('notes')), 'New note');
    await tester.enterText(find.byKey(const ValueKey('price')), '0.95');
    await tester.tap(find.byKey(const Key('discarded')));
    await tester.pump();
    // Discarded strikes the name through before saving.
    final name = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('name')),
        matching: find.byType(TextField),
      ),
    );
    expect(name.style?.decoration, TextDecoration.lineThrough);
    expect(patches, isEmpty);

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(jsonDecode(patches.single.body), {
      'name': 'Park flat',
      'address': '1 Park St, Kolkata',
      'price': 9500000,
      'size_sqft': 1100,
      'bedrooms': 2,
      'bathrooms': null,
      'listing_url': 'https://example.com/ad',
      'notes': 'New note',
      'discarded': true,
    });
    expect(find.text('LIST PAGE'), findsOneWidget);
  });

  testWidgets('field errors keep the form open', (tester) async {
    await openFlat(
      tester,
      MockClient(
        (req) async => req.method == 'PATCH'
            ? ok({
                'error': 'Invalid fields',
                'fields': {'address': 'At most 500 characters'},
              }, 400)
            : ok(flatJson()),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('price')), 'abc');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('Must be a positive number'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('price')), '0.95');
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('At most 500 characters'), findsOneWidget);
    expect(find.text('LIST PAGE'), findsNothing);
  });

  testWidgets('delete asks to confirm, then goes back to the list', (
    tester,
  ) async {
    var deleted = false;
    await openFlat(
      tester,
      MockClient((req) async {
        if (req.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        return ok(flatJson());
      }),
    );
    await tester.ensureVisible(find.byKey(const Key('delete')));
    await tester.tap(find.byKey(const Key('delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this property?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('LIST PAGE'), findsOneWidget);
  });

  testWidgets('the add form has no discarded flag, map or delete', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: FlatPage(client: MockClient((_) async => ok([])))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discarded')), findsNothing);
    expect(find.byKey(const Key('delete')), findsNothing);
    expect(find.byKey(const Key('pin-mode')), findsNothing);
  });
}

void addTests() {
  testWidgets('address is the last field', (tester) async {
    final client = MockClient((_) async => http.Response('[]', 200));
    await openAddPage(tester, client);
    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    for (final key in [
      'name',
      'price',
      'size_sqft',
      'bedrooms',
      'bathrooms',
      'listing_url',
      'notes',
    ]) {
      expect(top(key), lessThan(top('address')), reason: key);
    }
  });

  testWidgets('shows errors next to invalid fields without calling the API', (
    tester,
  ) async {
    var posts = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') posts++;
      return http.Response('[]', 200);
    });
    await openAddPage(tester, client);
    await fill(tester, {'price': '-1', 'size_sqft': 'big', 'bedrooms': '1.5'});
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));
    expect(find.text('Must be a positive number'), findsNWidgets(2));
    expect(find.text('Must be a whole number, 0 or more'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets('posts the flat, keeping the form when the session ended', (
    tester,
  ) async {
    final posts = <http.Request>[];
    final client = MockClient((req) async {
      if (req.method != 'POST') return http.Response('[]', 200);
      posts.add(req);
      if (posts.length == 1) {
        return http.Response('{"error":"Passphrase needed"}', 401);
      }
      return http.Response('{"id":7}', 201);
    });
    await openAddPage(tester, client);
    await fill(tester, {
      'name': '2-bed near park',
      'address': '12 Gariahat Road, Kolkata',
      'price': '1.05',
      'size_sqft': '1100',
      'bedrooms': '2',
    });
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 401: the session cookie is gone. Still on the form, values kept.
    expect(find.text(sessionEndedMessage), findsOneWidget);
    expect(find.text('2-bed near park'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = jsonDecode(posts.last.body) as Map<String, dynamic>;
    expect(body, {
      'name': '2-bed near park',
      'address': '12 Gariahat Road, Kolkata',
      'price': 10500000,
      'size_sqft': 1100,
      'bedrooms': 2,
      'bathrooms': null,
      'listing_url': null,
      'notes': null,
    });
    // Saved: back on the list.
    expect(find.text('Save'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add property'), findsOneWidget);
  });

  testWidgets('posts notes typed on the form, with no character counter', (
    tester,
  ) async {
    final posts = <http.Request>[];
    final client = MockClient((req) async {
      if (req.method != 'POST') return http.Response('[]', 200);
      posts.add(req);
      return http.Response('{"id":7}', 201);
    });
    await openAddPage(tester, client);
    await fill(tester, {
      'name': 'A',
      'notes': 'Ask about parking.\nSecond line',
      'address': 'B',
    });
    expect(find.textContaining('/ 10000'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body['notes'], 'Ask about parking.\nSecond line');
  });

  testWidgets('shows server field errors next to the field', (tester) async {
    final client = MockClient(
      (req) async => req.method == 'POST'
          ? http.Response(
              '{"error":"Some fields are invalid","fields":{"address":"At most 500 characters"}}',
              400,
            )
          : http.Response('[]', 200),
    );
    await openAddPage(tester, client);
    await fill(tester, {'name': 'A', 'address': 'B'});
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('At most 500 characters'), findsOneWidget);
    expect(find.text('Some fields are invalid'), findsOneWidget);
  });

  test('validators', () {
    expect(positiveNumber(''), isNull);
    expect(positiveNumber('0.95'), isNull);
    expect(positiveNumber('0'), isNotNull);
    expect(wholeNumber('0'), isNull);
    expect(wholeNumber('-1'), isNotNull);
    expect(httpUrl('https://example.com/ad'), isNull);
    expect(httpUrl('example.com'), isNotNull);
  });
}
