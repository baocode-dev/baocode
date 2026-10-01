// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/rule.ts (MIT, see LICENSE.md).

import 'grammar/grammar_dependencies.dart';
import 'js_semantics.dart';
import 'onig_lib.dart';
import 'raw_grammar.dart';
import 'utils.dart';

final RegExp _hasBackReferences = RegExp(r'\\(\d+)');
final RegExp _backReferencingEnd = RegExp(r'\\(\d+)');

/// Upstream brands a number; here it is the number.
typedef RuleId = int;

/// This is a special constant to indicate that the end regexp matched.
const int endRuleId = -1;

/// This is a special constant to indicate that the while regexp matched.
const int whileRuleId = -2;

RuleId ruleIdFromNumber(int id) {
  return id;
}

int ruleIdToNumber(RuleId id) {
  return id;
}

abstract interface class IRuleRegistry {
  /// The rule, or null for an id that is unknown or still being built
  /// (upstream returns `undefined`).
  Rule? getRule(RuleId ruleId);
  T registerRule<T extends Rule>(T Function(RuleId id) factory);
}

abstract interface class IGrammarRegistry {
  /// The initialized (copied) raw grammar for [scopeName], or null.
  Map<String, Object?>? getExternalGrammar(
    String scopeName, [
    Map<String, Object?>? repository,
  ]);
}

abstract interface class IRuleFactoryHelper
    implements IRuleRegistry, IGrammarRegistry {}

/// What `Rule.compile` needs: the rule registry and the regex engine.
abstract interface class IRuleRegistryAndOnigLib
    implements IRuleRegistry, IOnigLib {}

abstract class Rule {
  Rule(this.$location, this.id, Object? name, Object? contentName)
    : _name = jsTruthy(name) ? name : null,
      _contentName = jsTruthy(contentName) ? contentName : null {
    _nameIsCapturing = RegexSource.hasCaptures(_asRegexInput(_name));
    _contentNameIsCapturing = RegexSource.hasCaptures(
      _asRegexInput(_contentName),
    );
  }

  final ILocation? $location;
  final RuleId id;

  late final bool _nameIsCapturing;

  /// A string, or (from a malformed grammar) another truthy value, which
  /// fails when used, as upstream does.
  final Object? _name;

  late final bool _contentNameIsCapturing;
  final Object? _contentName;

  static String? _asRegexInput(Object? value) =>
      value == null ? null : jsToString(value);

  void dispose();

  String get debugName {
    final location = $location != null
        ? '${basename($location!.filename ?? 'null')}:${$location!.line}'
        : 'unknown';
    return '$debugClassName#$id @ $location';
  }

  /// Upstream uses `this.constructor.name`.
  String get debugClassName;

  String? getName(String? lineText, List<IOnigCaptureIndex>? captureIndices) {
    final name = _name;
    if (name == null) {
      return null;
    }
    if (name is! String) {
      jsTypeError('Rule name is not a string: $name');
    }
    if (!_nameIsCapturing || lineText == null || captureIndices == null) {
      return name;
    }
    return RegexSource.replaceCaptures(name, lineText, captureIndices);
  }

  String? getContentName(
    String lineText,
    List<IOnigCaptureIndex> captureIndices,
  ) {
    final contentName = _contentName;
    if (contentName == null) {
      return null;
    }
    if (contentName is! String) {
      jsTypeError('Rule contentName is not a string: $contentName');
    }
    if (!_contentNameIsCapturing) {
      return contentName;
    }
    return RegexSource.replaceCaptures(contentName, lineText, captureIndices);
  }

  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out);

  CompiledRule compile(IRuleRegistryAndOnigLib grammar, String? endRegexSource);

  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  );
}

class ICompilePatternsResult {
  const ICompilePatternsResult(this.patterns, this.hasMissingPatterns);

  final List<RuleId> patterns;
  final bool hasMissingPatterns;
}

class CaptureRule extends Rule {
  CaptureRule(
    super.$location,
    super.id,
    super.name,
    super.contentName,
    this.retokenizeCapturedWithRuleId,
  );

