// The Run and Debug UI's strings, in English and Chinese.
//
// Kept here rather than in the arb files while those are being edited
// elsewhere; to move to lib/l10n (app_en.arb, app_zh.arb) later.
// Upstream's English texts are VS Code's (debug.contribution.ts,
// debugViewlet.ts, variablesView.ts, watchExpressionsView.ts,
// callStackView.ts, breakpointsView.ts, repl.ts, debugToolBar.ts,
// welcomeView.ts, breakpointWidget.ts).

import 'package:flutter/widgets.dart';

/// The strings for one language.
class DebugStrings {
  const DebugStrings._(this._values);

  final Map<String, String> _values;

  static const en = DebugStrings._(_en);
  static const zh = DebugStrings._(_zh);

  /// The strings for [context]'s locale (Chinese for `zh*`, else English).
  static DebugStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return forLanguage(locale?.languageCode);
  }

  static DebugStrings forLanguage(String? languageCode) =>
      languageCode != null && languageCode.startsWith('zh') ? zh : en;

  String _t(String key) => _values[key] ?? _en[key] ?? key;

  /// The text of [key] (for tests and hosts without a build context).
  String text(String key) => _t(key);

  /// Every key the table has.
  Iterable<String> get keys => _en.keys;

  String _f(String key, List<Object?> args) {
    var text = _t(key);
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', '${args[i]}');
    }
    return text;
  }

  // View and section titles.
  String get runAndDebug => _t('runAndDebug');
  String get variables => _t('variables');
  String get watch => _t('watch');
  String get callStack => _t('callStack');
  String get breakpoints => _t('breakpoints');
  String get loadedScripts => _t('loadedScripts');
  String get debugConsole => _t('debugConsole');

  // Run and Debug view.
  String get startDebugging => _t('startDebugging');
  String get runWithoutDebugging => _t('runWithoutDebugging');
  String get noConfigurations => _t('noConfigurations');
  String get addConfiguration => _t('addConfiguration');
  String get openLaunchJson => _t('openLaunchJson');
  String get createLaunchJson => _t('createLaunchJson');
  String get welcomeRun => _t('welcomeRun');
  String get welcomeCustomize => _t('welcomeCustomize');
  String get welcomeNoFolder => _t('welcomeNoFolder');
  String get selectDebugger => _t('selectDebugger');
  String get noDebuggers => _t('noDebuggers');
  String get moreActions => _t('moreActions');

  // Toolbar.
  String get continue_ => _t('continue');
  String get pause => _t('pause');
  String get stepOver => _t('stepOver');
  String get stepInto => _t('stepInto');
  String get stepOut => _t('stepOut');
  String get stepBack => _t('stepBack');
  String get reverseContinue => _t('reverseContinue');
  String get restart => _t('restart');
  String get stop => _t('stop');
  String get disconnect => _t('disconnect');
  String get hotReload => _t('hotReload');

  // Call stack.
  String pausedOn(String reason) => _f('pausedOn', [reason]);
  String get paused => _t('paused');
  String get running => _t('running');
  String get restartFrame => _t('restartFrame');
  String get loadMoreStackFrames => _t('loadMoreStackFrames');
  String showMoreStackFrames(int n) => _f('showMoreStackFrames', [n]);
  String get copyCallStack => _t('copyCallStack');
  String get terminateThread => _t('terminateThread');
  String get unknownSource => _t('unknownSource');

  // Variables and watch.
  String get setValue => _t('setValue');
  String get copyValue => _t('copyValue');
  String get copyAsExpression => _t('copyAsExpression');
  String get addToWatch => _t('addToWatch');
  String get breakOnValueChange => _t('breakOnValueChange');
  String get breakOnValueRead => _t('breakOnValueRead');
  String get addExpression => _t('addExpression');
  String get editExpression => _t('editExpression');
  String get removeExpression => _t('removeExpression');
  String get removeAllExpressions => _t('removeAllExpressions');
  String get collapseAll => _t('collapseAll');
  String get refresh => _t('refresh');
  String get expressionPlaceholder => _t('expressionPlaceholder');
  String get notAvailable => _t('notAvailable');
  String get noVariables => _t('noVariables');
  String get notPaused => _t('notPaused');
  String showMoreVariables(int n) => _f('showMoreVariables', [n]);

  // Breakpoints.
  String get addFunctionBreakpoint => _t('addFunctionBreakpoint');
  String get addDataBreakpointAtAddress => _t('addDataBreakpointAtAddress');
  String get toggleActivateBreakpoints => _t('toggleActivateBreakpoints');
  String get removeAllBreakpoints => _t('removeAllBreakpoints');
  String get enableAllBreakpoints => _t('enableAllBreakpoints');
  String get disableAllBreakpoints => _t('disableAllBreakpoints');
  String get removeBreakpoint => _t('removeBreakpoint');
  String get editBreakpoint => _t('editBreakpoint');
  String get editCondition => _t('editCondition');
  String get editHitCount => _t('editHitCount');
  String get editLogMessage => _t('editLogMessage');
  String get enableBreakpoint => _t('enableBreakpoint');
  String get disableBreakpoint => _t('disableBreakpoint');
  String get functionBreakpointPlaceholder => _t('functionBreakpointPlaceholder');
  String get exceptionConditionPlaceholder => _t('exceptionConditionPlaceholder');
  String get unverifiedBreakpoint => _t('unverifiedBreakpoint');
  String get disabledBreakpoint => _t('disabledBreakpoint');
  String get breakpointsDeactivated => _t('breakpointsDeactivated');
  String get logpoint => _t('logpoint');
  String get conditionalBreakpoint => _t('conditionalBreakpoint');
  String get functionBreakpoint => _t('functionBreakpoint');
  String get dataBreakpoint => _t('dataBreakpoint');
  String get breakpoint => _t('breakpoint');
  String conditionLabel(String c) => _f('conditionLabel', [c]);
  String hitCountLabel(String c) => _f('hitCountLabel', [c]);
  String logMessageLabel(String c) => _f('logMessageLabel', [c]);
  String lineLabel(int line) => _f('lineLabel', [line]);

  // Breakpoint widget (in the editor).
  String get expression => _t('expression');
  String get hitCount => _t('hitCount');
  String get logMessage => _t('logMessage');
  String get conditionPlaceholder => _t('conditionPlaceholder');
  String get hitCountPlaceholder => _t('hitCountPlaceholder');
  String get logMessagePlaceholder => _t('logMessagePlaceholder');
  String get addBreakpoint => _t('addBreakpoint');
  String get addConditionalBreakpoint => _t('addConditionalBreakpoint');
  String get addLogpoint => _t('addLogpoint');
  String get runToLine => _t('runToLine');

  // Console.
  String get consolePlaceholder => _t('consolePlaceholder');
  String get clearConsole => _t('clearConsole');
  String get copyAll => _t('copyAll');
  String get collapseAllConsole => _t('collapseAll');
  String get noSession => _t('noSession');

  // Loaded scripts.
  String get noLoadedScripts => _t('noLoadedScripts');
}

