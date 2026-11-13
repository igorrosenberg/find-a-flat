import 'dart:js_interop';

@JS('history.back')
external void _back();

void historyBack() => _back();
