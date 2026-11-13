import 'package:find_a_flat/passphrase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Widget _app(int status, void Function(http.Response?) done) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => done(
          await sendWrite(
            context,
            (headers) async => http.Response('{}', status),
          ),
        ),
        child: const Text('Save'),
      ),
    ),
  ),
);

void main() {
  testWidgets('a write returns the response', (tester) async {
    http.Response? result;
    await tester.pumpWidget(_app(201, (r) => result = r));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.statusCode, 201);
  });

  testWidgets('a 401 says the session ended and returns null', (tester) async {
    var called = false;
    http.Response? result;
    await tester.pumpWidget(
      _app(401, (r) {
        called = true;
        result = r;
      }),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(result, isNull);
    expect(find.text(sessionEndedMessage), findsOneWidget);
  });
}