  /// A rule id, or 0 for none.
  final RuleId retokenizeCapturedWithRuleId;

  @override
  String get debugClassName => 'CaptureRule';

  @override
  void dispose() {
    // nothing to dispose
  }

  @override
  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out) {
    throw StateError('Not supported!');
  }

  @override
  CompiledRule compile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    throw StateError('Not supported!');
  }

  @override
  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    throw StateError('Not supported!');
  }
}

class MatchRule extends Rule {
  MatchRule(
    ILocation? $location,
    RuleId id,
    Object? name,
    Object? match,
    this.captures,
  ) : super($location, id, name, null) {
    _match = RegExpSource(match, this.id);
  }

  late final RegExpSource _match;
  final List<CaptureRule?> captures;
  RegExpSourceList? _cachedCompiledPatterns;

  @override
  String get debugClassName => 'MatchRule';

  @override
  void dispose() {
    if (_cachedCompiledPatterns != null) {
      _cachedCompiledPatterns!.dispose();
      _cachedCompiledPatterns = null;
    }
  }

  String get debugMatchRegExp {
    return _match.source;
  }

  @override
  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out) {
    out.push(_match);
  }

  @override
  CompiledRule compile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(grammar)
        .compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList _getCachedCompiledPatterns(IRuleRegistryAndOnigLib grammar) {
    if (_cachedCompiledPatterns == null) {
      _cachedCompiledPatterns = RegExpSourceList();
      collectPatterns(grammar, _cachedCompiledPatterns!);
    }
    return _cachedCompiledPatterns!;
  }
}

class IncludeOnlyRule extends Rule {
  IncludeOnlyRule(
    super.$location,
    super.id,
    super.name,
    super.contentName,
    ICompilePatternsResult patterns,
  ) : patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns;

  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList? _cachedCompiledPatterns;

  @override
  String get debugClassName => 'IncludeOnlyRule';

  @override
  void dispose() {
    if (_cachedCompiledPatterns != null) {
      _cachedCompiledPatterns!.dispose();
      _cachedCompiledPatterns = null;
    }
  }

  @override
  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out) {
    for (final pattern in patterns) {
      final rule = grammar.getRule(pattern)!;
      rule.collectPatterns(grammar, out);
    }
  }

  @override
  CompiledRule compile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(grammar)
        .compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList _getCachedCompiledPatterns(IRuleRegistryAndOnigLib grammar) {
    if (_cachedCompiledPatterns == null) {
      _cachedCompiledPatterns = RegExpSourceList();
      collectPatterns(grammar, _cachedCompiledPatterns!);
    }
    return _cachedCompiledPatterns!;
  }
}

class BeginEndRule extends Rule {
  BeginEndRule(
    super.$location,
    super.id,
    super.name,
    super.contentName,
    Object? begin,
    this.beginCaptures,
    Object? end,
    this.endCaptures,
    Object? applyEndPatternLast,
    ICompilePatternsResult patterns,
  ) : applyEndPatternLast = jsTruthy(applyEndPatternLast),
      patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns,
      super() {
    _begin = RegExpSource(begin, id);
    _end = RegExpSource(jsTruthy(end) ? end : '\uFFFF', -1);
    endHasBackReferences = _end.hasBackReferences;
  }

  late final RegExpSource _begin;
  final List<CaptureRule?> beginCaptures;
  late final RegExpSource _end;
  late final bool endHasBackReferences;
  final List<CaptureRule?> endCaptures;
  final bool applyEndPatternLast;
  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList? _cachedCompiledPatterns;

  @override
  String get debugClassName => 'BeginEndRule';

  @override
  void dispose() {
    if (_cachedCompiledPatterns != null) {
      _cachedCompiledPatterns!.dispose();
      _cachedCompiledPatterns = null;
    }
  }

  String get debugBeginRegExp {
    return _begin.source;
  }

  String get debugEndRegExp {
    return _end.source;
  }

