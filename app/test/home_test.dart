import 'package:find_a_flat/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows the empty state when there are no flats', (tester) async {
    final client = MockClient((_) async => http.Response('[]', 200));
    await tester.pumpWidget(FindAFlatApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('No flats yet.'), findsOneWidget);
  });

  testWidgets('lists flats from the API', (tester) async {
    final client = MockClient((_) async => http.Response(
        '[{"id":1,"name":"Test flat","price":9500000,"size_sqft":1100,'
        '"distance_m":1800,"discarded":0}]',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pumpWidget(FindAFlatApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Test flat'), findsOneWidget);
    expect(find.text('₹0.95 Cr'), findsOneWidget);
    expect(find.text('1.8 km'), findsOneWidget);
  });

  test('formatters', () {
    expect(formatCrore(10500000), '₹1.05 Cr');
    expect(formatCrore(null), '–');
    expect(formatKm(2345), '2.3 km');
  });
}
