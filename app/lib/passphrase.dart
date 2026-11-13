// Write passphrase, sent as X-Passphrase on every write.
//
// Minimal stand-in so the add form works on its own: the passphrase issue
// (#8) owns this file and replaces it, keeping these signatures.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String? _passphrase;

/// Runs [send] with the X-Passphrase header. Asks for the passphrase on first
/// use; on 401 forgets it, says "Wrong passphrase" and asks again. Returns
/// null if the user cancels, so the caller keeps what was typed.
Future<http.Response?> sendWrite(
  BuildContext context,
  Future<http.Response> Function(Map<String, String> headers) send,
) async {
  String? error;
  while (true) {
    var passphrase = _passphrase;
    if (passphrase == null) {
      passphrase = await _ask(context, error);
      if (passphrase == null) return null;
    }
    final res = await send({'X-Passphrase': passphrase});
    if (res.statusCode != 401) {
      _passphrase = passphrase;
      return res;
    }
    _passphrase = null;
    error = 'Wrong passphrase';
    if (!context.mounted) return null;
  }
}

Future<String?> _ask(BuildContext context, String? error) {
  final controller = TextEditingController();
  void submit(BuildContext ctx) => Navigator.of(ctx).pop(controller.text);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Passphrase'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Write passphrase',
          errorText: error,
        ),
        onSubmitted: (_) => submit(ctx),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: () => submit(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Drops the remembered passphrase; the top bar's "Forget passphrase".
void forgetPassphrase() => _passphrase = null;

/// Top bar action that drops the remembered passphrase.
class ForgetPassphraseButton extends StatelessWidget {
  const ForgetPassphraseButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: forgetPassphrase,
    child: const Text('Forget passphrase'),
  );
}
