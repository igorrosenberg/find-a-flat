// One page to add, view and edit a property.
//
// /flats/new is the empty form. /flats/:id loads the property into the same
// form, so viewing it is editing it, with the extras an existing property
// has: the discarded flag, the distance, a small map with its pin, and
// Delete. Save and Delete both go back to the list: Home > this page > Home.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_router.dart';
import 'main.dart' show flatsChanged, formatKm;
import 'passphrase.dart';
import 'top_bar.dart';
import 'zoom_buttons.dart';

const notesMax = 10000;
const deodarStreet = LatLng(22.5261, 88.3598);

/// The form's text fields, in page order. Address is always last.
const formFields = [
  'name',
  'price',
  'size_sqft',
  'bedrooms',
  'bathrooms',
  'listing_url',
  'notes',
  'address',
];

class FlatDetail {
  FlatDetail.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      name = j['name'] as String,
      address = j['address'] as String,
      price = j['price'] as int?,
      sizeSqft = j['size_sqft'] as int?,
      bedrooms = j['bedrooms'] as int?,
      bathrooms = j['bathrooms'] as int?,
      listingUrl = j['listing_url'] as String?,
      lat = (j['lat'] as num?)?.toDouble(),
      lng = (j['lng'] as num?)?.toDouble(),
      distanceM = j['distance_m'] as int?,
      notes = j['notes'] as String? ?? '',
      discarded = (j['discarded'] as int? ?? 0) == 1;

  final int id;
  final String name;
  final String address;
  final int? price;
  final int? sizeSqft;
  final int? bedrooms;
  final int? bathrooms;
  final String? listingUrl;
  final double? lat;
  final double? lng;
  final int? distanceM;
  final String notes;
  final bool discarded;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  /// The text each form field starts with.
  Map<String, String> get formText => {
    'name': name,
    // Stored as whole rupees, typed in crore.
    'price': price == null ? '' : (price! / 1e7).toStringAsFixed(2),
    'size_sqft': sizeSqft?.toString() ?? '',
    'bedrooms': bedrooms?.toString() ?? '',
    'bathrooms': bathrooms?.toString() ?? '',
    'listing_url': listingUrl ?? '',
    'notes': notes,
    'address': address,
  };
}

class NotFound implements Exception {}

/// The add and edit page: [id] null adds a property, otherwise edits it.
class FlatPage extends StatefulWidget {
  const FlatPage({super.key, this.id, required this.client});

  final int? id;
  final http.Client client;

  @override
  State<FlatPage> createState() => _FlatPageState();
}

class _FlatPageState extends State<FlatPage> {
  final _form = GlobalKey<FormState>();
  final _fields = {for (final f in formFields) f: TextEditingController()};

  bool get _adding => widget.id == null;
  late final Uri _url = Uri.base.resolve(
    _adding ? '/api/flats' : '/api/flats/${widget.id}',
  );

  /// The saved property; null while loading, and on the add form.
  FlatDetail? _flat;
  Object? _loadError;
  bool _discarded = false;

  /// A pin dropped by hand, saved with the rest of the form.
  LatLng? _newPin;
  bool _pinMode = false;

