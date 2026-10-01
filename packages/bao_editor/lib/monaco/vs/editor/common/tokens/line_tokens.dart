/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/tokens/lineTokens.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971 (not common/core at this revision).
// Comparison tests: src/vs/editor/test/common/core/lineTokens.test.ts.
//
// Scope: LineTokens, the private sliced view, TokenArray, TokenInfo and
// TokenArrayBuilder. The tiny ILanguageIdCodec contract is from languages.ts;
// callers supply it without depending on LanguagesRegistry or language services.
// UNPORTED: getStandardTokenTypeAtPosition (requires ITextModel/tokenization),
// the TypeScript-only brand, and the full OffsetRange class. OffsetRange inputs
// and callback arguments are instead immutable TokenOffsetRange named records.
// Text/metadata and insertion object literals likewise become named records.
// There is no tokenizer, mutable token store, deletion/replacement update engine,
// or bidi visual reordering here; only logical UTF-16 token spans and insertion.
//
// Deliberate Dart adaptations:
// - Storage is copied on entry; TokenArray/build snapshots cannot alias callers
//   or builders. defaultTokenMetadata is constant rather than mutable static.
// - Malformed pairs, non-monotone/out-of-line ends, invalid slices/insertions,
//   and negative TokenInfo lengths throw, instead of reporting an unexpected
//   error and continuing (or relying on JavaScript substring coercions).
// - convertToEndOffset still mutates its supplied buffer, never stored tokens.
// - TokenArray.toLineTokens requires the supplied text to match the total length
//   rather than silently truncating it. Range extraction/slicing still intersects
//   ranges extending outside the token sequence, as upstream does.

import 'dart:math' as math;
import 'dart:typed_data';

import '../encoded_token_attributes.dart';

/// Half-open, zero-based UTF-16 offsets; not character or visual bidi positions.
typedef TokenOffsetRange = ({int start, int endExclusive});

typedef TokenText = ({String text, int metadata});

typedef InsertedToken = ({int offset, String text, int tokenMetadata});

abstract interface class ILanguageIdCodec {
  int encodeLanguageId(String languageId);
  String decodeLanguageId(int languageId);
}

abstract interface class IViewLineTokens {
  ILanguageIdCodec get languageIdCodec;
  bool equals(IViewLineTokens other);
  int getCount();
  int getStandardTokenType(int tokenIndex);
  int getForeground(int tokenIndex);
  int getEndOffset(int tokenIndex);
  String getClassName(int tokenIndex);
  String getInlineStyle(int tokenIndex, List<String> colorMap);
  TokenPresentation getPresentation(int tokenIndex);
  int findTokenIndexAtOffset(int offset);
  String getLineContent();
  int getMetadata(int tokenIndex);
  String getLanguageId(int tokenIndex);
  String getTokenText(int tokenIndex);
  void forEach(void Function(int tokenIndex) callback);
}

/// Immutable text annotated by packed `(endOffset, uint32 metadata)` pairs.
///
/// Ends are nondecreasing UTF-16 code-unit offsets, with the last end equal to
/// the text length. Adjacent equal metadata and zero-length tokens are retained.
/// An empty token array is allowed only for empty text; [createEmpty] instead
/// creates one default token, including for an empty line.
final class LineTokens implements IViewLineTokens {
  LineTokens(List<int> tokens, String text, this.languageIdCodec)
    : _tokens = _copyAndValidate(tokens, text),
      _text = text;

  final Uint32List _tokens;
  final String _text;

  @override
  final ILanguageIdCodec languageIdCodec;

  int get _tokensCount => _tokens.length ~/ 2;

  static const int defaultTokenMetadata =
      (FontStyle.none << MetadataConsts.fontStyleOffset) |
      (ColorId.defaultForeground << MetadataConsts.foregroundOffset) |
      (ColorId.defaultBackground << MetadataConsts.backgroundOffset);

