import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'chat_models.dart';
import 'mock_conversation.dart';

/// A message submitted from the composer.
class ComposerMessage {
  const ComposerMessage({required this.text, this.mentions = const []});

  final String text;
  final List<String> mentions;

  bool get isEmpty => text.trim().isEmpty && mentions.isEmpty;
}

class AskQuestion {
  const AskQuestion({
    required this.prompt,
    required this.options,
    this.allowMultiple = false,
  });

  final String prompt;
  final List<String> options;
  final bool allowMultiple;
}

/// A tool call waiting on user input, rendered in the feedback area.
class AskQuestionRequest {
  const AskQuestionRequest({required this.title, required this.questions});

  final String title;
  final List<AskQuestion> questions;
}

enum TaskStatus { running, succeeded, failed }

class BackgroundTask {
  BackgroundTask({required this.command, required this.startedAt});

  final String command;
  final DateTime startedAt;
  TaskStatus status = TaskStatus.running;
}

class FileChange {
  const FileChange({
    required this.path,
    required this.added,
    required this.removed,
  });

  final String path;
  final int added;
  final int removed;

  String get fileName => path.split('/').last;
  String get directory {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }
}

class ContextSegment {
  const ContextSegment(this.label, this.tokens);

  final String label;
  final int tokens;
}

/// Mock agent session: history, the live turn, and side-panel state.
class ChatSession extends ChangeNotifier {
  ChatSession({this._historyCount = MockConversation.itemCount});

  /// Leading items that come from the mock history; editing a message there
  /// truncates it.
  int _historyCount;
  final List<ChatItem> _live = [];

  int get itemCount => _historyCount + _live.length;

  ChatItem itemAt(int index) => index < _historyCount
      ? MockConversation.itemAt(index)
      : _live[index - _historyCount];

  bool get isStreaming => _run != null;

  AskQuestionRequest? get pendingQuestion => _pendingQuestion;
  AskQuestionRequest? _pendingQuestion;
  Completer<String>? _answer;

  final List<BackgroundTask> tasks = [];
  final List<FileChange> fileChanges = [];

  static const contextWindow = 200000;
  int _conversationTokens = 41200;
  List<ContextSegment> get contextSegments => [
    const ContextSegment('System prompt', 3100),
    const ContextSegment('Tools', 11800),
    const ContextSegment('Rules & memory', 2400),
    ContextSegment('Files', 18600 + fileChanges.length * 1400),
    ContextSegment('Conversation', _conversationTokens),
  ];
  int get contextUsed =>
      contextSegments.fold(0, (sum, segment) => sum + segment.tokens);

  Object? _run;

  void send(ComposerMessage message) {
    if (message.isEmpty || isStreaming) return;
    _live.add(UserMessageItem(text: message.text.trim()));
    _conversationTokens += 60 + message.text.length * 2;
    final run = Object();
    _run = run;
    notifyListeners();
    unawaited(_script(run, message));
  }

  /// Resends the user message at [index] as [message]: everything after it
  /// is discarded and the turn runs again from there.
  void editMessage(int index, ComposerMessage message) {
    if (message.isEmpty || itemAt(index) is! UserMessageItem) return;
    stop();
    if (index < _historyCount) {
      _historyCount = index;
      _live.clear();
    } else {
      _live.removeRange(index - _historyCount, _live.length);
    }
    _pendingQuestion = null;
    tasks.clear();
    fileChanges.clear();
    send(message);
  }

  void stop() {
    if (_run == null) return;
    _run = null;
    _finishThinking();
    _removeStatus();
    _pendingQuestion = null;
    _answer = null;
    notifyListeners();
  }

  void answerQuestion(String summary) {
    _pendingQuestion = null;
    _answer?.complete(summary);
    _answer = null;
    notifyListeners();
  }

  void keepAllChanges() {
    fileChanges.clear();
    notifyListeners();
  }

