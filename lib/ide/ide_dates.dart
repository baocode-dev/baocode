/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Relative times ("3 days", "1 hr ago"), as the timeline and the graph's
// hovers show them.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/date.ts (`fromNow`).

const _minute = 60;
const _hour = _minute * 60;
const _day = _hour * 24;
const _week = _day * 7;
const _month = _day * 30;
const _year = _day * 365;

/// How long ago [date] was: "now", "5 mins", "1 day" ([ago] adds " ago";
/// [fullWords] spells "minutes" out).
String ideFromNow(
  DateTime date, {
  bool ago = false,
  bool fullWords = false,
  DateTime? now,
}) {
  final seconds =
      ((now ?? DateTime.now()).difference(date).inMilliseconds / 1000).round();
  if (seconds < -30) {
    return 'in ${ideFromNow(date, now: date.add(Duration(seconds: seconds.abs())))}';
  }
  if (seconds < 30) return 'now';

  String unit(int value, String short, String full) {
    final word = '${fullWords ? full : short}${value == 1 ? '' : 's'}';
    return '$value $word${ago ? ' ago' : ''}';
  }

  if (seconds < _minute) return unit(seconds, 'sec', 'second');
  if (seconds < _hour) {
    return unit((seconds / _minute).round(), 'min', 'minute');
  }
  if (seconds < _day) return unit((seconds / _hour).round(), 'hr', 'hour');
  if (seconds < _week) return unit((seconds / _day).round(), 'day', 'day');
  if (seconds < _month) return unit((seconds / _week).round(), 'wk', 'week');
  if (seconds < _year) return unit((seconds / _month).round(), 'mo', 'month');
  return unit((seconds / _year).round(), 'yr', 'year');
}