  static Uint32List _copyAndValidate(List<int> tokens, String text) {
    if (tokens.length.isOdd) {
      throw ArgumentError.value(
        tokens,
        'tokens',
        'Expected end/metadata pairs',
      );
    }
    var previousEnd = 0;
    for (var i = 0; i < tokens.length; i += 2) {
      final end = tokens[i];
      if (end < previousEnd || end > text.length) {
        throw ArgumentError.value(end, 'endOffset', 'Invalid token end');
      }
      previousEnd = end;
    }
    if (previousEnd != text.length) {
      throw ArgumentError('Token length and text length do not match');
    }
    // Uint32List has the same unsigned metadata coercion as Uint32Array.
    return Uint32List.fromList(tokens);
  }

  static LineTokens createEmpty(String lineContent, ILanguageIdCodec decoder) =>
      LineTokens(
        [lineContent.length, defaultTokenMetadata],
        lineContent,
        decoder,
      );

  static LineTokens createFromTextAndMetadata(
    List<TokenText> data,
    ILanguageIdCodec decoder,
  ) {
    final text = StringBuffer();
    final tokens = <int>[];
    var offset = 0;
    for (final token in data) {
      text.write(token.text);
      offset += token.text.length;
      tokens.addAll([offset, token.metadata]);
    }
    return LineTokens(tokens, text.toString(), decoder);
  }

  /// Converts start/metadata pairs to end/metadata pairs in place.
  /// An empty buffer is a no-op, matching a zero-length upstream typed array.
  static void convertToEndOffset(Uint32List tokens, int lineTextLength) {
    if (tokens.length.isOdd) {
      throw ArgumentError('Expected start/metadata pairs');
    }
    if (lineTextLength < 0 || lineTextLength > 0xffffffff) {
      throw RangeError.range(lineTextLength, 0, 0xffffffff, 'lineTextLength');
    }
    final lastTokenIndex = tokens.length ~/ 2 - 1;
    for (var tokenIndex = 0; tokenIndex < lastTokenIndex; tokenIndex++) {
      tokens[tokenIndex * 2] = tokens[(tokenIndex + 1) * 2];
    }
    if (lastTokenIndex >= 0) tokens[lastTokenIndex * 2] = lineTextLength;
  }

