import 'package:find_a_flat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MockClient _api(String body) => MockClient(
  (_) async => http.Response(
    body,
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

const _threeFlats =
    '['
    '{"id":3,"name":"Cheap far","price":8000000,"size_sqft":900,"distance_m":5000,"discarded":0},'
    '{"id":2,"name":"Rejected","price":12000000,"size_sqft":1500,"distance_m":null,"discarded":1},'
    '{"id":1,"name":"Big near","price":9500000,"size_sqft":1100,"distance_m":1800,"discarded":0}'
    ']';

List<String> _names(WidgetTester tester) => tester
    .widget<DataTable>(find.byType(DataTable))
    .rows
    .map((r) => ((r.cells.first.child as Text).data!))
    .toList();

void main() {
  setUp(() {
    hideDiscarded.value = false;
  });

  testWidgets('shows the empty state with an Add property button', (
    tester,
  ) async {
    await tester.pumpWidget(FindAFlatApp(client: _api('[]')));
    await tester.pumpAndSettle();
    expect(find.text('No flats yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add property'), findsOneWidget);
  });

  testWidgets('lists flats from the API, with the top bar', (tester) async {
    await tester.pumpWidget(FindAFlatApp(client: _api(_threeFlats)));
    await tester.pumpAndSettle();
    expect(find.text('Big near'), findsOneWidget);
    expect(find.text('₹0.95 Cr'), findsOneWidget);
    expect(find.text('1.8 km'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);
    for (final link in ['List', 'Map']) {
      expect(find.widgetWithText(TextButton, link), findsOneWidget);
    }
    // Add property is not in the top bar: one button, below the table.
    expect(find.widgetWithText(TextButton, 'Add property'), findsNothing);
    final add = find.widgetWithText(FilledButton, 'Add property');
    expect(add, findsOneWidget);
    expect(
      tester.getTopLeft(add).dy,
      greaterThan(tester.getBottomLeft(find.byType(DataTable)).dy),
    );
    expect(_names(tester), ['Cheap far', 'Rejected', 'Big near']);
  });

  testWidgets('discarded rows are struck through and can be hidden', (
    tester,
  ) async {
    await tester.pumpWidget(FindAFlatApp(client: _api(_threeFlats)));
    await tester.pumpAndSettle();
    final style = tester.widget<Text>(find.text('Rejected')).style!;
    expect(style.decoration, TextDecoration.lineThrough);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsNothing);
    expect(hideDiscarded.value, isTrue);
  });

  testWidgets('clicking a header sorts, clicking again reverses', (
    tester,
  ) async {
    await tester.pumpWidget(FindAFlatApp(client: _api(_threeFlats)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    expect(_names(tester), ['Cheap far', 'Big near', 'Rejected']);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    expect(_names(tester), ['Rejected', 'Big near', 'Cheap far']);
    // The table is wider than the test screen, so scroll the header into view.
    await tester.ensureVisible(find.text('Distance to Deodar Street'));
    await tester.tap(find.text('Distance to Deodar Street'));
    await tester.pumpAndSettle();
    expect(_names(tester), ['Big near', 'Cheap far', 'Rejected']);
  });

  testWidgets('clicking a row opens its detail page', (tester) async {
    final pushed = <String>[];
    await tester.pumpWidget(
      FindAFlatApp(
        client: _api(_threeFlats),
        navigatorObservers: [_Recorder(pushed)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Big near'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/flats/1');
  });

  test('formatters', () {
    expect(formatCrore(10500000), '₹1.05 Cr');
    expect(formatCrore(null), '–');
    expect(formatKm(2345), '2.3 km');
    expect(formatKm(null), '–');
  });
}

class _Recorder extends NavigatorObserver {
  _Recorder(this.names);
  final List<String> names;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name ?? '');
}