const _en = <String, String>{
  'runAndDebug': 'Run and Debug',
  'variables': 'Variables',
  'watch': 'Watch',
  'callStack': 'Call Stack',
  'breakpoints': 'Breakpoints',
  'loadedScripts': 'Loaded Scripts',
  'debugConsole': 'Debug Console',
  'startDebugging': 'Start Debugging',
  'runWithoutDebugging': 'Run Without Debugging',
  'noConfigurations': 'No Configurations',
  'addConfiguration': 'Add Configuration...',
  'openLaunchJson': "Open 'launch.json'",
  'createLaunchJson': 'create a launch.json file',
  'welcomeRun': 'Run and Debug',
  'welcomeCustomize': 'To customize Run and Debug, {link}.',
  'welcomeNoFolder': 'To customize Run and Debug, open a folder and create a launch.json file.',
  'selectDebugger': 'Select debugger',
  'noDebuggers': 'No debug extensions are installed.',
  'moreActions': 'More Actions...',
  'continue': 'Continue',
  'pause': 'Pause',
  'stepOver': 'Step Over',
  'stepInto': 'Step Into',
  'stepOut': 'Step Out',
  'stepBack': 'Step Back',
  'reverseContinue': 'Reverse',
  'restart': 'Restart',
  'stop': 'Stop',
  'disconnect': 'Disconnect',
  'hotReload': 'Hot Reload',
  'pausedOn': 'Paused on {0}',
  'paused': 'Paused',
  'running': 'Running',
  'restartFrame': 'Restart Frame',
  'loadMoreStackFrames': 'Load More Stack Frames',
  'showMoreStackFrames': 'Show {0} More Stack Frames',
  'copyCallStack': 'Copy Call Stack',
  'terminateThread': 'Terminate Thread',
  'unknownSource': 'Unknown Source',
  'setValue': 'Set Value',
  'copyValue': 'Copy Value',
  'copyAsExpression': 'Copy as Expression',
  'addToWatch': 'Add to Watch',
  'breakOnValueChange': 'Break on Value Change',
  'breakOnValueRead': 'Break on Value Read',
  'addExpression': 'Add Expression',
  'editExpression': 'Edit Expression',
  'removeExpression': 'Remove Expression',
  'removeAllExpressions': 'Remove All Expressions',
  'collapseAll': 'Collapse All',
  'refresh': 'Refresh',
  'expressionPlaceholder': 'Expression to watch',
  'notAvailable': 'not available',
  'noVariables': 'No variables',
  'notPaused': 'Not paused',
  'showMoreVariables': 'Show {0} more',
  'addFunctionBreakpoint': 'Add Function Breakpoint',
  'addDataBreakpointAtAddress': 'Add Data Breakpoint at Address',
  'toggleActivateBreakpoints': 'Toggle Activate Breakpoints',
  'removeAllBreakpoints': 'Remove All Breakpoints',
  'enableAllBreakpoints': 'Enable All Breakpoints',
  'disableAllBreakpoints': 'Disable All Breakpoints',
  'removeBreakpoint': 'Remove Breakpoint',
  'editBreakpoint': 'Edit Breakpoint...',
  'editCondition': 'Edit Condition...',
  'editHitCount': 'Edit Hit Count...',
  'editLogMessage': 'Edit Log Message...',
  'enableBreakpoint': 'Enable Breakpoint',
  'disableBreakpoint': 'Disable Breakpoint',
  'functionBreakpointPlaceholder': 'Function to break on',
  'exceptionConditionPlaceholder': 'Break when expression evaluates to true',
  'unverifiedBreakpoint': 'Unverified Breakpoint',
  'disabledBreakpoint': 'Disabled Breakpoint',
  'breakpointsDeactivated': 'Breakpoints are deactivated',
  'logpoint': 'Logpoint',
  'conditionalBreakpoint': 'Conditional Breakpoint',
  'functionBreakpoint': 'Function Breakpoint',
  'dataBreakpoint': 'Data Breakpoint',
  'breakpoint': 'Breakpoint',
  'conditionLabel': 'Condition: {0}',
  'hitCountLabel': 'Hit Count: {0}',
  'logMessageLabel': 'Log Message: {0}',
  'lineLabel': 'Line {0}',
  'expression': 'Expression',
  'hitCount': 'Hit Count',
  'logMessage': 'Log Message',
  'conditionPlaceholder': "Break when expression evaluates to true. 'Enter' to accept, 'esc' to cancel.",
  'hitCountPlaceholder': "Break when hit count condition is met. 'Enter' to accept, 'esc' to cancel.",
  'logMessagePlaceholder':
      "Message to log when breakpoint is hit. Expressions within {} are interpolated. 'Enter' to accept, 'esc' to cancel.",
  'addBreakpoint': 'Add Breakpoint',
  'addConditionalBreakpoint': 'Add Conditional Breakpoint...',
  'addLogpoint': 'Add Logpoint...',
  'runToLine': 'Run to Line',
  'consolePlaceholder': 'Evaluate expression',
  'clearConsole': 'Clear Console',
  'copyAll': 'Copy All',
  'noSession': 'Start a debug session to evaluate expressions',
  'noLoadedScripts': 'No loaded scripts',
};