  void undoAllChanges() {
    fileChanges.clear();
    _live.add(const AssistantTextItem('已撤销本轮的全部文件修改。'));
    notifyListeners();
  }

  void dismissTask(BackgroundTask task) {
    tasks.remove(task);
    notifyListeners();
  }

  // --- Mock script -------------------------------------------------------

  Future<bool> _wait(Object run, int milliseconds) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return identical(_run, run);
  }

  void _setStatus(String label) {
    _removeStatus();
    _live.add(LiveStatusItem(label));
    notifyListeners();
  }

  void _removeStatus() {
    if (_live.isNotEmpty && _live.last is LiveStatusItem) _live.removeLast();
  }

  void _append(ChatItem item) {
    _removeStatus();
    _live.add(item);
    notifyListeners();
  }

  Future<bool> _stream(Object run, String text) async {
    _removeStatus();
    final index = _live.length;
    _live.add(const AssistantTextItem(''));
    for (var end = 0; end < text.length;) {
      end = (end + 3).clamp(0, text.length);
      _live[index] = AssistantTextItem(text.substring(0, end));
      _conversationTokens += 2;
      notifyListeners();
      if (!await _wait(run, 16)) return false;
    }
    return true;
  }

  /// The streaming thought in [_live], and how long it has run (mock time,
  /// counted from its waits, so it is the same under test).
  int? _thinkingIndex;
  int _thinkingMs = 0;

  /// Thought streaming pace: slow enough to read along (~40 characters a
  /// second).
  static const _thinkingChunk = 2;
  static const _thinkingChunkMs = 50;

  Future<bool> _think(Object run, String text) async {
    _removeStatus();
    _thinkingIndex = _live.length;
    _thinkingMs = 0;
    _live.add(const ThinkingItem(text: '', tokens: 0));
    notifyListeners();
    Future<bool> wait(int milliseconds) {
      _thinkingMs += milliseconds;
      return _wait(run, milliseconds);
    }

    if (!await wait(400)) return false;
    var tokens = 0;
    for (var end = 0; end < text.length;) {
      end = (end + _thinkingChunk).clamp(0, text.length);
      tokens += 2;
      _live[_thinkingIndex!] = ThinkingItem(
        text: text.substring(0, end),
        tokens: tokens,
      );
      _conversationTokens += 2;
      notifyListeners();
      if (!await wait(_thinkingChunkMs)) return false;
    }
    _finishThinking();
    notifyListeners();
    return true;
  }

  /// Settles the streaming thought, if any, as done (also when stopped).
  void _finishThinking() {
    final index = _thinkingIndex;
    _thinkingIndex = null;
    if (index == null || index >= _live.length) return;
    final item = _live[index];
    if (item is! ThinkingItem || !item.streaming) return;
    _live[index] = ThinkingItem(
      text: item.text,
      tokens: item.tokens,
      seconds: math.max(1, (_thinkingMs / 1000).round()),
    );
  }

  Future<void> _script(Object run, ComposerMessage message) async {
    final target = message.mentions.isEmpty
        ? 'lib/chat/chat_screen.dart'
        : message.mentions.first;

    if (!await _think(
      run,
      '用户想调整输入框，先确认需求涉及的文件：$target 是入口，'
      '输入框本身在 composer 目录下，由 ChatComposer 管理编辑器、菜单和发送按钮。\n\n'
      '高度策略有几种做法：随内容自动增高、固定行数后滚动、可拖拽调整。'
      '自动增高最符合直觉，但要给一个上限，否则长文本会把历史记录挤没；'
      '固定行数实现最简单，只是短消息也会占着几行空白；'
      '可拖拽调整最灵活，但需要额外的拖拽手柄，还要记住用户调整后的高度。'
      '三种的交互差异不小，而且会影响发送按钮和工具栏的布局，'
      '直接选一种改下去风险偏高。\n\n'
      '快捷输入方面，@ 提及和 / 命令已经有菜单的基础实现，'
      '提及会变成不可拆分的标签，命令只在消息开头生效。'
      '粘贴图片还没有入口，需要额外处理剪贴板里的图片数据，'
      '在 web 上还要考虑浏览器的剪贴板权限。\n\n'
      '另外编辑已发送的消息也复用同一个输入框，改高度策略时要确认'
      '历史记录里的编辑框不会因此跳动。\n\n'
      '先读一下相关代码确认现状，再向用户确认高度策略和需要支持的快捷输入，'
      '避免改完之后返工。',
    )) {
      return;
    }
    _setStatus('Exploring');
    if (!await _wait(run, 500)) return;
    _append(ToolCallItem(kind: ToolKind.read, target: target.split('/').last));
    if (!await _wait(run, 350)) return;
    _append(
      const ToolCallItem(
        kind: ToolKind.grep,
        target: 'ChatComposer',
        detail: '3 results',
      ),
    );
    _setStatus('Generating');
    if (!await _wait(run, 400)) return;
    if (!await _stream(run, '我看了一下相关代码，开始修改之前需要先确认两点：')) return;

    final answer = Completer<String>();
    _answer = answer;
    _pendingQuestion = const AskQuestionRequest(
      title: 'Ask Question',
      questions: [
        AskQuestion(
          prompt: '输入框的高度策略用哪一种？',
          options: ['随内容自动增高，最多 8 行', '固定 3 行，超出滚动', '可拖拽调整高度'],
        ),
        AskQuestion(
          prompt: '需要支持哪些快捷输入？',
          options: ['@ 提及文件', '/ 命令', '粘贴图片'],
          allowMultiple: true,
        ),
      ],
    );
    _setStatus('Waiting for your answer');
    final summary = await answer.future;
    if (!identical(_run, run)) return;
    _append(AssistantTextItem('已收到：$summary'));

    _setStatus('Editing');
    if (!await _wait(run, 700)) return;
    _append(
      const CodeDiffItem(
        fileName: 'composer.dart',
        directory: 'lib/chat/composer',
        lines: [
          DiffLine(DiffLineType.context, 88, 'child: QuillEditor('),
          DiffLine(
            DiffLineType.removed,
            89,
            '  config: const QuillEditorConfig(),',
          ),
          DiffLine(DiffLineType.added, 89, '  config: QuillEditorConfig('),
          DiffLine(DiffLineType.added, 90, '    maxHeight: _maxEditorHeight,'),
          DiffLine(DiffLineType.added, 91, '    onKeyPressed: _handleKey,'),
          DiffLine(DiffLineType.added, 92, '  ),'),
        ],
      ),
    );
    fileChanges
      ..clear()
      ..addAll(const [
        FileChange(
          path: 'lib/chat/composer/composer.dart',
          added: 42,
          removed: 7,
        ),
        FileChange(path: 'lib/chat/chat_screen.dart', added: 12, removed: 3),
        FileChange(path: 'test/widget_test.dart', added: 18, removed: 0),
      ]);
    notifyListeners();

    final task = BackgroundTask(
      command: 'flutter test',
      startedAt: DateTime.now(),
    );
    tasks.add(task);
    _append(
      const TerminalItem(
        command: 'flutter test',
        output: 'Running in background…',
      ),
    );
    _setStatus('Generating');
    if (!await _wait(run, 300)) return;
    if (!await _stream(
      run,
      '修改已完成：\n- 输入框使用 `QuillEditor`，随内容增高\n- 支持 `@` 提及和 `/` 命令\n- 测试正在后台运行，结束后会更新状态',
    )) {
      return;
    }
    _run = null;
    _removeStatus();
    notifyListeners();

    await Future<void>.delayed(const Duration(seconds: 4));
    if (!tasks.contains(task)) return;
    task.status = TaskStatus.succeeded;
    notifyListeners();
  }
}
