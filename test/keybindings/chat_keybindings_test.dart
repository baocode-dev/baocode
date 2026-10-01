import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/l10n/app_localizations_zh.dart';
import 'package:baocode/l10n/command_titles.dart';
import 'package:baocode/l10n/l10n.dart';

void main() {
  test('the chat\'s commands are in the catalog, under Chat', () {
    for (final info in chatExtraCommands) {
      expect(commandCatalog[info.id]?.label, 'Chat: ${info.title}');
    }
    expect(
      commandCatalog.keys,
      containsAll([
        ChatCommandIds.newChat,
        '${ChatCommandIds.openAgentAtIndex}1',
        '${ChatCommandIds.openAgentAtIndex}9',
        '${ChatCommandIds.focusPane}4',
        ChatCommandIds.submit,
        ChatCommandIds.interactionDismiss,
      ]),
    );
  });

  test('their keys parse everywhere, and their `when` clauses read only '
      'the context keys there are', () {
    expect(knownContextKeys.containsAll(chatContextKeys), isTrue);
    for (final entry in chatExtraKeybindings) {
      expect(commandCatalog, contains(entry.command), reason: entry.command);
      for (final platform in KeybindingPlatform.values) {
        final item = KeybindingItem(
          entry: entry,
          source: KeybindingSource.defaults,
          platform: platform,
        );
        expect(item.keyError(platform), isNull, reason: '$entry');
        expect(item.when?.error, isNull, reason: '$entry');
        expect(
          item.unknownContextKeys(knownContextKeys),
          isEmpty,
          reason: '$entry',
        );
      }
    }
  });

  test('the keys each platform shows for them', () {
    final service = KeybindingService();
    String? mac(String id) =>
        service.labelFor(id, platform: KeybindingPlatform.mac);
    String? linux(String id) =>
        service.labelFor(id, platform: KeybindingPlatform.linux);
    String? windows(String id) =>
        service.labelFor(id, platform: KeybindingPlatform.windows);

    expect(mac(ChatCommandIds.newChat), '⌘N');
    expect(linux(ChatCommandIds.newChat), 'Ctrl+N');
    expect(windows(ChatCommandIds.newChat), 'Ctrl+N');
    expect(mac(ChatCommandIds.closePane), '⌘W');
    expect(windows(ChatCommandIds.closePane), 'Ctrl+W');
    expect(mac(ChatCommandIds.nextAgent), '⇧⌘]');
    expect(linux(ChatCommandIds.nextAgent), 'Ctrl+PageDown');
    expect(mac(ChatCommandIds.previousAgent), '⇧⌘[');
    expect(windows(ChatCommandIds.previousAgent), 'Ctrl+PageUp');
    expect(mac('${ChatCommandIds.openAgentAtIndex}3'), '⌃3');
    expect(linux('${ChatCommandIds.openAgentAtIndex}3'), 'Alt+3');
    expect(mac('${ChatCommandIds.focusPane}2'), '⌘2');
    expect(windows('${ChatCommandIds.focusPane}2'), 'Ctrl+2');
    expect(mac(ChatCommandIds.focusNextPane), isNull);
    expect(mac(ChatCommandIds.searchAgents), '⇧⌘F');
    expect(linux(ChatCommandIds.searchAgents), 'Ctrl+Shift+F');
    expect(mac(ChatCommandIds.openIde), '⌃⌘I');
    expect(windows(ChatCommandIds.openIde), 'Ctrl+Alt+I');
    expect(linux(ChatCommandIds.renameAgent), 'F2');

    expect(mac(ChatCommandIds.focusInput), '⌘L');
    expect(linux(ChatCommandIds.focusInput), 'Ctrl+L');
    expect(mac(ChatCommandIds.focusList), '⌘↑');
    expect(linux(ChatCommandIds.focusList), 'Ctrl+UpArrow');
    expect(mac(ChatCommandIds.cancel), '⌘Escape');
    expect(linux(ChatCommandIds.cancel), 'Ctrl+Escape');
    expect(windows(ChatCommandIds.cancel), 'Alt+Backspace');
    expect(mac(ChatCommandIds.acceptTool), '⌘Enter');
    expect(linux(ChatCommandIds.skipTool), 'Ctrl+Alt+Enter');

    expect(mac(ChatCommandIds.submit), 'Enter');
    expect(windows(ChatCommandIds.submit), 'Enter');
    expect(mac(ChatCommandIds.cancelEdit), 'Escape');
    expect(mac(ChatCommandIds.showPreviousPrompt), '↑');
    expect(linux(ChatCommandIds.showNextPrompt), 'DownArrow');
    expect(linux(ChatCommandIds.acceptPromptSuggestion), 'Tab');
    expect(mac(ChatCommandIds.openModePicker), '⌘.');
    expect(linux(ChatCommandIds.openModePicker), 'Ctrl+.');
    expect(mac(ChatCommandIds.openModelPicker), '⌥⌘.');
    expect(windows(ChatCommandIds.openModelPicker), 'Ctrl+Alt+.');
    expect(mac(ChatCommandIds.attachContext), '⌘/');
    expect(linux(ChatCommandIds.acceptSelectedSuggestion), 'Tab');
    expect(linux(ChatCommandIds.hideSuggestWidget), 'Escape');
    expect(linux(ChatCommandIds.interactionToggle), 'Space');
  });

  test('where both hold, the menu\'s keys win over the input\'s, and the '
      'input\'s over the list\'s', () {
    final service = KeybindingService()
      ..debugPlatform = KeybindingPlatform.linux;
    final resolver = service.resolver();
    String? commandFor(String key, Map<String, Object> context) {
      final item = resolver
          .itemsWithKeys(KeySequence.parse(key)!)
          .reversed
          .where((item) => resolver.appliesIn(item, (k) => context[k]))
          .firstOrNull;
      return item?.command;
    }

    const input = {
      ChatContextKeys.inChatInput: true,
      ChatContextKeys.cursorAtTop: true,
      ChatContextKeys.cursorAtBottom: true,
      'inputFocus': true,
    };
    expect(commandFor('enter', input), ChatCommandIds.submit);
    expect(commandFor('up', input), ChatCommandIds.showPreviousPrompt);
    const menu = {...input, ChatContextKeys.suggestWidgetVisible: true};
    expect(commandFor('enter', menu), ChatCommandIds.acceptSelectedSuggestion);
    expect(commandFor('up', menu), ChatCommandIds.selectPrevSuggestion);
    expect(commandFor('escape', menu), ChatCommandIds.hideSuggestWidget);
    expect(
      commandFor('escape', {...input, ChatContextKeys.requestInProgress: true}),
      ChatCommandIds.cancel,
    );
    expect(
      commandFor('escape', {
        ...input,
        ChatContextKeys.requestInProgress: true,
        ChatContextKeys.currentlyEditing: true,
      }),
      ChatCommandIds.cancelEdit,
    );
    expect(commandFor('up', {'listFocus': true}), 'list.focusUp');
    expect(
      commandFor('enter', {ChatContextKeys.inInteraction: true}),
      ChatCommandIds.interactionAccept,
    );
    // Only in the chat layout.
    expect(commandFor('ctrl+n', {'chatMode': true}), ChatCommandIds.newChat);
    expect(
      commandFor('ctrl+n', {'ideMode': true}),
      isNot(ChatCommandIds.newChat),
    );
  });

  test('a user\'s keybinding takes a command\'s place', () {
    final service = KeybindingService()
      ..debugPlatform = KeybindingPlatform.linux
      ..userEntries = const [
        KeybindingEntry(
          key: 'ctrl+enter',
          command: ChatCommandIds.submit,
          when: ChatContextKeys.inChatInput,
        ),
        KeybindingEntry(key: 'enter', command: '-${ChatCommandIds.submit}'),
      ];
    expect(service.labelFor(ChatCommandIds.submit), 'Ctrl+Enter');
  });

  test('their titles in Chinese', () {
    final zh = AppLocalizationsZh();
    String title(String id) {
      final info = commandCatalog[id]!;
      return localizedCommandTitleOf(
        zh,
        id,
        info.title,
        category: info.category,
      );
    }

    expect(title(ChatCommandIds.newChat), '聊天: 新建智能体');
    expect(title('${ChatCommandIds.openAgentAtIndex}3'), '聊天: 打开第 3 个智能体');
    expect(title('${ChatCommandIds.focusPane}2'), '聊天: 聚焦第 2 个窗格');
    expect(title(ChatCommandIds.focusPreviousPane), '聊天: 聚焦上一个窗格');
    expect(
      localizedCommandTitleOf(
        englishLocalizations,
        '${ChatCommandIds.openAgentAtIndex}3',
        'Open Agent at Index 3',
        category: 'Chat',
      ),
      'Chat: Open Agent at Index 3',
    );
  });
}