  String getEndWithResolvedBackReferences(
    String lineText,
    List<IOnigCaptureIndex> captureIndices,
  ) {
    return _end.resolveBackReferences(lineText, captureIndices);
  }

  @override
  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out) {
    out.push(_begin);
  }

  @override
  CompiledRule compile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    return _getCachedCompiledPatterns(grammar, endRegexSource).compile(grammar);
  }

  @override
  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(
      grammar,
      endRegexSource,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList _getCachedCompiledPatterns(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    var cached = _cachedCompiledPatterns;
    if (cached == null) {
      cached = _cachedCompiledPatterns = RegExpSourceList();

      for (final pattern in patterns) {
        final rule = grammar.getRule(pattern)!;
        rule.collectPatterns(grammar, cached);
      }

      if (applyEndPatternLast) {
        cached.push(_end.hasBackReferences ? _end.clone() : _end);
      } else {
        cached.unshift(_end.hasBackReferences ? _end.clone() : _end);
      }
    }
    if (_end.hasBackReferences) {
      if (applyEndPatternLast) {
        cached.setSource(cached.length() - 1, endRegexSource);
      } else {
        cached.setSource(0, endRegexSource);
      }
    }
    return cached;
  }
}

class BeginWhileRule extends Rule {
  BeginWhileRule(
    super.$location,
    super.id,
    super.name,
    super.contentName,
    Object? begin,
    this.beginCaptures,
    Object? whileSource,
    this.whileCaptures,
    ICompilePatternsResult patterns,
  ) : patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns,
      super() {
    _begin = RegExpSource(begin, id);
    _while = RegExpSource(whileSource, whileRuleId);
    whileHasBackReferences = _while.hasBackReferences;
  }

  late final RegExpSource _begin;
  final List<CaptureRule?> beginCaptures;
  final List<CaptureRule?> whileCaptures;
  late final RegExpSource _while;
  late final bool whileHasBackReferences;
  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList? _cachedCompiledPatterns;
  RegExpSourceList? _cachedCompiledWhilePatterns;

  @override
  String get debugClassName => 'BeginWhileRule';

  @override
  void dispose() {
    if (_cachedCompiledPatterns != null) {
      _cachedCompiledPatterns!.dispose();
      _cachedCompiledPatterns = null;
    }
    if (_cachedCompiledWhilePatterns != null) {
      _cachedCompiledWhilePatterns!.dispose();
      _cachedCompiledWhilePatterns = null;
    }
  }

  String get debugBeginRegExp {
    return _begin.source;
  }

  String get debugWhileRegExp {
    return _while.source;
  }

  String getWhileWithResolvedBackReferences(
    String lineText,
    List<IOnigCaptureIndex> captureIndices,
  ) {
    return _while.resolveBackReferences(lineText, captureIndices);
  }

  @override
  void collectPatterns(IRuleRegistry grammar, RegExpSourceList out) {
    out.push(_begin);
  }

  @override
  CompiledRule compile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule compileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(grammar)
        .compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList _getCachedCompiledPatterns(IRuleRegistryAndOnigLib grammar) {
    var cached = _cachedCompiledPatterns;
    if (cached == null) {
      cached = _cachedCompiledPatterns = RegExpSourceList();

      for (final pattern in patterns) {
        final rule = grammar.getRule(pattern)!;
        rule.collectPatterns(grammar, cached);
      }
    }
    return cached;
  }

  CompiledRule compileWhile(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    return _getCachedCompiledWhilePatterns(
      grammar,
      endRegexSource,
    ).compile(grammar);
  }