  /// Errors the server returned, shown next to the matching field.
  Map<String, String> _serverErrors = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!_adding) _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.client.get(_url);
      if (res.statusCode == 404) throw NotFound();
      if (res.statusCode != 200) {
        throw Exception(
          'GET /api/flats/${widget.id} returned ${res.statusCode}',
        );
      }
      final flat = FlatDetail.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() {
        _flat = flat;
        _discarded = flat.discarded;
        flat.formText.forEach((k, v) => _fields[k]!.text = v);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
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
      if (!_adding) 'discarded': _discarded,
      if (_newPin != null) ...{
        'lat': _newPin!.latitude,
        'lng': _newPin!.longitude,
      },
    };
  }

  Future<void> _save() async {
    setState(() {
      _serverErrors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = jsonEncode(_body());
      final res = await sendWrite(context, (headers) {
        final h = {'content-type': 'application/json', ...headers};
        return _adding
            ? widget.client.post(_url, headers: h, body: body)
            : widget.client.patch(_url, headers: h, body: body);
      });
      if (!mounted || res == null) return; // Cancelled: keep the form.
      if (res.statusCode == (_adding ? 201 : 200)) {
        flatsChanged.value++;
        returnHome(context);
        _snack('Saved');
        return;
      }
      final json = _decode(res.body);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this property?'),
        content: Text('"${_flat!.name}" will be removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await sendWrite(
        context,
        (headers) => widget.client.delete(_url, headers: headers),
      );
      if (res == null || !mounted) return;
      if (res.statusCode == 204 || res.statusCode == 404) {
        flatsChanged.value++;
        returnHome(context);
        _snack('Property deleted');
      } else {
        _snack(_decode(res.body)['error'] as String? ?? 'Delete failed');
      }
    } catch (e) {
      _snack('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: const TopBar(), body: _page(context));
  }

  Widget _page(BuildContext context) {
    if (_loadError is NotFound) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Property not found.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => resetTo(context, '/home'),
              child: const Text('Back to the list'),
            ),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(child: Text('Could not load property: $_loadError'));
    }
    final flat = _flat;
    if (!_adding && flat == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
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
                  style: _discarded
                      ? const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        )
                      : null,
                ),
                if (flat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CheckboxListTile(
                      key: const Key('discarded'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Discarded'),
                      value: _discarded,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _discarded = v ?? false),
                    ),
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
                  suffix: _openListingButton(),
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
                if (flat != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Distance to Deodar Street: ${formatKm(flat.distanceM)}',
                      key: const Key('distance'),
                    ),
                  ),
                  _map(flat),
                  const SizedBox(height: 12),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      key: const Key('save'),
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save'),
                    ),
                    if (flat != null)
                      OutlinedButton.icon(
                        key: const Key('delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the listing in a new tab once the field holds a valid link.
  Widget? _openListingButton() {
    final url = _text('listing_url');
    if (url.isEmpty || httpUrl(url) != null) return null;
    return IconButton(
      key: const Key('open-listing'),
      tooltip: 'Open the listing',
      icon: const Icon(Icons.open_in_new),
      onPressed: () => launchUrl(Uri.parse(url)),
    );
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
    TextStyle? style,
    Widget? suffix,
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
        style: style,
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
          suffixIcon: suffix,
        ),
        forceErrorText: _serverErrors[field],
        validator: (v) => validator?.call((v ?? '').trim()),
        onChanged: (_) {
          if (_serverErrors.containsKey(field)) {
            setState(() => _serverErrors = {..._serverErrors}..remove(field));
          } else if (field == 'listing_url') {
            setState(() {}); // Show or hide the open button.
          }
        },
      ),
    );
  }

  Widget _map(FlatDetail flat) {
    final point = _newPin ?? flat.point;
    final markers = [
      const Marker(
        point: deodarStreet,
        width: 28,
        height: 28,
        child: Tooltip(
          message: 'Deodar Street',
          child: Icon(Icons.star, color: Colors.deepOrange, size: 28),
        ),
      ),
      if (point != null)
        Marker(
          point: point,
          width: 36,
          height: 36,
          alignment: Alignment.topCenter,
          child: Icon(
            Icons.location_pin,
            key: const Key('flat-pin'),
            size: 36,
            color: _discarded ? Colors.grey : Colors.teal,
          ),
        ),
    ];
    final hint = _pinMode
        ? 'Tap the map where the property is.'
        : _newPin != null
        ? 'Pin moved. Save to keep it.'
        : point == null
        ? 'The address could not be found on the map. Fix the address, or drop the pin by hand.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(hint, key: const Key('pin-hint')),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 260,
            child: FlutterMap(
              key: ValueKey('map-${flat.lat}-${flat.lng}'),
              options: MapOptions(
                initialCenter: point ?? deodarStreet,
                initialZoom: point == null ? 13 : 15,
                onTap: _pinMode
                    ? (_, p) => setState(() {
                        _newPin = p;
                        _pinMode = false;
                      })
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'find_a_flat',
                ),
                MarkerLayer(markers: markers),
                const SimpleAttributionWidget(
                  source: Text('OpenStreetMap contributors'),
                ),
                const ZoomButtons(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('pin-mode'),
          onPressed: _busy ? null : () => setState(() => _pinMode = !_pinMode),
          icon: Icon(_pinMode ? Icons.close : Icons.push_pin_outlined),
          label: Text(
            _pinMode
                ? 'Cancel'
                : point == null
                ? 'Drop pin by hand'
                : 'Move pin',
          ),
        ),
      ],
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