  /// Binary search with upstream boundary affinity: an internal token end
  /// belongs to the next token; at/past the line end the last token is returned.
  /// With zero or one token this returns 0. Repeated ends use upstream's exact
  /// midpoint search (not an upper-bound search across all zero-length tokens).
  static int findIndexInTokensArray(List<int> tokens, int desiredIndex) {
    if (tokens.length <= 2) return 0;
    var low = 0;
    var high = tokens.length ~/ 2 - 1;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      final endOffset = tokens[mid * 2];
      if (endOffset == desiredIndex) {
        return mid + 1;
      } else if (endOffset < desiredIndex) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  int getTextLength() => _text.length;

  @override
  bool equals(IViewLineTokens other) =>
      other is LineTokens && slicedEquals(other, 0, _tokensCount);

  /// Like upstream, compares the entire text and token count, then only the
  /// selected packed token entries. Codec identity does not affect equality.
  bool slicedEquals(
    LineTokens other,
    int sliceFromTokenIndex,
    int sliceTokenCount,
  ) {
    if (_text != other._text || _tokensCount != other._tokensCount) {
      return false;
    }
    RangeError.checkValidRange(
      sliceFromTokenIndex,
      sliceFromTokenIndex + sliceTokenCount,
      _tokensCount,
    );
    final from = sliceFromTokenIndex * 2;
    final to = from + sliceTokenCount * 2;
    for (var i = from; i < to; i++) {
      if (_tokens[i] != other._tokens[i]) return false;
    }
    return true;
  }

  @override
  String getLineContent() => _text;

  @override
  int getCount() => _tokensCount;

  int getStartOffset(int tokenIndex) =>
      tokenIndex > 0 ? _tokens[(tokenIndex - 1) * 2] : 0;

  @override
  int getMetadata(int tokenIndex) => _tokens[tokenIndex * 2 + 1];

  @override
  String getLanguageId(int tokenIndex) => languageIdCodec.decodeLanguageId(
    TokenMetadata.getLanguageId(getMetadata(tokenIndex)),
  );

  @override
  int getStandardTokenType(int tokenIndex) =>
      TokenMetadata.getTokenType(getMetadata(tokenIndex));

  @override
  int getForeground(int tokenIndex) =>
      TokenMetadata.getForeground(getMetadata(tokenIndex));

  @override
  String getClassName(int tokenIndex) =>
      TokenMetadata.getClassNameFromMetadata(getMetadata(tokenIndex));

  @override
  String getInlineStyle(int tokenIndex, List<String> colorMap) =>
      TokenMetadata.getInlineStyleFromMetadata(
        getMetadata(tokenIndex),
        colorMap,
      );

  @override
  TokenPresentation getPresentation(int tokenIndex) =>
      TokenMetadata.getPresentationFromMetadata(getMetadata(tokenIndex));

  @override
  int getEndOffset(int tokenIndex) => _tokens[tokenIndex * 2];

  @override
  int findTokenIndexAtOffset(int offset) =>
      findIndexInTokensArray(_tokens, offset);

  IViewLineTokens inflate() => this;

  /// A zero-copy view. Ends and lookup offsets include [deltaOffset], but text
  /// does not. Like upstream, lookup is NOT clamped to this slice: its exclusive
  /// end can resolve to the next source token (an index equal to the count).
  IViewLineTokens sliceAndInflate(
    int startOffset,
    int endOffset,
    int deltaOffset,
  ) {
    RangeError.checkValidRange(startOffset, endOffset, _text.length);
    return _SliceLineTokens(this, startOffset, endOffset, deltaOffset);
  }

  IViewLineTokens sliceZeroCopy(TokenOffsetRange range) =>
      sliceAndInflate(range.start, range.endExclusive, 0);

  /// Pure insertion; offsets refer to the ORIGINAL text and must be sorted.
  /// Same-offset insertions retain input order. Empty insertions and adjacent
  /// equal metadata are not coalesced, matching the upstream segmentation.
  LineTokens withInserted(List<InsertedToken> insertTokens) {
    if (insertTokens.isEmpty) return this;
    var previousOffset = 0;
    for (final token in insertTokens) {
      if (token.offset < previousOffset || token.offset > _text.length) {
        throw ArgumentError('Insertion offsets must be sorted and in the line');
      }
      previousOffset = token.offset;
    }

    var nextOriginalTokenIdx = 0;
    var nextInsertTokenIdx = 0;
    final text = StringBuffer();
    var textLength = 0;
    final newTokens = <int>[];
    var originalEndOffset = 0;
    while (true) {
      final nextOriginalTokenEndOffset = nextOriginalTokenIdx < _tokensCount
          ? _tokens[nextOriginalTokenIdx * 2]
          : -1;
      final nextInsertToken = nextInsertTokenIdx < insertTokens.length
          ? insertTokens[nextInsertTokenIdx]
          : null;
      if (nextOriginalTokenEndOffset != -1 &&
          (nextInsertToken == null ||
              nextOriginalTokenEndOffset <= nextInsertToken.offset)) {
        text.write(
          _text.substring(originalEndOffset, nextOriginalTokenEndOffset),
        );
        textLength += nextOriginalTokenEndOffset - originalEndOffset;
        newTokens.addAll([textLength, getMetadata(nextOriginalTokenIdx)]);
        nextOriginalTokenIdx++;
        originalEndOffset = nextOriginalTokenEndOffset;
      } else if (nextInsertToken != null) {
        if (nextInsertToken.offset > originalEndOffset) {
          text.write(
            _text.substring(originalEndOffset, nextInsertToken.offset),
          );
          textLength += nextInsertToken.offset - originalEndOffset;
          newTokens.addAll([textLength, getMetadata(nextOriginalTokenIdx)]);
          originalEndOffset = nextInsertToken.offset;
        }
        text.write(nextInsertToken.text);
        textLength += nextInsertToken.text.length;
        newTokens.addAll([textLength, nextInsertToken.tokenMetadata]);
        nextInsertTokenIdx++;
      } else {
        break;
      }
    }
    return LineTokens(newTokens, text.toString(), languageIdCodec);
  }

  /// Intersects the range with each token, dropping zero-length intersections.
  TokenArray getTokensInRange(TokenOffsetRange range) {
    _checkRange(range);
    final builder = TokenArrayBuilder();
    final startTokenIndex = findTokenIndexAtOffset(range.start);
    final endTokenIndex = findTokenIndexAtOffset(range.endExclusive);
    // Empty token arrays have no entries even though upstream lookup returns 0.
    for (var i = startTokenIndex; i <= endTokenIndex && i < _tokensCount; i++) {
      final length =
          math.min<int>(getEndOffset(i), range.endExclusive) -
          math.max<int>(getStartOffset(i), range.start);
      if (length > 0) builder.add(length, getMetadata(i));
    }
    return builder.build();
  }

  @override
  String getTokenText(int tokenIndex) =>
      _text.substring(getStartOffset(tokenIndex), getEndOffset(tokenIndex));

  @override
  void forEach(void Function(int tokenIndex) callback) {
    for (var i = 0; i < _tokensCount; i++) {
      callback(i);
    }
  }

  @override
  String toString() {
    final result = StringBuffer();
    forEach((i) => result.write('[${getTokenText(i)}]{${getClassName(i)}}'));
    return result.toString();
  }
}

final class _SliceLineTokens implements IViewLineTokens {
  _SliceLineTokens(
    this._source,
    this._startOffset,
    this._endOffset,
    this._deltaOffset,
  ) : _firstTokenIndex = _source.findTokenIndexAtOffset(_startOffset) {
    var count = 0;
    for (var i = _firstTokenIndex; i < _source.getCount(); i++) {
      if (_source.getStartOffset(i) >= _endOffset) break;
      count++;
    }
    _tokensCount = count;
  }

