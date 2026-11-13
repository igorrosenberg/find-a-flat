import 'package:find_a_flat/passphrase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A page with one "Save" button that writes through [sendWrite]. [replies]
/// gives the status code for each request in turn.
class _Harness {
  _Harness(this.replies);

  final List<int> replies;
  final sent = <String?>[];
  http.Response? result;
  bool finished = false;

  Widget app() => MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [ForgetPassphraseButton()]),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await sendWrite(context, (headers) async {
                  sent.add(headers[passphraseHeader]);
                  return http.Response('{}', replies[sent.length - 1]);
                });
                finished = true;
              },
              child: const Text('Save'),
            ),
          ),
        ),
      );
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('passphrase-field')), text);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PassphraseStore.instance.reset();
  });

  testWidgets('first write asks, later writes reuse the passphrase',
      (tester) async {
    final h = _Harness([200, 200]);
    await tester.pumpWidget(h.app());
    expect(find.text('Forget passphrase'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(PassphraseDialog), findsOneWidget);
    await _type(tester, 'open sesame');
    expect(h.sent, ['open sesame']);
    expect(h.result!.statusCode, 200);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(PassphraseDialog), findsNothing);
    expect(h.sent, ['open sesame', 'open sesame']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('write_passphrase'), 'open sesame');
    expect(find.text('Forget passphrase'), findsOneWidget);
  });

  testWidgets('a wrong passphrase asks again, saying so', (tester) async {
    final h = _Harness([401, 200]);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await _type(tester, 'nope');
    expect(find.text('Wrong passphrase'), findsOneWidget);
    await _type(tester, 'open sesame');
    expect(h.sent, ['nope', 'open sesame']);
    expect(h.result!.statusCode, 200);
    expect(PassphraseStore.instance.current.value, 'open sesame');
  });

  testWidgets('cancelling the prompt sends nothing', (tester) async {
    final h = _Harness([]);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.finished, isTrue);
    expect(h.result, isNull);
    expect(h.sent, isEmpty);
  });

  testWidgets('Forget passphrase makes the next write ask again',
      (tester) async {
    SharedPreferences.setMockInitialValues({'write_passphrase': 'old'});
    final h = _Harness([200]);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget passphrase'));
    await tester.pumpAndSettle();
    expect(find.text('Forget passphrase'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(PassphraseDialog), findsOneWidget);
    await _type(tester, 'new');
    expect(h.sent, ['new']);
  });
}
