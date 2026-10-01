// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/parser/Params.ts (c58ea36).

import 'dart:typed_data';

import 'types.dart';

abstract final class _Constants {
  /// Max value supported for a single param/subparam (clamped to positive
  /// int32 range).
  static const int maxValue = 0x7FFFFFFF;

  /// Max allowed subparams for a single sequence (hardcoded limitation).
  static const int maxSubParams = 256;
}

/// Params storage class.
///
/// This type is used by the parser to accumulate sequence parameters and sub
/// parameters and transmit them to the input handler actions.
///
/// NOTES:
///  - params object for action handlers is borrowed, use [toArray] or
///    [clone] to get a copy
///  - never read beyond `params.length - 1` (likely to contain arbitrary
///    data)
///  - [getSubParams] returns a borrowed typed array, use [getSubParamsAll]
///    for cloned sub params
///  - hardcoded limitations:
///    - max. value for a single (sub) param is 2^31 - 1 (greater values are
///      clamped to that)
///    - max. 256 sub params possible
///    - negative values are not allowed beside -1 (placeholder for default
///      value)
///
/// About ZDM (Zero Default Mode):
/// ZDM is not orchestrated by this class. If the parser is in ZDM, it should
/// add 0 for empty params, otherwise -1. This does not apply to subparams,
/// empty subparams should always be added with -1.
class Params implements IParams {
  /// [maxLength] is the max length of storable parameters,
  /// [maxSubParamsLength] the max length of storable sub parameters.
  Params([this.maxLength = 32, this.maxSubParamsLength = 32])
    : _subParams = Int32List(_checkMaxSubParams(maxSubParamsLength)),
      params = Int32List(maxLength),
      _subParamsIdx = Uint16List(maxLength);

  static int _checkMaxSubParams(int maxSubParamsLength) {
    if (maxSubParamsLength > _Constants.maxSubParams) {
      throw ArgumentError('maxSubParamsLength must not be greater than 256');
    }
    return maxSubParamsLength;
  }

  @override
  int maxLength;
  @override
  int maxSubParamsLength;

  // params store and length
  @override
  Int32List params;
  @override
  int length = 0;

  // sub params store and length
  final Int32List _subParams;
  int _subParamsLength = 0;

  // sub params offsets from param: param idx --> [start, end] offset
  final Uint16List _subParamsIdx;
  bool _rejectDigits = false;
  bool _rejectSubDigits = false;
  bool _digitIsSub = false;

  /// Upstream protected `_subParams`; exposed for the ported tests.
  Int32List get subParams => _subParams;

  /// Upstream protected `_subParamsLength`; exposed for the ported tests.
  int get subParamsLength => _subParamsLength;

  /// Upstream private `_subParamsIdx`; exposed for the ported tests.
  Uint16List get subParamsIdx => _subParamsIdx;

  /// Upstream private `_rejectDigits`; exposed for the ported tests.
  bool get rejectDigits => _rejectDigits;

  /// Upstream private `_rejectSubDigits`; exposed for the ported tests.
  bool get rejectSubDigits => _rejectSubDigits;

  /// Upstream private `_digitIsSub`; exposed for the ported tests.
  bool get digitIsSub => _digitIsSub;

  /// Creates a `Params` type from its list representation.
  static Params fromArray(ParamsArray values) {
    final params = Params();
    if (values.isEmpty) {
      return params;
    }
    // skip leading sub params
    for (var i = (values[0] is List) ? 1 : 0; i < values.length; ++i) {
      final value = values[i];
      if (value is List) {
        for (var k = 0; k < value.length; ++k) {
          params.addSubParam(value[k] as int);
        }
      } else {
        params.addParam(value as int);
      }
    }
    return params;
  }

  /// Clones the object.
  @override
  Params clone() {
    final newParams = Params(maxLength, maxSubParamsLength);
    newParams.params.setRange(0, params.length, params);
    newParams.length = length;
    newParams._subParams.setRange(0, _subParams.length, _subParams);
    newParams._subParamsLength = _subParamsLength;
    newParams._subParamsIdx.setRange(0, _subParamsIdx.length, _subParamsIdx);
    newParams._rejectDigits = _rejectDigits;
    newParams._rejectSubDigits = _rejectSubDigits;
    newParams._digitIsSub = _digitIsSub;
    return newParams;
  }

