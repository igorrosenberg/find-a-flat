import 'package:find_a_flat/app_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A browser history in miniature: it records what the app writes to the
/// browser, and replays entries the way Back and Forward do.
class BrowserHistory {
  BrowserHistory(this.tester) {
    // The app's own Back (after a save) moves this history too.
    browserBack = () {
      pos--;
      _send();
    };
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
    addTearDown(() => browserBack = () {});
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
    _send();
    await tester.pumpAndSettle();
  }

  void _send() {
    final (uri, state) = entries[pos];
    final message = const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': uri, 'state': state}),
    );
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      message,
      (_) {},
    );
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