  final LineTokens _source;
  final int _startOffset;
  final int _endOffset;
  final int _deltaOffset;
  final int _firstTokenIndex;
  late final int _tokensCount;

  @override
  ILanguageIdCodec get languageIdCodec => _source.languageIdCodec;

  @override
  int getMetadata(int tokenIndex) =>
      _source.getMetadata(_firstTokenIndex + tokenIndex);

  @override
  String getLanguageId(int tokenIndex) =>
      _source.getLanguageId(_firstTokenIndex + tokenIndex);

  @override
  String getLineContent() =>
      _source.getLineContent().substring(_startOffset, _endOffset);

  @override
  bool equals(IViewLineTokens other) =>
      other is _SliceLineTokens &&
      _startOffset == other._startOffset &&
      _endOffset == other._endOffset &&
      _deltaOffset == other._deltaOffset &&
      _source.slicedEquals(other._source, _firstTokenIndex, _tokensCount);

  @override
  int getCount() => _tokensCount;

  @override
  int getStandardTokenType(int tokenIndex) =>
      _source.getStandardTokenType(_firstTokenIndex + tokenIndex);

  @override
  int getForeground(int tokenIndex) =>
      _source.getForeground(_firstTokenIndex + tokenIndex);

  @override
  int getEndOffset(int tokenIndex) =>
      math.min(
        _endOffset,
        _source.getEndOffset(_firstTokenIndex + tokenIndex),
      ) -
      _startOffset +
      _deltaOffset;

  @override
  String getClassName(int tokenIndex) =>
      _source.getClassName(_firstTokenIndex + tokenIndex);

  @override
  String getInlineStyle(int tokenIndex, List<String> colorMap) =>
      _source.getInlineStyle(_firstTokenIndex + tokenIndex, colorMap);

  @override
  TokenPresentation getPresentation(int tokenIndex) =>
      _source.getPresentation(_firstTokenIndex + tokenIndex);

  @override
  int findTokenIndexAtOffset(int offset) =>
      _source.findTokenIndexAtOffset(offset + _startOffset - _deltaOffset) -
      _firstTokenIndex;

