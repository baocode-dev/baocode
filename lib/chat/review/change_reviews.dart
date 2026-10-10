import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat_models.dart';
import 'change_review.dart';

/// The reviews of the folders an agent works in: its directory's and, in a
/// multi-folder workspace, each folder's ([ChangeReview] is of one), seen as
/// one. A file goes to the review of the folder it is in; one in none of
/// them to the first's, which lists it without being able to undo it.
class ChangeReviews extends ChangeNotifier {
  ChangeReviews._(this._parts) {
    for (final part in _parts) {
      part.addListener(_partChanged);
    }
  }

  /// The reviews of [roots] (the agent's directory first), continuing what
  /// [session] left, opened with [open]; null where there can be none.
  /// A folder inside another is the other's.
  static Future<ChangeReviews?> open(
    List<String> roots, {
    required Future<ChangeReview?> Function(String root, {String? session})
    open,
    String? session,
  }) async {
    final distinct = <String>[];
    for (final root in roots) {
      if (distinct.any((other) => p.equals(other, root))) continue;
      distinct.add(root);
    }
    final outermost = [
      for (final root in distinct)
        if (!distinct.any((other) => p.isWithin(other, root))) root,
    ];
    final opened = await Future.wait([
      for (final root in outermost)
        open(root, session: session).catchError((Object _) => null),
    ]);
    final parts = opened.nonNulls.toList();
    if (parts.isEmpty) return null;
    return ChangeReviews._(parts);
  }

  final List<ChangeReview> _parts;

  /// The first folder's (the agent's directory, where it has one).
  String get root => _parts.first.root;

  List<FileChange> get changes => [for (final part in _parts) ...part.changes];

  /// Why one of them stopped: their changes are then no longer known.
  String? get failure {
    for (final part in _parts) {
      if (part.failure case final failure?) return failure;
    }
    return null;
  }

  set session(String? id) {
    for (final part in _parts) {
      part.session = id;
    }
  }

  set working(bool working) {
    for (final part in _parts) {
      part.working = working;
    }
  }

  void abandon(String reason) {
    for (final part in _parts) {
      part.abandon(reason);
    }
  }

  Future<void> begin() => _all((part) => part.begin());

  Future<void> observe({bool full = true}) =>
      _all((part) => part.observe(full: full));

  /// A relative path is the agent's directory's, and so the first's.
  void report(FileChange change) => _partOf(change.path).report(change);

  Future<void> keep(Iterable<String> paths) =>
      _each(paths, (part, paths) => part.keep(paths));

  Future<void> keepAll() => _all((part) => part.keepAll());

  Future<void> undo(Iterable<String> paths) =>
      _each(paths, (part, paths) => part.undo(paths));

  Future<void> undoAll() => _all((part) => part.undoAll());

  Future<String> Function()? original(String path) =>
      _partOf(path).original(_absolute(path));

  Future<void> discard() => _all((part) => part.discard());

  Future<void> _all(Future<void> Function(ChangeReview part) operation) async {
    await Future.wait([for (final part in _parts) operation(part)]);
  }

  /// [operation] on each review, with those of [paths] in its folder.
  Future<void> _each(
    Iterable<String> paths,
    Future<void> Function(ChangeReview part, List<String> paths) operation,
  ) async {
    final byPart = <ChangeReview, List<String>>{};
    for (final path in paths) {
      byPart.putIfAbsent(_partOf(path), () => []).add(_absolute(path));
    }
    await Future.wait([
      for (final MapEntry(key: part, value: paths) in byPart.entries)
        operation(part, paths),
    ]);
  }

  /// [path] absolute: one relative is the agent's directory's.
  String _absolute(String path) =>
      p.isAbsolute(path) ? path : p.join(root, path);

  ChangeReview _partOf(String path) {
    final absolute = _absolute(path);
    for (final part in _parts) {
      if (p.equals(part.root, absolute) || p.isWithin(part.root, absolute)) {
        return part;
      }
    }
    return _parts.first;
  }

  void _partChanged() => notifyListeners();

  @override
  void dispose() {
    for (final part in _parts) {
      part
        ..removeListener(_partChanged)
        ..dispose();
    }
    super.dispose();
  }
}
