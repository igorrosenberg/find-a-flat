import 'dart:convert';

import 'package:find_a_flat/add_flat_page.dart';
import 'package:find_a_flat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Opens the add page from the list's Add property button.
Future<void> openAddPage(WidgetTester tester, http.Client client) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FindAFlatApp(client: client));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Add property'));
  await tester.pumpAndSettle();
  expect(find.text('Save'), findsOneWidget);
  // Start each test with no remembered passphrase.
  await tester.tap(find.text('Forget passphrase'));
  await tester.pump();
}

Future<void> fill(WidgetTester tester, Map<String, String> values) async {
  for (final e in values.entries) {
    await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
  }
}

Future<void> enterPassphrase(WidgetTester tester, String value) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Write passphrase'),
    value,
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
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

  testWidgets('posts the flat with the passphrase, keeping the form on 401', (
    tester,
  ) async {
    final posts = <http.Request>[];
    final client = MockClient((req) async {
      if (req.method != 'POST') return http.Response('[]', 200);
      posts.add(req);
      if (req.headers['X-Passphrase'] != 'right') {
        return http.Response('{"error":"Wrong passphrase"}', 401);
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

    await enterPassphrase(tester, 'wrong');
    expect(find.text('Wrong passphrase'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Cancelled after a wrong passphrase: still on the form, values kept.
    expect(find.text('2-bed near park'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester, 'right');

    final body = jsonDecode(posts.last.body) as Map<String, dynamic>;
    expect(body, {
      'name': '2-bed near park',
      'address': '12 Gariahat Road, Kolkata',
      'price': 10500000,
      'size_sqft': 1100,
      'bedrooms': 2,
      'bathrooms': null,
      'listing_url': null,
    });
    // Saved: the form is gone.
    expect(find.text('Save'), findsNothing);
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
    await enterPassphrase(tester, 'x');
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
