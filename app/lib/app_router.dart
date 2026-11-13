// Routing that writes one real browser history entry per page.
//
// The app used to rely on Navigator.pushNamed, which on the web keeps a
// single browser history entry and re-adds it from the popstate handler each
// time Back is pressed. Firefox skips entries added without a click, so Back
// did nothing. Here the browser history is the source of truth: every page
// opened is a new entry (pushed during the click), and Back and Forward move
// between those entries like on any web site.
//
// Pages navigate with [goTo], [replaceWith] and [resetTo].

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where the app is: a path, and its position in the browser history.
@immutable
class AppLocation {
  const AppLocation(this.path, [this.index]);

  final String path;

  /// Index of this entry in the browser history, stored in its state, or
  /// null for an entry the app did not create (a typed URL, a reload).
  final int? index;
}

/// Turns the browser URL into an [AppLocation] and back.
class AppRouteParser extends RouteInformationParser<AppLocation> {
  const AppRouteParser();

  static String normalize(String path) =>
      path.isEmpty || path == '/' ? '/home' : path;

  @override
  Future<AppLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final state = routeInformation.state;
    final index = state is Map ? state['i'] : null;
    return AppLocation(
      normalize(routeInformation.uri.path),
      index is int ? index : null,
    );
  }

  @override
  RouteInformation restoreRouteInformation(AppLocation configuration) =>
      RouteInformation(
        uri: Uri(path: configuration.path),
        state: {'i': configuration.index},
      );
}

class _Entry {
  _Entry(this.index, this.path);
  final int index;
  final String path;
  // One key per history entry, so the same path twice is two pages.
  final key = UniqueKey();
}

/// Keeps a page per browser history entry, from the first one the app
/// knows of up to the current one, so going Back shows the page underneath
/// as it was left (sort order, scroll position).
class AppRouterDelegate extends RouterDelegate<AppLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppLocation> {
  AppRouterDelegate({
    required this.buildPage,
    this.navigatorObservers = const [],
  });

  final Widget Function(String path) buildPage;
  final List<NavigatorObserver> navigatorObservers;

  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  final _stack = <_Entry>[];

  /// The paths of the pages kept, the current one last.
  List<String> get paths => [for (final e in _stack) e.path];

  @override
  AppLocation? get currentConfiguration =>
      _stack.isEmpty ? null : AppLocation(_stack.last.path, _stack.last.index);

  /// Called when the browser moves (first load, Back, Forward, typed URL).
  @override
  Future<void> setNewRoutePath(AppLocation location) {
    final i = location.index;
    final at = i == null ? -1 : _stack.indexWhere((e) => e.index == i);
    if (at >= 0 && _stack[at].path == location.path) {
      // Back (or Forward to a page still kept): drop the pages above it.
      _stack.removeRange(at + 1, _stack.length);
    } else if (i != null && _stack.isNotEmpty && i == _stack.last.index + 1) {
      // Forward to the next entry.
      _stack.add(_Entry(i, location.path));
    } else {
      // A page the app has no record of: show it on its own.
      _stack
        ..clear()
        ..add(_Entry(i ?? 0, location.path));
    }
    notifyListeners();
    return SynchronousFuture(null);
  }

  /// Opens [path] as a new page and a new browser history entry.
  void push(String path) {
    final next = _stack.isEmpty ? 0 : _stack.last.index + 1;
    _stack.add(_Entry(next, AppRouteParser.normalize(path)));
    notifyListeners();
  }

  /// Shows [path] in place of the current page and history entry.
  void replace(String path) {
    final top = _stack.isEmpty ? null : _stack.removeLast();
    _stack.add(_Entry(top?.index ?? 0, AppRouteParser.normalize(path)));
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    // Empty only until the browser's first URL has been read.
    if (_stack.isEmpty) return const SizedBox.shrink();
    return Navigator(
      key: navigatorKey,
      observers: navigatorObservers,
      pages: [
        for (final e in _stack)
          MaterialPage<void>(
            key: e.key,
            name: e.path,
            child: buildPage(e.path),
          ),
      ],
      onDidRemovePage: (page) => _stack.removeWhere((e) => e.key == page.key),
    );
  }
}

AppRouterDelegate? _delegateOf(BuildContext context) {
  final d = Router.maybeOf(context)?.routerDelegate;
  return d is AppRouterDelegate ? d : null;
}

/// Opens [path] as a new page; Back returns here.
void goTo(BuildContext context, String path) {
  final d = _delegateOf(context);
  if (d == null) {
    // A page tested on its own, inside a plain MaterialApp.
    Navigator.of(context).pushNamed(path);
  } else {
    d.push(path);
  }
}

/// Shows [path] in place of the current page, so Back skips this page
/// (e.g. the add form once the flat is saved).
void replaceWith(BuildContext context, String path) {
  final d = _delegateOf(context);
  if (d == null) {
    Navigator.of(context).pushReplacementNamed(path);
  } else {
    Router.neglect(context, () => d.replace(path));
  }
}

/// Shows [path] in place of the current page, e.g. the list after the flat
/// on this page was deleted.
void resetTo(BuildContext context, String path) {
  final d = _delegateOf(context);
  if (d == null) {
    Navigator.of(context).pushNamedAndRemoveUntil(path, (_) => false);
  } else {
    Router.neglect(context, () => d.replace(path));
  }
}
