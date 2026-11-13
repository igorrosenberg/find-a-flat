// Property detail page, /flats/:id: every field, distance, a small map,
// notes, the discarded flag, edit and delete.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_router.dart';
import 'main.dart' show formatCrore, formatKm;
import 'passphrase.dart';
import 'top_bar.dart';

const notesMax = 10000;
const deodarStreet = LatLng(22.5261, 88.3598);

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
}

class NotFound implements Exception {}

class FlatDetailPage extends StatefulWidget {
  const FlatDetailPage({super.key, required this.id, required this.client});

  final int id;
  final http.Client client;

  @override
  State<FlatDetailPage> createState() => _FlatDetailPageState();
}

class _FlatDetailPageState extends State<FlatDetailPage> {
  late final Uri _url = Uri.base.resolve('/api/flats/${widget.id}');
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  FlatDetail? _flat;
  Object? _loadError;
  bool _busy = false;
  bool _pinMode = false;

  @override
  void initState() {
    super.initState();
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus && _notesDirty) _saveNotes();
    });
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  bool get _notesDirty => _flat != null && _notes.text != _flat!.notes;

  Future<void> _load() async {
    try {
      final res = await widget.client.get(_url);
      if (res.statusCode == 404) throw NotFound();
      if (res.statusCode != 200) {
        throw Exception(
          'GET /api/flats/${widget.id} returned ${res.statusCode}',
        );
      }
      _show(FlatDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _show(FlatDetail flat) {
    if (!mounted) return;
    setState(() {
      _flat = flat;
      _notes.text = flat.notes;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _errorOf(http.Response res) {
    try {
      final e = (jsonDecode(res.body) as Map<String, dynamic>)['error'];
      if (e is String) return e;
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  /// Sends a PATCH and shows the saved flat. Returns the response, or null
  /// if the user cancelled the passphrase prompt.
  Future<http.Response?> _patch(
    Map<String, Object?> body, {
    String? done,
  }) async {
    setState(() => _busy = true);
    try {
      final res = await sendWrite(
        context,
        (headers) => widget.client.patch(
          _url,
          headers: {'content-type': 'application/json', ...headers},
          body: jsonEncode(body),
        ),
      );
      if (res == null) return null;
      if (res.statusCode == 200) {
        final saved = FlatDetail.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
        );
        // Keep unsaved typing in the notes box when saving something else.
        final typed = _notes.text;
        _show(saved);
        if (!body.containsKey('notes')) _notes.text = typed;
        if (done != null) _snack(done);
      } else if (res.statusCode != 400) {
        _snack(_errorOf(res));
      }
      return res;
    } catch (e) {
      _snack('Could not save: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Save and blur can both fire for one click; the second one is dropped.
  Future<void> _saveNotes() async {
    if (_busy || !_notesDirty) return;
    await _patch({'notes': _notes.text}, done: 'Notes saved');
  }

  Future<void> _setDiscarded(bool value) => _patch({'discarded': value});

  Future<void> _dropPin(LatLng p) async {
    setState(() => _pinMode = false);
    await _patch({'lat': p.latitude, 'lng': p.longitude}, done: 'Pin saved');
  }

  Future<void> _edit() async {
    final flat = _flat!;
    await showDialog<void>(
      context: context,
      builder: (_) => EditFlatDialog(
        flat: flat,
        save: (body) async {
          final res = await _patch(body, done: 'Saved');
          if (res == null) return const {};
          if (res.statusCode == 400) {
            final fields =
                (jsonDecode(res.body) as Map<String, dynamic>)['fields']
                    as Map<String, dynamic>?;
            return {
              for (final e in (fields ?? {}).entries) e.key: '${e.value}',
            };
          }
          return res.statusCode == 200 ? null : const {};
        },
      ),
    );
  }

  Future<void> _delete() async {
    final flat = _flat!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this property?'),
        content: Text('"${flat.name}" will be removed for good.'),
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
      if (res == null) return;
      if (res.statusCode == 204 || res.statusCode == 404) {
        if (!mounted) return;
        resetTo(context, '/home');
        _snack('Property deleted');
      } else {
        _snack(_errorOf(res));
      }
    } catch (e) {
      _snack('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: const TopBar(), body: _body(context));
  }

  Widget _body(BuildContext context) {
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
    if (flat == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              flat.name,
              key: const Key('flat-name'),
              style: theme.textTheme.headlineSmall?.copyWith(
                decoration: flat.discarded ? TextDecoration.lineThrough : null,
                color: flat.discarded ? Colors.grey : null,
              ),
            ),
            CheckboxListTile(
              key: const Key('discarded'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Discarded'),
              value: flat.discarded,
              onChanged: _busy ? null : (v) => _setDiscarded(v ?? false),
            ),
            _fields(flat),
            const SizedBox(height: 16),
            _map(flat),
            const SizedBox(height: 24),
            Text('Notes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const Key('notes'),
              controller: _notes,
              focusNode: _notesFocus,
              minLines: 4,
              maxLines: 12,
              maxLength: notesMax,
              // Enforce the limit without showing a character counter.
              buildCounter: (
                _, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Viewing notes, questions for the agent…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('save-notes'),
                onPressed: _busy || !_notesDirty ? null : _saveNotes,
                child: const Text('Save notes'),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  key: const Key('edit'),
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
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
    );
  }

  Widget _fields(FlatDetail flat) {
    final url = flat.listingUrl;
    TableRow row(String label, Widget value) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6, right: 16),
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: value),
      ],
    );
    Text t(String s) => Text(s);
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row('Address', SelectableText(flat.address)),
        row('Price', t(formatCrore(flat.price))),
        row('Size', t(flat.sizeSqft == null ? '–' : '${flat.sizeSqft} sq ft')),
        row('Bedrooms', t(flat.bedrooms?.toString() ?? '–')),
        row('Bathrooms', t(flat.bathrooms?.toString() ?? '–')),
        row(
          'Listing',
          url == null
              ? t('–')
              : Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => launchUrl(Uri.parse(url)),
                    child: Text(
                      url,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
        ),
        row('Distance to Deodar Street', t(formatKm(flat.distanceM))),
      ],
    );
  }

  Widget _map(FlatDetail flat) {
    final point = flat.point;
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
            size: 36,
            color: flat.discarded ? Colors.grey : Colors.teal,
          ),
        ),
    ];
    final hint = _pinMode
        ? 'Tap the map where the property is.'
        : point == null
        ? 'The address could not be found on the map. Fix the address with Edit, or drop the pin by hand.'
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
                onTap: _pinMode ? (_, p) => _dropPin(p) : null,
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

/// Edit form with the same fields as the add form. [save] returns null when
/// saved, or field errors to show (an empty map keeps the dialog open).
class EditFlatDialog extends StatefulWidget {
  const EditFlatDialog({super.key, required this.flat, required this.save});

  final FlatDetail flat;
  final Future<Map<String, String>?> Function(Map<String, Object?> body) save;

  @override
  State<EditFlatDialog> createState() => _EditFlatDialogState();
}

class _EditFlatDialogState extends State<EditFlatDialog> {
  final _form = GlobalKey<FormState>();
  late final _c = {
    'name': TextEditingController(text: widget.flat.name),
    'address': TextEditingController(text: widget.flat.address),
    'price': TextEditingController(
      text: widget.flat.price == null
          ? ''
          : (widget.flat.price! / 1e7).toStringAsFixed(2),
    ),
    'size_sqft': TextEditingController(
      text: widget.flat.sizeSqft?.toString() ?? '',
    ),
    'bedrooms': TextEditingController(
      text: widget.flat.bedrooms?.toString() ?? '',
    ),
    'bathrooms': TextEditingController(
      text: widget.flat.bathrooms?.toString() ?? '',
    ),
    'listing_url': TextEditingController(text: widget.flat.listingUrl ?? ''),
  };
  Map<String, String> _serverErrors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String k) => _c[k]!.text.trim();

  static String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? 'Required' : null;

  static String? _positive(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    return n == null || n <= 0 ? 'Must be a positive number' : null;
  }

  static String? _whole(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    return n == null || n < 0 ? 'Must be a whole number, 0 or more' : null;
  }

  static String? _link(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(s)
        ? null
        : 'Must be an http(s) link';
  }

  Future<void> _submit() async {
    setState(() => _serverErrors = {});
    if (!_form.currentState!.validate()) return;
    int? whole(String k) => _v(k).isEmpty ? null : int.parse(_v(k));
    final body = <String, Object?>{
      'name': _v('name'),
      'address': _v('address'),
      'price': _v('price').isEmpty
          ? null
          : (num.parse(_v('price')) * 1e7).round(),
      'size_sqft': _v('size_sqft').isEmpty
          ? null
          : num.parse(_v('size_sqft')).round(),
      'bedrooms': whole('bedrooms'),
      'bathrooms': whole('bathrooms'),
      'listing_url': _v('listing_url').isEmpty ? null : _v('listing_url'),
    };
    setState(() => _saving = true);
    final errors = await widget.save(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (errors == null) {
      Navigator.pop(context);
    } else {
      setState(() => _serverErrors = errors);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: Key('edit-$key'),
        controller: _c[key],
        validator: validator,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: _serverErrors[key],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Narrower margins than the default so the form has room on a phone.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Edit property'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field('name', 'Name', validator: _required),
                _field('address', 'Address', validator: _required),
                _field(
                  'price',
                  'Price (₹ crore)',
                  validator: _positive,
                  number: true,
                ),
                _field(
                  'size_sqft',
                  'Size (sq ft)',
                  validator: _positive,
                  number: true,
                ),
                _field(
                  'bedrooms',
                  'Bedrooms (optional)',
                  validator: _whole,
                  number: true,
                ),
                _field(
                  'bathrooms',
                  'Bathrooms (optional)',
                  validator: _whole,
                  number: true,
                ),
                _field(
                  'listing_url',
                  'Listing URL (optional)',
                  validator: _link,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('edit-save'),
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
