// The browser's Back button, pressed from code. On the web this is
// history.back(); elsewhere (tests on the Dart VM) it does nothing.
export 'browser_back_stub.dart'
    if (dart.library.js_interop) 'browser_back_web.dart';
