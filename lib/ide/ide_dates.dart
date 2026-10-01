/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Relative times ("3 days", "1 hr ago"), as the timeline and the graph's
// hovers show them.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/date.ts (`fromNow`).

import '../l10n/l10n.dart';

const _minute = 60;
const _hour = _minute * 60;
const _day = _hour * 24;
const _week = _day * 7;
const _month = _day * 30;
const _year = _day * 365;

/// How long ago [date] was: "now", "5 mins", "1 day" ([ago] adds " ago";
/// [fullWords] spells "minutes" out); in [l10n]'s language (English when
/// null).
String ideFromNow(
  DateTime date, {
  bool ago = false,
  bool fullWords = false,
  DateTime? now,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  final seconds =
      ((now ?? DateTime.now()).difference(date).inMilliseconds / 1000).round();
  if (seconds < -30) {
    return strings.dateIn(
      ideFromNow(
        date,
        now: date.add(Duration(seconds: seconds.abs())),
        l10n: strings,
      ),
    );
  }
  if (seconds < 30) return strings.dateNow;

  final full = '$fullWords';
  String unit(String Function(String full, int count) message, int value) {
    final time = message(full, value);
    return ago ? strings.dateAgo(time) : time;
  }

  if (seconds < _minute) return unit(strings.dateSeconds, seconds);
  if (seconds < _hour) {
    return unit(strings.dateMinutes, (seconds / _minute).round());
  }
  if (seconds < _day) return unit(strings.dateHours, (seconds / _hour).round());
  if (seconds < _week) return unit(strings.dateDays, (seconds / _day).round());
  if (seconds < _month) {
    return unit(strings.dateWeeks, (seconds / _week).round());
  }
  if (seconds < _year) {
    return unit(strings.dateMonths, (seconds / _month).round());
  }
  return unit(strings.dateYears, (seconds / _year).round());
}