const _zh = <String, String>{
  'runAndDebug': '运行和调试',
  'variables': '变量',
  'watch': '监视',
  'callStack': '调用堆栈',
  'breakpoints': '断点',
  'loadedScripts': '已载入的脚本',
  'debugConsole': '调试控制台',
  'startDebugging': '开始调试',
  'runWithoutDebugging': '以非调试模式运行',
  'noConfigurations': '没有配置',
  'addConfiguration': '添加配置...',
  'openLaunchJson': '打开 "launch.json"',
  'createLaunchJson': '创建 launch.json 文件',
  'welcomeRun': '运行和调试',
  'welcomeCustomize': '要自定义运行和调试，请{link}。',
  'welcomeNoFolder': '要自定义运行和调试，请打开文件夹并创建 launch.json 文件。',
  'selectDebugger': '选择调试器',
  'noDebuggers': '未安装调试扩展。',
  'moreActions': '更多操作...',
  'continue': '继续',
  'pause': '暂停',
  'stepOver': '单步跳过',
  'stepInto': '单步调试',
  'stepOut': '单步跳出',
  'stepBack': '后退',
  'reverseContinue': '反向',
  'restart': '重启',
  'stop': '停止',
  'disconnect': '断开连接',
  'hotReload': '热重载',
  'pausedOn': '因 {0} 已暂停',
  'paused': '已暂停',
  'running': '正在运行',
  'restartFrame': '重启框架',
  'loadMoreStackFrames': '加载更多堆栈帧',
  'showMoreStackFrames': '显示另外 {0} 个堆栈帧',
  'copyCallStack': '复制调用堆栈',
  'terminateThread': '终止线程',
  'unknownSource': '未知源',
  'setValue': '设置值',
  'copyValue': '复制值',
  'copyAsExpression': '复制为表达式',
  'addToWatch': '添加到监视',
  'breakOnValueChange': '值更改时中断',
  'breakOnValueRead': '读取值时中断',
  'addExpression': '添加表达式',
  'editExpression': '编辑表达式',
  'removeExpression': '删除表达式',
  'removeAllExpressions': '删除所有表达式',
  'collapseAll': '全部折叠',
  'refresh': '刷新',
  'expressionPlaceholder': '要监视的表达式',
  'notAvailable': '不可用',
  'noVariables': '没有变量',
  'notPaused': '未暂停',
  'showMoreVariables': '再显示 {0} 个',
  'addFunctionBreakpoint': '添加函数断点',
  'addDataBreakpointAtAddress': '在地址处添加数据断点',
  'toggleActivateBreakpoints': '切换激活断点',
  'removeAllBreakpoints': '删除所有断点',
  'enableAllBreakpoints': '启用所有断点',
  'disableAllBreakpoints': '禁用所有断点',
  'removeBreakpoint': '删除断点',
  'editBreakpoint': '编辑断点...',
  'editCondition': '编辑条件...',
  'editHitCount': '编辑命中次数...',
  'editLogMessage': '编辑日志消息...',
  'enableBreakpoint': '启用断点',
  'disableBreakpoint': '禁用断点',
  'functionBreakpointPlaceholder': '要中断的函数',
  'exceptionConditionPlaceholder': '在表达式计算结果为 true 时中断',
  'unverifiedBreakpoint': '未验证的断点',
  'disabledBreakpoint': '已禁用的断点',
  'breakpointsDeactivated': '断点已停用',
  'logpoint': '日志点',
  'conditionalBreakpoint': '条件断点',
  'functionBreakpoint': '函数断点',
  'dataBreakpoint': '数据断点',
  'breakpoint': '断点',
  'conditionLabel': '条件: {0}',
  'hitCountLabel': '命中次数: {0}',
  'logMessageLabel': '日志消息: {0}',
  'lineLabel': '第 {0} 行',
  'expression': '表达式',
  'hitCount': '命中次数',
  'logMessage': '日志消息',
  'conditionPlaceholder': '在表达式计算结果为 true 时中断。按 "Enter" 确认，按 "Esc" 取消。',
  'hitCountPlaceholder': '在满足命中次数条件时中断。按 "Enter" 确认，按 "Esc" 取消。',
  'logMessagePlaceholder': '命中断点时记录的消息。{} 中的表达式会被插值。按 "Enter" 确认，按 "Esc" 取消。',
  'addBreakpoint': '添加断点',
  'addConditionalBreakpoint': '添加条件断点...',
  'addLogpoint': '添加日志点...',
  'runToLine': '运行到行',
  'consolePlaceholder': '计算表达式',
  'clearConsole': '清除控制台',
  'copyAll': '全部复制',
  'noSession': '启动调试会话以计算表达式',
  'noLoadedScripts': '没有已载入的脚本',
};