  /// Gets a list representation of the current parameters and sub
  /// parameters.
  ///
  /// The list is structured as follows:
  ///    sequence: "1;2:3:4;5::6"
  ///    list    : [1, 2, [3, 4], 5, [-1, 6]]
  @override
  ParamsArray toArray() {
    final res = <Object>[];
    for (var i = 0; i < length; ++i) {
      res.add(params[i]);
      final start = _subParamsIdx[i] >> 8;
      final end = _subParamsIdx[i] & 0xFF;
      if (end - start > 0) {
        res.add(<int>[for (var k = start; k < end; ++k) _subParams[k]]);
      }
    }
    return res;
  }

  /// Resets to the initial empty state.
  @override
  void reset() {
    length = 0;
    _subParamsLength = 0;
    _rejectDigits = false;
    _rejectSubDigits = false;
    _digitIsSub = false;
  }

  /// Resets and adds 0 as first param (ZDM).
  @override
  void resetZdm() {
    length = 1;
    _subParamsLength = 0;
    _rejectDigits = false;
    _rejectSubDigits = false;
    _digitIsSub = false;
    _subParamsIdx[0] = 0;
    params[0] = 0;
  }

  /// Adds a parameter value.
  ///
  /// `Params` only stores up to [maxLength] parameters, any later parameter
  /// will be ignored.
  /// Note: VT devices only stored up to 16 values, xterm seems to store up
  /// to 30.
  @override
  void addParam(int value) {
    _digitIsSub = false;
    if (length >= maxLength) {
      _rejectDigits = true;
      return;
    }
    if (value < -1) {
      throw ArgumentError('values less than -1 are not allowed');
    }
    _subParamsIdx[length] = _subParamsLength << 8 | _subParamsLength;
    params[length++] = value > _Constants.maxValue
        ? _Constants.maxValue
        : value;
  }

  /// Adds a sub parameter value.
  ///
  /// The sub parameter is automatically associated with the last parameter
  /// value. Thus it is not possible to add a subparameter without any
  /// parameter added yet. `Params` only stores up to [maxSubParamsLength]
  /// sub parameters, any later sub parameter will be ignored.
  @override
  void addSubParam(int value) {
    _digitIsSub = true;
    if (length == 0) {
      return;
    }
    if (_rejectDigits || _subParamsLength >= maxSubParamsLength) {
      _rejectSubDigits = true;
      return;
    }
    if (value < -1) {
      throw ArgumentError('values less than -1 are not allowed');
    }
    _subParams[_subParamsLength++] = value > _Constants.maxValue
        ? _Constants.maxValue
        : value;
    _subParamsIdx[length - 1]++;
  }

  /// Whether parameter at index [idx] has sub parameters.
  @override
  bool hasSubParams(int idx) {
    return (_subParamsIdx[idx] & 0xFF) - (_subParamsIdx[idx] >> 8) > 0;
  }

  /// Returns sub parameters for parameter at index [idx].
  ///
  /// Note: The values are borrowed, thus you need to copy the values if you
  /// need to hold them in nonlocal scope.
  @override
  Int32List? getSubParams(int idx) {
    final start = _subParamsIdx[idx] >> 8;
    final end = _subParamsIdx[idx] & 0xFF;
    if (end - start > 0) {
      return Int32List.sublistView(_subParams, start, end);
    }
    return null;
  }

  /// Returns all sub parameters as {idx: subparams} mapping.
  ///
  /// Note: The values are not borrowed.
  @override
  Map<int, Int32List> getSubParamsAll() {
    final result = <int, Int32List>{};
    for (var i = 0; i < length; ++i) {
      final start = _subParamsIdx[i] >> 8;
      final end = _subParamsIdx[i] & 0xFF;
      if (end - start > 0) {
        result[i] = _subParams.sublist(start, end);
      }
    }
    return result;
  }

  /// Adds a single digit value to current parameter.
  ///
  /// This is used by the parser to account digits on a char by char basis.
  void addDigit(int value) {
    if (_rejectDigits) {
      return;
    }
    final isSub = _digitIsSub;
    final length = isSub ? _subParamsLength : this.length;
    if (length == 0 || (isSub && _rejectSubDigits)) {
      return;
    }
    final store = isSub ? _subParams : params;
    final cur = store[length - 1];
    if (cur != -1) {
      final next = cur * 10 + value;
      store[length - 1] = next < _Constants.maxValue
          ? next
          : _Constants.maxValue;
    } else {
      store[length - 1] = value;
    }
  }
}
