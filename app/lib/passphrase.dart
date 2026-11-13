// Writes from the app. The Worker only serves the app after the passphrase
// has been entered on its login page, and the browser then sends the session
// cookie with every request, so pages need no passphrase handling of their own.
//
// A page that writes calls:
//
//   final res = await sendWrite(context, (headers) =>
//       client.post(url, headers: {...headers, 'content-type': 'application/json'},
//           body: jsonEncode(data)));
//   if (res == null) return; // not sent; keep the form as typed
//
// [headers] is empty today; it stays so pages need not change if writes ever
// need extra headers.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const sessionEndedMessage =
    'Your session has ended. Reload the page and enter the passphrase.';

/// Sends a write. On 401 (the session cookie is gone, e.g. the passphrase was
/// changed) it says so and returns null, so the caller keeps what was typed.
Future<http.Response?> sendWrite(
  BuildContext context,
  Future<http.Response> Function(Map<String, String> headers) send,
) async {
  final res = await send(const {});
  if (res.statusCode != 401) return res;
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text(sessionEndedMessage)));
  }
  return null;
}
