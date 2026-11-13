// Write passphrase, sent as X-Passphrase on every write.
//
// Minimal version for the detail page: it remembers the passphrase in memory
// only. The passphrase work (issue #8) owns this file and replaces it with
// the stored version and the same signatures.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String? _passphrase;

/// Headers for a write, asking for the passphrase first if needed.
/// Returns null if the user cancels.
Future<Map<String, String>?> writeHeaders(BuildContext context) async {
  _passphrase ??= await _ask(context, null);
  final p = _passphrase;
  return p == null ? null : {'X-Passphrase': p};
}

/// Sends a write with the passphrase. On 401 it forgets the passphrase and
/// asks again. Returns null if the user cancels.
Future<http.Response?> sendWrite(
  BuildContext context,
  Future<http.Response> Function(Map<String, String> headers) send,
) async {
  String? error;
  while (true) {
    if (_passphrase == null) {
      if (!context.mounted) return null;
      _passphrase = await _ask(context, error);
      if (_passphrase == null) return null;
    }
    final res = await send({'X-Passphrase': _passphrase!});
    if (res.statusCode != 401) return res;
    _passphrase = null;
    error = 'Wrong passphrase';
  }
}

void forgetPassphrase() => _passphrase = null;

Future<String?> _ask(BuildContext context, String? error) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() => Navigator.pop(
        context,
        controller.text.isEmpty ? null : controller.text,
      );
      return AlertDialog(
        title: const Text('Passphrase'),
        content: TextField(
          key: const Key('passphrase-field'),
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Write passphrase',
            errorText: error,
          ),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: submit, child: const Text('OK')),
        ],
      );
    },
  );
}

class ForgetPassphraseButton extends StatelessWidget {
  const ForgetPassphraseButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () {
      forgetPassphrase();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Passphrase forgotten')));
    },
    child: const Text('Forget passphrase'),
  );
}