  CompiledRule compileWhileAG(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledWhilePatterns(
      grammar,
      endRegexSource,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList _getCachedCompiledWhilePatterns(
    IRuleRegistryAndOnigLib grammar,
    String? endRegexSource,
  ) {
    var cached = _cachedCompiledWhilePatterns;
    if (cached == null) {
      cached = _cachedCompiledWhilePatterns = RegExpSourceList();
      cached.push(_while.hasBackReferences ? _while.clone() : _while);
    }
    if (_while.hasBackReferences) {
      cached.setSource(
        0,
        (endRegexSource != null && endRegexSource.isNotEmpty)
            ? endRegexSource
            : '\uFFFF',
      );
    }
    return cached;
  }
}

/// Rules written onto arrays (which JavaScript allows) keep their id here.
final Expando<Object> _idOfNonMapRule = Expando<Object>('RuleId');

Object? _getRawRuleId(Object? desc) {
  if (desc is Map) return desc['id'];
  if (desc is List) return _idOfNonMapRule[desc];
  return jsGet(desc, 'id');
}

void _setRawRuleId(Object? desc, RuleId id) {
  if (desc is Map) {
    desc['id'] = id;
  } else if (desc is List) {
    _idOfNonMapRule[desc] = id;
  } else {
    jsTypeError("Cannot create property 'id' on ${jsToString(desc)}");
  }
}

RuleId _asRuleId(Object? id) {
  if (id is int) return id;
  if (id is double && id == id.truncateToDouble()) return id.toInt();
  jsTypeError('Not a rule id: $id');
}

/// `patterns.length` in JavaScript, or null when it is `undefined`.
int? _jsLength(Object? value) {
  if (value is List) return value.length;
  if (value is String) return value.length;
  return null;
}

abstract final class RuleFactory {
  static CaptureRule createCaptureRule(
    IRuleFactoryHelper helper,
    ILocation? $location,
    Object? name,
    Object? contentName,
    RuleId retokenizeCapturedWithRuleId,
  ) {
    return helper.registerRule((id) {
      return CaptureRule(
        $location,
        id,
        name,
        contentName,
        retokenizeCapturedWithRuleId,
      );
    });
  }

  /// [desc] is a raw rule: a map from the grammar's copy.
  static RuleId getCompiledRuleId(
    Object? desc,
    IRuleFactoryHelper helper,
    Map<String, Object?> repository,
  ) {
    if (!jsTruthy(_getRawRuleId(desc))) {
      helper.registerRule<Rule>((id) {
        _setRawRuleId(desc, id);

        final match = jsGet(desc, 'match');
        if (jsTruthy(match)) {
          return MatchRule(
            locationOf(desc),
            id,
            jsGet(desc, 'name'),
            match,
            RuleFactory._compileCaptures(
              jsGet(desc, 'captures'),
              helper,
              repository,
            ),
          );
        }

        // The grammar's copy has no null values (see `clone`), so null here
        // is JavaScript's `undefined`.
        final begin = jsGet(desc, 'begin');
        if (begin == null) {
          final descRepository = jsGet(desc, 'repository');
          if (jsTruthy(descRepository)) {
            repository = mergeObjects(<String, Object?>{}, [
              repository,
              descRepository,
            ]);
          }
          var patterns = jsGet(desc, 'patterns');
          final include = jsGet(desc, 'include');
          if (patterns == null && jsTruthy(include)) {
            patterns = [
              <String, Object?>{'include': include},
            ];
          }
          return IncludeOnlyRule(
            locationOf(desc),
            id,
            jsGet(desc, 'name'),
            jsGet(desc, 'contentName'),
            RuleFactory._compilePatterns(patterns, helper, repository),
          );
        }

        final captures = jsGet(desc, 'captures');
        final whileSource = jsGet(desc, 'while');
        if (jsTruthy(whileSource)) {
          return BeginWhileRule(
            locationOf(desc),
            id,
            jsGet(desc, 'name'),
            jsGet(desc, 'contentName'),
            begin,
            RuleFactory._compileCaptures(
              _or(jsGet(desc, 'beginCaptures'), captures),
              helper,
              repository,
            ),
            whileSource,
            RuleFactory._compileCaptures(
              _or(jsGet(desc, 'whileCaptures'), captures),
              helper,
              repository,
            ),
            RuleFactory._compilePatterns(
              jsGet(desc, 'patterns'),
              helper,
              repository,
            ),
          );
        }

        return BeginEndRule(
          locationOf(desc),
          id,
          jsGet(desc, 'name'),
          jsGet(desc, 'contentName'),
          begin,
          RuleFactory._compileCaptures(
            _or(jsGet(desc, 'beginCaptures'), captures),
            helper,
            repository,
          ),
          jsGet(desc, 'end'),
          RuleFactory._compileCaptures(
            _or(jsGet(desc, 'endCaptures'), captures),
            helper,
            repository,
          ),
          jsGet(desc, 'applyEndPatternLast'),
          RuleFactory._compilePatterns(
            jsGet(desc, 'patterns'),
            helper,
            repository,
          ),
        );
      });
    }

    return _asRuleId(_getRawRuleId(desc));
  }

  /// JavaScript `a || b`.
  static Object? _or(Object? a, Object? b) => jsTruthy(a) ? a : b;

  static List<CaptureRule?> _compileCaptures(
    Object? captures,
    IRuleFactoryHelper helper,
    Map<String, Object?> repository,
  ) {
    final r = <CaptureRule?>[];

    if (jsTruthy(captures)) {
      final entries = jsForInEntries(captures).toList();

      // Find the maximum capture id
      num maximumCaptureId = 0;
      for (final entry in entries) {
        if (entry.key == r'$vscodeTextmateLocation') {
          continue;
        }
        final numericCaptureId = jsParseInt(entry.key);
        if (numericCaptureId > maximumCaptureId) {
          maximumCaptureId = numericCaptureId;
        }
      }

      // Initialize result
      for (var i = 0; i <= maximumCaptureId; i++) {
        r.add(null);
      }

      // Fill out result
      for (final entry in entries) {
        if (entry.key == r'$vscodeTextmateLocation') {
          continue;
        }
        final numericCaptureId = jsParseInt(entry.key);
        final capture = entry.value;
        var retokenizeCapturedWithRuleId = 0;
        if (jsTruthy(jsGet(capture, 'patterns'))) {
          retokenizeCapturedWithRuleId = RuleFactory.getCompiledRuleId(
            capture,
            helper,
            repository,
          );
        }
        final captureRule = RuleFactory.createCaptureRule(
          helper,
          locationOf(capture),
          jsGet(capture, 'name'),
          jsGet(capture, 'contentName'),
          retokenizeCapturedWithRuleId,
        );
        // `r[NaN]` or `r[-1]` sets a property, not an element.
        if (numericCaptureId >= 0) {
          r[numericCaptureId.toInt()] = captureRule;
        }
      }
    }

    return r;
  }

  static ICompilePatternsResult _compilePatterns(
    Object? patterns,
    IRuleFactoryHelper helper,
    Map<String, Object?> repository,
  ) {
    final r = <RuleId>[];

    int? patternsLength;
    if (jsTruthy(patterns)) {
      patternsLength = _jsLength(patterns);
      for (var i = 0, len = patternsLength ?? 0; i < len; i++) {
        final pattern = jsGet(patterns, '$i');
        var ruleId = -1;

        final include = jsGet(pattern, 'include');
        if (jsTruthy(include)) {
          if (include is! String) {
            jsTypeError('include.indexOf is not a function');
          }
          final reference = parseInclude(include);

          switch (reference) {
            case BaseReference():
            case SelfReference():
              ruleId = RuleFactory.getCompiledRuleId(
                repository[include],
                helper,
                repository,
              );
              break;

            case RelativeReference(:final ruleName):
              // Local include found in `repository`
              final localIncludedRule = repository[ruleName];
              if (jsTruthy(localIncludedRule)) {
                ruleId = RuleFactory.getCompiledRuleId(
                  localIncludedRule,
                  helper,
                  repository,
                );
              } else {
                // console.warn('CANNOT find rule for scopeName: ' + pattern.include + ', I am: ', repository['$base'].name);
              }
              break;

            case TopLevelReference(:final scopeName):
            case TopLevelRepositoryReference(:final scopeName):
              final externalGrammarName = scopeName;
              final externalGrammarInclude =
                  reference is TopLevelRepositoryReference
                  ? reference.ruleName
                  : null;

              // External include
              final externalGrammar = helper.getExternalGrammar(
                externalGrammarName,
                repository,
              );

              if (externalGrammar != null) {
                final externalRepository =
                    externalGrammar['repository'] as Map<String, Object?>;
                if (externalGrammarInclude != null &&
                    externalGrammarInclude.isNotEmpty) {
                  final externalIncludedRule =
                      externalRepository[externalGrammarInclude];
                  if (jsTruthy(externalIncludedRule)) {
                    ruleId = RuleFactory.getCompiledRuleId(
                      externalIncludedRule,
                      helper,
                      externalRepository,
                    );
                  } else {
                    // console.warn('CANNOT find rule for scopeName: ' + pattern.include + ', I am: ', repository['$base'].name);
                  }
                } else {
                  ruleId = RuleFactory.getCompiledRuleId(
                    externalRepository[r'$self'],
                    helper,
                    externalRepository,
                  );
                }
              } else {
                // console.warn('CANNOT find grammar for scopeName: ' + pattern.include + ', I am: ', repository['$base'].name);
              }
              break;
          }
        } else {
          ruleId = RuleFactory.getCompiledRuleId(pattern, helper, repository);
        }

        if (ruleId != -1) {
          final rule = helper.getRule(ruleId);

          var skipRule = false;

          if (rule is IncludeOnlyRule) {
            skipRule = rule.hasMissingPatterns && rule.patterns.isEmpty;
          } else if (rule is BeginEndRule) {
            skipRule = rule.hasMissingPatterns && rule.patterns.isEmpty;
          } else if (rule is BeginWhileRule) {
            skipRule = rule.hasMissingPatterns && rule.patterns.isEmpty;
          }

          if (skipRule) {
            // console.log('REMOVING RULE ENTIRELY DUE TO EMPTY PATTERNS THAT ARE MISSING');
            continue;
          }

          r.add(ruleId);
        }
      }
    }

    // `patterns.length` is undefined for non-array values, which never
    // equals `r.length`.
    final bool hasMissingPatterns;
    if (!jsTruthy(patterns)) {
      hasMissingPatterns = r.isNotEmpty;
    } else if (patternsLength == null) {
      hasMissingPatterns = true;
    } else {
      hasMissingPatterns = patternsLength != r.length;
    }
    return ICompilePatternsResult(r, hasMissingPatterns);
  }
}

class _RegExpSourceAnchorCache {
  const _RegExpSourceAnchorCache(this.a0G0, this.a0G1, this.a1G0, this.a1G1);

  final String a0G0;
  final String a0G1;
  final String a1G0;
  final String a1G1;
}

class RegExpSource {
  /// [regExpSource] is the grammar's value. A string is the pattern; any
  /// other value reaches vscode-oniguruma as the empty pattern (its UTF-8
  /// conversion reads no `length`), except a non-empty array, which throws
  /// as upstream's `charAt` call does.
  RegExpSource(Object? regExpSource, this.ruleId) {
    if (regExpSource is String && regExpSource.isNotEmpty) {
      final len = regExpSource.length;
      var lastPushedPos = 0;
      StringBuffer? output;

      var hasAnchor = false;
      for (var pos = 0; pos < len; pos++) {
        final ch = regExpSource.codeUnitAt(pos);

        if (ch == 0x5C /* \ */ ) {
          if (pos + 1 < len) {
            final nextCh = regExpSource.codeUnitAt(pos + 1);
            if (nextCh == 0x7A /* z */ ) {
              output ??= StringBuffer();
              output.write(regExpSource.substring(lastPushedPos, pos));
              output.write(r'$(?!\n)(?<!\n)');
              lastPushedPos = pos + 2;
            } else if (nextCh == 0x41 /* A */ || nextCh == 0x47 /* G */ ) {
              hasAnchor = true;
            }
            pos++;
          }
        }
      }

      this.hasAnchor = hasAnchor;
      if (lastPushedPos == 0) {
        // No \z hit
        source = regExpSource;
      } else {
        output!.write(regExpSource.substring(lastPushedPos, len));
        source = output.toString();
      }
    } else {
      if (regExpSource is List && regExpSource.isNotEmpty) {
        jsTypeError('regExpSource.charAt is not a function');
      }
      hasAnchor = false;
      source = regExpSource is String ? regExpSource : '';
    }

    if (hasAnchor) {
      _anchorCache = _buildAnchorCache();
    } else {
      _anchorCache = null;
    }

    hasBackReferences = _hasBackReferences.hasMatch(source);
  }

  late String source;
  final RuleId ruleId;
  late bool hasAnchor;
  late final bool hasBackReferences;
  _RegExpSourceAnchorCache? _anchorCache;

  RegExpSource clone() {
    return RegExpSource(source, ruleId);
  }

  void setSource(String newSource) {
    if (source == newSource) {
      return;
    }
    source = newSource;

    if (hasAnchor) {
      _anchorCache = _buildAnchorCache();
    }
  }

  String resolveBackReferences(
    String lineText,
    List<IOnigCaptureIndex> captureIndices,
  ) {
    final capturedValues = [
      for (final capture in captureIndices)
        jsSubstring(lineText, capture.start, capture.end),
    ];
    return source.replaceAllMapped(_backReferencingEnd, (match) {
      final index = int.tryParse(match[1]!);
      final value = (index != null && index < capturedValues.length)
          ? capturedValues[index]
          : '';
      return escapeRegExpCharacters(value);
    });
  }

  _RegExpSourceAnchorCache _buildAnchorCache() {
    final source = this.source;
    final len = source.length;
    final a0G0 = List<int>.filled(len, 0);
    final a0G1 = List<int>.filled(len, 0);
    final a1G0 = List<int>.filled(len, 0);
    final a1G1 = List<int>.filled(len, 0);

    for (var pos = 0; pos < len; pos++) {
      final ch = source.codeUnitAt(pos);
      a0G0[pos] = ch;
      a0G1[pos] = ch;
      a1G0[pos] = ch;
      a1G1[pos] = ch;

      if (ch == 0x5C /* \ */ ) {
        if (pos + 1 < len) {
          final nextCh = source.codeUnitAt(pos + 1);
          if (nextCh == 0x41 /* A */ ) {
            a0G0[pos + 1] = 0xFFFF;
            a0G1[pos + 1] = 0xFFFF;
            a1G0[pos + 1] = 0x41;
            a1G1[pos + 1] = 0x41;
          } else if (nextCh == 0x47 /* G */ ) {
            a0G0[pos + 1] = 0xFFFF;
            a0G1[pos + 1] = 0x47;
            a1G0[pos + 1] = 0xFFFF;
            a1G1[pos + 1] = 0x47;
          } else {
            a0G0[pos + 1] = nextCh;
            a0G1[pos + 1] = nextCh;
            a1G0[pos + 1] = nextCh;
            a1G1[pos + 1] = nextCh;
          }
          pos++;
        }
      }
    }

    return _RegExpSourceAnchorCache(
      String.fromCharCodes(a0G0),
      String.fromCharCodes(a0G1),
      String.fromCharCodes(a1G0),
      String.fromCharCodes(a1G1),
    );
  }

  String resolveAnchors(bool allowA, bool allowG) {
    final anchorCache = _anchorCache;
    if (!hasAnchor || anchorCache == null) {
      return source;
    }

    if (allowA) {
      if (allowG) {
        return anchorCache.a1G1;
      } else {
        return anchorCache.a1G0;
      }
    } else {
      if (allowG) {
        return anchorCache.a0G1;
      } else {
        return anchorCache.a0G0;
      }
    }
  }
}

class RegExpSourceList {
  final List<RegExpSource> _items = <RegExpSource>[];
  bool _hasAnchors = false;
  CompiledRule? _cached;
  CompiledRule? _anchorCacheA0G0;
  CompiledRule? _anchorCacheA0G1;
  CompiledRule? _anchorCacheA1G0;
  CompiledRule? _anchorCacheA1G1;

  void dispose() {
    _disposeCaches();
  }

  void _disposeCaches() {
    if (_cached != null) {
      _cached!.dispose();
      _cached = null;
    }
    if (_anchorCacheA0G0 != null) {
      _anchorCacheA0G0!.dispose();
      _anchorCacheA0G0 = null;
    }
    if (_anchorCacheA0G1 != null) {
      _anchorCacheA0G1!.dispose();
      _anchorCacheA0G1 = null;
    }
    if (_anchorCacheA1G0 != null) {
      _anchorCacheA1G0!.dispose();
      _anchorCacheA1G0 = null;
    }
    if (_anchorCacheA1G1 != null) {
      _anchorCacheA1G1!.dispose();
      _anchorCacheA1G1 = null;
    }
  }

  void push(RegExpSource item) {
    _items.add(item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  void unshift(RegExpSource item) {
    _items.insert(0, item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  int length() {
    return _items.length;
  }

  /// A null [newSource] (no `endRule` on the stack) fails as it does
  /// upstream, where the null pattern cannot be compiled.
  void setSource(int index, String? newSource) {
    if (_items[index].source != newSource) {
      // bust the cache
      _disposeCaches();
      if (newSource == null) {
        jsTypeError('Cannot compile a null end pattern');
      }
      _items[index].setSource(newSource);
    }
  }

  CompiledRule compile(IOnigLib onigLib) {
    var cached = _cached;
    if (cached == null) {
      final regExps = [for (final e in _items) e.source];
      cached = _cached = CompiledRule(onigLib, regExps, [
        for (final e in _items) e.ruleId,
      ]);
    }
    return cached;
  }

  CompiledRule compileAG(IOnigLib onigLib, bool allowA, bool allowG) {
    if (!_hasAnchors) {
      return compile(onigLib);
    } else {
      if (allowA) {
        if (allowG) {
          return _anchorCacheA1G1 ??= _resolveAnchors(onigLib, allowA, allowG);
        } else {
          return _anchorCacheA1G0 ??= _resolveAnchors(onigLib, allowA, allowG);
        }
      } else {
        if (allowG) {
          return _anchorCacheA0G1 ??= _resolveAnchors(onigLib, allowA, allowG);
        } else {
          return _anchorCacheA0G0 ??= _resolveAnchors(onigLib, allowA, allowG);
        }
      }
    }
  }

  CompiledRule _resolveAnchors(IOnigLib onigLib, bool allowA, bool allowG) {
    final regExps = [for (final e in _items) e.resolveAnchors(allowA, allowG)];
    return CompiledRule(onigLib, regExps, [for (final e in _items) e.ruleId]);
  }
}

class CompiledRule {
  CompiledRule(IOnigLib onigLib, this.regExps, this.rules)
    : scanner = onigLib.createOnigScanner(regExps);

  final OnigScanner scanner;
  final List<String> regExps;
  final List<RuleId> rules;

  void dispose() {
    scanner.dispose();
  }

  @override
  String toString() {
    final r = <String>[];
    for (var i = 0, len = rules.length; i < len; i++) {
      r.add('   - ${rules[i]}: ${regExps[i]}');
    }
    return r.join('\n');
  }

  IFindNextMatchResult? findNextMatchSync(
    OnigString string,
    int startPosition,
    int options,
  ) {
    final result = scanner.findNextMatchSync(string, startPosition, options);
    if (result == null) {
      return null;
    }

    return IFindNextMatchResult(rules[result.index], result.captureIndices);
  }
}

class IFindNextMatchResult {
  const IFindNextMatchResult(this.ruleId, this.captureIndices);

  final RuleId ruleId;
  final List<IOnigCaptureIndex> captureIndices;
}
