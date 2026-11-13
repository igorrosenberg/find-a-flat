import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_router.dart';
import 'flat_detail.dart' show notesMax;
import 'passphrase.dart';
import 'top_bar.dart';

/// /flats/new: form to create a flat. The Worker geocodes the address and
/// computes the distance; on success the browser goes to the detail page.
class AddFlatPage extends StatefulWidget {
  const AddFlatPage({super.key, required this.client});

  final http.Client client;

  @override
  State<AddFlatPage> createState() => _AddFlatPageState();
}

class _AddFlatPageState extends State<AddFlatPage> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final f in [
      'name',
      'price',
      'size_sqft',
      'bedrooms',
      'bathrooms',
      'listing_url',
      'notes',
      'address',
    ])
      f: TextEditingController(),
  };

  /// Errors the server returned, shown next to the matching field.
  Map<String, String> _serverErrors = {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(String field) => _fields[field]!.text.trim();

  Map<String, Object?> _body() {
    num? number(String f) => _text(f).isEmpty ? null : num.parse(_text(f));
    final crore = number('price');
    return {
      'name': _text('name'),
      'address': _text('address'),
      // Typed in crore, stored as whole rupees.
      'price': crore == null ? null : (crore * 1e7).round(),
      'size_sqft': number('size_sqft')?.round(),
      'bedrooms': number('bedrooms'),
      'bathrooms': number('bathrooms'),
      'listing_url': _text('listing_url').isEmpty ? null : _text('listing_url'),
      'notes': _text('notes').isEmpty ? null : _fields['notes']!.text,
    };
  }

  Future<void> _save() async {
    setState(() {
      _serverErrors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = jsonEncode(_body());
      final res = await sendWrite(
        context,
        (headers) => widget.client.post(
          Uri.base.resolve('/api/flats'),
          headers: {'content-type': 'application/json', ...headers},
          body: body,
        ),
      );
      if (!mounted || res == null) return; // Cancelled: keep the form.
      final json = _decode(res.body);
      if (res.statusCode == 201) {
        replaceWith(context, '/flats/${json['id']}');
        return;
      }
      setState(() {
        final fields = json['fields'];
        if (fields is Map) {
          _serverErrors = fields.map((k, v) => MapEntry('$k', '$v'));
        }
        _error = json['error'] as String? ?? 'Save failed (${res.statusCode})';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  Widget _field(
    String field,
    String label, {
    String? Function(String)? validator,
    TextInputType? keyboard,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(field),
        controller: _fields[field],
        keyboardType: keyboard,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        // Enforce any limit without showing a character counter.
        buildCounter: (
          _, {
          required currentLength,
          required isFocused,
          maxLength,
        }) => null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: maxLines > 1,
          border: const OutlineInputBorder(),
        ),
        forceErrorText: _serverErrors[field],
        validator: (v) => validator?.call((v ?? '').trim()),
        onChanged: (_) {
          if (_serverErrors.containsKey(field)) {
            setState(() => _serverErrors = {..._serverErrors}..remove(field));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: const TopBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    'name',
                    'Name',
                    validator: requiredText,
                    hint: 'e.g. 2-bed near park',
                  ),
                  _field(
                    'price',
                    'Price (₹ crore)',
                    validator: positiveNumber,
                    keyboard: numberKeyboard,
                    hint: 'e.g. 1.05',
                  ),
                  _field(
                    'size_sqft',
                    'Size (sq ft)',
                    validator: positiveNumber,
                    keyboard: numberKeyboard,
                  ),
                  _field(
                    'bedrooms',
                    'Bedrooms (optional)',
                    validator: wholeNumber,
                    keyboard: TextInputType.number,
                  ),
                  _field(
                    'bathrooms',
                    'Bathrooms (optional)',
                    validator: wholeNumber,
                    keyboard: TextInputType.number,
                  ),
                  _field(
                    'listing_url',
                    'Listing URL (optional)',
                    validator: httpUrl,
                    keyboard: TextInputType.url,
                  ),
                  _field(
                    'notes',
                    'Notes (optional)',
                    keyboard: TextInputType.multiline,
                    hint: 'Viewing notes, questions for the agent…',
                    minLines: 4,
                    maxLines: 12,
                    maxLength: notesMax,
                  ),
                  _field('address', 'Address', validator: requiredText),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? requiredText(String v) => v.isEmpty ? 'Required' : null;

/// Empty is allowed: price and size are optional in the table.
String? positiveNumber(String v) {
  if (v.isEmpty) return null;
  final n = num.tryParse(v);
  return n == null || !n.isFinite || n <= 0
      ? 'Must be a positive number'
      : null;
}

String? wholeNumber(String v) {
  if (v.isEmpty) return null;
  final n = int.tryParse(v);
  return n == null || n < 0 ? 'Must be a whole number, 0 or more' : null;
}

String? httpUrl(String v) {
  if (v.isEmpty) return null;
  final uri = Uri.tryParse(v);
  return uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          uri.host.isEmpty
      ? 'Must be an http or https link'
      : null;
}
