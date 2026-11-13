// The shared write passphrase: asked for on the first write, remembered in the
// browser (local storage) until "Forget passphrase" is clicked, and sent to the
// Worker in the X-Passphrase header.
//
// A page that writes calls:
//
//   final res = await sendWrite(context, (headers) =>
//       client.post(url, headers: {...headers, 'content-type': 'application/json'},
//           body: jsonEncode(data)));
//   if (res == null) return; // the user cancelled the prompt; keep the form
//
// and puts `const ForgetPassphraseButton()` in its AppBar actions.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const passphraseHeader = 'X-Passphrase';
const _storageKey = 'write_passphrase';

/// The remembered passphrase. [current] is null when none is remembered.
class PassphraseStore {
  PassphraseStore._();

  static final instance = PassphraseStore._();

  final ValueNotifier<String?> current = ValueNotifier(null);
  Future<void>? _loading;

  Future<String?> load() async {
    await (_loading ??= SharedPreferences.getInstance()
        .then((p) => current.value = p.getString(_storageKey)));
    return current.value;
  }

  Future<void> remember(String passphrase) async {
    await load();
    current.value = passphrase;
    await (await SharedPreferences.getInstance())
        .setString(_storageKey, passphrase);
  }

  Future<void> forget() async {
    await load();
    current.value = null;
    await (await SharedPreferences.getInstance()).remove(_storageKey);
  }

  /// Tests only: drop the in-memory state so the next [load] re-reads storage.
  @visibleForTesting
  void reset() {
    _loading = null;
    current.value = null;
  }
}

/// Headers carrying the passphrase, asking for it first if none is remembered.
/// Returns null if the user cancels the prompt.
Future<Map<String, String>?> writeHeaders(BuildContext context,
    {String? error}) async {
  final store = PassphraseStore.instance;
  var passphrase = await store.load();
  if (passphrase == null) {
    if (!context.mounted) return null;
    passphrase = await showDialog<String>(
      context: context,
      builder: (_) => PassphraseDialog(error: error),
    );
    if (passphrase == null || passphrase.isEmpty) return null;
    await store.remember(passphrase);
  }
  return {passphraseHeader: passphrase};
}

/// Sends a write with the passphrase. On 401 the passphrase is forgotten and
/// the prompt opens again saying "Wrong passphrase". Returns the response, or
/// null if the user cancels the prompt (the caller keeps what was typed).
Future<http.Response?> sendWrite(
  BuildContext context,
  Future<http.Response> Function(Map<String, String> headers) send,
) async {
  String? error;
  while (true) {
    final headers = await writeHeaders(context, error: error);
    if (headers == null) return null;
    final res = await send(headers);
    if (res.statusCode != 401) return res;
    await PassphraseStore.instance.forget();
    error = 'Wrong passphrase';
    if (!context.mounted) return null;
  }
}

class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({super.key, this.error});

  final String? error;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Changes need the shared passphrase. '
              'This browser remembers it until you click Forget passphrase.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('passphrase-field'),
            controller: _controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              errorText: widget.error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

/// "Forget passphrase" for the top bar, shown only while one is remembered.
class ForgetPassphraseButton extends StatefulWidget {
  const ForgetPassphraseButton({super.key});

  @override
  State<ForgetPassphraseButton> createState() => _ForgetPassphraseButtonState();
}

class _ForgetPassphraseButtonState extends State<ForgetPassphraseButton> {
  @override
  void initState() {
    super.initState();
    PassphraseStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: PassphraseStore.instance.current,
      builder: (context, passphrase, _) => passphrase == null
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: () async {
                await PassphraseStore.instance.forget();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Passphrase forgotten')));
              },
              child: const Text('Forget passphrase'),
            ),
    );
  }
}