  @override
  String getTokenText(int tokenIndex) {
    final sourceIndex = _firstTokenIndex + tokenIndex;
    final tokenStart = _source.getStartOffset(sourceIndex);
    final tokenEnd = _source.getEndOffset(sourceIndex);
    var text = _source.getTokenText(sourceIndex);
    if (tokenStart < _startOffset) {
      text = text.substring(_startOffset - tokenStart);
    }
    if (tokenEnd > _endOffset) {
      text = text.substring(0, text.length - (tokenEnd - _endOffset));
    }
    return text;
  }

  @override
  void forEach(void Function(int tokenIndex) callback) {
    for (var i = 0; i < _tokensCount; i++) {
      callback(i);
    }
  }
}

/// Immutable length/metadata sequence, independent of any text or language model.
final class TokenArray {
  TokenArray._(List<TokenInfo> tokenInfo)
    : _tokenInfo = List<TokenInfo>.unmodifiable(tokenInfo);

  final List<TokenInfo> _tokenInfo;

  static TokenArray create(List<TokenInfo> tokenInfo) =>
      TokenArray._(tokenInfo);

  static TokenArray fromLineTokens(LineTokens lineTokens) => create([
    for (var i = 0; i < lineTokens.getCount(); i++)
      TokenInfo(
        lineTokens.getEndOffset(i) - lineTokens.getStartOffset(i),
        lineTokens.getMetadata(i),
      ),
  ]);

  LineTokens toLineTokens(String lineContent, ILanguageIdCodec decoder) {
    final length = _tokenInfo.fold<int>(0, (sum, token) => sum + token.length);
    if (length != lineContent.length) {
      throw ArgumentError('Token length and text length do not match');
    }
    return LineTokens.createFromTextAndMetadata(
      map(
        (range, token) => (
          text: lineContent.substring(range.start, range.endExclusive),
          metadata: token.metadata,
        ),
      ),
      decoder,
    );
  }

  void forEach(
    void Function(TokenOffsetRange range, TokenInfo tokenInfo) callback,
  ) {
    var lengthSum = 0;
    for (final token in _tokenInfo) {
      callback((
        start: lengthSum,
        endExclusive: lengthSum + token.length,
      ), token);
      lengthSum += token.length;
    }
  }

  List<T> map<T>(
    T Function(TokenOffsetRange range, TokenInfo tokenInfo) callback,
  ) {
    final result = <T>[];
    forEach((range, token) => result.add(callback(range, token)));
    return result;
  }

  /// Matches upstream even for empty ranges: a range inside a token can retain
  /// a zero-length token, unlike [LineTokens.getTokensInRange].
  TokenArray slice(TokenOffsetRange range) {
    _checkRange(range);
    final result = <TokenInfo>[];
    var lengthSum = 0;
    for (final token in _tokenInfo) {
      final tokenStart = lengthSum;
      final tokenEnd = tokenStart + token.length;
      if (tokenEnd > range.start) {
        if (tokenStart >= range.endExclusive) break;
        final deltaBefore = math.max(0, range.start - tokenStart);
        final deltaAfter = math.max(0, tokenEnd - range.endExclusive);
        result.add(
          TokenInfo(token.length - deltaBefore - deltaAfter, token.metadata),
        );
      }
      lengthSum += token.length;
    }
    return create(result);
  }

  /// Does not coalesce tokens, even when boundary metadata is identical.
  TokenArray append(TokenArray other) =>
      create([..._tokenInfo, ...other._tokenInfo]);
}

final class TokenInfo {
  TokenInfo(this.length, this.metadata) {
    if (length < 0) {
      throw RangeError.value(length, 'length', 'Must be nonnegative');
    }
  }

  final int length;
  final int metadata;
}

final class TokenArrayBuilder {
  final List<TokenInfo> _tokens = [];

  void add(int length, int metadata) =>
      _tokens.add(TokenInfo(length, metadata));

  /// An immutable snapshot; later additions do not change a previous build.
  TokenArray build() => TokenArray.create(_tokens);
}

void _checkRange(TokenOffsetRange range) {
  if (range.start > range.endExclusive) {
    throw ArgumentError.value(range, 'range', 'Start must not exceed end');
  }
}
