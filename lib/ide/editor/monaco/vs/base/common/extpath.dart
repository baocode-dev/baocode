/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/extpath.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `isEqualOrParent` (used by glob's
// relative patterns) and `isWindowsDriveLetter`.

import 'path.dart' as paths;
import 'strings.dart';

bool isEqualOrParent(
  String? base,
  String? parentCandidate, [
  bool? ignoreCase,
  bool forcePosixSemantics = false,
]) {
  final separator = forcePosixSemantics ? paths.posix.sep : paths.sep;

  if (base == parentCandidate) return true;
  if (base == null ||
      base.isEmpty ||
      parentCandidate == null ||
      parentCandidate.isEmpty) {
    return false;
  }

  if (base.contains('..') || parentCandidate.contains('..')) {
    base = forcePosixSemantics
        ? paths.posix.normalize(base)
        : paths.normalize(base);
    parentCandidate = forcePosixSemantics
        ? paths.posix.normalize(parentCandidate)
        : paths.normalize(parentCandidate);
  }

  if (parentCandidate.length > base.length) return false;

  if (ignoreCase == true) {
    final beginsWith = startsWithIgnoreCase(base, parentCandidate);
    if (!beginsWith) return false;
    if (parentCandidate.length == base.length) {
      return true; // same path, different casing
    }
    var sepOffset = parentCandidate.length;
    if (parentCandidate.endsWith(separator)) {
      sepOffset--; // the candidate already ends in a separator
    }
    return sepOffset < base.length && base[sepOffset] == separator;
  }

  if (!parentCandidate.endsWith(separator)) {
    parentCandidate += separator;
  }
  return base.startsWith(parentCandidate);
}

bool isWindowsDriveLetter(int char0) =>
    (char0 >= 65 && char0 <= 90) || (char0 >= 97 && char0 <= 122);
