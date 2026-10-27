// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonOk => '确定';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRename => '重命名';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCut => '剪切';

  @override
  String get commonPaste => '粘贴';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonRedo => '重做';

  @override
  String get commonSelectAll => '全选';

  @override
  String get languageSettingsTitle => '区域和语言';

  @override
  String get languageSettingsDisplayLanguage => '显示语言';

  @override
  String get languageSettingsDescription => 'BaoCode 的菜单、视图和消息所用的语言。更改立即生效。';

  @override
  String languageSettingsFollowSystemCurrent(String language) {
    return '跟随系统（$language）';
  }

  @override
  String languageSettingsDisplayLanguageLabel(String name) {
    return '显示语言: $name';
  }

  @override
  String get cmdCategoryFile => '文件';

  @override
  String get cmdCategoryView => '视图';

  @override
  String get cmdCategoryTerminal => '终端';

  @override
  String get cmdCategoryGo => '转到';

  @override
  String get cmdCategoryPreferences => '首选项';

  @override
  String get cmdCategoryDeveloper => '开发人员';

  @override
  String get cmdCategoryEditor => '编辑器';

  @override
  String get cmdCategoryHelp => '帮助';

  @override
  String get cmdCategoryList => '列表';

  @override
  String get composerSetMode => '设置模式';

  @override
  String get composerPickModel => '选择模型';

  @override
  String get interactionHintChoose => '1-9 选择';

  @override
  String interactionHintContinue(String keybinding) {
    return '$keybinding 继续';
  }

  @override
  String interactionHintBack(String keybinding) {
    return '$keybinding 上一步';
  }

  @override
  String interactionHintSkip(String keybinding) {
    return '$keybinding 跳过';
  }

  @override
  String get cmdCategoryChat => '聊天';

  @override
  String get cmdCategoryTasks => '任务';

  @override
  String get cmdChatNewAgent => '新对话';

  @override
  String get cmdChatClosePane => '关闭窗格';

  @override
  String get cmdChatCloseTab => '关闭对话';

  @override
  String get cmdChatNextAgent => '打开下一个智能体';

  @override
  String get cmdChatPreviousAgent => '打开上一个智能体';

  @override
  String cmdChatOpenAgentAtIndex(int index) {
    return '打开第 $index 个智能体';
  }

  @override
  String cmdChatFocusPane(int index) {
    return '聚焦第 $index 个窗格';
  }

  @override
  String get cmdChatFocusNextPane => '聚焦下一个窗格';

  @override
  String get cmdChatFocusPreviousPane => '聚焦上一个窗格';

  @override
  String get cmdChatSearch => '搜索';

  @override
  String get cmdChatSearchAgents => '搜索智能体';

  @override
  String get cmdChatOpenIde => '在 Fast Ide 中打开';

  @override
  String get cmdChatFocusInput => '聚焦聊天输入';

  @override
  String get cmdChatFocusList => '聚焦聊天列表';

  @override
  String get cmdChatFind => '在对话中查找';

  @override
  String get cmdChatCancel => '取消';

  @override
  String get cmdChatAcceptTool => '接受';

  @override
  String get cmdChatSkipTool => '跳过';

  @override
  String get cmdChatToggleContextPanel => '切换上下文面板';

  @override
  String get cmdChatRenameAgent => '重命名智能体';

  @override
  String get cmdChatCloseSubagent => '从子智能体返回';

  @override
  String get cmdChatSubmit => '发送';

  @override
  String get cmdChatCancelEdit => '取消编辑';

  @override
  String get cmdChatShowPreviousPrompt => '显示上一条提示';

  @override
  String get cmdChatShowNextPrompt => '显示下一条提示';

  @override
  String get cmdChatAcceptPromptSuggestion => '接受建议的提示';

  @override
  String get cmdChatOpenModePicker => '打开模式选择器';

  @override
  String get cmdChatNextMode => '切换到下一个模式';

  @override
  String get cmdChatOpenModelPicker => '打开模型选择器';

  @override
  String get cmdChatAttachContext => '添加上下文…';

  @override
  String get cmdChatPasteRaw => '粘贴为纯文本';

  @override
  String get cmdChatSelectNextSuggestion => '选择下一个建议';

  @override
  String get cmdChatSelectPrevSuggestion => '选择上一个建议';

  @override
  String get cmdChatAcceptSelectedSuggestion => '接受所选建议';

  @override
  String get cmdChatHideSuggestWidget => '隐藏建议';

  @override
  String get cmdChatInteractionFocusNext => '聚焦下一个选项';

  @override
  String get cmdChatInteractionFocusPrevious => '聚焦上一个选项';

  @override
  String get cmdChatInteractionBack => '返回上一题';

  @override
  String get cmdChatInteractionToggle => '切换选项';

  @override
  String get cmdChatInteractionAccept => '继续';

  @override
  String get cmdChatInteractionDismiss => '忽略';

  @override
  String get cmdOpenFilePreserveFocus => '打开文件并保留焦点';

  @override
  String ideSearchProject(String name) {
    return '搜索 $name';
  }

  @override
  String get idePanelProblems => '问题';

  @override
  String get idePanelReferences => '引用';

  @override
  String get idePanelTerminal => '终端';

  @override
  String get cmdScmFocus => '聚焦到“更改”视图';

  @override
  String get cmdScmAcceptInput => '接受输入';

  @override
  String get cmdScmClearValidation => '清除验证';

  @override
  String get cmdGitCheckout => '签出到...';

  @override
  String get cmdScmClearInput => '清除输入';

  @override
  String get cmdCategoryGit => 'Git';

  @override
  String get cmdProblemsFocus => '聚焦问题 (错误、警告、信息)';

  @override
  String get cmdProblemsOpen => '打开';

  @override
  String get cmdProblemsCopyMessage => '复制消息';

  @override
  String get cmdReferencesNext => '转到下一个引用';

  @override
  String get cmdReferencesPrevious => '转到上一个引用';

  @override
  String get cmdCategoryReferences => '引用';

  @override
  String get cmdTerminalFocusFind => '聚焦查找';

  @override
  String get cmdTerminalHideFind => '隐藏查找';

  @override
  String get cmdTerminalToggleFindRegex => '切换使用正则表达式查找';

  @override
  String get cmdTerminalToggleFindWholeWord => '切换使用全字匹配查找';

  @override
  String get cmdTerminalToggleFindCaseSensitive => '切换使用区分大小写查找';

  @override
  String get cmdTerminalSearchWorkspace => '搜索工作区';

  @override
  String get cmdTerminalCopySelection => '复制所选内容';

  @override
  String get cmdTerminalCopyAndClearSelection => '复制并清除所选内容';

  @override
  String get cmdTerminalPaste => '粘贴到活动终端中';

  @override
  String get cmdTerminalPasteSelection => '将所选内容粘贴到活动终端中';

  @override
  String get cmdTerminalClearSelection => '清除选定内容';

  @override
  String get cmdTerminalScrollDown => '向下滚动(行)';

  @override
  String get cmdTerminalScrollDownPage => '向下滚动(页)';

  @override
  String get cmdTerminalScrollToBottom => '滚动到底部';

  @override
  String get cmdTerminalScrollUp => '向上滚动(行)';

  @override
  String get cmdTerminalScrollUpPage => '向上滚动(页)';

  @override
  String get cmdTerminalScrollToTop => '滚动到顶部';

  @override
  String get cmdTerminalSendSequence => '发送序列';

  @override
  String get cmdTerminalKillAll => '终止所有终端';

  @override
  String get cmdFindInFiles => '在文件中查找';

  @override
  String get cmdReplaceInFiles => '在文件中替换';

  @override
  String get cmdFocusNextSearchResult => '聚焦下一搜索结果';

  @override
  String get cmdFocusPreviousSearchResult => '聚焦上一搜索结果';

  @override
  String get cmdToggleSearchCaseSensitive => '切换区分大小写';

  @override
  String get cmdToggleSearchWholeWord => '切换全字匹配';

  @override
  String get cmdToggleSearchRegex => '切换正则表达式';

  @override
  String get cmdToggleSearchPreserveCase => '切换保留大小写';

  @override
  String get cmdSearchFocusNextInput => '聚焦下一个输入';

  @override
  String get cmdSearchFocusPreviousInput => '聚焦上一个输入';

  @override
  String get cmdFocusSearchFromResults => '从结果中聚焦搜索';

  @override
  String get cmdSearchFocusList => '聚焦列表';

  @override
  String get cmdSearchOpenMatch => '打开匹配项';

  @override
  String get cmdCloseReplaceWidget => '关闭替换小组件';

  @override
  String get cmdCancelSearch => '取消搜索';

  @override
  String get cmdToggleQueryDetails => '切换查询详细信息';

  @override
  String get cmdCategoryQuickInput => '快速输入';

  @override
  String get wbQuickEditors => '键入要打开的编辑器名称。';

  @override
  String get quickOpenNoMatchingEditors => '没有匹配的编辑器';

  @override
  String get cmdQuickInputFocusNext => '聚焦下一项';

  @override
  String get cmdQuickInputFocusPrevious => '聚焦上一项';

  @override
  String get cmdQuickInputFocusNextPage => '聚焦下一页';

  @override
  String get cmdQuickInputFocusPreviousPage => '聚焦上一页';

  @override
  String get cmdQuickInputAccept => '接受';

  @override
  String get cmdQuickInputAcceptInBackground => '在后台接受';

  @override
  String get cmdQuickInputHide => '隐藏';

  @override
  String get cmdCloseQuickOpen => '关闭快速打开';

  @override
  String get cmdAcceptSelectedQuickOpenItem => '接受所选的快速打开项';

  @override
  String get cmdFocusQuickOpen => '聚焦到快速打开';

  @override
  String get cmdQuickOpenSelectNext => '在快速打开中选择下一个';

  @override
  String get cmdQuickOpenSelectPrevious => '在快速打开中选择上一个';

  @override
  String get cmdQuickOpenNavigateNext => '在快速打开中导航到下一个';

  @override
  String get cmdQuickOpenNavigatePrevious => '在快速打开中导航到上一个';

  @override
  String get cmdQuickOpenNavigateNextInFilePicker => '在文件选取器中导航到下一个';

  @override
  String get cmdQuickOpenNavigatePreviousInFilePicker => '在文件选取器中导航到上一个';

  @override
  String get cmdQuickOpenNavigateNextInEditorPicker => '在编辑器选取器中导航到下一个';

  @override
  String get cmdQuickOpenNavigatePreviousInEditorPicker => '在编辑器选取器中导航到上一个';

  @override
  String get cmdQuickOpenPreviousEditor => '快速打开上一个编辑器';

  @override
  String get cmdShowAllEditors => '按外观显示所有编辑器';

  @override
  String get cmdShowEditorsInActiveGroup => '按最近使用显示活动组中的编辑器';

  @override
  String get cmdShowAllEditorsByMostRecentlyUsed => '按最近使用显示所有编辑器';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditor => '快速打开上一个最近使用过的编辑器';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditor => '快速打开最近最少使用的编辑器';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditorInGroup =>
      '快速打开组中上一个最近使用过的编辑器';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditorInGroup => '快速打开组中最近最少使用的编辑器';

  @override
  String get cmdOpenPreviousEditorFromHistory => '从历史记录中快速打开上一个编辑器';

  @override
  String get cmdOpenNextRecentlyUsedEditor => '打开下一个最近使用的编辑器';

  @override
  String get cmdOpenPreviousRecentlyUsedEditor => '打开上一个最近使用的编辑器';

  @override
  String get cmdOpenNextRecentlyUsedEditorInGroup => '打开组中下一个最近使用的编辑器';

  @override
  String get cmdOpenPreviousRecentlyUsedEditorInGroup => '打开组中上一个最近使用的编辑器';

  @override
  String get cmdNextEditorInGroup => '打开组中的下一个编辑器';

  @override
  String get cmdPreviousEditorInGroup => '打开组中上一个编辑器';

  @override
  String get cmdFirstEditorInGroup => '打开组中的第一个编辑器';

  @override
  String get cmdCloseEditorsInGroup => '关闭组中的所有编辑器';

  @override
  String get cmdCloseEditorsToTheLeft => '关闭组中左侧的编辑器';

  @override
  String get cmdNavigateToLastEditLocation => '转到上一编辑位置';

  @override
  String get cmdNavigateLast => '转到上一个';

  @override
  String get cmdOpenUserSettings => '打开用户设置';

  @override
  String get cmdToggleMaximizedPanel => '切换最大化面板';

  @override
  String get cmdFocusPanel => '聚焦到面板中';

  @override
  String get cmdClosePanel => '隐藏面板';

  @override
  String get cmdFocusSideBar => '聚焦到主侧边栏';

  @override
  String get cmdCloseSidebar => '隐藏主侧边栏';

  @override
  String get cmdCloseChat => '隐藏聊天';

  @override
  String get cmdFocusActiveEditorGroup => '聚焦到活动编辑器组';

  @override
  String get cmdFocusFirstEditorGroup => '聚焦于第一个编辑器组';

  @override
  String get cmdFocusLastEditorGroup => '聚焦到最后一个编辑器组';

  @override
  String get cmdListFocusDown => '焦点下移';

  @override
  String get cmdListFocusUp => '焦点上移';

  @override
  String get cmdListFocusPageDown => '焦点下移一页';

  @override
  String get cmdListFocusPageUp => '焦点上移一页';

  @override
  String get cmdListFocusFirst => '聚焦第一项';

  @override
  String get cmdListFocusLast => '聚焦最后一项';

  @override
  String get cmdListExpand => '展开';

  @override
  String get cmdListCollapse => '折叠';

  @override
  String get cmdListSelect => '选择';

  @override
  String get cmdListToggleExpand => '切换展开';

  @override
  String get cmdListExpandSelectionDown => '向下扩展选择';

  @override
  String get cmdListExpandSelectionUp => '向上扩展选择';

  @override
  String get cmdListSelectAll => '全选';

  @override
  String get cmdListClear => '清除选择';

  @override
  String get cmdEditorCursorLeft => '光标左移';

  @override
  String get cmdEditorCursorLeftSelect => '光标左移并选择';

  @override
  String get cmdEditorCursorRight => '光标右移';

  @override
  String get cmdEditorCursorRightSelect => '光标右移并选择';

  @override
  String get cmdEditorCursorUp => '光标上移';

  @override
  String get cmdEditorCursorUpSelect => '光标上移并选择';

  @override
  String get cmdEditorCursorDown => '光标下移';

  @override
  String get cmdEditorCursorDownSelect => '光标下移并选择';

  @override
  String get cmdEditorCursorPageUp => '光标上移一页';

  @override
  String get cmdEditorCursorPageUpSelect => '光标上移一页并选择';

  @override
  String get cmdEditorCursorPageDown => '光标下移一页';

  @override
  String get cmdEditorCursorPageDownSelect => '光标下移一页并选择';

  @override
  String get cmdEditorCursorHome => '光标移到行首';

  @override
  String get cmdEditorCursorHomeSelect => '光标移到行首并选择';

  @override
  String get cmdEditorCursorEnd => '光标移到行尾';

  @override
  String get cmdEditorCursorEndSelect => '光标移到行尾并选择';

  @override
  String get cmdEditorCursorLineStart => '光标移到行的起点';

  @override
  String get cmdEditorCursorLineStartSelect => '光标移到行的起点并选择';

  @override
  String get cmdEditorCursorLineEnd => '光标移到行的终点';

  @override
  String get cmdEditorCursorLineEndSelect => '光标移到行的终点并选择';

  @override
  String get cmdEditorCursorTop => '光标移到文件开头';

  @override
  String get cmdEditorCursorTopSelect => '光标移到文件开头并选择';

  @override
  String get cmdEditorCursorBottom => '光标移到文件末尾';

  @override
  String get cmdEditorCursorBottomSelect => '光标移到文件末尾并选择';

  @override
  String get cmdEditorCursorColumnSelectLeft => '列选择左移';

  @override
  String get cmdEditorCursorColumnSelectRight => '列选择右移';

  @override
  String get cmdEditorCursorColumnSelectUp => '列选择上移';

  @override
  String get cmdEditorCursorColumnSelectDown => '列选择下移';

  @override
  String get cmdEditorCursorColumnSelectPageUp => '列选择上移一页';

  @override
  String get cmdEditorCursorColumnSelectPageDown => '列选择下移一页';

  @override
  String get cmdEditorScrollLineUp => '向上滚动一行';

  @override
  String get cmdEditorScrollLineDown => '向下滚动一行';

  @override
  String get cmdEditorScrollPageUp => '向上滚动一页';

  @override
  String get cmdEditorScrollPageDown => '向下滚动一页';

  @override
  String get cmdEditorCancelSelection => '取消选择';

  @override
  String get cmdEditorLineBreakInsert => '插入换行符';

  @override
  String get cmdEditorTab => 'Tab 键';

  @override
  String get cmdEditorOutdent => '减少缩进';

  @override
  String get cmdEditorDeleteLeft => '向左删除';

  @override
  String get cmdEditorDeleteRight => '向右删除';

  @override
  String get cmdEditorCursorWordLeft => '光标左移一个单词';

  @override
  String get cmdEditorCursorWordLeftSelect => '光标左移一个单词并选择';

  @override
  String get cmdEditorCursorWordStartLeft => '光标左移到单词开头';

  @override
  String get cmdEditorCursorWordStartLeftSelect => '光标左移到单词开头并选择';

  @override
  String get cmdEditorCursorWordEndLeft => '光标左移到单词末尾';

  @override
  String get cmdEditorCursorWordEndLeftSelect => '光标左移到单词末尾并选择';

  @override
  String get cmdEditorCursorWordRight => '光标右移一个单词';

  @override
  String get cmdEditorCursorWordRightSelect => '光标右移一个单词并选择';

  @override
  String get cmdEditorCursorWordStartRight => '光标右移到单词开头';

  @override
  String get cmdEditorCursorWordStartRightSelect => '光标右移到单词开头并选择';

  @override
  String get cmdEditorCursorWordEndRight => '光标右移到单词末尾';

  @override
  String get cmdEditorCursorWordEndRightSelect => '光标右移到单词末尾并选择';

  @override
  String get cmdEditorCursorWordPartLeft => '光标左移一个单词部分';

  @override
  String get cmdEditorCursorWordPartLeftSelect => '光标左移一个单词部分并选择';

  @override
  String get cmdEditorCursorWordPartStartLeft => '光标左移到单词部分开头';

  @override
  String get cmdEditorCursorWordPartStartLeftSelect => '光标左移到单词部分开头并选择';

  @override
  String get cmdEditorCursorWordPartRight => '光标右移一个单词部分';

  @override
  String get cmdEditorCursorWordPartRightSelect => '光标右移一个单词部分并选择';

  @override
  String get cmdEditorDeleteWordLeft => '向左删除单词';

  @override
  String get cmdEditorDeleteWordRight => '向右删除单词';

  @override
  String get cmdEditorDeleteWordStartLeft => '向左删除到单词开头';

  @override
  String get cmdEditorDeleteWordEndLeft => '向左删除到单词末尾';

  @override
  String get cmdEditorDeleteWordStartRight => '向右删除到单词开头';

  @override
  String get cmdEditorDeleteWordEndRight => '向右删除到单词末尾';

  @override
  String get cmdEditorDeleteWordPartLeft => '向左删除单词部分';

  @override
  String get cmdEditorDeleteWordPartRight => '向右删除单词部分';

  @override
  String get cmdEditorSmartSelectGrow => '展开选择';

  @override
  String get cmdEditorFormat => '格式化选定内容或文档';

  @override
  String get cmdEditorJumpToNextSnippetPlaceholder => '转到下一个代码片段占位符';

  @override
  String get cmdEditorJumpToPrevSnippetPlaceholder => '转到上一个代码片段占位符';

  @override
  String get cmdEditorLeaveSnippet => '退出代码片段';

  @override
  String get cmdEditorLeaveEditorMessage => '关闭消息';

  @override
  String get cmdEditorNextMatchFindAction => '查找下一个';

  @override
  String get cmdEditorPreviousMatchFindAction => '查找上一个';

  @override
  String get cmdEditorNextSelectionMatchFindAction => '查找下一个选择';

  @override
  String get cmdEditorPreviousSelectionMatchFindAction => '查找上一个选择';

  @override
  String get cmdEditorFindWithSelection => '查找选定内容';

  @override
  String get cmdEditorCloseFindWidget => '关闭查找小组件';

  @override
  String get cmdEditorToggleFindCaseSensitive => '切换区分大小写';

  @override
  String get cmdEditorToggleFindWholeWord => '切换全字匹配';

  @override
  String get cmdEditorToggleFindRegex => '切换使用正则表达式';

  @override
  String get cmdEditorReplaceOne => '替换一处';

  @override
  String get cmdEditorReplaceAll => '全部替换';

  @override
  String get cmdEditorSelectAllMatches => '选择所有匹配项';

  @override
  String get cmdEditorMarkerNext => '转到下一个问题 (错误、警告、信息)';

  @override
  String get cmdEditorMarkerPrev => '转到上一个问题 (错误、警告、信息)';

  @override
  String get cmdEditorShowContextMenu => '显示编辑器上下文菜单';

  @override
  String get cmdEditorAcceptSelectedSuggestion => '接受所选建议';

  @override
  String get cmdEditorAcceptAlternativeSelectedSuggestion => '接受所选建议 (替代)';

  @override
  String get cmdEditorHideSuggestWidget => '隐藏建议小组件';

  @override
  String get cmdEditorSelectNextSuggestion => '选择下一个建议';

  @override
  String get cmdEditorSelectPrevSuggestion => '选择上一个建议';

  @override
  String get cmdEditorSelectNextPageSuggestion => '选择下一页建议';

  @override
  String get cmdEditorSelectPrevPageSuggestion => '选择上一页建议';

  @override
  String get cmdEditorToggleSuggestionDetails => '切换建议详细信息';

  @override
  String get cmdEditorCloseParameterHints => '关闭参数提示';

  @override
  String get cmdEditorShowPrevParameterHint => '显示上一个参数提示';

  @override
  String get cmdEditorShowNextParameterHint => '显示下一个参数提示';

  @override
  String get cmdEditorAcceptRenameInput => '接受重命名';

  @override
  String get cmdEditorCancelRenameInput => '取消重命名';

  @override
  String get cmdEditorJoinLines => '合并行';

  @override
  String get cmdEditorDuplicateSelection => '重复选择';

  @override
  String get cmdEditorInsertCursorAtEndOfEachLineSelected => '在行尾添加光标';

  @override
  String get cmdEditorSmartSelectExpand => '展开选择';

  @override
  String get cmdEditorSmartSelectShrink => '收起选择';

  @override
  String get cmdEditorWordHighlightNext => '转到下一个突出显示的符号';

  @override
  String get cmdEditorWordHighlightPrev => '转到上一个突出显示的符号';

  @override
  String get cmdEditorFold => '折叠';

  @override
  String get cmdEditorUnfold => '展开';

  @override
  String get cmdEditorToggleFold => '切换折叠';

  @override
  String get cmdEditorFoldRecursively => '以递归方式折叠';

  @override
  String get cmdEditorUnfoldRecursively => '以递归方式展开';

  @override
  String get cmdEditorToggleFoldRecursively => '以递归方式切换折叠';

  @override
  String get cmdEditorFoldAll => '全部折叠';

  @override
  String get cmdEditorUnfoldAll => '全部展开';

  @override
  String get cmdEditorFoldAllBlockComments => '折叠所有块注释';

  @override
  String get cmdEditorFoldAllMarkerRegions => '折叠所有区域';

  @override
  String get cmdEditorUnfoldAllMarkerRegions => '展开所有区域';

  @override
  String get cmdEditorFoldAllExcept => '折叠除所选区域之外的所有区域';

  @override
  String get cmdEditorUnfoldAllExcept => '展开除所选区域之外的所有区域';

  @override
  String get cmdEditorGoToDeclaration => '转到声明';

  @override
  String get cmdEditorReferenceSearchTrigger => '速览引用';

  @override
  String cmdEditorFoldLevel(int level) {
    return '折叠级别 $level';
  }

  @override
  String get cmdShowAllCommands => '显示所有命令';

  @override
  String get cmdQuickOpen => '转到文件…';

  @override
  String get cmdGotoLine => '转到行/列…';

  @override
  String get cmdChangeEol => '更改行尾序列';

  @override
  String get cmdFind => '查找';

  @override
  String get cmdReplace => '替换';

  @override
  String get cmdSave => '保存';

  @override
  String get cmdSaveAll => '全部保存';

  @override
  String get cmdToggleAutoSave => '切换自动保存';

  @override
  String get cmdCloseEditor => '关闭编辑器';

  @override
  String get cmdCloseOtherEditors => '关闭其他编辑器';

  @override
  String get cmdCloseEditorsToTheRight => '关闭右侧编辑器';

  @override
  String get cmdCloseSavedEditors => '关闭已保存的编辑器';

  @override
  String get cmdCloseAllEditors => '关闭所有编辑器';

  @override
  String get cmdReopenClosedEditor => '重新打开已关闭的编辑器';

  @override
  String get cmdNextEditor => '打开下一个编辑器';

  @override
  String get cmdPreviousEditor => '打开上一个编辑器';

  @override
  String cmdOpenEditorAtIndex(int index) {
    return '打开第 $index 个编辑器';
  }

  @override
  String get cmdToggleSidebar => '切换主侧边栏可见性';

  @override
  String get cmdToggleChat => '切换聊天';

  @override
  String get cmdToggleFullScreen => '切换全屏';

  @override
  String get cmdToggleWordWrap => '切换自动换行';

  @override
  String get menuWordWrap => '自动换行';

  @override
  String get cmdTogglePanel => '切换面板可见性';

  @override
  String get cmdToggleTerminal => '切换终端';

  @override
  String get cmdNewTerminal => '新建终端';

  @override
  String get cmdKillTerminal => '终止活动终端实例';

  @override
  String get cmdRenameTerminal => '重命名...';

  @override
  String get cmdFocusNextTerminal => '聚焦下一个终端组';

  @override
  String get cmdFocusPreviousTerminal => '聚焦上一个终端组';

  @override
  String get cmdFocusTerminal => '聚焦到终端';

  @override
  String get cmdRunTask => '运行任务';

  @override
  String get cmdRunBuildTask => '运行生成任务';

  @override
  String get cmdRunTestTask => '运行测试任务';

  @override
  String get cmdRerunTask => '重新运行上一个任务';

  @override
  String get cmdRestartTask => '重启正在运行的任务';

  @override
  String get cmdTerminateTask => '终止任务';

  @override
  String get cmdShowTaskLog => '显示任务日志';

  @override
  String get cmdConfigureTask => '配置任务';

  @override
  String get cmdShowExplorer => '显示资源管理器';

  @override
  String get cmdShowSearch => '显示搜索';

  @override
  String get cmdShowSourceControl => '显示源代码管理';

  @override
  String get cmdShowExtensions => '显示扩展';

  @override
  String get cmdRevealActiveFileInExplorer => '在资源管理器视图中显示活动文件';

  @override
  String get cmdRefreshExplorer => '刷新资源管理器';

  @override
  String get cmdCollapseExplorerFolders => '在资源管理器中折叠文件夹';

  @override
  String get cmdCopyPathOfActiveFile => '复制活动文件的路径';

  @override
  String get cmdCopyRelativePathOfActiveFile => '复制活动文件的相对路径';

  @override
  String get cmdGotoSymbol => '转到编辑器中的符号...';

  @override
  String get cmdToggleProblems => '切换问题';

  @override
  String get cmdShowOutline => '显示大纲';

  @override
  String get cmdNextProblemInFiles => '转到文件中的下一个问题 (错误、警告、信息)';

  @override
  String get cmdPreviousProblemInFiles => '转到文件中的上一个问题 (错误、警告、信息)';

  @override
  String get cmdGoBack => '返回';

  @override
  String get cmdGoForward => '前进';

  @override
  String get cmdColorTheme => '颜色主题';

  @override
  String get cmdTurnOnFormatOnSave => '开启保存时格式化';

  @override
  String get cmdTurnOffFormatOnSave => '关闭保存时格式化';

  @override
  String get cmdRetryLanguageServices => '重试语言服务';

  @override
  String get cmdBackToChat => '返回聊天';

  @override
  String get cmdOpenSettings => '打开设置';

  @override
  String get cmdOpenKeyboardShortcuts => '打开键盘快捷方式';

  @override
  String get cmdOpenLspSettings => '打开语言服务器设置 (JSON)';

  @override
  String get cmdJumpToBracket => '转到括号';

  @override
  String get cmdUndo => '撤销';

  @override
  String get cmdRedo => '重做';

  @override
  String get cmdCut => '剪切';

  @override
  String get cmdCopy => '复制';

  @override
  String get cmdPaste => '粘贴';

  @override
  String get cmdSelectAll => '全选';

  @override
  String get cmdToggleLineComment => '切换行注释';

  @override
  String get cmdToggleBlockComment => '切换块注释';

  @override
  String get cmdMoveLineUp => '向上移动行';

  @override
  String get cmdMoveLineDown => '向下移动行';

  @override
  String get cmdCopyLineUp => '向上复制行';

  @override
  String get cmdCopyLineDown => '向下复制行';

  @override
  String get cmdDeleteLine => '删除行';

  @override
  String get cmdInsertLineBelow => '在下面插入行';

  @override
  String get cmdInsertLineAbove => '在上面插入行';

  @override
  String get cmdIndentLine => '行缩进';

  @override
  String get cmdOutdentLine => '行减少缩进';

  @override
  String get cmdExpandLineSelection => '展开行选择';

  @override
  String get cmdDeleteAllLeft => '删除左侧所有内容';

  @override
  String get cmdDeleteAllRight => '删除右侧所有内容';

  @override
  String get cmdAddSelectionToNextFindMatch => '将选择添加到下一个查找匹配项';

  @override
  String get cmdMoveSelectionToNextFindMatch => '将上次选择移动到下一个查找匹配项';

  @override
  String get cmdSelectHighlights => '选择所有找到的查找匹配项';

  @override
  String get cmdChangeAll => '更改所有匹配项';

  @override
  String get cmdInsertCursorAbove => '在上面添加光标';

  @override
  String get cmdInsertCursorBelow => '在下面添加光标';

  @override
  String get cmdRemoveSecondaryCursors => '删除辅助光标';

  @override
  String get cmdCursorUndo => '光标撤销';

  @override
  String get cmdTransformToUppercase => '转换为大写';

  @override
  String get cmdTransformToLowercase => '转换为小写';

  @override
  String get cmdDetectIndentation => '从内容中检测缩进方式';

  @override
  String get cmdGoToDefinition => '转到定义';

  @override
  String get cmdGoToTypeDefinition => '转到类型定义';

  @override
  String get cmdGoToImplementations => '转到实现';

  @override
  String get cmdGoToReferences => '转到引用';

  @override
  String get cmdRenameSymbol => '重命名符号';

  @override
  String get cmdFormatDocument => '格式化文档';

  @override
  String get cmdFormatSelection => '格式化选定内容';

  @override
  String get cmdQuickFix => '快速修复...';

  @override
  String get cmdRefactor => '重构...';

  @override
  String get cmdSourceAction => '源代码操作...';

  @override
  String get cmdTriggerSuggest => '触发建议';

  @override
  String get cmdTriggerParameterHints => '触发参数提示';

  @override
  String get cmdShowHover => '显示或聚焦悬停';

  @override
  String get quickOpenRecentlyOpened => '最近打开';

  @override
  String get quickOpenFiles => '文件';

  @override
  String get quickOpenLoadingFiles => '正在加载文件…';

  @override
  String get quickOpenSearchingFiles => '正在搜索文件…';

  @override
  String get quickOpenNoFiles => '此项目中没有文件';

  @override
  String get quickOpenNoMatchingResults => '没有匹配的结果';

  @override
  String get quickOpenRecentlyUsed => '最近使用';

  @override
  String get quickOpenOtherCommands => '其他命令';

  @override
  String get quickOpenNoMatchingCommands => '没有匹配的命令';

  @override
  String get gotoLineNoEditor => '请先打开文本编辑器，然后再转到行。';

  @override
  String gotoLineCurrent(int line, int character, int lineCount) {
    return '当前行: $line，字符: $character。键入要导航到的行号 (介于 1 和 $lineCount 之间)。';
  }

  @override
  String gotoLineLine(int line) {
    return '转到第 $line 行。';
  }

  @override
  String gotoLineLineAndCharacter(int line, int character) {
    return '转到第 $line 行第 $character 个字符。';
  }

  @override
  String get menuFile => '文件';

  @override
  String get menuEdit => '编辑';

  @override
  String get menuView => '查看';

  @override
  String get menuHelp => '帮助';

  @override
  String get menuApplication => '应用程序菜单';

  @override
  String get menuOpenFolder => '打开文件夹…';

  @override
  String get menuCloseWindow => '关闭窗口';

  @override
  String get menuAutoSave => '自动保存';

  @override
  String get menuBackToChat => '返回聊天';

  @override
  String get menuShowSidebar => '显示侧边栏';

  @override
  String get menuHideSidebar => '隐藏侧边栏';

  @override
  String get menuKeepOnTop => '窗口置顶';

  @override
  String get menuContextPanel => '上下文面板';

  @override
  String get menuAboutBaoCode => '关于 BaoCode';

  @override
  String get windowShowSidebar => '显示侧边栏';

  @override
  String get windowHideSidebar => '隐藏侧边栏';

  @override
  String get chatTerminalHide => '隐藏终端';

  @override
  String get cmdToggleSidePanel => '切换侧栏';

  @override
  String get cmdToggleSidePanelPosition => '切换侧栏位置';

  @override
  String get cmdSidePanelChanges => '显示智能体变更';

  @override
  String get cmdSidePanelFiles => '显示智能体文件';

  @override
  String get cmdSidePanelTerminal => '显示智能体终端';

  @override
  String get cmdSidePanelCloseTab => '关闭侧边面板标签页';

  @override
  String get sidePanelFiles => '文件';

  @override
  String get sidePanelTerminal => '终端';

  @override
  String get sidePanelBrowser => '浏览器';

  @override
  String get browserNotConnected =>
      '没有连接浏览器。在 Chrome（或 Edge、Brave、Arc）中添加 BaoCode 扩展后，agent 就能使用你共享给它的标签页。';

  @override
  String get browserNoSharedTab =>
      '还没有共享的标签页。让 agent 打开网页，或在浏览器工具栏点 BaoCode 按钮共享当前标签页。';

  @override
  String get browserOtherApp => '另一个 BaoCode 已连接浏览器。';

  @override
  String get browserSharedTabs => '共享的标签页';

  @override
  String get browserReload => '重新加载';

  @override
  String get browserShowInBrowser => '在浏览器中显示';

  @override
  String get browserDetached => '浏览器已停止让 BaoCode 查看这个标签页。';

  @override
  String get browserReconnect => '重新连接';

  @override
  String get browserShowInPanel => '在侧边栏查看';

  @override
  String get browserWatchTitle => '正在看你在浏览器里操作';

  @override
  String get browserWatchHint =>
      '请在浏览器的 BaoCode 标签页里操作。完成后点这里的“完成”，或点浏览器工具栏上的 BaoCode 按钮。';

  @override
  String browserWatchSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已记录 $count 步',
      zero: '还没有记录',
    );
    return '$_temp0';
  }

  @override
  String get browserWatchCancel => '取消';

  @override
  String get browserWatchDone => '完成';

  @override
  String browserWatchedStep(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'click': '点击',
      'input': '填写',
      'key': '按下',
      'submit': '提交',
      'navigate': '前往',
      'closed': '关闭了标签页',
      'other': '操作',
    });
    return '$_temp0';
  }

  @override
  String browserTraceReveal(String app) {
    return '在$app中显示 trace 文件（拖进 DevTools 的性能面板可以细看）';
  }

  @override
  String browserStepDone(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': '已列出标签页',
      'open': '已打开',
      'navigate': '已前往',
      'back': '已后退',
      'forward': '已前进',
      'reload': '已重新加载',
      'snapshot': '已读取页面',
      'screenshot': '已截图',
      'click': '已点击',
      'type': '已输入',
      'press': '已按下',
      'scroll': '已滚动',
      'evaluate': '已运行',
      'close': '已关闭标签页',
      'console': '已查看控制台',
      'network': '已查看请求',
      'request': '已查看请求',
      'performance': '已分析性能',
      'recordStart': '已开始录制性能',
      'recordStop': '已分析性能',
      'emulate': '已模拟',
      'watch': '已看完你的操作',
      'act': '已执行',
      'inspect': '已检查元素',
      'sources': '已查看源码',
      'breakpoints': '已设置断点',
      'debugger': '已调试',
      'intercept': '已拦截请求',
      'storage': '已查看站点数据',
      'dialog': '已应答弹窗',
      'coverage': '已统计覆盖率',
      'memory': '已分析内存',
      'history': '已查看调试记录',
      'other': '已使用浏览器',
    });
    return '$_temp0';
  }

  @override
  String browserStepRunning(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': '正在列出标签页',
      'open': '正在打开',
      'navigate': '正在前往',
      'back': '正在后退',
      'forward': '正在前进',
      'reload': '正在重新加载',
      'snapshot': '正在读取页面',
      'screenshot': '正在截图',
      'click': '正在点击',
      'type': '正在输入',
      'press': '正在按下',
      'scroll': '正在滚动',
      'evaluate': '正在运行',
      'close': '正在关闭标签页',
      'console': '正在查看控制台',
      'network': '正在查看请求',
      'request': '正在查看请求',
      'performance': '正在分析性能',
      'recordStart': '正在开始录制性能',
      'recordStop': '正在分析性能',
      'emulate': '正在模拟',
      'watch': '正在看你操作',
      'act': '正在执行',
      'inspect': '正在检查元素',
      'sources': '正在查看源码',
      'breakpoints': '正在设置断点',
      'debugger': '正在调试',
      'intercept': '正在拦截请求',
      'storage': '正在查看站点数据',
      'dialog': '正在应答弹窗',
      'coverage': '正在统计覆盖率',
      'memory': '正在分析内存',
      'history': '正在查看调试记录',
      'other': '正在使用浏览器',
    });
    return '$_temp0';
  }

  @override
  String get sidePanelPlan => '计划';

  @override
  String get sidePanelOpenInFiles => '在文件中打开';

  @override
  String get sidePanelNoTerminals => '没有后台命令';

  @override
  String get sidePanelTaskCompleted => '已完成';

  @override
  String get sidePanelTaskFailed => '失败';

  @override
  String get sidePanelWaitingOutput => '等待输出';

  @override
  String get sidePanelOutputUnavailable => '无法读取输出';

  @override
  String get sidePanelShow => '显示侧栏';

  @override
  String get sidePanelHide => '隐藏侧栏';

  @override
  String get sidePanelMoveLeft => '移到对话左侧';

  @override
  String get sidePanelMoveRight => '移到对话右侧';

  @override
  String get sidePanelChanges => '变更';

  @override
  String get sidePanelOpenFile => '在侧栏中打开';

  @override
  String get sidePanelOpenDiff => '在侧栏中查看改动';

  @override
  String get sidePanelOpenInIde => '在 Fast Ide 中打开';

  @override
  String get sidePanelCloseTab => '关闭';

  @override
  String get sidePanelPreview => '预览';

  @override
  String get sidePanelSource => '源码';

  @override
  String get commandOpenDetails => '查看详情';

  @override
  String get sidePanelNoOriginal => '不知道智能体修改前的文件内容，显示当前内容。';

  @override
  String get sidePanelUnchanged => '没有差异';

  @override
  String get sidePanelDeleted => '智能体删除了这个文件。';

  @override
  String get sidePanelTerminals => '终端';

  @override
  String get sidePanelRevealInFiles => '在文件中显示';

  @override
  String get sidePanelAddToChat => '添加到对话';

  @override
  String get termClearTask => '清除';

  @override
  String get termClearEndedTasks => '清除所有已结束的任务';

  @override
  String get sidePanelBackgroundTasks => '后台任务';

  @override
  String get sidePanelSelectFile => '选择一个文件以预览';

  @override
  String get sidePanelSelectTerminal => '选择一个后台任务以查看输出';

  @override
  String get sidePanelNoFolder => '这个对话没有项目文件夹';

  @override
  String get sidePanelSearchFiles => '搜索项目文本';

  @override
  String get sidePanelCloseSearch => '关闭搜索';

  @override
  String get sidePanelShowList => '显示列表';

  @override
  String get sidePanelHideList => '隐藏列表';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '还原';

  @override
  String get windowClose => '关闭';

  @override
  String get aboutDescription =>
      '智能体以本地进程运行 Claude Code；它们所做的一切——消息、工具、差异和面板——都显示在这里。';

  @override
  String get agentUntitled => '新对话';

  @override
  String agentImageTitle(String name) {
    return '图片：$name';
  }

  @override
  String get agentImageUntitled => '图片';

  @override
  String get sidebarNewAgent => '新对话';

  @override
  String get sidebarGroupingProject => '项目';

  @override
  String get sidebarGroupingDate => '日期';

  @override
  String get sidebarGroupingStatus => '状态';

  @override
  String get sidebarByProject => '按项目';

  @override
  String get sidebarByDate => '按日期';

  @override
  String get sidebarByStatus => '按状态';

  @override
  String get sidebarTimeNow => '刚刚';

  @override
  String sidebarTimeMinutes(int count) {
    return '$count分钟';
  }

  @override
  String sidebarTimeHours(int count) {
    return '$count小时';
  }

  @override
  String sidebarTimeDays(int count) {
    return '$count天';
  }

  @override
  String sidebarTimeWeeks(int count) {
    return '$count周';
  }

  @override
  String sidebarMonthDay(String month, int day) {
    return '$month月$day日';
  }

  @override
  String get sidebarPinned => '已置顶';

  @override
  String get sidebarToday => '今天';

  @override
  String get sidebarYesterday => '昨天';

  @override
  String get sidebarPrevious7Days => '过去 7 天';

  @override
  String get sidebarOlder => '更早';

  @override
  String get sidebarNeedsInput => '等待输入';

  @override
  String get sidebarRunning => '运行中';

  @override
  String get sidebarUnread => '未读';

  @override
  String sidebarHoverModel(String model) {
    return '模型：$model';
  }

  @override
  String get sidebarDone => '已完成';

  @override
  String get sidebarArchived => '已归档';

  @override
  String get sidebarOpenFolder => '打开文件夹…';

  @override
  String get sidebarAgents => '智能体';

  @override
  String get sidebarCollapseAll => '全部折叠';

  @override
  String get sidebarExpandAll => '全部展开';

  @override
  String get sidebarNoMatchingAgents => '没有匹配的智能体';

  @override
  String get sidebarNoAgentsYet => '还没有智能体';

  @override
  String get sidebarHideArchived => '隐藏已归档';

  @override
  String sidebarArchivedCount(int count) {
    return '已归档 · $count';
  }

  @override
  String get sidebarDeleteAgentTitle => '删除智能体？';

  @override
  String sidebarDeleteAgentMessage(String title) {
    return '“$title”及其对话将被移除。';
  }

  @override
  String get sidebarDeleteAgentsTitle => '删除智能体？';

  @override
  String sidebarDeleteAgentsMessage(int count) {
    return '$count 个智能体及其对话将被删除，内核中的记录也会一并删除。此操作无法撤销。';
  }

  @override
  String sidebarDeleteAgentMessageKernel(String title, String kernel) {
    return '“$title”及其对话将被删除，$kernel 中的记录也会一并删除。此操作无法撤销。';
  }

  @override
  String get sidebarSearchAgents => '搜索智能体…';

  @override
  String get ideChatHistory => '历史智能体';

  @override
  String get ideChatShowArchived => '显示已归档的智能体';

  @override
  String get ideChatNoAgents => '此项目中没有智能体';

  @override
  String sidebarNewAgentIn(String project) {
    return '在 $project 中新对话';
  }

  @override
  String get newChatRemoteGroup => '远程';

  @override
  String get newChatOpenRemoteDetail => '通过 SSH 打开主机上的文件夹';

  @override
  String get newChatWorkingFolder => '在哪个文件夹中工作';

  @override
  String get newChatNoFolder => '不使用文件夹';

  @override
  String get newChatNoFolderDetail => '在桌面中工作';

  @override
  String newChatOpenFrom(String app) {
    return '从$app打开';
  }

  @override
  String get sidebarPin => '置顶';

  @override
  String get sidebarUnpin => '取消置顶';

  @override
  String get sidebarArchive => '归档';

  @override
  String get sidebarUnarchive => '取消归档';

  @override
  String sidebarPinCount(int count) {
    return '置顶 $count 个智能体';
  }

  @override
  String sidebarUnpinCount(int count) {
    return '取消置顶 $count 个智能体';
  }

  @override
  String sidebarArchiveCount(int count) {
    return '归档 $count 个智能体';
  }

  @override
  String sidebarUnarchiveCount(int count) {
    return '取消归档 $count 个智能体';
  }

  @override
  String sidebarDeleteCount(int count) {
    return '删除 $count 个智能体…';
  }

  @override
  String get sidebarCopySessionId => '复制会话 ID';

  @override
  String sidebarOpenStash(int id) {
    return '打开 Stash #$id';
  }

  @override
  String get sidebarFork => 'Fork 对话';

  @override
  String sidebarShowMore(int count) {
    return '显示更多（$count）';
  }

  @override
  String get sidebarShowLess => '收起';

  @override
  String get sidebarNewAgentHere => '在此新建对话';

  @override
  String sidebarRevealIn(String app) {
    return '在$app中显示';
  }

  @override
  String get sidebarSortByTime => '按时间排序';

  @override
  String get sidebarArchiveAll => '全部归档';

  @override
  String get sidebarUnarchiveAll => '全部取消归档';

  @override
  String get sidebarDeleteArchived => '删除全部已归档…';

  @override
  String get sidebarDeleteArchivedTitle => '删除已归档的智能体？';

  @override
  String sidebarDeleteArchivedMessage(int count) {
    return '$count 个已归档的智能体及其对话将被删除，内核中的记录也会一并删除。此操作无法撤销。';
  }

  @override
  String get sidebarRemoveFromList => '从列表移除';

  @override
  String get sidebarDropToPin => '拖到这里置顶';

  @override
  String get sidebarMoreActions => '更多操作…';

  @override
  String get sidebarChangeIcon => '更改图标…';

  @override
  String sidebarProjectIcon(String project) {
    return '更改 $project 的图标';
  }

  @override
  String get iconPickerEmoji => 'Emoji';

  @override
  String get iconPickerIcons => '图标';

  @override
  String get iconPickerCustom => '自定义';

  @override
  String get iconPickerRemove => '移除';

  @override
  String get iconPickerSearch => '搜索…';

  @override
  String get iconPickerRandom => '随机';

  @override
  String get iconPickerRecent => '最近使用';

  @override
  String get iconPickerNoResults => '没有找到';

  @override
  String get iconPickerDefaultColor => '默认颜色';

  @override
  String get iconPickerUpload => '上传图片';

  @override
  String get iconPickerUploadHint => '上传、拖入或粘贴图片：PNG、JPG、WebP、GIF、SVG，5 MB 以内';

  @override
  String get iconPickerDropHere => '将图片拖到这里';

  @override
  String get iconPickerUploaded => '已上传';

  @override
  String get iconPickerDeleteFromLibrary => '从图库删除';

  @override
  String get iconPickerBrands => '品牌';

  @override
  String get iconPickerSiteIcon => '使用网站图标';

  @override
  String iconPickerSiteIconNone(String host) {
    return '没有在 $host 找到图标';
  }

  @override
  String get iconUploadTooLarge => '文件超过 5 MB';

  @override
  String get iconUploadUnsupported => '不是 PNG、JPG、WebP、GIF 或 SVG 图片';

  @override
  String get iconUploadUnreadable => '无法读取文件';

  @override
  String get emojiGroupSmileys => '笑脸和情感';

  @override
  String get emojiGroupPeople => '人物和身体';

  @override
  String get emojiGroupAnimals => '动物和自然';

  @override
  String get emojiGroupFood => '食物和饮料';

  @override
  String get emojiGroupTravel => '旅行和地点';

  @override
  String get emojiGroupActivities => '活动';

  @override
  String get emojiGroupObjects => '物品';

  @override
  String get emojiGroupSymbols => '符号';

  @override
  String get emojiGroupFlags => '旗帜';

  @override
  String get workspaceBackToChat => '返回聊天';

  @override
  String get workspaceNotEnoughRoom => '此屏幕空间不足';

  @override
  String get workspaceWindowGrows => '窗口将扩大以容纳';

  @override
  String get workspaceCopyPath => '复制路径';

  @override
  String workspaceOpenIn(String app) {
    return '在 $app 中打开';
  }

  @override
  String get workspaceChooseEditor => '选择编辑器';

  @override
  String get workspaceFinder => '访达';

  @override
  String get workspaceFileExplorer => '文件资源管理器';

  @override
  String get workspaceFileManager => '文件管理器';

  @override
  String get workspaceTerminalApp => '终端';

  @override
  String get workspaceWindowsTerminal => 'Windows 终端';

  @override
  String get workspaceKeepOnTopUnavailable => '窗口置顶仅在桌面应用中可用';

  @override
  String get workspaceUnpinWindow => '取消窗口置顶';

  @override
  String get workspacePinWindow => '将窗口置顶';

  @override
  String get chatConversation => '对话';

  @override
  String get chatBackEsc => '返回 (Esc)';

  @override
  String get chatBack => '返回';

  @override
  String get statusRunningInBackground => '在后台运行';

  @override
  String chatToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个工具',
    );
    return '$_temp0';
  }

  @override
  String chatTokens(String tokens) {
    return '$tokens token';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds秒';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes分$seconds秒';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String get agentStateRunningInBackground => '在后台运行';

  @override
  String get agentStateRunning => '运行中';

  @override
  String get agentStateDone => '已完成';

  @override
  String get agentStateFailed => '失败';

  @override
  String chatSubagentSemantics(String description, String status) {
    return '子智能体 $description，$status';
  }

  @override
  String get chatOpensItsConversation => '打开其对话';

  @override
  String get chatLoadEarlier => '加载更早的消息';

  @override
  String get chatStop => '停止';

  @override
  String get chatKeepRunningHint => '让它继续运行，智能体接着往下进行';

  @override
  String get chatBackground => '转到后台';

  @override
  String get stepThinking => '正在思考';

  @override
  String get stepThought => '已思考';

  @override
  String get stepBriefly => '片刻';

  @override
  String get toolReading => '正在读取';

  @override
  String get toolRead => '已读取';

  @override
  String get toolGrepping => '正在搜索';

  @override
  String get toolGrepped => '已搜索';

  @override
  String get toolListing => '正在列出';

  @override
  String get toolListed => '已列出';

  @override
  String get toolSearching => '正在搜索';

  @override
  String get toolSearched => '已搜索';

  @override
  String get toolEditing => '正在编辑';

  @override
  String get toolEdited => '已编辑';

  @override
  String get toolRunning => '正在运行';

  @override
  String get toolRan => '已运行';

  @override
  String get toolFetching => '正在获取';

  @override
  String get toolFetched => '已获取';

  @override
  String get toolAgent => '智能体';

  @override
  String get toolUpdatingTodos => '正在更新待办';

  @override
  String get toolUpdatedTodos => '已更新待办';

  @override
  String get toolSending => '正在说';

  @override
  String get toolSent => '说';

  @override
  String get toolAsking => '正在提问';

  @override
  String get toolAsked => '提问';

  @override
  String get toolQuestionSkipped => '已跳过提问';

  @override
  String get toolUsing => '正在使用';

  @override
  String get toolUsed => '已使用';

  @override
  String get toolGeneratingImage => '正在生成图片';

  @override
  String get toolGeneratedImage => '已生成图片';

  @override
  String get toolImageFailed => '图片未生成';

  @override
  String get toolImageWaiting => '生成图片';

  @override
  String get imagePickTitle => '选择用来生成的模型';

  @override
  String get imagePickGenerate => '生成';

  @override
  String get imagePickDecline => '不生成';

  @override
  String get imageSetDefault => '设为默认';

  @override
  String get imageDefaultSet => '已设为默认图片模型';

  @override
  String get toolProposingGoal => '正在提议目标';

  @override
  String get toolProposedGoal => '提议目标';

  @override
  String get goalAdopt => '设为目标';

  @override
  String get goalAdopted => '已设为目标';

  @override
  String get goalLabel => '目标';

  @override
  String get goalWorking => '进行中';

  @override
  String get goalWaiting => '等待中';

  @override
  String get goalNeedsYou => '等你回复';

  @override
  String get goalMet => '已达成';

  @override
  String get goalFailed => '无法达成';

  @override
  String goalChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已检查 $count 次',
    );
    return '$_temp0';
  }

  @override
  String get goalLastCheck => '上次检查';

  @override
  String get goalEdit => '修改目标';

  @override
  String get goalClear => '清除目标';

  @override
  String get goalClearConfirm => '清除这个目标？';

  @override
  String get goalSet => '设定目标';

  @override
  String get goalDismiss => '关闭';

  @override
  String get goalStopsTurn => '将中断当前这一轮，立即生效';

  @override
  String imageChip(int number) {
    return '图片 $number';
  }

  @override
  String imageReferenceRemoved(int number) {
    return '[图片 $number]';
  }

  @override
  String pastedTextChip(int number) {
    return '粘贴的文本 #$number';
  }

  @override
  String pastedTextGone(String path) {
    return '这段粘贴的内容已不在 $path。';
  }

  @override
  String pastedTextLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count 行',
    );
    return '$_temp0';
  }

  @override
  String get imageCopy => '复制图片';

  @override
  String stepsRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '读取 $count 个文件',
    );
    return '$_temp0';
  }

  @override
  String stepsSearched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '搜索 $count 次',
    );
    return '$_temp0';
  }

  @override
  String stepsListed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '列出 $count 个目录',
    );
    return '$_temp0';
  }

  @override
  String stepsFetched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '获取 $count 个网页',
    );
    return '$_temp0';
  }

  @override
  String stepsRan(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '运行 $count 条命令',
    );
    return '$_temp0';
  }

  @override
  String stepsBrowsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '操作浏览器 $count 次',
    );
    return '$_temp0';
  }

  @override
  String stepsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '使用 $count 个工具',
    );
    return '$_temp0';
  }

  @override
  String get stepsSeparator => '，';

  @override
  String stepsThought(String duration) {
    return '思考 $duration';
  }

  @override
  String get turnCopy => '复制回复';

  @override
  String get turnCopied => '已复制';

  @override
  String turnSpeed(String speed) {
    return '$speed tok/s';
  }

  @override
  String turnTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String turnTokensHint(String input, String output) {
    return '本轮：输入 $input（含缓存），输出 $output';
  }

  @override
  String get turnSpeedHint => '平均输出速度';

  @override
  String get turnOutputTokensHint => '本轮已输出';

  @override
  String get turnSpeedLiveHint => '输出速度（最近 2 秒采样）';

  @override
  String get turnDurationHint => '本轮耗时';

  @override
  String get turnCostHint => '本轮花费';

  @override
  String turnWorked(String duration) {
    return '已处理 $duration';
  }

  @override
  String get planCardLabel => '计划';

  @override
  String planCardRound(int round) {
    return 'v$round';
  }

  @override
  String get planDrafting => '起草中';

  @override
  String get planAwaiting => '待开始';

  @override
  String get planApproved => '已批准';

  @override
  String get planSentBack => '已退回';

  @override
  String get planStart => '开始执行';

  @override
  String get planStartHint => '退出计划模式，按此计划开始执行';

  @override
  String get planStartMessage => '按计划开始执行';

  @override
  String turnFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
    );
    return '$_temp0';
  }

  @override
  String toolLines(String range) {
    return '第 $range 行';
  }

  @override
  String get commandStarted => '已启动';

  @override
  String get commandInBackground => '在后台';

  @override
  String get commandCopyCommand => '复制命令';

  @override
  String get commandCopyOutput => '复制输出';

  @override
  String get commandMoveToBackground => '转到后台';

  @override
  String get commandMore => '更多';

  @override
  String get chatSubagent => '子智能体';

  @override
  String get chatLoadingHistory => '正在加载对话…';

  @override
  String get activityCompacting => '正在压缩对话';

  @override
  String get activityPlanning => '正在规划下一步';

  @override
  String get activityMusings =>
      '冥思苦想\n琢磨一下\n慢慢酝酿\n深思熟虑\n文火慢炖\n修修补补\n融会贯通\n反复掂量\n连点成线\n追一个直觉\n酝酿计划\n孵化方案\n权衡利弊\n理清头绪\n赶着一群 token\n召唤上下文\n请教小黄鸭\n在餐巾纸上打草稿\n眯眼看 diff\n数括号\n和编译器交朋友\n与类型系统谈判\n驯服边界情况\n追踪调用栈\n翻阅文档\n探索代码库\n摇一摇魔法 8 号球\n绑定 Monad\n求问神谕\n打磨计划\n打个腹稿\n掐指一算\n抽丝剥茧\n顺藤摸瓜\n在脑子里跑一遍\n把思路捋直\n拆解问题';

  @override
  String activityMusingsCommand(String name) {
    return '对着 $name 的输出点点头\n品一品 $name 的输出\n给 $name 的输出划重点\n看 $name 跑出了什么名堂\n把 $name 的结果过一遍';
  }

  @override
  String activityMusingsCommandFailed(String name) {
    return '和 $name 的报错大眼瞪小眼\n盯着 $name 的报错挠头\n给 $name 的报错号号脉\n琢磨 $name 为什么不高兴\n顺着 $name 的报错往回找';
  }

  @override
  String activityMusingsRead(String name) {
    return '把 $name 翻来覆去地看\n在 $name 里找线头\n跟 $name 混个脸熟\n在 $name 的字里行间找答案\n把 $name 记在心里';
  }

  @override
  String activityMusingsEdit(String name) {
    return '欣赏刚改好的 $name\n替 $name 捏把汗\n回头再瞄一眼 $name\n想想 $name 还缺点啥\n给 $name 收个尾';
  }

  @override
  String activityMusingsSearch(String name) {
    return '在 $name 处结果里淘金\n从 $name 处结果里挑出真身\n顺着 $name 条线索摸过去';
  }

  @override
  String activityMusingsFolder(String name) {
    return '在 $name 里东张西望\n给 $name 点个名\n摸清 $name 的家底';
  }

  @override
  String activityMusingsWeb(String name) {
    return '从 $name 抄点笔记\n消化 $name 上看来的东西';
  }

  @override
  String activityMusingsAgent(String name) {
    return '听 $name 汇报\n批改 $name 交上来的作业\n消化 $name 带回来的情报';
  }

  @override
  String activityMusingsMcp(String name) {
    return '拆 $name 寄回来的包裹\n看 $name 回了些什么';
  }

  @override
  String get activityMusingsBrowser => '端详页面截图\n看看浏览器里发生了什么';

  @override
  String get activityMusingsImage => '端详刚画好的图\n给新图挑挑刺';

  @override
  String get activityMusingsDenied => '收到，换条路走\n另想办法';

  @override
  String get composerCommands => '命令';

  @override
  String get composerMentions => '文件和对话';

  @override
  String get composerPlaceholder => '规划、搜索、构建任何内容  ·  拖入或粘贴文件  / 命令';

  @override
  String composerApprovalTitle(String agent) {
    return '$agent 应如何获得批准？';
  }

  @override
  String get composerApprovalDefault => '逐项批准';

  @override
  String get composerApprovalDefaultDetail => '编辑和命令前都先询问';

  @override
  String get composerApprovalAcceptEdits => '自动接受编辑';

  @override
  String get composerApprovalAcceptEditsDetail => '直接编辑文件，运行命令前询问';

  @override
  String get composerApprovalAuto => '替我批准';

  @override
  String get composerApprovalAutoDetail => '安全的自动通过，有风险的拦下';

  @override
  String get composerApprovalDontAsk => '仅限已允许';

  @override
  String get composerApprovalDontAskDetail => '未预先允许的一律拒绝';

  @override
  String get composerApprovalFullAccess => '完全访问';

  @override
  String get composerApprovalFullAccessDetail => '不做任何检查，编辑和命令直接执行';

  @override
  String get composerContextUsage => '上下文用量';

  @override
  String get composerSend => '发送  ↵';

  @override
  String get composerStop => '停止';

  @override
  String get composerSettingContext => '上下文';

  @override
  String get composerSettingEffort => '推理强度';

  @override
  String get composerNoResults => '无结果';

  @override
  String stripOpen(String name) {
    return '打开 $name';
  }

  @override
  String stripRunningElapsed(int seconds) {
    return '运行中 · $seconds秒';
  }

  @override
  String stripFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已更改 $count 个文件',
    );
    return '$_temp0';
  }

  @override
  String stripAgentsRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个子代理运行中',
    );
    return '$_temp0';
  }

  @override
  String stripTasksRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个后台任务运行中',
    );
    return '$_temp0';
  }

  @override
  String get stripUndoAll => '全部撤销';

  @override
  String get stripKeepAll => '全部保留';

  @override
  String get stripKeep => '保留';

  @override
  String get stripUndo => '撤销';

  @override
  String get agentKeepFile => '保留当前';

  @override
  String get agentUndoFile => '撤销当前';

  @override
  String get agentPreviousChange => '上一处更改';

  @override
  String get agentNextChange => '下一处更改';

  @override
  String get agentMoreActions => '更多操作';

  @override
  String get stripChangeAdded => '新增';

  @override
  String get stripChangeModified => '已修改';

  @override
  String get stripChangeDeleted => '已删除';

  @override
  String get stripChangeConflict => '智能体改完后这个文件又被改过，无法自动撤销智能体的改动。请手动处理后再保留。';

  @override
  String get stripChangeShared => '同一时间还有别的智能体在这个项目里工作，这处改动可能有一部分是它的。';

  @override
  String get stripChangeUntracked =>
      '不知道改动前的内容（文件被忽略或过大、不在项目快照中，智能体也没有提供；或在项目之外）：只能保留，无法撤销。';

  @override
  String get stripChangesDiff => '智能体改动';

  @override
  String get usageUsed => '已用';

  @override
  String get usageContextWindow => '上下文窗口';

  @override
  String usageTokensSummary(String used, String total, String percent) {
    return '$used / $total token · $percent%';
  }

  @override
  String get usageReservedForCompaction => '为压缩预留';

  @override
  String get usagePromptCache => '提示缓存';

  @override
  String usageCacheLast(String read, String written, String uncached) {
    return '最近一次请求：读取 $read · 写入 $written · 未缓存 $uncached';
  }

  @override
  String usageCacheOverall(String percent) {
    return '主对话 $percent%';
  }

  @override
  String usageCacheConversation(String read, String written, String percent) {
    return '主对话：读取 $read · 写入 $written · 命中 $percent%';
  }

  @override
  String get usageCacheExcludes => '不含子智能体、压缩及 CLI 的附带请求';

  @override
  String get usagePlanUsage => '套餐用量';

  @override
  String get usageThisSession => '本次会话';

  @override
  String get usageCheckingLimits => '正在获取额度…';

  @override
  String get usageLimitsUnavailable => '暂时获取不到额度，稍后重新打开再试。';

  @override
  String get usageLimitsAfterMessage => '额度随对话自动更新，对话后即可看到。';

  @override
  String usageResets(String when) {
    return '$when重置';
  }

  @override
  String usageInMinutes(int minutes) {
    return '$minutes分钟后';
  }

  @override
  String usageInHours(int hours) {
    return '$hours小时后';
  }

  @override
  String usageInHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分钟后';
  }

  @override
  String usageInDays(int days) {
    return '$days天后';
  }

  @override
  String usageInDaysHours(int days, int hours) {
    return '$days天$hours小时后';
  }

  @override
  String healthStopped(String name) {
    return '$name 已停止';
  }

  @override
  String healthFolderGone(String folder) {
    return '项目文件夹不存在：$folder';
  }

  @override
  String get healthHideDetails => '隐藏详细信息';

  @override
  String get markdownDetails => '详细信息';

  @override
  String get healthDetails => '详细信息';

  @override
  String get healthRetry => '重试';

  @override
  String get interactionOther => '其他';

  @override
  String get interactionTypeYourAnswer => '输入你的回答';

  @override
  String get interactionAllowOnce => '允许一次';

  @override
  String get interactionDeny => '拒绝';

  @override
  String get interactionDenyHint => '告诉智能体改做什么';

  @override
  String interactionStepOf(int step, int total) {
    return '$step / $total';
  }

  @override
  String get interactionSkip => '跳过';

  @override
  String get interactionSubmit => '提交';

  @override
  String get interactionNext => '下一步';

  @override
  String get interactionBack => '上一步';

  @override
  String get interactionCollapse => '收起';

  @override
  String get interactionExpand => '展开';

  @override
  String interactionMoreLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '… 还有 $count 行',
    );
    return '$_temp0';
  }

  @override
  String get mcpServers => 'MCP 服务器';

  @override
  String mcpConnectedOf(int connected, int total) {
    return '已连接 $connected/$total';
  }

  @override
  String get mcpRefresh => '刷新';

  @override
  String get mcpNoServers => '此项目未配置 MCP 服务器。';

  @override
  String get mcpConnected => '已连接';

  @override
  String get mcpConnecting => '正在连接…';

  @override
  String get mcpFailed => '失败';

  @override
  String get mcpNeedsSignIn => '需要登录';

  @override
  String get mcpDisabled => '已禁用';

  @override
  String get mcpReconnect => '重新连接';

  @override
  String get mcpSignIn => '登录';

  @override
  String get mcpEnable => '启用';

  @override
  String get mcpDisable => '禁用';

  @override
  String get mcpTest => '测试连接';

  @override
  String get mcpTestAll => '全部重新检测';

  @override
  String get mcpViewLog => '查看日志';

  @override
  String mcpExitCode(int code) {
    return '进程已退出，退出码 $code';
  }

  @override
  String mcpTimedOut(int seconds) {
    return '$seconds 秒内没有响应';
  }

  @override
  String get mcpLog => '输出（stderr）';

  @override
  String get mcpNoLog => '没有任何输出。';

  @override
  String get mcpSignInHint => '在对话的 MCP 服务器面板或用 /mcp 登录。';

  @override
  String get mcpProbeNote =>
      '启动后用 MCP 的 initialize 握手检测，与 `claude mcp list` 的检测方式相同。';

  @override
  String todoCount(int done, int total) {
    return '待办 $done/$total';
  }

  @override
  String queuedMessages(int count) {
    return '$count 条排队中 · 当前任务结束后依次发送';
  }

  @override
  String queuedImages(int count) {
    return '$count 张图片';
  }

  @override
  String get queuedEdit => '撤回并编辑';

  @override
  String get queuedSendNow => '中断当前任务，立即发送';

  @override
  String get queuedRemove => '移出队列';

  @override
  String get stopConfirmMessage => '要停止 Agent 吗？';

  @override
  String stopConfirmDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '后台运行中的 $count 个任务也会一并停止。',
    );
    return '$_temp0';
  }

  @override
  String get stopConfirmStop => '停止';

  @override
  String get tabClose => '关闭';

  @override
  String get tabCloseOthers => '关闭其他';

  @override
  String get tabCloseToTheRight => '关闭右侧';

  @override
  String get tabCloseSaved => '关闭已保存';

  @override
  String get tabCloseAll => '全部关闭';

  @override
  String get fileLinkOpen => '打开';

  @override
  String get fileLinkOpenInPanel => '在侧边栏中打开';

  @override
  String get fileLinkPreview => '预览';

  @override
  String get fileLinkOpenInBrowser => '在浏览器中打开';

  @override
  String get tabCopyPath => '复制路径';

  @override
  String get tabCopyRelativePath => '复制相对路径';

  @override
  String get tabRevealInExplorerView => '在资源管理器视图中显示';

  @override
  String get tabMoreActions => '更多操作…';

  @override
  String get markdownShowPreview => '预览';

  @override
  String get markdownShowSource => 'Markdown';

  @override
  String get markdownFindInSource => '预览中不能查找，已切换到 Markdown 源码。';

  @override
  String markdownPasteFolder(String name) {
    return '不能把文件夹粘贴到文档里：$name';
  }

  @override
  String get markdownPasteLargeTitle => '复制大文件？';

  @override
  String markdownPasteLargeMessage(String name, String size) {
    return '$name 有 $size，确定复制到文档旁边吗？';
  }

  @override
  String get markdownPasteLargeConfirm => '复制';

  @override
  String markdownPasteFailed(String name, String error) {
    return '无法粘贴 $name：$error';
  }

  @override
  String get markdownPasteMoved => '粘贴期间文档被修改，链接已插入到文末。';

  @override
  String tabCloseNamed(String name) {
    return '关闭 $name';
  }

  @override
  String tabDeleted(String name) {
    return '$name (已删除)';
  }

  @override
  String get commonDismiss => '关闭';

  @override
  String layoutTogglePrimarySideBar(String keybinding) {
    return '切换主侧边栏 ($keybinding)';
  }

  @override
  String layoutTogglePanel(String keybinding) {
    return '切换面板 ($keybinding)';
  }

  @override
  String layoutToggleChat(String keybinding) {
    return '切换聊天 ($keybinding)';
  }

  @override
  String get dialogCloseDialog => '关闭对话框';

  @override
  String get menuDismissMenu => '关闭菜单';

  @override
  String get notificationsHide => '隐藏通知';

  @override
  String get notificationsNone => '没有通知';

  @override
  String get notificationsNoNew => '没有新通知';

  @override
  String notificationsNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条新通知',
    );
    return '$_temp0';
  }

  @override
  String get notificationsCenterNoNew => '没有新通知';

  @override
  String get notificationsCenterTitle => '通知';

  @override
  String get notificationsClearAll => '清除所有通知';

  @override
  String get notificationsCollapse => '折叠通知';

  @override
  String get notificationsExpand => '展开通知';

  @override
  String get notificationsMoreActions => '更多操作...';

  @override
  String get notificationsClear => '清除通知';

  @override
  String notificationsSource(String source) {
    return '来源: $source';
  }

  @override
  String explorerCannotReadFolder(String error) {
    return '无法读取文件夹: $error';
  }

  @override
  String get explorerNameRequired => '必须提供文件或文件夹名称。';

  @override
  String get explorerNameStartsWithSlash => '文件或文件夹名称不能以斜杠开头。';

  @override
  String explorerNameExists(String name) {
    return '此位置已存在文件或文件夹 $name。请选择其他名称。';
  }

  @override
  String explorerNameInvalid(String name) {
    return '名称 $name 不是有效的文件或文件夹名称。请选择其他名称。';
  }

  @override
  String get explorerNameWhitespace => '在文件或文件夹名称中检测到前导或尾随空格。';

  @override
  String get explorerMoveToTrash => '移到废纸篓';

  @override
  String explorerDeleteFolderUnsaved(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '你正在删除文件夹 $name，其中 $count 个文件有未保存的更改。是否继续?',
    );
    return '$_temp0';
  }

  @override
  String explorerDeleteFileUnsaved(String name) {
    return '你正在删除有未保存更改的 $name。是否继续?';
  }

  @override
  String get explorerChangesLost => '如果不保存，你的更改将丢失。';

  @override
  String explorerConfirmDeleteFolder(String name) {
    return '确定要删除“$name”及其内容吗?';
  }

  @override
  String explorerConfirmDeleteFile(String name) {
    return '确定要删除“$name”吗?';
  }

  @override
  String get explorerRestoreFromTrash => '可以从废纸篓还原此文件。';

  @override
  String explorerConfirmPermanentDeleteFolder(String name) {
    return '确定要永久删除“$name”及其内容吗?';
  }

  @override
  String explorerConfirmPermanentDeleteFile(String name) {
    return '确定要永久删除“$name”吗?';
  }

  @override
  String get explorerIrreversible => '此操作不可逆!';

  @override
  String get explorerRestoreWithUndo => '可以使用“撤销”命令还原此文件。';

  @override
  String get explorerDeleteFilesUnsaved => '你正在删除有未保存更改的文件。是否继续?';

  @override
  String explorerConfirmDeleteMultiple(int count) {
    return '确定要删除以下 $count 个文件/目录及其内容吗?';
  }

  @override
  String explorerConfirmPermanentDeleteMultiple(int count) {
    return '确定要永久删除以下 $count 个文件/目录及其内容吗?';
  }

  @override
  String get explorerRestoreFilesFromTrash => '可以从废纸篓还原这些文件。';

  @override
  String get explorerRestoreFilesWithUndo => '可以使用“撤销”命令还原这些文件。';

  @override
  String explorerMoreFilesNotShown(int count) {
    return '...另有 $count 个文件未显示';
  }

  @override
  String get explorerTrashFailed => '无法通过废纸篓删除。是否改为永久删除?';

  @override
  String get explorerDeletePermanently => '永久删除';

  @override
  String get explorerPasteIntoAncestor => '要粘贴的文件是目标文件夹的上级';

  @override
  String explorerUploading(int done, int total) {
    return '正在上传文件… $done/$total';
  }

  @override
  String explorerDownloading(int done, int total) {
    return '正在下载文件… $done/$total';
  }

  @override
  String get explorerPreparingTransfer => '正在准备文件…';

  @override
  String composerCopyToHostFailed(String error) {
    return '无法把文件复制到远程主机：$error';
  }

  @override
  String get explorerNewFile => '新建文件...';

  @override
  String get explorerNewFolder => '新建文件夹...';

  @override
  String get explorerRevealInFinder => '在访达中显示';

  @override
  String get explorerFindInFolder => '在文件夹中查找...';

  @override
  String get explorerOpenInTerminal => '在终端中打开';

  @override
  String get explorerRename => '重命名...';

  @override
  String get findNoResults => '无结果';

  @override
  String findMatchOf(String current, String total) {
    return '第 $current 项，共 $total 项';
  }

  @override
  String get findFind => '查找';

  @override
  String get findMatchCase => '区分大小写';

  @override
  String get findWholeWord => '全字匹配';

  @override
  String get findRegularExpression => '使用正则表达式';

  @override
  String get findPreviousMatch => '上一个匹配项';

  @override
  String get findNextMatch => '下一个匹配项';

  @override
  String get findClose => '关闭查找';

  @override
  String get findReplace => '替换';

  @override
  String get findReplaceMatch => '替换';

  @override
  String get findReplaceAll => '全部替换';

  @override
  String get findToggleReplace => '切换替换';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionLanguage => '区域和语言';

  @override
  String get settingsSectionKeyboard => '键盘快捷方式';

  @override
  String get settingsSectionDataDirectory => '数据目录';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsGroupPreferences => '偏好设置';

  @override
  String get settingsGroupAdvanced => '高级';

  @override
  String get generalSettingsTitle => '通用';

  @override
  String get generalSettingsCommitAttribution => '提交署名';

  @override
  String get generalSettingsCommitAttributionDescription =>
      'Agent 在它写的提交和 Pull Request 中添加的署名。更改对之后启动的 Agent 生效；目前仅支持 Claude Code。';

  @override
  String get generalSettingsClaudeCore => '内核';

  @override
  String get generalSettingsClaudeCoreDescription =>
      'Claude Code CLI：Anthropic 官方程序，沿用本机的登录和配置，用 Claude 订阅请选它。内置：BaoCode 自带，只用 设置 → 模型 里添加的模型。默认用 CLI，本机没有时会自动下载。改动对新开的会话生效。';

  @override
  String get generalSettingsClaudeCoreBuiltin => '内置';

  @override
  String get generalSettingsClaudeCoreCli => 'Claude Code CLI';

  @override
  String get generalSettingsQueuedMessages => '工作中发送的消息';

  @override
  String get generalSettingsQueuedMessagesDescription =>
      'Agent 还在工作时发出的消息何时被处理。更改对之后发送的消息生效；目前仅支持 Claude Code。';

  @override
  String get generalSettingsQueuedAfterTurn => '当前任务完成后依次执行';

  @override
  String get generalSettingsQueuedDuringTurn => '插入当前任务';

  @override
  String get generalSettingsPromptSuggestions => '建议下一条提示';

  @override
  String get generalSettingsPromptSuggestionsDescription =>
      '每轮结束后在输入框里给出灰色的下一条消息建议，按 Tab 采用。每条建议都会带着整段对话额外请求一次模型，关掉可以节省 token。从下一条消息起生效；目前仅支持 Claude Code。';

  @override
  String generalSettingsCommitAttributionLabel(String name) {
    return '提交署名: $name';
  }

  @override
  String get generalSettingsAttributionAgent => '跟随 Agent';

  @override
  String get generalSettingsAttributionAgentDetail =>
      'Agent 自带的署名（如 Claude Code 的），或你在 ~/.claude/settings.json 中设置的 attribution。';

  @override
  String get generalSettingsAttributionNone => '不署名';

  @override
  String get generalSettingsAttributionNoneDetail =>
      '不在提交和 Pull Request 中添加任何署名。';

  @override
  String get settingsSectionNotifications => '通知';

  @override
  String get notificationsSettingsTitle => '通知';

  @override
  String get notificationsEnabled => 'Agent 需要我时通知我';

  @override
  String get notificationsEnabledDescription =>
      'Agent 向你提问或跑完一轮时，发出系统通知并播放提示音。无论是否开启，应用图标都会显示等待你回复或未读的 Agent 数量。';

  @override
  String get notificationsEvents => '在 Agent 这些时候通知';

  @override
  String get notificationsEventNeedsInput => '需要你回复';

  @override
  String get notificationsEventNeedsInputDetail => '它在提问、请求权限，或等你确认计划。';

  @override
  String get notificationsEventFinished => '跑完一轮';

  @override
  String get notificationsEventFinishedDetail => '它做完了，等你发下一条消息。';

  @override
  String get notificationsWhen => '何时通知';

  @override
  String get notificationsWhenDescription => '窗口在前台、你正在看的那个 Agent，是否也要通知。';

  @override
  String get notificationsWhenUnfocused => '我没在看它时';

  @override
  String get notificationsWhenAlways => '总是';

  @override
  String notificationsWhenLabel(String name) {
    return '何时通知：$name';
  }

  @override
  String get notificationsSound => '提示音';

  @override
  String get notificationsSoundMicrowave => '微波炉“叮”';

  @override
  String get notificationsSoundManOhYeah => 'man-oh-yeah';

  @override
  String get notificationsSoundGulpGulpGulpGulp => 'Gulp Gulp Gulp Gulp';

  @override
  String get notificationsSoundNone => '无';

  @override
  String get notificationsSoundChoose => '选择文件…';

  @override
  String notificationsSoundLabel(String name) {
    return '提示音：$name';
  }

  @override
  String get notificationsSoundPlay => '试听';

  @override
  String get traySettings => '托盘';

  @override
  String get trayEnabledMacOS => '在菜单栏显示图标';

  @override
  String get trayEnabledWindows => '在系统托盘显示图标';

  @override
  String get trayEnabledDescription =>
      '关闭窗口时隐藏到这里，Agent 继续在后台运行；它的菜单列出等待你回复的 Agent，也从这里退出应用。';

  @override
  String get trayShow => '显示 BaoCode';

  @override
  String get trayWaiting => '等待你回复';

  @override
  String trayWaitingCount(int count) {
    return '$count 个等待中';
  }

  @override
  String trayRunning(int count) {
    return '$count 个运行中';
  }

  @override
  String get trayQuit => '退出 BaoCode';

  @override
  String get attentionNeedsInput => '需要你回复';

  @override
  String get attentionFinished => '已完成';

  @override
  String get attentionPlanReady => '计划待确认';

  @override
  String get placeholderBinary => '此文件是二进制文件或使用了不支持的文本编码，所以无法在文本编辑器中显示。';

  @override
  String placeholderTooLarge(String size) {
    return '文件未在文本编辑器中显示，因为它非常大($size)。';
  }

  @override
  String get placeholderNotFound => '无法打开编辑器，因为找不到该文件。';

  @override
  String get placeholderUnexpected => '由于意外错误，无法打开编辑器。';

  @override
  String get placeholderOpenAnyway => '仍然打开';

  @override
  String get changeOpenWith => '打开方式';

  @override
  String get openInDefaultApp => '使用默认应用打开';

  @override
  String openInDefaultAppFailed(String name) {
    return '无法使用默认应用打开“$name”。';
  }

  @override
  String get placeholderTryAgain => '重试';

  @override
  String fileErrorConflict(String path) {
    return '文件已在磁盘上更改。请在保存前重新打开: $path';
  }

  @override
  String fileErrorNotFound(String path) {
    return '找不到文件: $path';
  }

  @override
  String fileErrorBinary(String path) {
    return '无法编辑二进制文件: $path';
  }

  @override
  String fileErrorTooLarge(String path) {
    return '无法编辑超过 5 MB 的文件: $path';
  }

  @override
  String fileErrorExists(String name) {
    return '此位置已存在文件或文件夹 $name。';
  }

  @override
  String get themeDefaultLight => '默认浅色';

  @override
  String get themeDefaultDark => '默认深色';

  @override
  String get themeLightThemes => '浅色主题';

  @override
  String get themeDarkThemes => '深色主题';

  @override
  String get themeHighContrastThemes => '高对比度主题';

  @override
  String get themeSelectPlaceholder => '选择颜色主题(检测系统颜色模式已禁用)';

  @override
  String get dateNow => '现在';

  @override
  String dateAgo(String time) {
    return '$time前';
  }

  @override
  String dateIn(String time) {
    return '$time后';
  }

  @override
  String dateSeconds(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 秒'});
    return '$_temp0';
  }

  @override
  String dateMinutes(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 分钟'});
    return '$_temp0';
  }

  @override
  String dateHours(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 小时'});
    return '$_temp0';
  }

  @override
  String dateDays(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 天'});
    return '$_temp0';
  }

  @override
  String dateWeeks(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 周'});
    return '$_temp0';
  }

  @override
  String dateMonths(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 个月'});
    return '$_temp0';
  }

  @override
  String dateYears(String full, int count) {
    String _temp0 = intl.Intl.selectLogic(full, {'other': '$count 年'});
    return '$_temp0';
  }

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonMoreActions => '更多操作...';

  @override
  String get commonCollapseAll => '全部折叠';

  @override
  String get commonYes => '是';

  @override
  String get gitStatusIndexModified => '索引已修改';

  @override
  String get gitStatusModified => '已修改';

  @override
  String get gitStatusIndexAdded => '索引已添加';

  @override
  String get gitStatusIndexDeleted => '索引已删除';

  @override
  String get gitStatusDeleted => '已删除';

  @override
  String get gitStatusIndexRenamed => '索引已重命名';

  @override
  String get gitStatusIndexCopied => '索引已复制';

  @override
  String get gitStatusUntracked => '未跟踪';

  @override
  String get gitStatusIgnored => '已忽略';

  @override
  String get gitStatusIntentToAdd => '打算添加';

  @override
  String get gitStatusIntentToRename => '打算重命名';

  @override
  String get gitStatusTypeChanged => '类型已更改';

  @override
  String get gitStatusBothDeleted => '冲突: 两个都已删除';

  @override
  String get gitStatusAddedByUs => '冲突: 已由我们添加';

  @override
  String get gitStatusDeletedByThem => '冲突: 已被他们删除';

  @override
  String get gitStatusAddedByThem => '冲突: 已由他们添加';

  @override
  String get gitStatusDeletedByUs => '冲突: 已被我们删除';

  @override
  String get gitStatusBothAdded => '冲突: 两个都已添加';

  @override
  String get gitStatusBothModified => '冲突: 两个都已修改';

  @override
  String get gitIgnoredInGit => '已在 Git 中忽略';

  @override
  String get gitBlameNotCommittedYet => '尚未提交';

  @override
  String get gitContainsEmphasizedItems => '包含强调项';

  @override
  String get gitChangeIndex => '索引';

  @override
  String get gitChangeWorkingTree => '工作树';

  @override
  String get gitChangeDeleted => '已删除';

  @override
  String get gitChangeTheirs => '他们的';

  @override
  String get gitChangeOurs => '我们的';

  @override
  String get gitChangeUntracked => '未跟踪';

  @override
  String get gitChangeIntentToAdd => '打算添加';

  @override
  String get gitChangeTypeChanged => '类型已更改';

  @override
  String get scmTitle => '源代码管理';

  @override
  String get scmNoProviders => '未注册源代码管理提供程序。';

  @override
  String get scmInstallGit => '安装 Git (一种流行的源代码管理系统)，以跟踪代码更改并与他人协作。';

  @override
  String get scmNoRepository =>
      '当前打开的文件夹中没有 Git 仓库。可初始化一个仓库，它将实现 Git 提供支持的源代码管理功能。';

  @override
  String get scmInitializeRepository => '初始化仓库';

  @override
  String get scmChanges => '更改';

  @override
  String scmTooManyChanges(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '此仓库的更改过多：仅显示前 $countString 项，文件变化时也不再自动刷新。需要时请手动刷新。';
  }

  @override
  String get scmGroupMerge => '合并更改';

  @override
  String get scmGroupStaged => '暂存的更改';

  @override
  String get scmGraph => '图形';

  @override
  String get scmCommit => '提交';

  @override
  String get scmCommitChanges => '提交更改';

  @override
  String get scmCommitAmend => '提交(修改)';

  @override
  String get scmCommitStaged => '提交已暂存文件';

  @override
  String get scmCommitAll => '全部提交';

  @override
  String get scmCommitStagedAmend => '提交已暂存文件(修改)';

  @override
  String get scmCommitAllAmend => '全部提交(修改)';

  @override
  String get scmUndoLastCommit => '撤消上次提交';

  @override
  String get scmGraphBranches => '显示的分支';

  @override
  String get scmGraphCurrentBranch => '当前分支';

  @override
  String get scmGraphAllBranches => '所有分支';

  @override
  String get scmGoToCurrent => '转到当前历史记录项';

  @override
  String get scmViewAndSort => '视图和排序';

  @override
  String get scmViewAsList => '以列表形式查看';

  @override
  String get scmViewAsTree => '以树形式查看';

  @override
  String get scmSortByName => '按名称对更改进行排序';

  @override
  String get scmSortByPath => '按路径对更改进行排序';

  @override
  String get scmSortByStatus => '按状态对更改进行排序';

  @override
  String get scmStageChanges => '暂存更改';

  @override
  String get scmUnstageChanges => '取消暂存更改';

  @override
  String get scmDiscardChanges => '放弃更改';

  @override
  String get scmStageAllMerge => '暂存所有合并更改';

  @override
  String get scmStageAll => '暂存所有更改';

  @override
  String get scmUnstageAll => '取消暂存所有更改';

  @override
  String get scmDiscardAll => '放弃所有更改';

  @override
  String get scmOpenFile => '打开文件';

  @override
  String get scmOpenChanges => '打开更改';

  @override
  String get scmOpenFileHead => '打开文件(HEAD)';

  @override
  String get scmAddToGitignore => '添加到 .gitignore';

  @override
  String get scmInput => '源代码管理输入';

  @override
  String scmMessagePlaceholder(String keybinding) {
    return '消息(按 $keybinding 提交)';
  }

  @override
  String scmMessagePlaceholderBranch(String keybinding, String branch) {
    return '消息(按 $keybinding 在“$branch”上提交)';
  }

  @override
  String get scmGenerateCommitMessage => '生成提交消息';

  @override
  String get scmCancelGenerateCommitMessage => '取消生成提交消息';

  @override
  String get scmNoChangesToGenerate => '没有可用于生成提交消息的更改。';

  @override
  String get scmPublishBranch => '发布 Branch';

  @override
  String scmPublishBranchNamed(String branch) {
    return '发布 Branch“$branch”';
  }

  @override
  String scmPublishingBranchNamed(String branch) {
    return '正在发布 Branch“$branch”...';
  }

  @override
  String get scmSyncChanges => '同步更改';

  @override
  String get scmSynchronizeChanges => '同步更改';

  @override
  String get scmSynchronizingChanges => '正在同步更改...';

  @override
  String get scmFetch => '获取';

  @override
  String get scmFetchFromAllRemotes => '从所有远程获取';

  @override
  String get scmPull => '拉取';

  @override
  String get scmPush => '推送';

  @override
  String scmPullCommits(int count, String upstream) {
    return '从 $upstream 拉取 $count 个提交';
  }

  @override
  String scmPushCommits(int count, String upstream) {
    return '将 $count 个提交推送到 $upstream';
  }

  @override
  String scmPullPushCommits(int behind, int ahead, String upstream) {
    return '在 $upstream 之间拉取 $behind 个提交并推送 $ahead 个提交';
  }

  @override
  String scmConfirmSync(String upstream) {
    return '此操作将从“$upstream”拉取提交并向其推送提交。';
  }

  @override
  String get scmDontShowAgain => '确定，且不再显示';

  @override
  String get scmNoRemotes => '仓库未配置任何要发布到的远程仓库。';

  @override
  String get scmProvideMessage => '请提供提交消息';

  @override
  String get scmNoStagedChanges => '没有可提交的暂存更改。\n\n是否要暂存所有更改并直接提交?';

  @override
  String get scmAlways => '始终';

  @override
  String get scmNever => '从不';

  @override
  String get scmNoChangesToCommit => '没有要提交的更改。';

  @override
  String get scmCreateEmptyCommit => '创建空提交';

  @override
  String get scmCantUndo => '无法撤消，因为 HEAD 不指向任何提交。';

  @override
  String get scmConfirmUndoMerge => '上次提交是合并提交。确定要撤消它吗?';

  @override
  String get scmUndoMergeCommit => '撤消合并提交';

  @override
  String get scmIrreversibleFile => '此操作不可撤消!\n如果继续操作，此文件将永久丢失。';

  @override
  String get scmIrreversibleFiles => '此操作不可撤消!\n如果继续操作，这些文件将永久丢失。';

  @override
  String get scmIrreversibleWorkingSet => '此操作不可撤消!\n如果继续操作，你当前的工作集将永久丢失。';

  @override
  String scmConfirmDeleteUntracked(String name) {
    return '确定要删除以下未跟踪的文件吗: \'$name\'?';
  }

  @override
  String scmConfirmDeleteUntrackedCount(int count) {
    return '确定要删除这 $count 个未跟踪的文件吗?';
  }

  @override
  String get scmRestoreFilesFromTrash => '可以从回收站中还原这些文件。';

  @override
  String get scmDeleteFile => '删除文件';

  @override
  String scmDeleteAllFiles(int count) {
    return '删除全部 $count 个文件';
  }

  @override
  String scmConfirmRestore(String name) {
    return '确定要还原 \'$name\' 吗?';
  }

  @override
  String scmConfirmRestoreAll(int count) {
    return '确定要还原全部 $count 个文件吗?';
  }

  @override
  String scmConfirmDiscard(String name) {
    return '确定要放弃 \'$name\' 中的更改吗?';
  }

  @override
  String scmConfirmDiscardAll(int count) {
    return '确定要放弃 $count 个文件中的全部更改吗?';
  }

  @override
  String get scmRestoreFile => '还原文件';

  @override
  String scmRestoreAllFiles(int count) {
    return '还原全部 $count 个文件';
  }

  @override
  String get scmDiscardFile => '放弃文件';

  @override
  String scmDiscardAllFiles(int count) {
    return '放弃全部 $count 个文件';
  }

  @override
  String scmDiscardTrackedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '放弃全部 $count 个已跟踪的文件',
      one: '放弃 1 个已跟踪的文件',
    );
    return '$_temp0';
  }

  @override
  String get scmCopyCommitHash => '复制提交哈希';

  @override
  String get scmCopyCommitMessage => '复制提交消息';

  @override
  String get scmIncomingChanges => '传入的更改';

  @override
  String get scmOutgoingChanges => '传出的更改';

  @override
  String scmCommitDate(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String period,
  ) {
    String _temp0 = intl.Intl.selectLogic(period, {'am': '上午', 'other': '下午'});
    return '$year年$month月$day日 $_temp0$hour:$minute';
  }

  @override
  String get gitCheckoutBranchTag => '签出分支/标记...';

  @override
  String get gitSelectBranchOrTag => '选择要签出的分支或标记';

  @override
  String get gitSelectBranchDetached => '选择要在分离模式下签出的分支';

  @override
  String get gitCreateBranch => '创建新分支...';

  @override
  String get gitCreateBranchFrom => '创建新分支依据...';

  @override
  String get gitCheckoutDetached => '签出已分离...';

  @override
  String get gitBranches => '分支';

  @override
  String get gitRemoteBranches => '远程分支';

  @override
  String get gitTags => '标记';

  @override
  String gitRemoteBranchAt(String commit) {
    return '$commit 处的远程分支';
  }

  @override
  String gitTagAt(String commit) {
    return '$commit 处的标记';
  }

  @override
  String get gitSelectRefToBranchFrom => '选择一个 ref 以从中创建分支';

  @override
  String get gitBranchName => '分支名称';

  @override
  String get gitProvideBranchName => '请提供新的分支名称';

  @override
  String gitBranchExists(String name) {
    return '分支“$name”已存在';
  }

  @override
  String gitNewBranchWillBe(String name) {
    return '新分支将为“$name”';
  }

  @override
  String get timelineCopyCommitId => '复制提交 ID';

  @override
  String get timelineNoEditor => '活动编辑器无法提供时间线信息。';

  @override
  String get timelineNotConfigured => '未提供时间线信息。尚未配置源代码管理。';

  @override
  String timelineLoading(String name) {
    return '正在加载 $name 的时间线...';
  }

  @override
  String get timelineNone => '未提供时间线信息。';

  @override
  String get timelineLoadMore => '加载更多';

  @override
  String timelineYou(String time) {
    return '你，$time';
  }

  @override
  String get commonExpandAll => '全部展开';

  @override
  String get searchTitle => '搜索';

  @override
  String get searchClearResults => '清除搜索结果';

  @override
  String searchMatchCase(String keybinding) {
    return '区分大小写($keybinding)';
  }

  @override
  String searchMatchWholeWord(String keybinding) {
    return '全字匹配($keybinding)';
  }

  @override
  String searchUseRegExp(String keybinding) {
    return '使用正则表达式($keybinding)';
  }

  @override
  String searchPreserveCase(String keybinding) {
    return '保留大小写($keybinding)';
  }

  @override
  String get searchReplace => '替换';

  @override
  String get searchReplaceAll => '全部替换';

  @override
  String searchReplaceKeys(String keybinding) {
    return '替换($keybinding)';
  }

  @override
  String searchReplaceAllKeys(String keybinding) {
    return '全部替换($keybinding)';
  }

  @override
  String get searchDismiss => '消除';

  @override
  String searchDismissKeys(String keybinding) {
    return '消除($keybinding)';
  }

  @override
  String get searchCopyAll => '全部复制';

  @override
  String get searchToggleReplace => '切换替换';

  @override
  String get searchToggleDetails => '切换搜索详细信息';

  @override
  String get searchFilesToInclude => '包含的文件';

  @override
  String get searchFilesToExclude => '排除的文件';

  @override
  String get searchIncludeExample => '例如 *.ts, src/**/include';

  @override
  String get searchExcludeExample => '例如 *.ts, src/**/exclude';

  @override
  String get searchUseExcludeSettings => '使用“排除设置”与“忽略文件”';

  @override
  String get searchLimitHit => '结果集仅包含所有匹配项的子集。请使搜索更加具体，以缩小结果范围。';

  @override
  String searchResultCount(int matches, int files) {
    return '$files 个文件中有 $matches 个结果';
  }

  @override
  String searchNoResultsIncludeExclude(String include, String exclude) {
    return '在“$include”中找不到结果(“$exclude”除外)';
  }

  @override
  String searchNoResultsInclude(String include) {
    return '在“$include”中找不到结果';
  }

  @override
  String searchNoResultsExclude(String exclude) {
    return '除“$exclude”外，找不到任何结果';
  }

  @override
  String get searchNoResults => '未找到结果。请查看设置中配置的排除项，并检查 gitignore 文件';

  @override
  String searchOccurrences(int occurrences, int files) {
    return '$files 个文件中的 $occurrences 个匹配项';
  }

  @override
  String searchConfirmReplace(String counts) {
    return '是否替换 $counts?';
  }

  @override
  String searchConfirmReplaceWith(String counts, String value) {
    return '是否将 $counts 替换为“$value”?';
  }

  @override
  String searchReplaced(String counts) {
    return '已替换 $counts。';
  }

  @override
  String searchReplacedWith(String counts, String value) {
    return '已将 $counts 替换为“$value”。';
  }

  @override
  String get extTitle => '扩展';

  @override
  String get extTitleInstalled => '扩展: 已安装';

  @override
  String get extTitleRecommended => '扩展: 推荐';

  @override
  String get extTitleMarketplace => '扩展: 商店';

  @override
  String get extFilter => '筛选扩展...';

  @override
  String get extInstalled => '已安装';

  @override
  String get extRecommended => '推荐';

  @override
  String get extClearSearch => '清除扩展搜索结果';

  @override
  String get extSearchPlaceholder => '在商店中搜索扩展';

  @override
  String get extNoneFound => '找不到扩展。';

  @override
  String get extInstall => '安装';

  @override
  String get extUninstall => '卸载';

  @override
  String get extInstalling => '正在安装';

  @override
  String get extUninstalling => '正在卸载';

  @override
  String get extManage => '管理';

  @override
  String get extCopyId => '复制扩展 ID';

  @override
  String extInstallError(String id, String error) {
    return '安装“$id”扩展时出错。$error';
  }

  @override
  String extUninstallError(String id, String error) {
    return '卸载“$id”扩展时出错。$error';
  }

  @override
  String get extLanguageServer => '语言服务器';

  @override
  String extLanguageServerFor(String languages) {
    return '适用于 $languages 的语言服务器';
  }

  @override
  String extMissingRuntime(String id, String runtime) {
    return '安装“$id”需要 $runtime，但未找到。请先安装 $runtime，然后重试。';
  }

  @override
  String extUnavailable(String id) {
    return '在 PATH 中找不到“$id”，且无法自动安装。';
  }

  @override
  String langStarting(String id) {
    return '$id: 正在启动…';
  }

  @override
  String langStartingTooltip(String id) {
    return '正在启动 $id';
  }

  @override
  String langRunning(String id) {
    return '$id 正在运行';
  }

  @override
  String langRestarting(String id) {
    return '$id: 正在重启…';
  }

  @override
  String get langClickToRestart => '单击以立即重启';

  @override
  String langFailed(String id) {
    return '$id 失败';
  }

  @override
  String get langClickToRetry => '单击以重试';

  @override
  String langInstallingItem(String id) {
    return '正在安装 $id…';
  }

  @override
  String langInstallingTooltip(String id) {
    return '正在安装 $id';
  }

  @override
  String langNoneFound(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': '未找到定义',
      'typeDefinition': '未找到类型定义',
      'implementation': '未找到实现',
      'other': '未找到引用',
    });
    return '$_temp0';
  }

  @override
  String langNoneFoundFor(String kind, String word) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': '未找到“$word”的定义',
      'typeDefinition': '未找到“$word”的类型定义',
      'implementation': '未找到“$word”的实现',
      'other': '未找到“$word”的引用',
    });
    return '$_temp0';
  }

  @override
  String get langReferences => '引用';

  @override
  String langReferencesTo(String word) {
    return '“$word”的引用';
  }

  @override
  String get langDefinitions => '定义';

  @override
  String get langTypeDefinitions => '类型定义';

  @override
  String get langImplementations => '实现';

  @override
  String get langCantRename => '无法重命名此元素。';

  @override
  String langRenameFailed(String error) {
    return '重命名失败: $error';
  }

  @override
  String get langNoResult => '无结果。';

  @override
  String get langRenameCancelled => '文档已更改，重命名已取消。';

  @override
  String get langRenameNotApplied => '无法应用重命名。';

  @override
  String get langNoSelectionFormatter => '此文件没有可用于所选内容的格式化程序。';

  @override
  String get langNoFormatter => '此文件没有格式化程序。';

  @override
  String langNoFormatterInstall(String id, String language) {
    return '此文件没有格式化程序。安装“$id”语言服务器后即可格式化 $language 文件。';
  }

  @override
  String get langNoRefactorings => '没有可用的重构操作';

  @override
  String get langNoSourceActions => '没有可用的源代码操作';

  @override
  String get langNoCodeActions => '没有可用的代码操作';

  @override
  String get langCodeActionNotApplied => '无法应用此代码操作。';

  @override
  String get langShowCodeActions => '显示代码操作';

  @override
  String get langLoading => '正在加载...';

  @override
  String get langNoSuggestions => '无建议。';

  @override
  String get langPreferred => '首选';

  @override
  String get langRenameHint => '按 Enter 重命名，按 Esc 取消';

  @override
  String get symbolsNoEditor => '要转到符号，请先打开包含符号信息的文本编辑器。';

  @override
  String get symbolsLoading => '正在加载符号…';

  @override
  String get symbolsNone => '没有编辑器符号';

  @override
  String get symbolsNoMatching => '没有匹配的编辑器符号';

  @override
  String get outlineTitle => '大纲';

  @override
  String get outlineNoEditor => '活动编辑器无法提供大纲信息。';

  @override
  String get outlineNoSymbols => '在文档中找不到符号。';

  @override
  String get outlineLoading => '正在加载文档符号…';

  @override
  String get panelProblems => '问题';

  @override
  String get panelReferences => '引用';

  @override
  String get panelTerminal => '终端';

  @override
  String get panelClose => '关闭面板';

  @override
  String get panelTerminalUnavailable => '终端不可用。';

  @override
  String get problemsNone => '未在工作区检测到问题。';

  @override
  String problemsPosition(int line, int column) {
    return '[行 $line，列 $column]';
  }

  @override
  String referencesPosition(int line, int column) {
    return '行 $line，列 $column';
  }

  @override
  String get referencesNone => '尚无引用: 请使用“转到引用”(⇧F12)。';

  @override
  String referencesSummary(String title, int count, int files) {
    return '$title — $files 个文件中有 $count 个结果';
  }

  @override
  String get termRename => '重命名...';

  @override
  String get termKillTerminal => '终止终端';

  @override
  String get termNewTerminal => '新建终端';

  @override
  String termNewTerminalKeys(String keybinding) {
    return '新建终端($keybinding)';
  }

  @override
  String get termLaunchProfile => '启动配置文件...';

  @override
  String termProfileDefault(String name) {
    return '$name (默认)';
  }

  @override
  String get termSelectDefaultProfile => '选择默认配置文件';

  @override
  String get termSelectProfileToCreate => '选择要创建的终端配置文件';

  @override
  String get termChooseDefaultProfile => '选择默认终端配置文件';

  @override
  String get termProfilesGroup => '配置文件';

  @override
  String get termProfilesDetected => '已检测到';

  @override
  String get cmdTerminalNewWithProfile => '创建新终端(使用配置文件)';

  @override
  String get termKill => '终止';

  @override
  String termKillKeys(String keybinding) {
    return '终止($keybinding)';
  }

  @override
  String get termRenameEmpty => '不提供名称会将其重置为默认值';

  @override
  String get termRenameLabel => '键入终端名称。按 Enter 确认或按 Esc 取消。';

  @override
  String get termRerunCommand => '重新运行命令';

  @override
  String get termCopyCommand => '复制命令';

  @override
  String get termCopyOutput => '复制输出';

  @override
  String get termClear => '清除';

  @override
  String get termPasteAsOneLine => '粘贴为一行';

  @override
  String termPasteConfirm(int count) {
    return '确定要将 $count 行文本粘贴到终端吗?';
  }

  @override
  String get commonSave => '保存';

  @override
  String get commonDontSave => '不保存';

  @override
  String wbConfirmSave(String name) {
    return '是否要保存对 $name 的更改?';
  }

  @override
  String wbHeadNotAvailable(String name) {
    return '“$name”的 HEAD 版本不可用。';
  }

  @override
  String wbRecommendServer(String id, String language) {
    return '是否要为 $language 语言安装推荐的“$id”语言服务器?';
  }

  @override
  String get wbDontShowAgainServer => '不再针对此语言服务器显示';

  @override
  String get wbQuickCommands => '键入要运行的命令的名称。';

  @override
  String get wbQuickSymbols => '键入要转到的符号的名称。';

  @override
  String get wbQuickFiles => '按名称搜索文件(追加 : 转到行，追加 > 运行命令)';

  @override
  String get quickInputEntry => '按 \"Enter\" 以确认或按 \"Esc\" 以取消';

  @override
  String quickInputEntryWithPrompt(String prompt) {
    return '$prompt (按 \"Enter\" 以确认或按 \"Esc\" 以取消)';
  }

  @override
  String wbChordWaiting(String chord) {
    return '已按下($chord)。正在等待按下第二个键...';
  }

  @override
  String wbChordNotCommand(String chord, String keypress) {
    return '组合键($chord，$keypress)不是命令。';
  }

  @override
  String get wbExplorer => '资源管理器';

  @override
  String get wbSearchFiles => '搜索文件';

  @override
  String wbPendingChanges(int count) {
    return '$count 个挂起的更改';
  }

  @override
  String get wbOutline => '大纲';

  @override
  String get wbTimeline => '时间线';

  @override
  String get wbPinTimeline => '固定当前时间线';

  @override
  String get wbUnpinTimeline => '取消固定当前时间线';

  @override
  String get wbNoProblems => '没有问题';

  @override
  String wbProblemCounts(int errors, int warnings) {
    return '错误: $errors，警告: $warnings';
  }

  @override
  String wbProblemCountsInfos(int errors, int warnings, int infos) {
    return '错误: $errors，警告: $warnings，信息: $infos';
  }

  @override
  String wbSelectedCount(int count) {
    return '(已选择 $count)';
  }

  @override
  String get wbGoToLineColumn => '转到行/列';

  @override
  String wbSpaces(int size) {
    return '空格: $size';
  }

  @override
  String wbTabSize(int size) {
    return '制表符长度: $size';
  }

  @override
  String get wbIndentation => '缩进';

  @override
  String get wbEncoding => '编码';

  @override
  String get wbEolMixed => '混合';

  @override
  String get wbSelectEol => '选择行尾序列';

  @override
  String get wbEditorReadOnly => '活动代码编辑器为只读模式。';

  @override
  String get wbLanguageMode => '语言模式';

  @override
  String get shownImage => '图片';

  @override
  String get shownReadOnly => '只读';

  @override
  String get languageModeAuto => '自动检测';

  @override
  String get languageModePlaceholder => '选择语言模式';

  @override
  String get languageModeChange => '更改语言模式';

  @override
  String get editorCommandPalette => '命令面板...';

  @override
  String get editorStartTyping => '开始键入…';

  @override
  String editorEditLanguage(String language) {
    return '编辑 $language…';
  }

  @override
  String get workspaceClosePane => '关闭窗格';

  @override
  String get workspaceLoadingProjects => '正在加载项目…';

  @override
  String get workspaceDesktopOnly => '智能体在桌面应用中运行';

  @override
  String get workspaceDesktopOnlyDetail => 'Claude Code 以本地进程运行，浏览器无法启动它。';

  @override
  String get workspaceOpenProjectFolder => '打开项目文件夹';

  @override
  String get workspaceOpenProjectFolderDetail =>
      '其中的 Claude Code 会话显示在侧边栏中；新智能体也在其中运行。';

  @override
  String settingsFileError(String file, String error) {
    return '无法应用 $file: $error。在修复之前，上次从中读取的内容仍然有效。';
  }

  @override
  String get cmdLastEditorInGroup => '打开组中最后一个编辑器';

  @override
  String get cmdToggleFormatOnSave => '切换保存时格式化';

  @override
  String get cmdToggleGitBlameEditorDecoration => '切换 Git 追溯编辑器修饰';

  @override
  String get kbSourceDefault => '默认';

  @override
  String get kbSourceUser => '用户';

  @override
  String get kbKeymap => '键盘映射方案';

  @override
  String kbKeymapLabel(String name) {
    return '键盘映射方案: $name';
  }

  @override
  String get kbNone => '无';

  @override
  String get kbImport => '从 VS Code/Cursor 导入…';

  @override
  String kbWhenNotParse(String error) {
    return 'when 子句无法解析($error): 此快捷键永远不会生效。';
  }

  @override
  String kbUnknownContextKeys(int count, String keys) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'BaoCode 无法识别上下文键 $keys: 此快捷键永远不会生效。',
    );
    return '$_temp0';
  }

  @override
  String kbChangeFailed(String error) {
    return '无法更改快捷键($error)。请打开 keybindings.json 并检查其中的错误。';
  }

  @override
  String get kbCopyCommandId => '复制命令 ID';

  @override
  String get kbCopyCommandTitle => '复制命令标题';

  @override
  String get kbChangeKeybindingEllipsis => '修改快捷键…';

  @override
  String get kbAddKeybindingEllipsis => '添加快捷键…';

  @override
  String get kbChangeKeybinding => '修改快捷键';

  @override
  String get kbAddKeybinding => '添加快捷键';

  @override
  String get kbRemoveKeybinding => '移除快捷键';

  @override
  String get kbResetKeybinding => '重置快捷键';

  @override
  String get kbChangeWhen => '修改 When 表达式';

  @override
  String get kbShowSame => '查看相同快捷键';

  @override
  String get kbRecordingPlaceholder => '正在录制按键。按 Esc 退出';

  @override
  String get kbSearchPlaceholder => '键入以在快捷键中搜索';

  @override
  String get kbSearchLabel => '搜索快捷键';

  @override
  String kbRecordKeys(String keybinding) {
    return '录制按键($keybinding)';
  }

  @override
  String get kbRecordingKeys => '正在录制按键';

  @override
  String get kbColumnCommand => '命令';

  @override
  String get kbColumnKeybinding => '快捷键';

  @override
  String get kbColumnWhen => 'When';

  @override
  String get kbColumnSource => '来源';

  @override
  String get kbWhenLabel => 'When 表达式';

  @override
  String get kbNoneFound => '未找到快捷键';

  @override
  String kbCannotReadKey(String key) {
    return 'BaoCode 无法识别按键“$key”: 此快捷键永远不会生效。';
  }

  @override
  String get kbNotSupported => '不支持';

  @override
  String get kbNotSupportedHover => 'BaoCode 没有此命令: 快捷键会保留，但不起作用。';

  @override
  String get kbPressKeys => '先按所需的组合键，再按 Enter 键。';

  @override
  String get kbChordTo => '再按';

  @override
  String kbExistingCommands(int count) {
    return '已有 $count 个命令使用此快捷键';
  }

  @override
  String get dataDirFullPath => '请选择完整路径。';

  @override
  String get dataDirInUse => '这是正在使用的文件夹。';

  @override
  String get dataDirInsideCurrent => '新文件夹不能位于正在使用的文件夹内。';

  @override
  String get dataDirContainsCurrent => '新文件夹不能包含正在使用的文件夹。';

  @override
  String dataDirCannotMake(String error) {
    return '无法创建文件夹: $error';
  }

  @override
  String dataDirNotThere(String path) {
    return '文件夹 $path 不存在。';
  }

  @override
  String dataDirNotFolder(String path) {
    return '$path 不是文件夹。';
  }

  @override
  String dataDirNotWritable(String path) {
    return '无法在 $path 中写入文件。';
  }

  @override
  String get dataDirRevealInFileExplorer => '在文件资源管理器中显示';

  @override
  String get dataDirRevealInFileManager => '在文件管理器中显示';

  @override
  String get dataDirChecking => '正在检查文件夹…';

  @override
  String get dataDirAlreadyHolds => '该文件夹中已有 BaoCode 数据';

  @override
  String get dataDirMoveBack => '将 BaoCode 的数据移回默认文件夹?';

  @override
  String get dataDirMoveHere => '将 BaoCode 的数据移到此文件夹?';

  @override
  String get dataDirUseAsIsDetail =>
      '重启后 BaoCode 将直接使用那里的数据；不会复制任何内容，当前文件夹中的数据保持不变。';

  @override
  String get dataDirCopyDetail =>
      'BaoCode 会将其设置、快捷键、语言服务器和状态复制到那里，并在重启后使用该文件夹。';

  @override
  String get dataDirOtherFiles => '该文件夹中还有其他文件: 它们会保留，与 BaoCode 自己的文件并存。';

  @override
  String get dataDirUseItsData => '使用其中的数据';

  @override
  String get dataDirCopyAndSwitch => '复制并切换';

  @override
  String get dataDirCopying => '正在复制…';

  @override
  String dataDirCopyingProgress(int done, int total) {
    return '正在复制… $done/$total 个文件';
  }

  @override
  String dataDirMoveFailed(String error) {
    return '无法移动数据: $error';
  }

  @override
  String dataDirMoveInUse(String path) {
    return '$path 正被其他程序占用。请关闭该程序后重试。';
  }

  @override
  String get dataDirRestartTitle => '重启 BaoCode 以使用新的数据文件夹';

  @override
  String dataDirRestartDetail(String current, String next) {
    return 'BaoCode 在重启前会继续使用 $current。下次启动时将使用 $next，并询问是否移除旧文件夹中剩余的内容。';
  }

  @override
  String get dataDirTheNewFolder => '新文件夹';

  @override
  String get quitConfirmMessage => '要退出 BaoCode 吗？';

  @override
  String get quitConfirmDetail => '正在运行的 Agent 和终端会一并停止。';

  @override
  String get quitConfirmQuit => '退出';

  @override
  String get dataDirQuitNow => '立即退出';

  @override
  String get dataDirLater => '稍后';

  @override
  String dataDirSetByEnv(String variable) {
    return '由环境变量 $variable 设置。';
  }

  @override
  String dataDirSetIn(String file) {
    return '在 $file 中设置。';
  }

  @override
  String get dataDirDefaultLocation => '默认位置。';

  @override
  String dataDirTemporaryDefault(String file) {
    return '默认位置(仅本次): $file 中设置的文件夹不可用。';
  }

  @override
  String get dataDirTitle => '数据文件夹';

  @override
  String get dataDirDescription =>
      'BaoCode 存放你的设置、快捷键、语言服务器及其自身状态的位置。其他程序也会在此存放文件(如网页视图的缓存)；BaoCode 从不移动或删除这些文件。';

  @override
  String get dataDirCurrentFolder => '当前文件夹';

  @override
  String get dataDirNewFolder => '新文件夹';

  @override
  String dataDirAfterRestart(String path) {
    return '重启后: $path';
  }

  @override
  String get dataDirChange => '更改…';

  @override
  String get dataDirResetDefault => '恢复默认';

  @override
  String dataDirEnvDecides(String variable) {
    return '文件夹由 $variable 决定；取消设置该变量后才能在此选择。';
  }

  @override
  String dataDirCannotWritePointer(String file, String error) {
    return '无法写入 $file: $error';
  }

  @override
  String get dataDirSettingUnreadable => '无法读取 BaoCode 的数据文件夹设置';

  @override
  String get dataDirCannotWrite => 'BaoCode 无法写入其数据文件夹';

  @override
  String get dataDirUnavailable => 'BaoCode 的数据文件夹不可用';

  @override
  String dataDirWhereEnv(String variable) {
    return '它由环境变量 $variable 设置。';
  }

  @override
  String dataDirWhereFixPointer(String file) {
    return '请修复或删除 $file 后重试；只有在你选择其他文件夹时 BaoCode 才会更改它。';
  }

  @override
  String dataDirWherePointer(String file) {
    return '它在 $file 中设置。如果它位于未连接的驱动器上，请连接后重试。';
  }

  @override
  String dataDirDefaultIs(String path) {
    return '默认文件夹为 $path。';
  }

  @override
  String get dataDirRetry => '重试';

  @override
  String get dataDirUseDefaultOnce => '本次使用默认文件夹';

  @override
  String get dataDirChooseAnother => '选择其他文件夹…';

  @override
  String get dataDirRemoveOldTitle => '是否移除 BaoCode 留在之前文件夹中的数据?';

  @override
  String dataDirRemoveOldDetail(String current, String items) {
    return 'BaoCode 现在将数据存放在 $current。只会从之前的文件夹中移除它自己的项目($items)；该文件夹及其中的其他内容都会保留。';
  }

  @override
  String get dataDirRemove => '移除';

  @override
  String get dataDirKeep => '保留';

  @override
  String get dataDirRemoveOldInUse => '部分旧数据未能移除';

  @override
  String dataDirRemoveOldInUseDetail(String items) {
    return '$items 中有文件正在使用(可能被其他程序占用)。其余内容均已移除；BaoCode 下次启动时会再次询问是否移除剩下的部分。';
  }

  @override
  String get impTitle => '导入快捷键';

  @override
  String get impImport => '导入';

  @override
  String get impNothingFound =>
      '未找到 Visual Studio Code、Cursor、Windsurf 或 VSCodium 的快捷键或键盘映射方案。';

  @override
  String get impKeybindingsFrom => '快捷键来源';

  @override
  String impKeybindingCount(int count) {
    return '$count 条快捷键';
  }

  @override
  String get impImportAs => '导入方式';

  @override
  String get impMerge => '与我的快捷键合并';

  @override
  String get impMergeDetail => '将你没有的快捷键添加到你的快捷键之后。';

  @override
  String get impReplace => '替换我的快捷键';

  @override
  String get impReplaceDetail => '按原样复制文件(包括注释)。你的文件将保留为 keybindings.json.bak。';

  @override
  String impAlsoUse(String name) {
    return '同时导入并使用 $name';
  }

  @override
  String impInstalledIn(String products) {
    return '安装于 $products';
  }

  @override
  String impImportedFrom(String source) {
    return '已从 $source 导入';
  }

  @override
  String impApplied(int supported) {
    return '生效 $supported 条';
  }

  @override
  String impAppliedUnsupported(int supported, int unsupported) {
    return '生效 $supported 条，$unsupported 条命令暂不支持';
  }

  @override
  String impDuplicates(int count) {
    return '已跳过 $count 条你已有的快捷键。';
  }

  @override
  String impBackup(String path) {
    return '你之前的快捷键: $path';
  }

  @override
  String get impNotSupportedYet => '暂不支持';

  @override
  String get impNotSupportedDetail =>
      '这些快捷键会保留在 keybindings.json 中，待应用支持相应命令后即可生效。';

  @override
  String impKeymapBuiltIn(String name) {
    return '键盘映射方案: $name 为内置方案，现已启用。';
  }

  @override
  String impKeymapImported(String name) {
    return '键盘映射方案: $name 已导入，现已启用。';
  }

  @override
  String impKeybindingsError(String error) {
    return '无法导入快捷键: $error';
  }

  @override
  String impKeymapError(String name, String error) {
    return '无法导入 $name: $error';
  }

  @override
  String get explorerNoFolderTitle => '无打开的文件夹';

  @override
  String get explorerNoFolder => '尚未打开文件夹。';

  @override
  String get explorerOpenFolder => '打开文件夹';

  @override
  String get ideSearchOpenFiles => '搜索已打开的文件';

  @override
  String get ideWelcomeRecent => '最近';

  @override
  String get ideStartRecent => '最近的项目';

  @override
  String ideStartViewAll(int count) {
    return '查看全部（$count）';
  }

  @override
  String get ideOpenRecentPlaceholder => '选择要打开的文件夹或文件';

  @override
  String get ideRecentFolders => '文件夹';

  @override
  String get ideRecentFiles => '文件';

  @override
  String get ideNoRecent => '没有最近打开的文件夹或文件';

  @override
  String get ideClearRecentConfirm => '是否要清除所有最近打开的文件和文件夹?';

  @override
  String get ideClearRecentDetail => '此操作不可逆!';

  @override
  String get ideClearRecent => '清除';

  @override
  String get ideChatNoFolder => '打开文件或文件夹后，即可与智能体对话。';

  @override
  String ideCannotOpen(String path, String error) {
    return '无法打开 $path：$error';
  }

  @override
  String get cmdNewUntitledFile => '新建文本文件';

  @override
  String get cmdOpenFile => '打开文件...';

  @override
  String get cmdOpenFolder => '打开文件夹...';

  @override
  String get cmdOpenRecent => '打开最近的文件...';

  @override
  String get cmdSaveAs => '另存为...';

  @override
  String get cmdMarkdownShowPreview => '打开预览';

  @override
  String get cmdMarkdownShowSource => '显示源码';

  @override
  String get cmdCloseFolder => '关闭文件夹';

  @override
  String get cmdClearRecentlyOpened => '清除最近打开...';

  @override
  String cmdInstallShellCommand(String name) {
    return '在 PATH 中安装“$name”命令';
  }

  @override
  String cmdUninstallShellCommand(String name) {
    return '从 PATH 中卸载“$name”命令';
  }

  @override
  String get cmdCategoryWorkspaces => '工作区';

  @override
  String get cmdCategoryShellCommand => 'Shell 命令';

  @override
  String shellCommandInstalled(String name) {
    return '已成功在 PATH 中安装了 Shell 命令“$name”。';
  }

  @override
  String shellCommandUninstalled(String name) {
    return '已成功从 PATH 卸载了 Shell 命令“$name”。';
  }

  @override
  String shellCommandOccupied(String path, String name) {
    return '$path 已是其他应用的“$name”命令。要替换为 BaoCode 的吗?';
  }

  @override
  String get shellCommandReplace => '替换';

  @override
  String shellCommandFailed(String name, String error) {
    return '无法安装 Shell 命令“$name”：$error';
  }

  @override
  String shellCommandUninstallFailed(String name, String error) {
    return '无法卸载 Shell 命令“$name”：$error';
  }

  @override
  String get generalSettingsMainWindow => '启动时打开';

  @override
  String get generalSettingsMainWindowDescription =>
      'BaoCode 启动时打开 Agent 还是 IDE 窗口（IDE 窗口按“恢复窗口”恢复），二者不会同时出现。默认是上次退出时所在的那个。';

  @override
  String generalSettingsMainWindowLabel(String name) {
    return '启动时打开：$name';
  }

  @override
  String get generalSettingsMainWindowChat => '固定 Agent';

  @override
  String get generalSettingsMainWindowIde => '固定 IDE';

  @override
  String get generalSettingsMainWindowLast => '最后离开';

  @override
  String get generalSettingsWindows => '窗口';

  @override
  String get generalSettingsIde => 'Fast IDE';

  @override
  String get explorerExcludeSetting => '隐藏的文件和文件夹';

  @override
  String get explorerExcludeSettingDescription =>
      '资源管理器中不显示的文件和文件夹，用逗号分隔：文件名（`node_modules`、`*.log`）匹配任意位置，路径（`build/**`、`src/generated`）匹配所在文件夹内的位置。';

  @override
  String get explorerExcludeSettingPlaceholder =>
      '例如 .git, node_modules, *.log';

  @override
  String get claudePathSetting => '路径';

  @override
  String get claudePathSettingDescription =>
      '留空则自动用本机最新版本的 Claude Code，没有时自动下载。填入路径则固定用那一份，比如你自己编译的版本。（claudeCode.path）';

  @override
  String get claudePathSettingHint => '自动';

  @override
  String get claudePathChecking => '正在检查…';

  @override
  String claudePathInUse(String path, String version) {
    return '当前使用：$path（$version）';
  }

  @override
  String claudePathInUseUnknown(String path) {
    return '当前使用：$path';
  }

  @override
  String claudePathInUseDownloaded(String version) {
    return '当前使用：BaoCode 下载的 Claude Code $version';
  }

  @override
  String get claudePathMissing => '尚未找到：开始第一个对话时会自动下载 Claude Code。';

  @override
  String get generalSettingsIdeWindows => 'Fast Ide 窗口';

  @override
  String get generalSettingsIdeWindowsDescription =>
      'Fast Ide 在哪里打开：在主窗口中替换对话，一次一个文件夹；或独立窗口，每个文件夹一个（新建窗口 ⇧⌘N / Ctrl+Shift+N 打开一个空窗口）。立即生效。（window.ideWindows）';

  @override
  String get generalSettingsIdeWindowsSeparate => '独立窗口';

  @override
  String get generalSettingsIdeWindowsMain => '在主窗口中';

  @override
  String generalSettingsWindowLabel(String setting, String name) {
    return '$setting：$name';
  }

  @override
  String get generalSettingsOpenFolders => '在新窗口中打开文件夹';

  @override
  String get generalSettingsOpenFoldersDescription =>
      '从窗口里打开文件夹（打开文件夹…、打开最近的文件）时是否使用新窗口。默认替换当前窗口，按住 ⌘/Ctrl 时用新窗口。（window.openFoldersInNewWindow）';

  @override
  String get generalSettingsOpenFiles => '在新窗口中打开文件';

  @override
  String get generalSettingsOpenFilesDescription =>
      '从窗口里打开文件时是否使用新窗口。默认在当前窗口中打开。（window.openFilesInNewWindow）';

  @override
  String get generalSettingsOpenOn => '在新窗口中';

  @override
  String get generalSettingsOpenOff => '在当前窗口中';

  @override
  String get generalSettingsRestoreWindows => '恢复窗口';

  @override
  String get generalSettingsRestoreWindowsDescription =>
      '启动时重新打开哪些 IDE 窗口，各自回到原来的位置。（window.restoreWindows）';

  @override
  String get generalSettingsRestoreAll => '全部窗口';

  @override
  String get generalSettingsRestoreOne => '最近活动的窗口';

  @override
  String get generalSettingsRestoreFolders => '有文件夹的窗口';

  @override
  String get generalSettingsRestoreNone => '不恢复';

  @override
  String get generalSettingsNewWindowDimensions => '新窗口大小';

  @override
  String get generalSettingsNewWindowDimensionsDescription =>
      '新打开的窗口的大小。（window.newWindowDimensions）';

  @override
  String get generalSettingsDimensionsDefault => '默认';

  @override
  String get generalSettingsDimensionsInherit => '与最近活动的窗口相同';

  @override
  String get generalSettingsDimensionsMaximized => '最大化';

  @override
  String get generalSettingsDimensionsFullscreen => '全屏';

  @override
  String get generalSettingsConfirmBeforeClose => '关闭前确认';

  @override
  String get generalSettingsConfirmBeforeCloseDescription =>
      '关闭窗口前是否先询问，即使没有未保存的内容。（window.confirmBeforeClose）';

  @override
  String get generalSettingsConfirmNever => '从不';

  @override
  String get generalSettingsConfirmKeyboard => '用快捷键关闭时';

  @override
  String get generalSettingsConfirmAlways => '总是';

  @override
  String get cmdNewWindow => '新建窗口';

  @override
  String get cmdCloseWindow => '关闭窗口';

  @override
  String get cmdSwitchWindow => '切换窗口...';

  @override
  String get cmdShowChatWindow => '显示对话窗口';

  @override
  String get windowChatTitle => '对话';

  @override
  String get windowWelcomeTitle => '欢迎';

  @override
  String get windowConfirmClose => '确定要关闭窗口吗？';

  @override
  String get windowTerminateTerminals => '是否终止窗口中终端里正在运行的进程？';

  @override
  String get windowTerminate => '终止';

  @override
  String windowSaveChanges(int count) {
    return '是否保存对以下 $count 个文件的更改？';
  }

  @override
  String get windowSaveAll => '全部保存';

  @override
  String get windowCurrent => '当前';

  @override
  String get windowSwitchPlaceholder => '选择要切换到的窗口';

  @override
  String get windowCycle => '循环切换窗口';

  @override
  String get windowMenuWindows => '窗口';

  @override
  String get windowOpened => '已打开';

  @override
  String get generalSettingsShellCommand => 'Shell 命令';

  @override
  String generalSettingsShellCommandDescription(String location) {
    return '在终端中用“code <路径>”在 BaoCode 中打开文件和文件夹。安装位置：$location。';
  }

  @override
  String get generalSettingsShellCommandInstalled => '已安装';

  @override
  String get generalSettingsShellCommandNotInstalled => '未安装';

  @override
  String get generalSettingsShellCommandOccupied => '已安装其他应用的命令';

  @override
  String get generalSettingsShellCommandInstall => '安装';

  @override
  String get generalSettingsShellCommandUninstall => '卸载';

  @override
  String get menuMore => '更多…';

  @override
  String get sidebarSearch => '搜索';

  @override
  String get sidebarCustomize => '技能';

  @override
  String get sidebarOpenProject => '打开项目';

  @override
  String get palettePlaceholder => '搜索智能体、对话内容、文件、操作…';

  @override
  String get paletteFilterAll => '全部';

  @override
  String get paletteFilterAgents => '智能体';

  @override
  String get paletteFilterFiles => '文件';

  @override
  String get paletteFilterActions => '操作';

  @override
  String get paletteFilterSettings => '设置';

  @override
  String get paletteRecentAgents => '最近的智能体';

  @override
  String get paletteRecentActions => '最近的操作';

  @override
  String get paletteMessages => '对话内容';

  @override
  String paletteFilesIn(String project) {
    return '$project 中的文件';
  }

  @override
  String get paletteSearching => '正在搜索…';

  @override
  String get paletteNoResults => '无结果';

  @override
  String get paletteNoProject => '打开项目后可搜索其文件';

  @override
  String get paletteTypeToSearch => '输入以搜索';

  @override
  String get paletteHintSelect => '选择';

  @override
  String get paletteHintOpen => '打开';

  @override
  String get paletteHintChangeFilter => '切换筛选';

  @override
  String get customizeTitle => '自定义';

  @override
  String get customizeSearchPlaceholder => '搜索插件、技能、MCP…';

  @override
  String get customizeKindPlugins => '插件';

  @override
  String get customizeKindMcps => 'MCP';

  @override
  String get customizeKindSkills => '技能';

  @override
  String get customizeKindSubagents => '子智能体';

  @override
  String get customizeKindRules => '规则';

  @override
  String get customizeKindCommands => '命令';

  @override
  String get customizeKindHooks => '钩子';

  @override
  String get customizeScopeUser => '用户';

  @override
  String get customizeScopeProject => '项目';

  @override
  String get customizeScopeLocal => '本地';

  @override
  String get customizeScopePlugin => '已安装';

  @override
  String get customizeUserOnly => '仅用户';

  @override
  String get customizeNew => '新建';

  @override
  String get customizeEmpty => '暂无内容';

  @override
  String get customizeNoMatches => '无匹配项';

  @override
  String get customizeUnsupported => '自定义 Claude Code 需要桌面版应用。';

  @override
  String get customizeSave => '保存';

  @override
  String get customizeRevert => '还原';

  @override
  String get customizeSaved => '已保存';

  @override
  String get customizeUnsaved => '有未保存的更改';

  @override
  String get customizeEdit => '编辑';

  @override
  String get customizeReadOnly => '只读：此文件由 Claude Code 自行维护。';

  @override
  String get customizeEnabled => '已启用';

  @override
  String get customizeDisabled => '已停用';

  @override
  String get customizeBack => '返回';

  @override
  String get customizeClose => '关闭自定义';

  @override
  String customizeDeleteTitle(String name) {
    return '删除 $name？';
  }

  @override
  String customizeDeleteMessage(String path) {
    return '将删除 $path，且无法撤销。';
  }

  @override
  String customizeNewTitle(String kind) {
    return '新建$kind';
  }

  @override
  String get customizeNameHint => '名称';

  @override
  String get customizeNameInvalid =>
      '须以文字或数字开头，不能含空格和 / \\ : * ? \" < > |（最多 64 个）';

  @override
  String get customizeNameUnofficial => '官方规范只用小写字母、数字和 -，上传 claude.ai 可能被拒';

  @override
  String get customizeNameTaken => '已存在同名项';

  @override
  String get customizeCreate => '创建';

  @override
  String customizeLoadFailed(String error) {
    return '无法读取：$error';
  }

  @override
  String customizeSaveFailed(String error) {
    return '无法保存：$error';
  }

  @override
  String get settingsBack => '返回';

  @override
  String get settingsSearch => '搜索设置';

  @override
  String get customizeScopeSynced => '从 claude.ai 同步';

  @override
  String get customizeSyncedReadOnly => '只读：此技能从 claude.ai 同步，本地修改会在下次同步时被覆盖。';

  @override
  String customizeEditFile(String file) {
    return '编辑 $file';
  }

  @override
  String get customizeEmptyPlugins => '还没有安装插件。在 Claude Code 里用 /plugin 安装。';

  @override
  String get customizeEmptyMcpsUser =>
      '暂无。用这条命令添加：claude mcp add --scope user <名称> -- <命令>';

  @override
  String get customizeEmptyMcpsLocal => '暂无。在项目目录里运行 claude mcp add 添加。';

  @override
  String get customizeEmptyMcpsProject => '暂无。和项目共享的服务器写在项目的 .mcp.json 里。';

  @override
  String customizeEmptyHooks(String file) {
    return '暂无。钩子写在 $file 的 \"hooks\" 里。';
  }

  @override
  String get customizeConnectorReadOnly =>
      '只读：这是 claude.ai 连接器，请在 claude.ai 设置的「连接器」里管理。';

  @override
  String get settingsSectionModels => '模型';

  @override
  String get modelsTitle => '模型';

  @override
  String get modelsDefault => '新会话默认模型';

  @override
  String get modelsDefaultDescription => '未设置时，新会话沿用上次选择的模型。';

  @override
  String get modelsDefaultLast => '上次所选';

  @override
  String modelsChoiceLabel(String label, String value) {
    return '$label：$value';
  }

  @override
  String get modelsBuiltinName => 'Claude Code（跟随本机配置）';

  @override
  String get modelsBuiltinDefault => 'Claude Code 默认';

  @override
  String get modelsBuiltinBadge => '内置';

  @override
  String get modelsBuiltinDescription => '使用本机的登录和配置，不做任何改动';

  @override
  String get modelsProviders => '上游';

  @override
  String modelsEnableProvider(String name) {
    return '在模型选择中显示 $name';
  }

  @override
  String get modelsFeaturedWhy => '为什么我看到这个？';

  @override
  String get modelsFeaturedNote => '这些站点目前已经被官方收录';

  @override
  String get modelsFeaturedNoteHow => '接入一键导入，即可免费参与收录';

  @override
  String get modelsFeaturedNoteLink => '我也要接入';

  @override
  String modelsImportTitle(String host) {
    return '从 $host 导入上游';
  }

  @override
  String get modelsImportProtocol => '协议';

  @override
  String get modelsImportUrl => '地址';

  @override
  String get modelsImportKeyLabel => '密钥';

  @override
  String get modelsImportListedBadge => '官方收录';

  @override
  String get modelsImportNoKey => '无，导入后再填';

  @override
  String modelsImportExisting(String name) {
    return '你已经添加过这个上游：$name。';
  }

  @override
  String get modelsImportNamePlaceholder => '名称';

  @override
  String get modelsImportAdd => '导入模型';

  @override
  String get modelsImportFinish => '导入';

  @override
  String get modelsImportWithoutModels => '不选模型，直接导入';

  @override
  String get modelsImportPreparing => '正在为您准备模型中…';

  @override
  String modelsImportUpdateKey(String name) {
    return '更新「$name」的密钥';
  }

  @override
  String modelsImportOpenExisting(String name) {
    return '打开「$name」';
  }

  @override
  String get modelsImportAsNew => '另存为新上游';

  @override
  String get modelsImportInvalid => '这个导入链接无法使用';

  @override
  String get modelsImportInvalidDetail =>
      '链接里需要有 Base URL（http 或 https）和 BaoCode 支持的协议。请让站点重新生成链接，或在 设置 → 模型 中手动添加上游。';

  @override
  String get modelsAddProvider => '添加上游';

  @override
  String get modelsNewProviderName => '新上游';

  @override
  String get modelsProviderNoUrl => '未设置 Base URL';

  @override
  String modelsModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get modelsAccounts => '账号';

  @override
  String get modelsAccountsDescription =>
      '用 ChatGPT 账号登录，按套餐额度使用 Codex 模型。添加多个账号时，请求按下方的负载模式分配，额度用尽的账号会自动让给下一个。';

  @override
  String get modelsAccountsNone => '还没有账号';

  @override
  String modelsAccountCount(int count) {
    return '$count 个账号';
  }

  @override
  String get modelsAddAccount => '添加账号';

  @override
  String get modelsAddAccountDescription => '在浏览器中打开 ChatGPT 登录页。';

  @override
  String get modelsAccountSigningIn => '等待登录…';

  @override
  String get modelsAccountSigningInDetail => '请在浏览器中完成登录；如果浏览器没有打开，可复制链接手动打开。';

  @override
  String get modelsAccountCopyLink => '复制链接';

  @override
  String modelsAccountSignInFailed(String error) {
    return '登录失败：$error';
  }

  @override
  String get modelsRefreshQuota => '刷新额度';

  @override
  String get modelsAccountRemove => '移除账号';

  @override
  String modelsAccountRemoveConfirm(String name) {
    return '移除“$name”？';
  }

  @override
  String get modelsAccountRemoveDetail => '将从本机删除它的登录凭据。';

  @override
  String modelsAccountEnable(String name) {
    return '使用 $name';
  }

  @override
  String get modelsAccountLimited => '额度已用尽';

  @override
  String get modelsAccountQuotaUnknown => '额度尚未获取';

  @override
  String get modelsQuotaWeek => '每周';

  @override
  String modelsQuotaHours(int count) {
    return '$count 小时';
  }

  @override
  String modelsQuotaDays(int count) {
    return '$count 天';
  }

  @override
  String modelsQuotaUsed(int percent) {
    return '已用 $percent%';
  }

  @override
  String modelsQuotaResetsIn(String time) {
    return '$time后重置';
  }

  @override
  String modelsQuotaResetsAt(String time) {
    return '$time 重置';
  }

  @override
  String modelsQuotaCredits(String credits) {
    return '额外点数：$credits';
  }

  @override
  String modelsDurationMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String modelsDurationHours(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String get modelsBalance => '负载模式';

  @override
  String get modelsBalanceRoundRobin => '轮询';

  @override
  String get modelsBalanceRoundRobinDescription =>
      '每个新会话轮流分给下一个账号，之后一直留在该账号上（保留缓存）。';

  @override
  String get modelsBalanceFillFirst => '用完再换';

  @override
  String get modelsBalanceFillFirstDescription => '优先使用排在前面的账号，额度用尽后再换下一个。';

  @override
  String get modelsBalanceMostRemaining => '剩余优先';

  @override
  String get modelsBalanceMostRemainingDescription => '每个新会话分给剩余额度最多的账号。';

  @override
  String get modelsAccountPortBusy =>
      '登录回调用的 1455 端口被其他程序占用了（例如 Docker 里的代理，或正在登录的 Codex CLI）。照常在浏览器里登录即可：登录后的页面会打不开或显示别的内容，把地址栏里的完整地址复制粘贴到下面。';

  @override
  String get modelsAccountCallback => '登录后的地址';

  @override
  String get modelsAccountCallbackDetail => '如果浏览器没有自动跳回，把登录后地址栏里的地址粘贴到这里。';

  @override
  String get modelsProtocolAnthropic => 'Anthropic 兼容';

  @override
  String get modelsConnection => '连接';

  @override
  String get modelsName => '名称';

  @override
  String get modelsIcon => '图标';

  @override
  String get modelsIconDescription =>
      '显示在模型选择器中它的分组标题前：厂商标识、网站图标或自定义图片。未设置时按 Base URL 识别厂商。';

  @override
  String get modelsIconChange => '更换图标';

  @override
  String get modelsProtocol => '协议';

  @override
  String get modelsProtocolDescription =>
      'OpenAI 接口经本地代理转换 Claude Code 的请求和响应。';

  @override
  String get modelsBaseUrl => 'Base URL';

  @override
  String get modelsBaseUrlAnthropicHint =>
      '不带 /v1，同 ANTHROPIC_BASE_URL：Claude Code 会自己加 /v1/messages。';

  @override
  String get modelsBaseUrlOpenAIHint => '按上游文档填写；路径里没有版本号（…/v1）时自动加 /v1。';

  @override
  String get modelsApiKey => 'API Key';

  @override
  String get modelsApiKeyDescription => '保存在系统钥匙串中，不写入 settings.json。';

  @override
  String get modelsApiKeyShow => '显示 Key';

  @override
  String get modelsApiKeyHide => '隐藏 Key';

  @override
  String modelsApiKeyError(String error) {
    return 'Key 保存失败：$error';
  }

  @override
  String get modelsTest => '测试连接';

  @override
  String get modelsTesting => '正在连接…';

  @override
  String modelsTestOk(int count) {
    return '连接成功：上游列出了 $count 个模型。';
  }

  @override
  String modelsTestFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get modelsModelsGroup => '模型列表';

  @override
  String get modelsModelsDescription => '勾选的模型会出现在模型选择中。';

  @override
  String get modelsFetch => '从上游获取…';

  @override
  String get modelsAddModel => '手动添加…';

  @override
  String get modelsSearch => '搜索模型';

  @override
  String get modelsNone => '还没有模型：从上游获取，或手动添加。';

  @override
  String get modelsNoMatch => '没有匹配的模型。';

  @override
  String get modelsMissing => '上游已下架';

  @override
  String get modelsMissingTooltip => '上游已不再列出此模型；会一直保留，直到你手动移除。';

  @override
  String modelsRemoveMissing(int count) {
    return '移除已下架（$count）';
  }

  @override
  String modelsRemoveMissingConfirm(int count) {
    return '移除 $count 个上游已下架的模型？';
  }

  @override
  String get modelsCustom => '手动';

  @override
  String modelsShowAll(int count) {
    return '显示全部（$count）';
  }

  @override
  String get modelsShowChecked => '仅显示已勾选';

  @override
  String get modelsNoneChecked => '还没有勾选模型：点「显示全部」来勾选。';

  @override
  String get modelsEdit => '编辑…';

  @override
  String get modelsDuplicate => '复制…';

  @override
  String get modelsRemove => '移除';

  @override
  String get modelsMore => '更多操作';

  @override
  String get modelsTestModel => '测试';

  @override
  String get modelsTestModels => '批量测试';

  @override
  String get modelsTestModelFailed => '失败';

  @override
  String modelsTestFirstText(String seconds) {
    return '首字 ${seconds}s';
  }

  @override
  String modelsTestTotal(String seconds) {
    return '总耗时 ${seconds}s';
  }

  @override
  String modelsEnableModel(String name) {
    return '启用 $name';
  }

  @override
  String get modelsRoles => '角色映射';

  @override
  String get modelsRolesDescription =>
      'Claude Code 在各类工作中使用的模型；未设置时使用当前所选模型。除主模型外，都可以选其他上游的模型，请求会经 BaoCode 的本地代理发过去。';

  @override
  String get modelsRoleUnset => '未设置';

  @override
  String get modelsRoleMain => '主模型';

  @override
  String get modelsRoleMainDescription => '会话所选的模型被移除后，改用此模型。';

  @override
  String get modelsRoleOpus => 'Opus 档位';

  @override
  String get modelsRoleOpusDescription =>
      'ANTHROPIC_DEFAULT_OPUS_MODEL：「opus」对应的模型，例如计划模式。';

  @override
  String get modelsRoleSonnet => 'Sonnet 档位';

  @override
  String get modelsRoleSonnetDescription =>
      'ANTHROPIC_DEFAULT_SONNET_MODEL：「sonnet」对应的模型。';

  @override
  String get modelsRoleHaiku => 'Haiku 档位';

  @override
  String get modelsRoleHaikuDescription =>
      'ANTHROPIC_DEFAULT_HAIKU_MODEL：Claude Code 的后台任务，以及会话标题生成。';

  @override
  String get modelsRoleHaikuWarning => '未设置时，后台任务会使用所选模型，可能更慢、更贵。建议选一个小而快的模型。';

  @override
  String get modelsRoleSubagent => '子 Agent';

  @override
  String get modelsRoleSubagentDescription =>
      'CLAUDE_CODE_SUBAGENT_MODEL：所有子 Agent 使用的模型，优先于子 Agent 定义或调用时指定的模型（定义为 inherit 的除外）。';

  @override
  String get modelsRoleMissing => '这个模型已不在它的上游里，用到它的请求会失败。';

  @override
  String get modelsAdvanced => '高级';

  @override
  String get modelsAuth => '认证方式';

  @override
  String get modelsAuthDescription =>
      'Key 的发送方式。自动：api.anthropic.com 用 x-api-key，其他用 Bearer。';

  @override
  String get modelsAuthAuto => '自动';

  @override
  String get modelsNonessential => '禁用非必要流量';

  @override
  String get modelsNonessentialDescription =>
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC：不发送遥测、错误报告和更新检查（Anthropic 以外的上游不会响应这些请求）。';

  @override
  String get modelsPreserveThinking => '回传推理内容';

  @override
  String get modelsPreserveThinkingDescription =>
      '在后续请求中回传模型的推理内容（reasoning_content），DeepSeek 等上游需要。';

  @override
  String get modelsPromptCacheKey => '提示缓存键';

  @override
  String get modelsPromptCacheKeyDescription =>
      '为每个对话发送独立的 prompt_cache_key，让上游（或背后有多个后端的中转站）把同一对话的请求路由到已缓存的位置。上游不接受该字段时请关闭。';

  @override
  String get modelsCodexVersion => 'Codex 版本';

  @override
  String get modelsCodexVersionDescription =>
      '以哪个版本的 Codex CLI 身份发起请求。后端只列出该版本支持的模型，缺少新模型时可填更新的版本号，再刷新模型列表。留空使用应用默认值。';

  @override
  String get modelsEnv => '额外环境变量';

  @override
  String get modelsEnvDescription => '每行一个 KEY=VALUE，在以上设置之后传给 Claude Code。';

  @override
  String get modelsHeaders => '自定义请求头';

  @override
  String get modelsHeadersDescription =>
      '每行一个 Name: Value，对此上游的每次请求都会带上。值里可用双花括号变量 CLAUDE_SESSION_ID（本次对话的会话）与 ANTHROPIC_MODEL（所请求的模型）；走直连 Anthropic 协议时这两个变量原样发出，可用的只有固定值。鉴权头（Authorization、x-api-key）在此忽略：Key 在下方设置。';

  @override
  String get modelsHeadersPlaceholder => 'x-session-id: my-session';

  @override
  String get modelsDuplicateProvider => '复制上游';

  @override
  String get modelsDuplicateProviderDescription => '复制一份此上游，连同模型、设置和 Key。';

  @override
  String modelsDuplicateName(String name) {
    return '$name 副本';
  }

  @override
  String get modelsDelete => '删除上游';

  @override
  String get modelsDeleteDescription => '删除此上游，以及钥匙串中的 Key。';

  @override
  String modelsDeleteConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get modelsDeleteDetail => '使用其模型的会话下次启动时改用 Claude Code 自带的模型。';

  @override
  String modelsFetchTitle(String name) {
    return '$name 的模型';
  }

  @override
  String get modelsFetchLoading => '正在向上游获取…';

  @override
  String modelsFetchFailed(String error) {
    return '获取模型失败：$error';
  }

  @override
  String get modelsFetchEmpty => '上游没有列出任何模型。';

  @override
  String get modelsFetchSelectAll => '全选';

  @override
  String get modelsFetchSelectNone => '全不选';

  @override
  String modelsFetchSelected(int count, int total) {
    return '已选 $count / $total';
  }

  @override
  String get modelsFetchNew => '新';

  @override
  String get modelsFetchApply => '应用';

  @override
  String get modelsRetry => '重试';

  @override
  String get modelsAddTitle => '添加模型';

  @override
  String get modelsEditTitle => '编辑模型';

  @override
  String get modelsModelId => '模型 ID';

  @override
  String get modelsModelIdHint => '上游的模型名，如 gpt-5';

  @override
  String get modelsModelIdTaken => '该上游已有此模型。';

  @override
  String get modelsModelLabel => '显示名';

  @override
  String get modelsModelLabelHint => '可选';

  @override
  String get modelsContextWindow => '默认上下文';

  @override
  String get modelsContextWindowHint => 'token 数，如 128K；留空为 200K';

  @override
  String get modelsContextInvalid => '请输入 token 数，如 200K。';

  @override
  String get modelsEffortOptions => '推理强度档位';

  @override
  String get modelsEffortOptionsDescription => '在模型选择中提供；未选择时默认 Medium。';

  @override
  String get modelsEffortAddHint => '如 minimal';

  @override
  String get modelsEffortInvalid => '只能包含字母、数字和连字符。';

  @override
  String get modelsContextOptions => '上下文档位';

  @override
  String get modelsContextOptionsDescription => '在模型选择中提供；默认上下文总在其中。';

  @override
  String get modelsContextAddHint => '如 128K';

  @override
  String get modelsOptionAdd => '添加';

  @override
  String modelsOptionRemove(String name) {
    return '移除 $name';
  }

  @override
  String get modelsOptionsReset => '恢复默认';

  @override
  String get modelsOptionsNone => '无：不提供选择。';

  @override
  String get modelsNoImages => '不支持图片';

  @override
  String get modelsKind => '用途';

  @override
  String get modelsKindChat => '对话';

  @override
  String get modelsKindImage => '图片生成（Images API）';

  @override
  String get modelsKindImageChat => '图片生成（对话接口）';

  @override
  String get modelsKindDescription =>
      '图片模型不出现在模型选择器里：agent 通过 generate_image 工具用它们生成图片。';

  @override
  String get modelsEndpoint => '端点类型';

  @override
  String modelsEndpointUpstream(String protocol) {
    return '跟随上游（$protocol）';
  }

  @override
  String get modelsEndpointDescription =>
      '这个模型的请求发往哪种接口，Base URL 和 Key 与上游相同。中转站同时提供多种接口时，可以让 Claude 模型走 Anthropic 接口、GPT 模型走 Responses。';

  @override
  String get modelsImageBadge => '图片';

  @override
  String get modelsImage => '图片生成模型';

  @override
  String get modelsImageDescription =>
      'agent 生成图片（generate_image 工具）时用的模型，除非你让它换一个；选「每次询问」时在对话里选。图片模型在上游的模型列表里启用。';

  @override
  String get modelsImageFirst => '每次询问';

  @override
  String get modelsImageNone => '未启用图片模型';

  @override
  String get modelsSave => '保存';

  @override
  String get modelsManage => '管理模型…';

  @override
  String modelsSwitchTitle(String name) {
    return '切换到 $name？';
  }

  @override
  String get modelsSwitchDetail =>
      'Claude Code 会在新上游上重启，并用 --resume 接续当前对话。历史记录会原样发给新模型，部分上游首次处理会较慢。如果还有回复在进行，发送下一条消息时会先停止它。';

  @override
  String get modelsSwitchConfirm => '切换';

  @override
  String get modelsAuxiliary => '辅助模型';

  @override
  String get modelsAuxiliaryDescription =>
      '用于一些辅助性的工作，比如生成对话标题、提交信息等。自动：使用会话的模型（提交信息使用新会话默认模型），属于上游时取该上游的 Haiku 档位。';

  @override
  String get modelsAuxiliaryAuto => '自动';

  @override
  String get modelsAuxiliaryBuiltin => 'Claude Code Haiku（本机配置）';

  @override
  String get settingsSectionUpdates => '更新';

  @override
  String get updatesSettingsTitle => '更新';

  @override
  String get updatesSettingsDescription => 'BaoCode 会在 baocode.dev 上检查新版本。';

  @override
  String get updateCurrentVersion => '当前版本';

  @override
  String updateLastChecked(String time) {
    return '上次检查：$time';
  }

  @override
  String get updateNeverChecked => '尚未检查';

  @override
  String get updateCheckNow => '检查更新';

  @override
  String get updateChecking => '正在检查更新…';

  @override
  String get updateUpToDate => 'BaoCode 已是最新版本。';

  @override
  String updateAvailable(String version) {
    return 'BaoCode $version 已发布。';
  }

  @override
  String updateReady(String version) {
    return 'BaoCode $version 已下载，重启即可完成更新。';
  }

  @override
  String updateDownloading(String version) {
    return '正在下载 BaoCode $version…';
  }

  @override
  String updateDownloadingProgress(String version, int percent) {
    return '正在下载 BaoCode $version… $percent%';
  }

  @override
  String updateMandatory(String version) {
    return '当前版本的 BaoCode 已停止支持，请更新到 $version。';
  }

  @override
  String get updateRestartNow => '立即重启更新';

  @override
  String get updateLater => '稍后';

  @override
  String get updateSkip => '跳过此版本';

  @override
  String get updateSkippedNote => '已跳过此版本：不会再提醒，但仍可在此安装。';

  @override
  String updateFailed(String error) {
    return 'BaoCode 更新失败：$error';
  }

  @override
  String updateCheckFailed(String error) {
    return '检查更新失败：$error';
  }

  @override
  String get updateDisabled => '更新已关闭（update.mode 为 \"none\"）。';

  @override
  String get updateUnsupported => '此版本的 BaoCode 不支持自动更新。';

  @override
  String updateManual(String reason) {
    return 'BaoCode 无法在当前位置自动更新（$reason），请从 baocode.dev 下载新版本。';
  }

  @override
  String get updateOpenDownloadPage => '打开下载页';

  @override
  String updateUnfinished(String version, String current) {
    return 'BaoCode $version 没有装上，当前仍是 $current。可以在“设置 → 更新”里重试，或者从 baocode.dev 下载安装。';
  }

  @override
  String get updateShowLog => '查看安装日志';

  @override
  String get updateReleaseNotes => '更新日志';

  @override
  String updateReleaseNotesFor(String version) {
    return '$version 更新内容';
  }

  @override
  String get updateMode => '更新方式';

  @override
  String get updateModeDescription => 'BaoCode 是否自动检查新版本（设置项 update.mode）。';

  @override
  String updateModeLabel(String name) {
    return '更新方式：$name';
  }

  @override
  String get updateModeDefault => '自动检查并下载';

  @override
  String get updateModeManual => '仅手动检查';

  @override
  String get updateModeNone => '关闭';

  @override
  String get diagnosticsTitle => '诊断日志';

  @override
  String get diagnosticsDescription =>
      '把 BaoCode 的错误日志发给开发者，帮助排查问题。只有点击上传时才会发送。';

  @override
  String get diagnosticsUpload => '上传…';

  @override
  String get diagnosticsDialogTitle => '上传诊断日志';

  @override
  String get diagnosticsNotePlaceholder => '备注（选填）：遇到了什么问题，怎样复现';

  @override
  String diagnosticsFiles(int count, String size) {
    return '将上传 $count 个日志文件（$size）。';
  }

  @override
  String get diagnosticsNoFiles => '暂时没有日志，只会上传备注和版本信息。';

  @override
  String diagnosticsDumps(int count, String size) {
    return '包含卡死时的内存转储（$count 个，$size）';
  }

  @override
  String get diagnosticsDumpsDetail => '内存转储可能含有已打开文件的内容和路径。超过 10 MB 时只附带最新的。';

  @override
  String get diagnosticsPrivacy =>
      '日志里的用户目录会替换成 ~。同时发送版本、系统和语言，但不包含使用统计的安装 ID。服务器上保存 90 天。';

  @override
  String get diagnosticsSend => '上传';

  @override
  String get diagnosticsUploading => '正在上传…';

  @override
  String get diagnosticsUploaded => '已上传。报告编号：';

  @override
  String get diagnosticsUploadedDetail => '把这个编号告诉 BaoCode 开发者，就能找到这份日志。';

  @override
  String diagnosticsOmittedDumps(int count) {
    return '已省略 $count 个较早的内存转储（超过 10 MB）。';
  }

  @override
  String get diagnosticsCopyId => '复制编号';

  @override
  String get diagnosticsCopied => '已复制';

  @override
  String get diagnosticsRetry => '重试';

  @override
  String get diagnosticsTooLarge => '日志超过 10 MB，无法上传。';

  @override
  String get diagnosticsRateLimited => '上传太频繁，请稍后再试。';

  @override
  String diagnosticsRefused(int status) {
    return '服务器没有接受这份日志（HTTP $status）。';
  }

  @override
  String diagnosticsServerError(String status) {
    return '服务器暂时无法接收日志（$status），请稍后再试。';
  }

  @override
  String diagnosticsFailed(String error) {
    return '上传失败：$error';
  }

  @override
  String get cmdCheckForUpdates => '检查更新...';

  @override
  String get settingsSectionAppearance => '外观';

  @override
  String get settingsAppearanceKeywords => '主题 颜色 配色 深色 浅色 theme color';

  @override
  String get appearanceSettingsTitle => '外观';

  @override
  String get appearanceSettingsColorTheme => '颜色主题';

  @override
  String get appearanceSettingsColorThemeDescription => '对话、IDE 和终端使用的配色。';

  @override
  String appearanceSettingsColorThemeDescriptionWithKey(String key) {
    return '对话、IDE 和终端使用的配色。“首选项：颜色主题”（$key）可在列表中边移动边预览。';
  }

  @override
  String appearanceSettingsColorThemeLabel(String theme) {
    return '颜色主题：$theme';
  }

  @override
  String get appearanceSettingsChatWidth => '对话宽度';

  @override
  String get appearanceSettingsChatWidthDescription =>
      '窗口很宽时，对话、输入框和设置页最多能有多宽。';

  @override
  String get appearanceSettingsChatWidthDefault => '默认';

  @override
  String get appearanceSettingsChatWidthFull => '全宽';

  @override
  String appearanceSettingsChatWidthLabel(String width) {
    return '对话宽度：$width';
  }

  @override
  String get appearanceSettingsAgentLoader => '智能体加载中';

  @override
  String get appearanceSettingsAgentLoaderDescription =>
      '侧栏、标签页和搜索里，智能体工作时，或它启动的任务仍在后台运行时，显示在它旁边的动画。';

  @override
  String get appearanceSettingsSubagentLoader => '子代理运行中';

  @override
  String get appearanceSettingsSubagentLoaderDescription =>
      '子代理运行时，显示在对话里它的卡片和输入框上方它那一行的动画。';

  @override
  String appearanceSettingsLoaderLabel(String what, String style) {
    return '$what：$style';
  }

  @override
  String get appearanceSettingsLoaderSpeed => '速度';

  @override
  String appearanceSettingsLoaderSpeedLabel(String what, String speed) {
    return '$what速度：$speed';
  }

  @override
  String get loaderStyleSnake => '贪吃蛇';

  @override
  String get loaderStyleStack => '堆积消行';

  @override
  String get loaderStyleTwinkle => '随机闪烁';

  @override
  String get loaderStyleFill => '堆满再清空';

  @override
  String get loaderStylePulse => '方形脉冲';

  @override
  String get loaderStyleRipple => '十字涟漪';

  @override
  String get loaderStyleSweep => '斜向扫描';

  @override
  String get loaderStyleRain => '像素雨';

  @override
  String get loaderStyleChecker => '棋盘交替';

  @override
  String get loaderStyleSpinner => '经典转圈';

  @override
  String get loaderStyleTwinSpinner => '双头转圈';

  @override
  String get loaderStyleCorners => '四角轮闪';

  @override
  String get loaderStyleDots => '三点跳动';

  @override
  String get loaderStyleEqualizer => '均衡器';

  @override
  String get loaderStyleBar => '不定进度条';

  @override
  String get loaderStyleScan => '扫描线';

  @override
  String get loaderStyleHourglass => '沙漏';

  @override
  String get loaderStyleBreathe => '整体呼吸';

  @override
  String get loaderStyleCircle => '圆环（原版）';

  @override
  String get appearanceSettingsUserMessageStyle => '用户消息样式';

  @override
  String get appearanceSettingsUserMessageStyleDescription =>
      '你发出的消息在对话中的样子：整宽显示，滚动时当前这轮的消息停在顶部；或者像聊天一样靠右显示为气泡，随内容滚走。';

  @override
  String get appearanceSettingsUserMessageStyleSticky => '整宽滚动吸顶';

  @override
  String get appearanceSettingsUserMessageStyleBubble => '用户对话风格';

  @override
  String appearanceSettingsUserMessageStyleLabel(String style) {
    return '用户消息样式：$style';
  }

  @override
  String get appearanceSettingsReplyScroll => '回复时滚动';

  @override
  String get appearanceSettingsReplyScrollDescription =>
      'Agent 回复时对话停在哪里：自动跟随最新输出；或者锚定开头，你的消息到顶部后就不再自动滚动，从回复开头往下读。手动滚到底部后恢复跟随。';

  @override
  String get appearanceSettingsReplyScrollFollow => '自动';

  @override
  String get appearanceSettingsReplyScrollStart => '锚定开头';

  @override
  String appearanceSettingsReplyScrollLabel(String choice) {
    return '回复时滚动：$choice';
  }

  @override
  String get appearanceSettingsMinimap => '对话缩略图';

  @override
  String get appearanceSettingsMinimapDescription =>
      '在对话左侧显示整段对话的缩略图，滚动时显示当前所在位置，点击或拖动即可跳转。开启时代替右侧滚动条；窗口太窄时不显示。关闭后恢复右侧滚动条。';

  @override
  String get appearanceSettingsWindowBlur => '原生高斯模糊';

  @override
  String get appearanceSettingsWindowBlurDescription =>
      '窗口底部使用系统的模糊效果（macOS 的侧边栏材质、Windows 11 的亚克力），侧边栏和对话区会透出窗口后面的内容。关闭后窗口不透明。';

  @override
  String get appearanceSettingsSidebarTimes => '侧边栏显示时间';

  @override
  String get appearanceSettingsSidebarTimesDescription =>
      '在侧边栏每个智能体的右侧显示它最后一次活动的时间。关闭后只在鼠标悬停时显示。';

  @override
  String get appearanceSettingsMinimapGlass => '液态玻璃不透明度';

  @override
  String get appearanceSettingsMinimapGlassDescription =>
      '缩略图上标出当前位置的液态玻璃有多明显，包括它的底色、阴影和高光。调到 0% 时只保留当前位置的内容提亮。';

  @override
  String appearanceSettingsMinimapGlassLabel(String opacity) {
    return '缩略图玻璃不透明度：$opacity';
  }

  @override
  String get appearanceSettingsMinimapElasticity => '液态玻璃弹性';

  @override
  String get appearanceSettingsMinimapElasticityDescription =>
      '滚动时液态玻璃跟随的弹性：越弹，玻璃移动时上下拉伸得越明显，停下时再收回。';

  @override
  String appearanceSettingsMinimapElasticityLabel(String level) {
    return '缩略图玻璃弹性：$level';
  }

  @override
  String get minimapElasticityOff => '关闭';

  @override
  String get minimapElasticitySubtle => '轻微';

  @override
  String get minimapElasticityMedium => '适中';

  @override
  String get minimapElasticityBouncy => 'Q 弹';

  @override
  String get appearanceSettingsCodeFont => '代码字体';

  @override
  String get appearanceSettingsCodeFontDescription =>
      '代码使用的字体：编辑器、终端、对话和预览中的代码。按顺序输入字体名，用逗号分隔，或从预设中选择。';

  @override
  String get appearanceSettingsCodeFontDefault => '默认';

  @override
  String get appearanceSettingsCodeFontField => '字体名';

  @override
  String appearanceSettingsCodeFontLabel(String font) {
    return '代码字体：$font';
  }

  @override
  String get appearanceSettingsCodeSize => '代码字号';

  @override
  String get appearanceSettingsCodeSizeDescription =>
      'Fast IDE 编辑器及侧边栏文件、变更视图中源码的字号。对话中的代码跟随界面大小，终端使用终端字号。';

  @override
  String appearanceSettingsCodeSizeLabel(String size) {
    return '代码字号：$size';
  }

  @override
  String get appearanceSettingsLigatures => '字体连字';

  @override
  String get appearanceSettingsLigaturesDescription =>
      '字体有对应字形时，把 => 、!= 等组合画成一个字形。终端不使用连字。';

  @override
  String get appearanceSettingsWordWrap => '自动换行';

  @override
  String get appearanceSettingsWordWrapDescription =>
      '长行在编辑器宽度处折行，所有编辑器共用。编辑器右键菜单和命令面板（切换自动换行）也能切换。超过 5000 行的文件不折行。';

  @override
  String get appearanceSettingsUiScale => '界面大小';

  @override
  String get appearanceSettingsUiScaleDescription =>
      '缩放整个界面（文字、图标与间距）、对话中的代码，以及终端字号为“跟随界面大小”时的终端文字。Fast IDE 编辑器及侧边栏文件、变更中的源码使用代码字号。';

  @override
  String appearanceSettingsUiScaleLabel(String percent) {
    return '界面大小：$percent%';
  }

  @override
  String get appearanceSettingsTerminalSize => '终端字号';

  @override
  String get appearanceSettingsTerminalSizeDescription =>
      '终端文字的字号。默认跟随界面大小，也可单独设定。';

  @override
  String get appearanceSettingsTerminalSizeFollow => '跟随界面大小';

  @override
  String get appearanceSettingsTerminalSizeCustom => '自定义';

  @override
  String get appearanceSettingsTerminalSizeValue => '自定义字号';

  @override
  String appearanceSettingsTerminalSizeLabel(String size) {
    return '终端字号：$size';
  }

  @override
  String get generalSettingsContextMenuFinder => '访达右键菜单';

  @override
  String get generalSettingsContextMenuExplorer => '文件资源管理器右键菜单';

  @override
  String get generalSettingsContextMenuDescription =>
      '在文件、文件夹及文件夹空白处的右键菜单中加入“用 BaoCode 打开”（新对话）和“用 Fast Ide 打开”（新 IDE 窗口）。';

  @override
  String get generalSettingsContextMenuMacNote =>
      '访达的扩展开关在系统设置的“扩展”中，也可以在那里开启或关闭 BaoCode 扩展。';

  @override
  String get generalSettingsContextMenuOn => '已开启';

  @override
  String get generalSettingsContextMenuOff => '未开启';

  @override
  String get generalSettingsContextMenuUnsupported => '此版本的应用未包含访达扩展。';

  @override
  String get generalSettingsContextMenuTurnOn => '开启';

  @override
  String get generalSettingsContextMenuTurnOff => '关闭';

  @override
  String get generalSettingsContextMenuSystemSettings => '系统设置…';

  @override
  String generalSettingsContextMenuFailed(String error) {
    return '无法更改右键菜单：$error';
  }

  @override
  String contextMenuOpenWith(String name) {
    return '用 $name 打开';
  }

  @override
  String get cmdOpenRemoteFolder => '打开远程项目...';

  @override
  String get cmdOpenRemoteFile => '打开远程文件...';

  @override
  String get remoteHostPlaceholder => '选择主机、新增一个，或直接输入 user@host[:port]';

  @override
  String remoteConnectTo(String host) {
    return '连接到 $host';
  }

  @override
  String get remoteNoHosts => '还没有主机：新增一个，或直接输入 user@host';

  @override
  String get remoteInvalidHost => '不是有效的主机：不能含空格，也不能以 \'-\' 开头';

  @override
  String remoteConnecting(String host) {
    return '正在连接 $host...';
  }

  @override
  String remoteConnectFailed(String host) {
    return '无法连接到 $host';
  }

  @override
  String get remoteRetry => '重试';

  @override
  String remoteSignInTitle(String host) {
    return '登录 $host';
  }

  @override
  String get remoteSignInRefused => '不正确，请重试。';

  @override
  String get remoteSignInRemember => '在本机记住（保存在系统钥匙串中）';

  @override
  String get remoteSignInConnect => '连接';

  @override
  String remoteFolderPlaceholder(String host) {
    return '$host 上的文件夹：选择一个，或输入路径';
  }

  @override
  String get remoteOpenThisFolder => '打开此文件夹';

  @override
  String get remoteParentFolder => '上级文件夹';

  @override
  String remoteGoTo(String path) {
    return '前往 $path';
  }

  @override
  String remoteListFailed(String path) {
    return '无法列出 $path';
  }

  @override
  String get remoteFileHostPlaceholder => '选择主机，浏览它的文件';

  @override
  String remoteFilePlaceholder(String host) {
    return '$host 上的文件：选择一个，或输入路径';
  }

  @override
  String remoteOpenFile(String path) {
    return '打开 $path';
  }

  @override
  String remoteOpenFailed(String path) {
    return '无法打开 $path';
  }

  @override
  String get remoteRecentFiles => '最近的远程文件';

  @override
  String remoteOpenFileOn(String host) {
    return '在 $host 上打开文件...';
  }

  @override
  String remoteStatusActions(String host) {
    return '点击查看主机和 $host 的操作';
  }

  @override
  String remoteStatus(String kind, String host) {
    return '$kind: $host';
  }

  @override
  String remoteStatusConnecting(String kind, String host) {
    return '$kind: $host（正在连接...）';
  }

  @override
  String remoteStatusReconnecting(String kind, String host) {
    return '$kind: $host（正在重连...）';
  }

  @override
  String remoteStatusFailed(String kind, String host) {
    return '$kind: $host（已断开）';
  }

  @override
  String remoteStatusInstalling(String kind, String host, int percent) {
    return '$kind: $host（正在安装 Claude Code $percent%）';
  }

  @override
  String remoteStatusInstallingUnsized(String kind, String host) {
    return '$kind: $host（正在安装 Claude Code...）';
  }

  @override
  String remoteInstallingClaude(String host) {
    return '正在 $host 上安装 Claude Code…';
  }

  @override
  String remoteInstallingClaudeProgress(String host, int percent) {
    return '正在 $host 上安装 Claude Code… $percent%';
  }

  @override
  String localDownloadingClaude(int percent) {
    return '正在下载 Claude Code… $percent%';
  }

  @override
  String remoteUploadingClaude(String host, int percent) {
    return '正在把 Claude Code 传到 $host… $percent%';
  }

  @override
  String remoteStatusTooltip(String kind, String host) {
    return '已通过 $kind 连接到 $host';
  }

  @override
  String remoteStatusTooltipLost(String host) {
    return '与 $host 的连接已断开：点击立即重连';
  }

  @override
  String remoteStatusTooltipResuming(String host) {
    return '与 $host 的连接已断开，正在重连；远端的终端和 Claude Code 仍在运行。点击立即重连';
  }

  @override
  String get remoteReconnect => '重新连接';

  @override
  String remoteProjectTooltip(String kind, String host) {
    return '位于 $host（通过 $kind）';
  }

  @override
  String quitConfirmRemote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '远程主机上的 $count 个会话和终端也会结束。',
    );
    return '$_temp0';
  }

  @override
  String get updateButton => '更新';

  @override
  String get tipsSetupTitle => '设置 BaoCode';

  @override
  String tipsSetupCount(int done, int total) {
    return '$done/$total';
  }

  @override
  String tipsSetupEntry(int done, int total) {
    return '设置 $done/$total';
  }

  @override
  String get tipsHide => '收起';

  @override
  String get tipsTurnOn => '开启';

  @override
  String get tipsDismiss => '关闭';

  @override
  String get tipsDone => '已完成';

  @override
  String get tipsDontShowAgain => '不再提示';

  @override
  String tipsFailed(String title, String error) {
    return '无法开启$title：$error';
  }

  @override
  String tipsUpdated(String version, String features) {
    return 'BaoCode 已更新到 $version。新功能：$features。';
  }

  @override
  String get tipsListSeparator => '、';

  @override
  String get tipsSettingsTitle => '推荐功能';

  @override
  String get tipsSettingsDescription =>
      '尚未开启的功能。「显示设置向导」可重新打开设置清单；在 settings.json 中设置 \"workbench.tips.enabled\": false 可关闭所有推荐。';

  @override
  String get tipContextMenuBody => '在右键菜单中直接用 BaoCode 打开文件和文件夹。';

  @override
  String tipShellCommandTitle(String name) {
    return '$name 命令';
  }

  @override
  String tipShellCommandBody(String name) {
    return '在终端里用 $name <路径> 在 BaoCode 中打开文件夹。';
  }

  @override
  String get tipImportKeybindingsTitle => '导入快捷键';

  @override
  String get tipImportKeybindingsBody => '从 VS Code 或 Cursor 导入你的快捷键。';

  @override
  String get tipColorThemeBody => '选择对话、IDE 和终端使用的配色。';

  @override
  String get cmdShowSetupGuide => '显示设置向导';

  @override
  String get cmdStarOnGitHub => '在 GitHub 上为 BaoCode 点 Star';

  @override
  String get starPromptMessage => 'BaoCode 用得还顺手吗？';

  @override
  String get starPromptDetail =>
      'BaoCode 免费开源。如果它对你有帮助，欢迎在 GitHub 上点个 Star，让更多人发现它。';

  @override
  String get starPromptStar => '去 GitHub 点 Star';

  @override
  String get starPromptLater => '以后再说';

  @override
  String get cmdResetFeatureTips => '重置功能推荐';

  @override
  String get newChatWorkspaceGroup => '工作区';

  @override
  String newChatWorkspaceDetail(int count, String names) {
    return '$count 个文件夹 · $names';
  }

  @override
  String newChatHostProjects(int count) {
    return '$count 个项目';
  }

  @override
  String get newChatPickRemoteFolder => '选择目录…';

  @override
  String get newChatPickRemoteFolderDetail => '打开这台主机上的文件夹';

  @override
  String get newChatCreateWorkspace => '创建工作区…';

  @override
  String get newChatCreateWorkspaceDetail => '在多个文件夹中工作';

  @override
  String get workspaceCreateTitle => '创建工作区';

  @override
  String get workspaceEditTitle => '编辑工作区';

  @override
  String get workspaceName => '名称';

  @override
  String get workspaceNameHint => '我的工作区';

  @override
  String get workspaceFolders => '文件夹';

  @override
  String get workspaceFoldersDescription => '在此工作区中对话时，智能体可以读写这些文件夹中的文件。';

  @override
  String workspaceFoldersEmpty(String app) {
    return '还没有文件夹。从已有项目或$app添加。';
  }

  @override
  String get workspaceNoFolders => '请至少添加一个文件夹。';

  @override
  String get workspaceAddProject => '从已有项目添加';

  @override
  String workspaceAddFolder(String app) {
    return '从$app添加…';
  }

  @override
  String get workspaceNoProjects => '没有可添加的项目';

  @override
  String workspaceRemoveFolder(String name) {
    return '移除 $name';
  }

  @override
  String get workspaceCreate => '创建';

  @override
  String workspaceHover(String folders) {
    return '工作区：$folders';
  }

  @override
  String get sidebarEditWorkspace => '编辑工作区…';

  @override
  String get sidebarDeleteWorkspace => '删除工作区';

  @override
  String get sidebarEditProject => '编辑项目…';

  @override
  String get projectEditTitle => '编辑项目';

  @override
  String get projectLocation => '项目地址';

  @override
  String get projectLocationDescription =>
      '文件夹搬走或改名后，把地址改成新位置，这个项目的对话会一起迁移过去。不会移动文件夹本身。';

  @override
  String projectChooseFolder(String app) {
    return '在$app中选择…';
  }

  @override
  String get projectFolderNotFound => '这个地址没有文件夹。';

  @override
  String get projectRelocateBusy => '这个项目还有对话在运行，或在单独的窗口中打开，结束后再改地址。';

  @override
  String get projectRelocateFailed => '没能迁移这个项目的对话。';

  @override
  String get projectRelocating => '正在迁移对话…';

  @override
  String ideWorkspaceTitle(String name) {
    return '$name（工作区）';
  }

  @override
  String get ideAddFolderToWorkspace => '将文件夹添加到工作区…';

  @override
  String get ideRemoveFolderFromWorkspace => '从工作区中移除文件夹';

  @override
  String get ideEmptyWorkspace => '此工作区中还没有文件夹。';

  @override
  String get scmRepositories => '存储库';

  @override
  String get cmdCreateWorkspace => '创建工作区...';

  @override
  String get settingsSectionNetwork => '网络';

  @override
  String get settingsNetworkKeywords => '代理 网络 proxy clash vpn 梯子';

  @override
  String get networkSettingsTitle => '网络';

  @override
  String get networkSettingsDescription => 'BaoCode 及其启动的 Claude Code 如何访问网络。';

  @override
  String get networkProxy => '代理';

  @override
  String get networkProxyDescription =>
      'BaoCode 和 Claude Code 使用的代理（http.proxyMode）。跟随系统代理：使用系统设置里的代理，例如 Clash 开启的系统代理。更改对新会话生效，正在运行的会话需重新开始。';

  @override
  String networkProxyLabel(String name) {
    return '代理：$name';
  }

  @override
  String get networkProxySystem => '跟随系统代理';

  @override
  String get networkProxyManual => '手动设置';

  @override
  String get networkProxyOff => '不使用代理';

  @override
  String get networkProxyUrl => '代理地址';

  @override
  String get networkProxyUrlDescription =>
      'HTTP 代理，例如 Clash 的端口：http://127.0.0.1:7890（http.proxy）。不支持 SOCKS。';

  @override
  String networkProxyUrlInvalid(String url) {
    return '不是 HTTP 代理地址：$url。请填写类似 http://127.0.0.1:7890 的地址。';
  }

  @override
  String get networkProxyStatus => '当前使用';

  @override
  String get networkProxyStatusChecking => '正在检测…';

  @override
  String networkProxyStatusSystem(String server) {
    return '系统代理 $server';
  }

  @override
  String networkProxyStatusEnvironment(String server) {
    return '$server，来自环境变量（HTTPS_PROXY）：系统没有设置代理';
  }

  @override
  String networkProxyStatusManual(String server) {
    return '$server';
  }

  @override
  String get networkProxyStatusManualMissing => '请填写代理地址。';

  @override
  String get networkProxyStatusNone => '直连：系统没有设置代理。';

  @override
  String get networkProxyStatusOff => '直连。';

  @override
  String get networkProxyStatusAutoConfig =>
      '直连：系统使用自动代理配置（PAC），BaoCode 暂不支持。请在 Clash 中开启系统代理，或手动填写代理地址。';

  @override
  String get networkProxyRefresh => '重新检测';

  @override
  String get networkTest => '连通性测试';

  @override
  String get networkTestDescription =>
      '通过当前使用的代理访问这些网站，看能否连上、速度如何（新建连接到开始收到响应的用时）。';

  @override
  String get networkTesting => '测试中…';

  @override
  String get networkTestRun => '开始测试';

  @override
  String get networkTestRunAgain => '重新测试';

  @override
  String get networkTestIdle => '未测试';

  @override
  String networkTestMs(int ms) {
    return '$ms ms';
  }

  @override
  String get networkTestUnreachable => '无法访问';

  @override
  String networkTestSummary(int reached, int total) {
    return '$total 个网站中 $reached 个可以访问。';
  }

  @override
  String get networkFailureTimeout => '超时';

  @override
  String get networkFailureRefused => '连接被拒绝';

  @override
  String get networkFailureReset => '连接被重置';

  @override
  String get networkFailureDns => '域名解析失败';

  @override
  String get networkFailureTls => 'TLS 握手失败';

  @override
  String get networkFailureProxyAuth => '代理需要认证';

  @override
  String get networkFailureOther => '连接失败';

  @override
  String get networkTestHintRefused => '代理地址上没有程序响应：请确认 Clash（或其他代理）正在运行。';

  @override
  String get networkTestHintOffline => '所有网站都无法访问：请检查本机网络和代理。';

  @override
  String get networkTestHintBlocked =>
      '只有百度能访问：其他网站没有经过代理。请检查上面的代理设置，或 Clash 的模式和规则。';

  @override
  String get extsCapabilityFull => '完全支持';

  @override
  String get extsCapabilityFullDetail => '它的颜色主题或文件图标主题都能使用。';

  @override
  String get extsCapabilityPartial => '部分支持';

  @override
  String get extsCapabilityPartialDetail => '主题可以使用；其余部分在 BaoCode 中不起作用。';

  @override
  String extsEngineIncompatible(String current, String requested) {
    return '需要 VS Code $requested，当前为 $current。';
  }

  @override
  String get extsEngineMissing => '它没有说明需要哪个版本的 VS Code。';

  @override
  String extsEngineInvalid(String requested) {
    return '无效的引擎“$requested”。';
  }

  @override
  String extsEngineCompatible(String engine) {
    return '需要 VS Code $engine。';
  }

  @override
  String get extsTitleUpdates => '更新';

  @override
  String get extsTitleOpenVsx => 'Open VSX';

  @override
  String get extsUpdates => '更新';

  @override
  String get extsCheckForUpdates => '检查更新';

  @override
  String get extsMoreActions => '更多操作...';

  @override
  String get extsInstallFromVsix => '从 VSIX 安装...';

  @override
  String get extsSearchPlaceholder => '搜索 Open VSX 扩展';

  @override
  String extsSearchFailed(String error) {
    return '无法搜索 Open VSX：$error';
  }

  @override
  String get extsLoadMore => '加载更多';

  @override
  String extsUpdateTo(String version) {
    return '更新到 $version';
  }

  @override
  String get extsUpdating => '正在更新...';

  @override
  String get extsEnable => '启用';

  @override
  String get extsDisable => '禁用';

  @override
  String get extsDisabled => '已禁用';

  @override
  String get extsSwitchToPreRelease => '切换到预发布版本';

  @override
  String get extsSwitchToRelease => '切换到正式版本';

  @override
  String get extsInstallPreRelease => '安装预发布版本';

  @override
  String extsInstallVersion(String version) {
    return '安装 $version';
  }

  @override
  String get extsPreRelease => '预发布';

  @override
  String get extsVerifiedPublisher => '已验证的发布者';

  @override
  String extsDownloads(String count) {
    return '$count 次下载';
  }

  @override
  String extsLoadFailed(String error) {
    return '无法加载：$error';
  }

  @override
  String get extsVersion => '版本';

  @override
  String get extsPreReleaseToggle => '预发布';

  @override
  String get extsLatestVersion => '最新';

  @override
  String get extsTabDetails => '详情';

  @override
  String get extsTabFeatures => '功能';

  @override
  String get extsTabChangelog => '更新日志';

  @override
  String get extsNoReadme => '此扩展没有 README。';

  @override
  String get extsNoChangelog => '此扩展没有更新日志。';

  @override
  String get extsContributions => '贡献点';

  @override
  String get extsNoContributions => '此扩展没有任何贡献点。';

  @override
  String get extsActivationEvents => '激活事件';

  @override
  String get extsApiProposals => 'API 提案';

  @override
  String get extsCompatibility => '兼容性';

  @override
  String get extsInformation => '信息';

  @override
  String get extsInfoIdentifier => '标识符';

  @override
  String get extsInfoVersion => '版本';

  @override
  String get extsInfoLatest => '最新';

  @override
  String get extsInfoLastUpdated => '最后更新';

  @override
  String get extsInfoEngine => 'VS Code';

  @override
  String get extsInfoPlatform => '平台';

  @override
  String get extsInfoLicense => '许可证';

  @override
  String get extsInfoRepository => '仓库';

  @override
  String get extsInfoCategories => '分类';

  @override
  String get extsInfoLocation => '位置';

  @override
  String get extsVsixTitle => '安装扩展 VSIX';

  @override
  String extsVsixInvalid(String name, String error) {
    return '$name 不是有效的 VSIX：$error';
  }

  @override
  String extsVsixPlatformMismatch(String platform, String current) {
    return '它是为 $platform 构建的，不适用于 $current。';
  }

  @override
  String extsVsixReplaces(String version) {
    return '它将替换版本 $version。';
  }

  @override
  String extsPlatformCompatible(String platform) {
    return '平台：$platform';
  }

  @override
  String get extsPlatformUniversal => '通用';

  @override
  String extsPageTitle(String name) {
    return '扩展: $name';
  }

  @override
  String get themeSelectIconThemePlaceholder => '选择文件图标主题（按上下箭头键预览）';

  @override
  String get themeIconThemeBuiltIn => '内置';

  @override
  String get extsCapabilityUnsupported => '不支持';

  @override
  String get extsCapabilityUnsupportedDetail =>
      '它没有颜色主题或文件图标主题：BaoCode 只使用扩展中的主题。';

  @override
  String get extsFindingCode => '它的代码不会运行。';

  @override
  String extsFindingContribution(String name) {
    return '未使用：$name';
  }

  @override
  String get extsPopularThemes => '热门主题';

  @override
  String get extsTabThemes => '主题';

  @override
  String get extsTabLanguageServers => '语言服务器';

  @override
  String get sidebarAllHosts => '全部';

  @override
  String get sidebarThisMachine => '本机';

  @override
  String get sidebarSwitchHost => '在本机和 SSH 主机之间切换';

  @override
  String get sidebarAddSshHost => '添加 SSH 主机...';

  @override
  String sidebarOpenFolderOn(String host) {
    return '在 $host 上打开文件夹...';
  }

  @override
  String sidebarNoProjectsOn(String host) {
    return '$host 上还没有项目。';
  }

  @override
  String get sidebarHostConnected => '已连接';

  @override
  String get sidebarHostConnecting => '正在连接...';

  @override
  String get sidebarHostDisconnected => '已断开';

  @override
  String get sidebarHostIdle => '未连接';

  @override
  String get sidebarDisconnectHost => '断开连接';

  @override
  String get sidebarRemoveHost => '移除主机';

  @override
  String sidebarRemoveHostTitle(String host) {
    return '移除 $host？';
  }

  @override
  String get sidebarRemoveHostMessage => '它的项目会从侧栏移走。对话不会删除，重新添加这台主机后会回来。';

  @override
  String get sidebarRemove => '移除';

  @override
  String sidebarElsewhereNeedsYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '其他环境有 $count 个对话需要处理',
    );
    return '$_temp0';
  }

  @override
  String get sidebarRenameHost => '重命名主机';

  @override
  String get sidebarEditHost => '编辑连接…';

  @override
  String get explorerNoPermission => '没有权限读取此文件夹';

  @override
  String fileErrorAccessDenied(String path) {
    return '没有权限访问: $path';
  }

  @override
  String get remoteAddedHosts => '已添加';

  @override
  String explorerUndoCreateChanged(String name) {
    return '$name 创建后已被修改，仍要撤销（删除它）吗？';
  }

  @override
  String get settingsSectionMobile => '手机';

  @override
  String get settingsMobileKeywords => '手机 移动端 配对 扫码 二维码 远程 局域网 iphone android';

  @override
  String get mobileSettingsDescription =>
      '在手机上的 BaoCode 里查看并操作这台电脑的智能体，经由局域网或公网直连。两端之间的内容端到端加密。';

  @override
  String get mobileAllow => '允许手机连接';

  @override
  String get mobileAllowDescription => '与这台电脑配对过的手机可以直接连接它。';

  @override
  String get mobileStatus => '状态';

  @override
  String get mobileStatusOff => '已关闭';

  @override
  String get mobileStatusStarting => '正在启动…';

  @override
  String mobileStatusListening(int port) {
    return '正在监听端口 $port';
  }

  @override
  String mobileStatusFailed(String error) {
    return '无法监听：$error';
  }

  @override
  String get mobileAddresses => '地址';

  @override
  String get mobileAddressesDescription => '手机按此顺序尝试连接这台电脑：先局域网，再公网。';

  @override
  String get mobileAddressesNone => '未找到可用的网络。';

  @override
  String get mobileAddressesRefresh => '刷新';

  @override
  String get mobilePort => '端口';

  @override
  String get mobilePortDescription => '手机连接的端口。在路由器上转发此端口，即可从公网访问这台电脑。';

  @override
  String mobilePortInvalid(String text) {
    return '不是有效端口：$text。请填写 1 到 65535 之间的数字。';
  }

  @override
  String get mobilePublicAddress => '公网地址';

  @override
  String get mobilePublicAddressDescription =>
      '可从公网访问这台电脑的域名或 IP（需转发端口），会写入二维码；多个用逗号分隔。经只收 HTTPS 的代理（如 Cloudflare Tunnel）访问时，写成 wss://域名。公网 IPv6 地址会自动加入。';

  @override
  String get mobileRelay => '中转';

  @override
  String get mobileRelayDescription => '当这台电脑的地址都无法直连时，经由 BaoCode 中转服务连接。即将推出。';

  @override
  String get mobileRelayUnavailable => '暂不可用';

  @override
  String get mobilePair => '配对手机';

  @override
  String get mobilePairDescription =>
      '在手机 BaoCode 上扫码（我的 → 已配对的电脑 → 配对新电脑），或在那里的「附近的电脑」中选择这台电脑。';

  @override
  String get mobilePairShow => '显示二维码';

  @override
  String get mobilePairCancel => '取消';

  @override
  String get mobilePairNewCode => '换一个';

  @override
  String get mobilePairCopyLink => '复制链接';

  @override
  String get mobilePairCopied => '已复制';

  @override
  String mobilePairExpires(int minutes) {
    return '$minutes 分钟内有效，仅可使用一次。无法扫码的手机也可以粘贴链接。';
  }

  @override
  String get mobilePairExpired => '二维码已过期。';

  @override
  String mobilePairVerifyTitle(String name) {
    return '与 $name 核对';
  }

  @override
  String get mobilePairVerifyBody => '确认手机上显示的安全码与此相同，然后在手机上确认。';

  @override
  String get mobilePairMismatch => '安全码不一致';

  @override
  String mobilePaired(String name) {
    return '已与 $name 配对。';
  }

  @override
  String get mobilePhones => '已配对的手机';

  @override
  String get mobilePhonesNone => '还没有配对的手机。';

  @override
  String get mobilePhoneConnected => '已连接';

  @override
  String mobilePhoneLastSeen(String time) {
    return '上次连接于 $time';
  }

  @override
  String get mobilePhoneRemove => '移除';

  @override
  String get mobileThisComputerKey => '这台电脑的密钥';

  @override
  String get mobileThisComputerKeyDescription => '手机上也会显示它：两边一致，就说明中间没有人截取。';

  @override
  String get mobileDiscoverable => '局域网发现';

  @override
  String get mobileDiscoverableDescription =>
      '已配对的手机在局域网里自动找到这台电脑，地址变了也能连上；配对时，新手机还能在「附近的电脑」里看到它。';

  @override
  String get mobilePairNearbyHint => '同一网络里的手机也可以在「附近的电脑」中选择这台电脑。';

  @override
  String mobilePairRequestTitle(String name) {
    return '$name 请求配对';
  }

  @override
  String get mobilePairRequestBody => '它是在「附近的电脑」里找到这台电脑的。手机上显示的安全码一致才允许。';

  @override
  String get mobilePairAllow => '允许';

  @override
  String get settingsSectionStash => 'Stash';

  @override
  String get settingsSectionCustomize => '自定义';

  @override
  String get settingsCustomizeKeywords => '技能 子智能体 规则 命令 记忆 钩子 插件 mcp';

  @override
  String get stashTitle => 'Stash';

  @override
  String get stashHeading => 'Stash';

  @override
  String get stashNew => '新便签';

  @override
  String get stashLinkOpen => '打开链接';

  @override
  String get stashLinkEdit => '编辑链接';

  @override
  String get stashLinkCopy => '复制链接地址';

  @override
  String get stashLinkRemove => '移除链接';

  @override
  String get stashFormatMenu => '格式';

  @override
  String get stashDraft => '草稿';

  @override
  String get stashCodeChip => '代码';

  @override
  String get stashTableChip => '表格';

  @override
  String stashLines(int count) {
    return '$count 行';
  }

  @override
  String get stashNewButton => '新建';

  @override
  String get stashNewTooltip => '新建便签';

  @override
  String get stashPlaceholder => '随手记下…';

  @override
  String get stashHintNew => '新建';

  @override
  String get stashProjectTooltip => '关联的项目';

  @override
  String get stashNoProject => '无项目';

  @override
  String get stashFormatBold => '粗体';

  @override
  String get stashFormatItalic => '斜体';

  @override
  String get stashFormatStrike => '删除线';

  @override
  String get stashFormatUnderline => '下划线';

  @override
  String get stashFormatCode => '代码';

  @override
  String get stashFormatLink => '链接';

  @override
  String get stashFormatColor => '文字颜色与背景色';

  @override
  String get stashFormatHeading1 => '一级标题';

  @override
  String get stashFormatHeading2 => '二级标题';

  @override
  String get stashFormatHeading3 => '三级标题';

  @override
  String get stashFormatBullets => '无序列表';

  @override
  String get stashFormatNumbers => '有序列表';

  @override
  String get stashFormatTasks => '任务列表';

  @override
  String get stashFormatQuote => '引用';

  @override
  String get stashFormatCodeBlock => '代码块';

  @override
  String get markdownTableInsertRowAbove => '在上方插入行';

  @override
  String get markdownTableInsertRowBelow => '在下方插入行';

  @override
  String get markdownTableDeleteRow => '删除行';

  @override
  String get markdownTableInsertColumnLeft => '在左侧插入列';

  @override
  String get markdownTableInsertColumnRight => '在右侧插入列';

  @override
  String get markdownTableDeleteColumn => '删除列';

  @override
  String get markdownTableAlignLeft => '左对齐';

  @override
  String get markdownTableAlignCenter => '居中对齐';

  @override
  String get markdownTableAlignRight => '右对齐';

  @override
  String get markdownTableDuplicateRow => '复制行';

  @override
  String get markdownTableMoveRowUp => '上移行';

  @override
  String get markdownTableMoveRowDown => '下移行';

  @override
  String get markdownTableClearRow => '清空行';

  @override
  String get markdownTableDuplicateColumn => '复制列';

  @override
  String get markdownTableMoveColumnLeft => '左移列';

  @override
  String get markdownTableMoveColumnRight => '右移列';

  @override
  String get markdownTableClearColumn => '清空列';

  @override
  String get markdownTableDeleteTable => '删除表格';

  @override
  String get stashFormatClear => '清除格式';

  @override
  String get stashPolish => '润色';

  @override
  String get stashPolishing => '润色中…';

  @override
  String get stashPolishHint => '让 AI 把选中的文字理顺，保持你的原意，不加结构';

  @override
  String get composerPolish => '润色';

  @override
  String get composerPolishing => '润色中…';

  @override
  String get composerPolishHint =>
      '润色：用辅助模型把消息改得更清楚，保留你的意思和口吻；图片、文件、代码和链接原样不动，可撤销';

  @override
  String composerPolishFailed(String error) {
    return '润色失败：$error';
  }

  @override
  String get generalSettingsComposerPolish => '润色按钮';

  @override
  String get generalSettingsComposerPolishDescription =>
      '在输入框里显示润色按钮，发送前用辅助模型把写的内容改得更清楚';

  @override
  String get generalSettingsLiveTurnStats => '运行时实时显示详细速率和时间';

  @override
  String get generalSettingsLiveTurnStatsDescription =>
      '运行中在回复下方实时显示本轮耗时、输出速度和已输出的 token。一轮结束后的统计始终显示';

  @override
  String usageLimitScheduled(String time) {
    return '已达到用量上限，将在 $time 重置后自动继续';
  }

  @override
  String usageLimitTomorrow(String time) {
    return '明天 $time';
  }

  @override
  String get resumeAfterResetPrompt => '用量已重置，请从中断的地方继续。';

  @override
  String get resumeAfterLimitToggle => '限额重置后自动继续';

  @override
  String stashPolishFailed(String error) {
    return '没能润色：$error';
  }

  @override
  String get stashLinkTitle => '链接';

  @override
  String get stashRemove => '移除';

  @override
  String get stashEdit => '编辑';

  @override
  String get stashFormulaTitle => '公式（TeX）';

  @override
  String get stashTableTitle => '表格（Markdown）';

  @override
  String get stashCodeTitle => '代码块';

  @override
  String stashBigFileTitle(String name) {
    return '“$name”超过 200 MB';
  }

  @override
  String get stashBigFileDetail => '只链接到它所在的位置，还是仍然复制进便签？';

  @override
  String get stashBigFileLink => '只链接';

  @override
  String get stashBigFileCopy => '复制';

  @override
  String get stashSearchPlaceholder => '搜索便签（包括图片里的文字）';

  @override
  String get stashAiSearch => 'AI 搜索';

  @override
  String get stashAiSearchHint => '按意思而不只是字面去找。会调用模型，这个要花钱。';

  @override
  String stashAiResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'AI 找到 $count 条',
      zero: 'AI 没找到',
    );
    return '$_temp0';
  }

  @override
  String get stashAiClear => '清除';

  @override
  String stashAiSearchFailed(String error) {
    return 'AI 搜索失败：$error';
  }

  @override
  String get stashAiNoAnswer => '模型没有给出可用的回答。';

  @override
  String get aiModelAuxiliary => '跟随辅助模型';

  @override
  String get aiModelFirst => '先选一个模型，之后的 AI 操作都用它';

  @override
  String get aiModelNone => '尚未选择';

  @override
  String aiModelTooltip(String model) {
    return 'AI 操作使用的模型：$model';
  }

  @override
  String get stashFilterAnyTime => '任何时间';

  @override
  String get stashFilterAnyProject => '所有项目';

  @override
  String get stashFilterAnyStatus => '所有状态';

  @override
  String get stashFilterOpen => '未完成';

  @override
  String get stashGroupPinned => '置顶';

  @override
  String get stashGroupToday => '今天';

  @override
  String get stashGroupYesterday => '昨天';

  @override
  String get stashGroupWeek => '过去 7 天';

  @override
  String get stashGroupMonth => '过去 30 天';

  @override
  String get stashGroupEarlier => '更早';

  @override
  String get stashGroupDone => '已完成';

  @override
  String get stashStatus => '状态';

  @override
  String get stashStatusCollected => '收集';

  @override
  String get stashStatusRequirement => '已成需求';

  @override
  String get stashStatusImplementing => '实施中';

  @override
  String get stashStatusDone => '已完成';

  @override
  String stashEmpty(String hotkey) {
    return '还没有便签。\n在任何应用里按 $hotkey 随手记一条。';
  }

  @override
  String get stashEmptyNoHotkey => '还没有便签。\n点 + 新建一条；在设置里设个快捷键，就能在任何应用里随手记。';

  @override
  String get stashNoMatch => '没有匹配的便签。';

  @override
  String get stashPin => '置顶';

  @override
  String get stashUnpin => '取消置顶';

  @override
  String get stashOpenInPanel => '在浮动面板中打开';

  @override
  String get stashLinkProject => '关联项目';

  @override
  String get stashMerge => '合并';

  @override
  String stashMergeTitle(String stashes) {
    return '合并 $stashes？';
  }

  @override
  String stashMergeDetail(String target) {
    return '它们的内容会依次并入 $target，其余几条删除，编号会指向它。';
  }

  @override
  String stashMergeSuggestion(String stashes) {
    return '$stashes 看起来是同一件事。';
  }

  @override
  String get stashDismiss => '忽略';

  @override
  String get stashDelete => '删除';

  @override
  String stashDeleteOne(String stash) {
    return '删除 $stash？';
  }

  @override
  String stashDeleteMany(int count) {
    return '删除 $count 条便签？';
  }

  @override
  String get stashDeleteDetail => '它们的图片和文件也会一并删除，无法撤销。';

  @override
  String stashPicked(int count) {
    return '已选 $count 条';
  }

  @override
  String get stashMarkDone => '标为已完成';

  @override
  String get stashReopen => '恢复未完成';

  @override
  String get stashClearPicked => '取消选择';

  @override
  String get stashClose => '关闭 Stash';

  @override
  String get stashCloseDetail => '关闭';

  @override
  String get stashMore => '更多';

  @override
  String get stashExpand => '说清楚';

  @override
  String get stashExpandHint => 'AI 把原话说清楚：结合图片和附件补全意思，不加结构；直接替换原文，可以撤销';

  @override
  String get stashClarifying => '正在说清楚…';

  @override
  String get stashCancelClarify => '停止说清楚';

  @override
  String get stashClarifyFailedShort => '没说清楚';

  @override
  String get stashClarifyChanged => '说清楚期间便签被改动了，没有替换，可以再试一次。';

  @override
  String get stashRetry => '重试';

  @override
  String stashExpandFailed(String error) {
    return '没能说清楚：$error';
  }

  @override
  String get stashImplement => '在 BaoCode 中实施';

  @override
  String get stashImplementHow => '让 agent 怎样开发？';

  @override
  String get stashImplementHowDetail =>
      '在新的 git worktree 里（独立分支，不动你当前的工作区），还是直接在项目当前分支上。';

  @override
  String get stashImplementWorktree => '新建 worktree';

  @override
  String get stashImplementDirect => '直接开发';

  @override
  String stashImplementStarter(String stash) {
    return '请实现 $stash 中的需求。';
  }

  @override
  String get stashImplementInWorktree =>
      '先为这项工作新建一个 git worktree（新分支），在其中开发，完成后告诉我分支名。';

  @override
  String get stashImplementInPlace => '直接在当前项目、当前分支上开发。';

  @override
  String get stashImplementComplete => '全部完成后，在 Stash 里把它标为已完成。';

  @override
  String get stashThreads => '对话';

  @override
  String get stashThreadSource => '在这个对话里记下';

  @override
  String get stashThreadNoReply => '还没有回复';

  @override
  String get stashThreadGone => '已不在对话列表中';

  @override
  String get stashOpenThread => '打开';

  @override
  String stashProjectSuggestion(String project) {
    return 'AI 觉得这条和 $project 有关。';
  }

  @override
  String get stashLinkIt => '关联';

  @override
  String get stashSettingsDescription =>
      '在任何应用里随手记下的便签，浮动面板呼出，之后可以变成需求交给 agent。';

  @override
  String get stashSettingsHotkey => '快捷键';

  @override
  String stashSettingsHotkeyCurrent(String hotkey) {
    return '在任何应用里按 $hotkey 呼出面板。';
  }

  @override
  String get stashSettingsHotkeyNone => '没有快捷键：只能从 Stash 页打开面板。';

  @override
  String get stashSettingsHotkeyTaken => '这个快捷键被其他应用占用了，请换一个。';

  @override
  String get stashSettingsHotkeyHelp => '点击后按下新的组合键；Esc 取消，Delete 清除。';

  @override
  String get stashHotkeyPress => '按下组合键…';

  @override
  String get stashHotkeyRefused => '要带修饰键，配字母、数字或常用键';

  @override
  String get stashHotkeyNone => '未设置';

  @override
  String get stashHotkeyClear => '清除';

  @override
  String stashHotkeySuggested(String hotkey) {
    return '使用 $hotkey';
  }

  @override
  String get stashHotkeyGlobal => '呼出 Stash 快捷窗口';

  @override
  String get stashHotkeyGlobalHint => '全局快捷键，在任何应用里都能用。';

  @override
  String get stashHotkeyTooltip => '呼出快捷窗口的快捷键，点击更改';

  @override
  String get stashSettingsDirectory => '存放位置';

  @override
  String get stashSettingsDirectoryChange => '更改…';

  @override
  String get stashSettingsDirectoryReset => '恢复默认';

  @override
  String get stashSettingsDirectoryRestart => '重启 BaoCode 后生效。';

  @override
  String get stashAll => '所有';

  @override
  String get stashAllTooltip => '显示所有便签';

  @override
  String get stashHintSave => '保存';

  @override
  String get stashHintClose => '关闭';

  @override
  String get stashSaved => '已保存';

  @override
  String get stashFilter => '过滤';

  @override
  String get stashSort => '排序';

  @override
  String get stashSortManual => '自定义（拖动排序）';

  @override
  String get stashSortUpdated => '最近编辑';

  @override
  String get stashSortCreated => '最近创建';

  @override
  String get stashSortNumber => '编号';

  @override
  String get stashOpen => '打开';

  @override
  String stashCount(int count) {
    return '$count 条便签';
  }

  @override
  String get stashFormatMore => '更多';

  @override
  String get branchBarSwitch => '切换分支';

  @override
  String get branchBarSearch => '搜索分支';

  @override
  String get branchBarCreate => '新建分支…';

  @override
  String branchBarCreateFrom(String branch) {
    return '从“$branch”新建分支';
  }

  @override
  String branchBarCreateIn(String folder) {
    return '在“$folder”中新建分支';
  }

  @override
  String get branchBarCreateButton => '创建';

  @override
  String get branchBarDetached => '分离的 HEAD';

  @override
  String get branchBarRunning => 'Agent 运行时不能切换分支';

  @override
  String branchBarFailed(String branch) {
    return '无法切换到“$branch”';
  }

  @override
  String get branchBarNotRepository => '不是 Git 仓库';

  @override
  String get branchBarWorkspace => '各文件夹的分支';

  @override
  String get settingsSectionAccounts => 'Git 账号';

  @override
  String get settingsAccountsKeywords =>
      'GitHub GitLab 登录 令牌 token issue PR 合并请求';

  @override
  String get accountsDescription =>
      '登录 GitHub 或 GitLab 后，Stash 中链接的 issue 和 PR 会显示最新状态，可以把 issue 导入为 Stash，并在你确认后回帖。';

  @override
  String get accountsSignedIn => '已登录';

  @override
  String get accountsAdd => '添加账号';

  @override
  String get accountsKeptLocally =>
      '令牌只保存在本机钥匙串里，只会发给对应的 GitHub 或 GitLab。未经你确认，不会发布任何内容。';

  @override
  String get accountsGitHubHosts => 'github.com，或公司的 GitHub Enterprise';

  @override
  String get accountsGitLabHosts => 'gitlab.com，或自建的 GitLab';

  @override
  String get accountsSignInBrowser => '在浏览器中登录';

  @override
  String get accountsSignInToken => '使用令牌…';

  @override
  String get accountsViaBrowser => '浏览器登录';

  @override
  String get accountsViaToken => '令牌登录';

  @override
  String get accountsSignOut => '退出登录';

  @override
  String accountsSignOutTitle(String login, String forge) {
    return '退出 $forge 账号 $login？';
  }

  @override
  String accountsSignOutDetail(String forge) {
    return '会删除本机保存的令牌。要彻底撤销 BaoCode 的访问权限，还需要到 $forge 的设置里撤销。';
  }

  @override
  String accountsRevoke(String forge) {
    return '退出并打开 $forge 设置';
  }

  @override
  String accountsTokenTitle(String forge) {
    return '用令牌登录 $forge';
  }

  @override
  String get accountsSignIn => '登录';

  @override
  String get accountsHost => '地址';

  @override
  String get accountsToken => '令牌';

  @override
  String get accountsTokenGitHubScopes =>
      '需要勾选 repo 和 read:user 的经典令牌，或对 Issues、Pull requests 有读写权限的细粒度令牌。';

  @override
  String get accountsTokenGitLabScopes => '需要勾选 api 范围的个人访问令牌。';

  @override
  String accountsTokenCreate(String host) {
    return '在 $host 上创建令牌';
  }

  @override
  String get accountsTokenRefused => '令牌无效，请检查是否完整、是否已过期。';

  @override
  String accountsBrowserTitle(String forge) {
    return '登录 $forge';
  }

  @override
  String accountsBrowserDetail(String host) {
    return '在 $host 上输入下面的代码，授权 BaoCode 访问你的账号：';
  }

  @override
  String get accountsCopyAndOpen => '复制代码并打开浏览器';

  @override
  String get accountsOpenAgain => '已复制 · 再次打开';

  @override
  String get accountsBrowserStarting => '正在获取代码…';

  @override
  String get accountsBrowserWaiting => '等待你在浏览器中授权…';

  @override
  String get accountsRetry => '重试';

  @override
  String get forgeStateOpen => '打开';

  @override
  String get forgeStateDraft => '草稿';

  @override
  String get forgeStateClosed => '已关闭';

  @override
  String get forgeStateMerged => '已合并';

  @override
  String get forgeChecksPassed => '检查已通过';

  @override
  String get forgeChecksFailed => '检查未通过';

  @override
  String get forgeChecksRunning => '检查进行中';

  @override
  String get stashIssues => 'Issue 与 PR';

  @override
  String stashIssueClosedBanner(String tag) {
    return '$tag 已关闭，这条 Stash 也完成了吗？';
  }

  @override
  String stashIssueOpenBanner(String tag) {
    return '这条 Stash 已完成，但 $tag 还开着。';
  }

  @override
  String get stashIssueReplyClose => '回帖并关闭…';

  @override
  String stashIssueNotSignedIn(String forge) {
    return '登录 $forge 后显示最新状态';
  }

  @override
  String get stashIssueSignIn => '登录…';

  @override
  String get stashIssueFailed => '获取状态失败';

  @override
  String get stashIssueOpen => '在浏览器中打开';

  @override
  String get stashIssueCopy => '复制链接';

  @override
  String get stashIssueComment => '回帖…';

  @override
  String get stashIssueClose => '关闭 issue…';

  @override
  String get stashIssueUnlink => '取消关联';

  @override
  String stashWriteFixedIn(String pulls) {
    return '已在 $pulls 中修复。';
  }

  @override
  String stashWriteTitle(String tag) {
    return '回帖到 $tag';
  }

  @override
  String stashWriteCloseTitle(String tag) {
    return '关闭 $tag';
  }

  @override
  String get stashWriteSend => '发送';

  @override
  String get stashWriteSendClose => '发送并关闭';

  @override
  String get stashWriteCloseOnly => '关闭 issue';

  @override
  String get stashWriteSendAnyway => '仍然发送';

  @override
  String get stashWritePlaceholder => '写下回帖内容（支持 Markdown）';

  @override
  String get stashWriteAlsoClose => '同时关闭 issue';

  @override
  String get stashWriteSensitive => '内容里像是有本机路径或密钥，发出后能看到这个 issue 的人都能看到：';

  @override
  String stashWriteAs(String login, String host) {
    return '将以 $login 的身份发到 $host。';
  }

  @override
  String stashWriteFailed(String error) {
    return '发送失败：$error';
  }

  @override
  String get stashImport => '从 issue 导入…';

  @override
  String get stashImportTitle => '导入 issue';

  @override
  String get stashImportAction => '导入';

  @override
  String stashImportCount(int count) {
    return '导入 $count 条';
  }

  @override
  String get stashImportPaste => '粘贴 issue 或 PR 链接';

  @override
  String get stashImportAdd => '添加';

  @override
  String get stashImportNotALink => '不是 GitHub 或 GitLab 的 issue / PR 链接。';

  @override
  String stashImportSignIn(String forge) {
    return '在 设置 → 账号 中登录 $forge 后才能列出 issue。';
  }

  @override
  String get stashImportRepo => '仓库';

  @override
  String get stashImportAssigned => '指派给我';

  @override
  String get stashImportCreated => '我创建的';

  @override
  String get stashImportAll => '全部打开的';

  @override
  String get stashImportSearch => '搜索';

  @override
  String get stashImportLoading => '正在加载…';

  @override
  String get stashImportNoRepos =>
      '没有项目的 Git 远程在 GitHub 或 GitLab 上，可以在上面粘贴 issue 链接。';

  @override
  String get stashImportNone => '这里没有打开的 issue。';

  @override
  String stashImportKnown(int id) {
    return '已在 Stash #$id';
  }

  @override
  String sidebarOpenPull(String tag) {
    return '打开 $tag';
  }

  @override
  String get stashGroupOthers => '其他';

  @override
  String stashFilterProjects(int count) {
    return '$count 个项目';
  }

  @override
  String get stashFilterJoiner => '、';

  @override
  String get stashWelcomeTitle => '认识 Stash';

  @override
  String get stashWelcomeLead => '想到就记下，准备好了交给 agent 去做，每一条进展如何一眼看清。';

  @override
  String get stashWelcomeNoteTitle => '随手记下';

  @override
  String get stashWelcomeAgentTitle => '交给 agent';

  @override
  String get stashWelcomeAgent => '点「在 BaoCode 中实施」，或在对话里 @ 它；对话和便签会自动关联。';

  @override
  String get stashWelcomeTrackTitle => '看清进展';

  @override
  String get stashWelcomeTrack =>
      '卡片上实时显示对话状态，链接的 GitHub、GitLab issue 和 PR 也会同步状态。';

  @override
  String get stashWelcomeStart => '开始使用';

  @override
  String get stashWelcomeNoteBody => '文字、截图、链接都能放进来，每一条都有自己的编号，像 issue 一样。';

  @override
  String get stashWelcomeHotkeyTitle => '设置呼出快捷键';

  @override
  String get stashWelcomeHotkeySetTitle => '快捷键已设置';

  @override
  String get stashWelcomeHotkey =>
      '在任何 App 里按下它，就能立刻弹出 Stash 面板记一条。点下面的框，按下想用的组合键。';

  @override
  String stashWelcomeHotkeySet(String hotkey) {
    return '在任何 App 里按 $hotkey 就能记一条，随时可以在这里或 设置 → Stash 中修改。';
  }

  @override
  String get stashWelcomeHotkeyLater => '也可以之后在 设置 → Stash 中设置。';

  @override
  String get settingsSectionBrowser => '浏览器';

  @override
  String get settingsBrowserKeywords =>
      '浏览器 chrome 扩展 插件 网页 标签页 edge brave arc';

  @override
  String get browserSettingsDescription =>
      '让 agent 用你自己的浏览器，沿用你的登录状态：在你共享给它的标签页里打开网页、读取内容、点击和输入。它的每一步操作都能在侧边栏里看到。';

  @override
  String get browserSettingsUnsupported => '浏览器功能只支持 macOS、Windows 和 Linux。';

  @override
  String get browserSettingsEnabled => '允许 agent 使用浏览器';

  @override
  String get browserSettingsEnabledDescription =>
      '关闭后 agent 不再有浏览器工具，扩展也会断开连接。';

  @override
  String get browserSettingsStatus => '状态';

  @override
  String get browserSettingsNotInstalled => '还没有浏览器连接过';

  @override
  String get browserSettingsNotInstalledDescription =>
      '用下方任一方式安装扩展，之后打开浏览器就会自动连接。';

  @override
  String get browserSettingsNotRunning => '浏览器未连接';

  @override
  String get browserSettingsNotRunningDescription =>
      '打开装有 BaoCode 扩展的浏览器，会自动连接。';

  @override
  String get browserSettingsSandboxed => 'Snap 和 Flatpak 装的浏览器连不上';

  @override
  String get browserSettingsSandboxedDescription =>
      '它们的沙箱不让 BaoCode 的辅助程序运行。请改用浏览器官方的 .deb 或 .rpm 安装包，例如从 google.com/chrome 下载 Google Chrome。';

  @override
  String browserSettingsConnected(String browser) {
    return '$browser 已连接';
  }

  @override
  String browserSettingsIncompatible(String browser) {
    return '$browser 的扩展版本不匹配';
  }

  @override
  String browserSettingsExtensionVersion(String version) {
    return '扩展版本 $version';
  }

  @override
  String get browserSettingsExtensionOld =>
      '扩展版本太旧，需要更新。商店版会自动更新，也可以在 chrome://extensions 里点「更新」；手动安装的请重新下载 zip，覆盖原来的文件夹后点刷新。';

  @override
  String get browserSettingsAppOld => '扩展比当前的 BaoCode 新，请更新 BaoCode。';

  @override
  String get browserSettingsInstall => '安装扩展';

  @override
  String get browserSettingsStore => 'Chrome 应用商店';

  @override
  String get browserSettingsStoreDescription =>
      '推荐。会自动更新，Chrome、Edge、Brave、Arc 等 Chromium 内核的浏览器都能装。';

  @override
  String get browserSettingsStoreOpen => '打开商店';

  @override
  String get browserSettingsUnpacked => '手动安装（开发者模式）';

  @override
  String get browserSettingsUnpackedDescription =>
      '下载后解压到一个固定的文件夹（之后不要删）。在 chrome://extensions 打开右上角的「开发者模式」，点「加载已解压的扩展程序」，选中这个文件夹。不会自动更新。';

  @override
  String get browserSettingsUnpackedDownload => '下载 zip';

  @override
  String get browserSettingsOpen => '浏览器设置';

  @override
  String get browserHistoryTitle => '调试记录';

  @override
  String get browserHistoryDescription =>
      '共享给 BaoCode 的标签页里打开过的页面、发出的请求、控制台的错误和警告会一直记下来，不用专门录制。你说“刚才保存时报错了”这类话时，agent 会自己翻看。记录只存在这台电脑上，不保存 Cookie 和令牌。';

  @override
  String get browserHistoryDetailed => '详细记录';

  @override
  String get browserHistoryDetailedDescription =>
      '另外记下请求体和响应体、你的操作（点击和输入，不含密码）以及全部控制台日志，占用空间更多。';

  @override
  String browserHistorySize(String size) {
    return '已占用 $size';
  }

  @override
  String get browserHistoryClear => '清理';

  @override
  String get browserHistoryClearConfirm => '清理全部调试记录？';

  @override
  String get browserHistoryClearDetail => '已记下的页面、请求和控制台日志都会被删除，无法恢复。';

  @override
  String browserHistoryTooLarge(String size) {
    return '浏览器调试记录已占用 $size';
  }

  @override
  String get browserHistoryTooLargeDetail => '可以直接清理，也可以去 设置 → 浏览器 查看。';

  @override
  String get browserHistoryOpenSettings => '浏览器设置';

  @override
  String get browserWelcomeTitle => 'agent 现在能用你的浏览器了';

  @override
  String get browserWelcomeLead =>
      '装上 BaoCode 扩展，agent 就能在你自己的 Chrome 里打开网页、阅读、点击和输入，带着你的登录状态。';

  @override
  String get browserWelcomeSharedTitle => '只用你共享的标签页';

  @override
  String get browserWelcomeShared => '它只在黄色的「BaoCode」标签页分组里工作，其他标签页仍然只属于你。';

  @override
  String get browserWelcomeWatchTitle => '看着它操作';

  @override
  String get browserWelcomeWatch => '侧边栏实时显示它正在用的网页，你随时可以接手。';

  @override
  String get browserWelcomeShowTitle => '演示一遍就会';

  @override
  String get browserWelcomeShow => '让 agent 看着，你在浏览器里自己操作一遍，它就能看到你的每一步。';

  @override
  String get browserWelcomeInstallTitle => '安装扩展';

  @override
  String get browserWelcomeInstall =>
      'Chrome、Edge、Brave、Arc 都能用。装好后会自动连接，这里会变成绿色。';

  @override
  String get browserWelcomeTurnedOff => '浏览器功能已在 设置 → 浏览器 中关闭。';

  @override
  String browserWelcomeConnected(String browser) {
    return '$browser 已连接';
  }

  @override
  String get browserWelcomeTry => '试试对 agent 说：「打开 baocode.dev 看看下载页」。';

  @override
  String get browserWelcomeUnpacked => '开发者模式 zip';

  @override
  String get browserWelcomeDone => '知道了';

  @override
  String get cmdBrowserWelcome => '连接浏览器...';

  @override
  String get cmdStashWelcome => '认识 Stash...';

  @override
  String get cmdModelWelcome => '设置模型...';

  @override
  String get modelWelcomeTitle => '选一个模型开始';

  @override
  String get modelWelcomeLead =>
      'BaoCode 用你选的模型来运行 agent。添加一个上游（提供 API Key 的服务），它的模型就能直接用了。';

  @override
  String get modelWelcomeAnyTitle => '任意上游';

  @override
  String get modelWelcomeAny =>
      '支持 Anthropic API、OpenAI Chat Completions 和 Responses，以及兼容它们的服务，比如 OpenRouter、DeepSeek。';

  @override
  String get modelWelcomeKeysTitle => 'Key 只在你手里';

  @override
  String get modelWelcomeKeys => 'Key 存在系统钥匙串里，请求从这台电脑直接发往上游。';

  @override
  String get modelWelcomeSwitchTitle => '随时切换';

  @override
  String get modelWelcomeSwitch => '之后随时可以再添加上游，每个对话都能在输入框下方选模型。';

  @override
  String get modelWelcomeStepTitle => '添加第一个上游';

  @override
  String get modelWelcomeStep => '填上地址和 Key，再勾选要用的模型。部分服务也能在 设置 → 模型 里一键导入。';

  @override
  String get modelWelcomeReadyTitle => '准备好了';

  @override
  String modelWelcomeReady(String model) {
    return '新对话会使用 $model，随时可以在输入框下方换成别的。';
  }

  @override
  String get modelWelcomeLater => '也可以之后在 设置 → 模型 中添加。';

  @override
  String get modelWelcomeSkip => '稍后';

  @override
  String get modelWelcomeStart => '开始对话';

  @override
  String get healthNoModel => '选一个模型就能开始：添加一个上游，它的模型就能直接用了。';

  @override
  String get modelSetUp => '设置模型';

  @override
  String get claudeCoreHint =>
      '当前用的是 BaoCode 内置内核。推荐换成 Claude Code 内核，体验更完整；没安装的话会自动帮你下载。';

  @override
  String get claudeCoreHintSwitch => '切换到 Claude Code';

  @override
  String get claudeCoreHintLater => '暂不';

  @override
  String get remoteAddServer => '新增 SSH 服务器…';

  @override
  String get remoteEditServer => '编辑';

  @override
  String get settingsSectionSsh => 'SSH 服务器';

  @override
  String get settingsSshKeywords =>
      'ssh 远程 服务器 主机 跳板机 私钥 密码 内核 remote server host';

  @override
  String get sshSettingsDescription => '远程项目连接的服务器：地址、登录方式、跳板机，以及每台用的内核。';

  @override
  String get sshSettingsServers => '服务器';

  @override
  String get sshSettingsServersDescription => '在应用里添加的，以及侧栏里用过的主机。';

  @override
  String get sshSettingsNone => '还没有服务器';

  @override
  String get sshSettingsAdd => '添加服务器…';

  @override
  String get sshSettingsEdit => '编辑…';

  @override
  String get sshSettingsConnect => '连接';

  @override
  String get sshSettingsDisconnect => '断开';

  @override
  String sshSettingsDisconnectTitle(String host) {
    return '断开 $host？';
  }

  @override
  String get sshSettingsDisconnectDetail => '这台主机上正在运行的对话和终端会结束。';

  @override
  String sshSettingsCore(String core) {
    return '内核：$core';
  }

  @override
  String sshSettingsVia(String host) {
    return '经 $host';
  }

  @override
  String get sshSettingsTyped => '按输入的地址';

  @override
  String get sshSettingsConfigHosts => '~/.ssh/config 里的主机';

  @override
  String get sshSettingsConfigHostsDescription => '在这个文件里修改；内核按“自动”。';

  @override
  String get sshSettingsOpenConfig => '打开文件';

  @override
  String get sshServerAddTitle => '新增 SSH 服务器';

  @override
  String get sshServerAddSubtitle => '保存后会出现在远程列表里，点一下就能连接。';

  @override
  String sshServerEditTitle(String name) {
    return '编辑 $name';
  }

  @override
  String get sshServerHost => '主机';

  @override
  String get sshServerHostPlaceholder => '域名或 IP，粘贴 user@host:port 会自动拆开';

  @override
  String get sshServerPort => '端口';

  @override
  String get sshServerUser => '用户名';

  @override
  String get sshServerName => '名称（可选）';

  @override
  String get sshServerNamePlaceholder => '如“生产环境”';

  @override
  String get sshServerAuth => '登录方式';

  @override
  String get sshServerAuthPassword => '密码';

  @override
  String get sshServerAuthKey => '私钥';

  @override
  String get sshServerAuthAuto => '自动';

  @override
  String get sshServerAuthAutoHint =>
      '和终端里的 ssh 一样：用 ssh-agent、~/.ssh 里的密钥和 ~/.ssh/config 的设置；服务器要密码时会再问。';

  @override
  String get sshServerPasswordHint => '保存在系统钥匙串中。留空则连接时再问。';

  @override
  String get sshServerPasswordKept => '已保存，不修改请留空';

  @override
  String get sshServerKeyPlaceholder => '私钥文件路径，如 ~/.ssh/id_ed25519';

  @override
  String get sshServerKeyBrowse => '浏览…';

  @override
  String get sshServerKeysFound => '~/.ssh 中的密钥';

  @override
  String get sshServerKeyHint => '如果私钥有口令，连接时会问。';

  @override
  String get sshServerCore => '内核';

  @override
  String get sshServerCoreAuto => '自动';

  @override
  String get sshServerCoreAutoHint => '服务器上装了 Claude Code CLI 就用它，没装就用内置内核。';

  @override
  String get sshServerCoreBuiltinHint => 'BaoCode 自带的内核，使用“设置 → 模型”里的上游。';

  @override
  String get sshServerCoreCliHint => '服务器上的 Claude Code CLI，没装会自动装上。';

  @override
  String get sshServerJump => '跳板机（可选）';

  @override
  String get sshServerNoJump => '不使用，直接连接';

  @override
  String get sshServerSaveConnect => '保存并连接';

  @override
  String get sshServerSave => '保存';

  @override
  String get sshServerHostRequired => '请填写服务器的域名或 IP';

  @override
  String get sshServerHostInvalid => '不能含空格，也不能以 - 开头';

  @override
  String get sshServerPortInvalid => '端口应为 1 到 65535';

  @override
  String get sshServerKeyRequired => '请选择私钥文件';

  @override
  String get sshServerKeyMissing => '找不到这个文件';

  @override
  String get remoteForgetHostKey => '移除旧指纹并重新连接';

  @override
  String remoteForgetHostKeyTitle(String host) {
    return '移除 $host 的旧指纹？';
  }

  @override
  String get remoteForgetHostKeyDetail =>
      '只有在确认服务器重装过或更换过密钥时才这样做，否则可能有人在中间截获连接。移除后，下次连接会接受服务器现在的指纹。';

  @override
  String get remoteForgetHostKeyButton => '移除并连接';

  @override
  String get remoteFailNoSsh => '本机没有 ssh：请安装 OpenSSH 客户端。';

  @override
  String get remoteFailAuth => '服务器拒绝登录：请检查用户名、密码或密钥。';

  @override
  String get remoteFailCancelled => '已取消登录。';

  @override
  String get remoteFailHostKey =>
      '服务器的指纹未知，而你的 ssh 配置要求不自动接受新指纹（StrictHostKeyChecking）。';

  @override
  String get remoteFailHostKeyChanged =>
      '服务器的指纹和上次连接时不同：可能是服务器重装过，也可能有人在中间截获连接。';

  @override
  String get remoteFailUnreachable => '连不上服务器：请检查地址、端口和网络。';

  @override
  String get remoteFailWsl => 'WSL 无法启动这个发行版：请确认已安装 WSL，并且 wsl --list 里有这个发行版。';

  @override
  String get channelSetupTitle => '欢迎使用 BaoCode';

  @override
  String get channelSetupLead => '打开官网完成首次设置，大约 10 秒。';

  @override
  String get channelSetupStepTitle => '在浏览器中完成设置';

  @override
  String get channelSetupStep =>
      'BaoCode 会在浏览器里打开 baocode.dev，网页显示完成后，这里会自动继续。';

  @override
  String get channelSetupWaitingTitle => '正在等待浏览器完成…';

  @override
  String get channelSetupWaiting => '网页显示完成后，这里会自动继续。不小心关掉了网页，可以重新打开。';

  @override
  String get channelSetupOpenFailedTitle => '浏览器没有打开';

  @override
  String get channelSetupOpenFailed => '复制下面的网址，粘贴到浏览器里打开。网页显示完成后，这里会自动继续。';

  @override
  String get channelSetupAddressCopied => '已复制';

  @override
  String get channelSetupOffline => '连不上 baocode.dev，需要联网才能完成设置。';

  @override
  String get channelSetupRetry => '重试';

  @override
  String get channelSetupDoneTitle => '设置完成';

  @override
  String get channelSetupOpen => '在浏览器中完成设置';

  @override
  String get channelSetupOpenAgain => '重新打开网页';

  @override
  String get channelSetupNoResponse => '浏览器没反应？';

  @override
  String get channelSetupPasteLead => '网页上如果有一段链接，复制后粘贴到这里：';

  @override
  String get channelSetupPasteConfirm => '确定';

  @override
  String get channelSetupLinkInvalid => '这不是网页上的链接，请复制网页上显示的完整链接。';

  @override
  String get channelSetupLinkOther => '这个链接属于另一个 BaoCode（别的电脑或重装前的），请用这里打开的网页。';

  @override
  String get channelSetupTrouble => '遇到问题？';

  @override
  String get channelSetupOnceTitle => '只需一次';

  @override
  String get channelSetupOnce => '完成后不会再出现，更新后也不会。';

  @override
  String get channelSetupPrivateTitle => '不涉及个人信息';

  @override
  String get channelSetupPrivate => '网页只告诉 BaoCode 你是从哪里知道它的，比如某个视频或网站。';

  @override
  String get channelSetupFindingTitle => '正在读取渠道信息…';

  @override
  String get channelSetupFinding => '马上就好。';

  @override
  String get channelSetupSiteOfflineTitle => '连不上 baocode.dev';

  @override
  String get channelSetupSiteOffline => '需要联网读取渠道信息，请检查网络后重试。';

  @override
  String get channelSetupUnavailableTitle => '这个渠道暂时用不了';

  @override
  String get channelSetupUnavailable =>
      '这份安装包对应的渠道还没有开通账号服务。如果你是从别的渠道下载的，去浏览器确认一下来源；否则请联系提供安装包的一方，或到 baocode.dev 下载普通版。';

  @override
  String get channelSetupConfirmAgain => '去浏览器确认';

  @override
  String channelWelcomeTitle(String channel) {
    return '欢迎使用 $channel';
  }

  @override
  String channelWelcomeText(String channel) {
    return '登录你的 $channel 账号，就可以开始使用了。';
  }

  @override
  String get channelWelcomeSignIn => '登录';

  @override
  String get channelWelcomeSigningIn => '请在弹出的窗口中登录…';

  @override
  String get channelWelcomePreparing => '正在准备…';

  @override
  String channelWelcomeFailed(String error) {
    return '没能完成登录：$error';
  }

  @override
  String get channelAccountTitle => '账号管理';

  @override
  String get channelAccountBalance => '余额';

  @override
  String get channelAccountRefresh => '刷新账户';

  @override
  String get channelAccountSignOut => '退出登录';

  @override
  String get channelAccountSignOutTitle => '退出登录？';

  @override
  String channelAccountSignOutDetail(String channel) {
    return '退出后，需要重新登录 $channel 才能继续使用 BaoCode。';
  }

  @override
  String get channelAccountOpenSite => '打开网站';

  @override
  String get channelAccountDefaultModel => '新对话默认模型';

  @override
  String get channelAccountNoModels => '正在使用的 Key 没有可用的模型。';

  @override
  String get channelAccountKeys => '我的 API Key';

  @override
  String get channelAccountCreateKey => '创建 Key';

  @override
  String get channelAccountKeyName => '名称';

  @override
  String get channelAccountKeyGroup => '分组';

  @override
  String get channelAccountUseKey => '使用此 Key';

  @override
  String get channelAccountInUse => '使用中';

  @override
  String get channelAccountNoKeys => '还没有 API Key。';

  @override
  String get channelAccountSignedOut => '还没有登录。';

  @override
  String get channelAccountUnavailable => '这个渠道暂时用不了，请联系提供安装包的一方。';

  @override
  String channelAccountFailed(String error) {
    return '出错了：$error';
  }

  @override
  String channelAccountBlocked(String site, String request) {
    return '$site 拒绝了这台电脑的连接（$request），可能是当前网络或代理的 IP 被它的防火墙拦截了。换个网络，或让 $site 不走代理后再试。';
  }

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get aboutTagline => '好看又好用的 Claude Code 桌面应用，内置毫秒级响应的 IDE。';

  @override
  String aboutVersion(String version, int build) {
    return '版本 $version（$build）';
  }

  @override
  String aboutRepository(String repository) {
    return '$repository · 免费开源，GPL-3.0 许可证';
  }

  @override
  String get aboutWebsite => '官网';

  @override
  String get aboutChangelog => '更新日志';

  @override
  String get aboutChangelogDetail => '每个版本改了什么';

  @override
  String get aboutFeedback => '反馈问题';

  @override
  String get aboutFeedbackDetail => '在 GitHub 上提 issue，或者看看别人提过的';

  @override
  String get aboutOpen => '打开';

  @override
  String get stashSettingsIssueSync => 'Issue 同步为 Stash';

  @override
  String get stashSettingsIssueSyncDescription =>
      '项目是 GitHub / GitLab 上的 Git 仓库（并已在「账号」中登录）时，它的未关闭 issue 会成为 Stash，一个 issue 只对应一条，双向保持一致。删除或取消关联的不会再被拉回来。';

  @override
  String get stashIssueSyncMine => '只同步指派给我或我创建的';

  @override
  String get stashIssueSyncOff => '关闭：只保留手动导入或发布的';

  @override
  String get stashIssueLocal => '仅本地';

  @override
  String get stashIssueAllow => '允许发布为 issue';

  @override
  String get stashIssueNotPublished => '尚未发布为 issue';

  @override
  String stashIssuePublishTo(String repo) {
    return '发布为 $repo 的 issue…';
  }

  @override
  String get stashIssueKeepLocal => '仅本地保存';

  @override
  String get stashIssuePush => '把本地改动推送到 issue…';

  @override
  String get stashIssuePushShort => '推送';

  @override
  String get stashIssueTakeRemote => '放弃本地改动，用 issue 上的版本';

  @override
  String get stashIssueUnlinkOwn => '取消关联，仅本地保存';

  @override
  String stashIssueConflict(String tag) {
    return '$tag 在远端也被改过了，保留哪一边？';
  }

  @override
  String get stashIssueKeepMine => '保留本地（推送）';

  @override
  String get stashIssueKeepTheirs => '用 issue 的';

  @override
  String stashIssueChangedHere(String tag) {
    return '本地改动还没同步到 $tag。';
  }

  @override
  String get stashIssueDiscard => '放弃改动';

  @override
  String stashIssuePublishTitle(String repo) {
    return '发布为 $repo 的 issue';
  }

  @override
  String stashIssuePushTitle(String tag) {
    return '把改动推送到 $tag';
  }

  @override
  String get stashIssuePublish => '发布';

  @override
  String get stashIssueNoText => '（没有描述）';

  @override
  String stashIssuePicturesGitHub(int count, String branch) {
    return '$count 张图片会上传到仓库的 $branch 分支，供 issue 显示。';
  }

  @override
  String stashIssuePicturesGitLab(int count) {
    return '$count 张图片会上传到项目，供 issue 显示。';
  }

  @override
  String get stashImplementShort => '实施';

  @override
  String stashImplementIssue(String issue) {
    return '它对应 issue $issue，提 PR 时写明修复了它。';
  }

  @override
  String get stashIssueSyncAll => '全部打开的 issue';

  @override
  String get stashIssueChecking => '正在查找仓库…';

  @override
  String get stashIssueRefresh => '立即刷新';

  @override
  String get stashIssuePublishButton => '发布为 issue';

  @override
  String get stashIssuePushButton => '推送到 issue';

  @override
  String get stashIssueLoading => '正在获取…';

  @override
  String get stashSyncing => '正在同步 issue…';

  @override
  String stashSyncingRepo(String repo, int index, int total) {
    return '正在同步 $repo 的 issue（$index/$total）…';
  }

  @override
  String get stashSyncTooltip => '立即同步 issue';

  @override
  String stashSyncTooltipLast(String time) {
    return '立即同步 issue · 上次 $time';
  }

  @override
  String stashSyncFailed(String repo, String error) {
    return '同步 $repo 的 issue 失败：$error';
  }

  @override
  String stashSyncSignIn(String forge, String repo, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '登录 $forge 后，$repo 等 $count 个仓库的 issue 会同步为 Stash。',
      one: '登录 $forge 后，$repo 的 issue 会同步为 Stash。',
    );
    return '$_temp0';
  }

  @override
  String get stashSyncingEmpty => '正在同步项目的 issue…';

  @override
  String get stashFilterAnyIssue => '所有来源';

  @override
  String get stashFilterIssue => '来自 issue';

  @override
  String get stashFilterNotIssue => '仅本地';

  @override
  String get stashImplementEmpty => '先写点内容，再在 BaoCode 中实施';

  @override
  String stashIssueDuplicateBanner(String issue, String stash) {
    return '$issue 来自合并进这条的 Stash $stash，还开着。作为重复关闭？';
  }

  @override
  String get stashIssueCloseDuplicate => '作为重复关闭…';

  @override
  String get stashIssueDuplicateNoIssue => '已合并到另一条记录，作为重复关闭。';

  @override
  String get stashNewsOpened => '新 issue';

  @override
  String get stashNewsChanged => '远端有改动';

  @override
  String get stashNewsCommented => '有新评论';

  @override
  String get stashNewsClosed => '已在远端关闭';

  @override
  String get stashNewsReopened => '已在远端重新打开';

  @override
  String stashNewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条新动态',
    );
    return '$_temp0';
  }

  @override
  String get stashNewsCountTooltip => '只看与你有关的新动态：你的 issue 和 PR、指派给你的、@ 你的';

  @override
  String get stashNewsCountTooltipOn => '正在只看与你有关的新动态，点一下看全部';

  @override
  String get stashFilterNews => '与你有关的动态';

  @override
  String get stashMarkAllSeen => '全部标为已读';

  @override
  String stashIssueComments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条评论',
    );
    return '$_temp0';
  }

  @override
  String get stashIssueDiscussion => '讨论';

  @override
  String stashIssueDiscussionAll(int count, String forge) {
    return '在 $forge 上查看全部 $count 条';
  }

  @override
  String get stashIssueDiscussionFailed => '评论加载失败。';

  @override
  String get stashIssueDiscussionLoading => '正在加载评论…';

  @override
  String stashDeleteAndClose(String issue) {
    return '删除并关闭 $issue…';
  }

  @override
  String stashDeleteOpenIssue(String issue) {
    return '它的 issue $issue 在远端还开着，除非一并关闭。';
  }

  @override
  String stashIssueInSync(String issue) {
    return '与 $issue 一致';
  }

  @override
  String stashIssueSyncedAt(String time) {
    return '$time 同步';
  }

  @override
  String get stashIssueNotPushed => '本地有改动，尚未推送';

  @override
  String get stashIssueRemoteNewer => '远端有改动';

  @override
  String get stashIssueBothChanged => '本地和远端都改了';

  @override
  String get stashIssueDiscussionEmpty => '还没有评论';

  @override
  String get stashNewsMerged => 'PR 已合并';

  @override
  String get stashNewsChangesRequested => 'PR 被要求修改';

  @override
  String get stashNewsChecksFailed => 'PR 检查没通过';

  @override
  String get stashNewsMarked => '标为未读';

  @override
  String stashNewsOther(String news) {
    return '$news（与你无关）';
  }

  @override
  String stashNewsSidebar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条与你有关的新动态',
    );
    return '$_temp0';
  }

  @override
  String get stashFilterAllNews => '所有新动态';

  @override
  String get stashMarkSeen => '标为已读';

  @override
  String get stashMarkUnseen => '标为未读';

  @override
  String stashPullChecksFailedBanner(String pull) {
    return '$pull 的检查没通过。';
  }

  @override
  String stashPullChangesBanner(String pull) {
    return '$pull 被要求修改。';
  }

  @override
  String stashPullMergedBanner(String pull) {
    return '$pull 已合并。这条也完成了吗？';
  }

  @override
  String get stashPullFix => '回到对话修复';

  @override
  String get stashPullView => '查看';

  @override
  String stashPullFixChecks(String pull) {
    return '$pull 的检查没通过，看看哪里失败了并修复。';
  }

  @override
  String stashPullFixChanges(String pull) {
    return '$pull 被要求修改，看一下评审意见并照着改。';
  }

  @override
  String stashWriteManyTitle(int count) {
    return '回复 $count 个 issue';
  }

  @override
  String stashWriteCloseManyTitle(int count) {
    return '关闭 $count 个 issue';
  }

  @override
  String stashDeleteOpenIssues(int count, String issues) {
    return '它们的 issue $issues 在远端还开着，除非一并关闭。';
  }

  @override
  String stashDeleteAndCloseMany(int count) {
    return '删除并关闭 $count 个 issue…';
  }

  @override
  String get gitLogRepository => '仓库';

  @override
  String get gitLogSearch => '搜索提交信息，多个用 | 分隔';

  @override
  String get gitLogClearSearch => '清除搜索';

  @override
  String get gitLogUser => '用户';

  @override
  String get gitLogAllUsers => '所有用户';

  @override
  String get gitLogMe => '我';

  @override
  String get gitLogDate => '日期';

  @override
  String get gitLogAnyDate => '不限';

  @override
  String get gitLogLastDay => '最近 24 小时';

  @override
  String get gitLogLastWeek => '最近 7 天';

  @override
  String get gitLogLastMonth => '最近 30 天';

  @override
  String get gitLogLastYear => '最近一年';

  @override
  String get gitLogHighlight => '高亮提交';

  @override
  String get gitLogHighlightNone => '不高亮';

  @override
  String get gitLogHighlightMine => '我的提交';

  @override
  String get gitLogClearFilters => '清除筛选';

  @override
  String get gitLogCheckout => '签出到...';

  @override
  String get gitLogSortTopo => '按拓扑顺序';

  @override
  String get gitLogSortDate => '按日期顺序';

  @override
  String get gitLogLocalBranches => '本地分支';

  @override
  String get gitLogRemoteBranches => '远程分支';

  @override
  String get gitLogTags => '标签';

  @override
  String get gitLogBackToLog => '返回日志';

  @override
  String get gitLogNoCommits => '没有符合条件的提交。';

  @override
  String get gitLogLocalChanges => '本地更改';

  @override
  String gitLogLocalChangesCount(int count) {
    return '本地更改（$count）';
  }

  @override
  String get gitLogSelectCommit => '选择一个提交以查看详情。';

  @override
  String get gitLogAuthor => '作者';

  @override
  String get gitLogParents => '父提交：';

  @override
  String get gitLogShowBranches => '显示分支';

  @override
  String get gitLogHideBranches => '隐藏分支';

  @override
  String get gitLogShowSizes => '显示大小';

  @override
  String get gitLogHideSizes => '隐藏大小';

  @override
  String gitLogFileCount(int count) {
    return '$count 个文件';
  }

  @override
  String get gitLogInNoBranch => '没有分支包含此提交。';

  @override
  String get gitLogList => '列表';

  @override
  String get gitLogTree => '树形';

  @override
  String get gitLogFilterFiles => '筛选文件，支持 * 和 ? 通配符';

  @override
  String get gitLogCopyPath => '复制路径';

  @override
  String get gitLogCopyRelativePath => '复制相对路径';

  @override
  String get gitLogBinary => '二进制';

  @override
  String get gitLogPreviousFile => '上一个文件';

  @override
  String get gitLogNextFile => '下一个文件';

  @override
  String get gitLogOpenInEditor => '在编辑器中打开';

  @override
  String get checkpointsTitle => '检查点';

  @override
  String get checkpointsDescription =>
      '智能体工作的项目快照，用来撤销它们的改动。对话 30 天没有新改动后会自动清理。';

  @override
  String checkpointsSize(String size) {
    return '已占用 $size';
  }

  @override
  String get checkpointsMeasuring => '正在计算…';

  @override
  String get checkpointsClear => '清理';

  @override
  String get checkpointsClearing => '正在清理…';

  @override
  String get checkpointsClearConfirm => '清理检查点？';

  @override
  String get checkpointsClearDetail => '没有打开的对话里，智能体的改动将无法再撤销。项目里的文件本身不受影响。';

  @override
  String gitLogToday(String time) {
    return '今天 $time';
  }

  @override
  String gitLogYesterday(String time) {
    return '昨天 $time';
  }

  @override
  String get gitLogCheckoutRevision => '签出此修订';

  @override
  String get gitLogNewBranch => '新建分支…';

  @override
  String gitLogNewBranchAt(String commit) {
    return '在 $commit 新建分支';
  }

  @override
  String gitLogCheckoutBranch(String branch) {
    return '签出“$branch”';
  }

  @override
  String get gitLogCopyHash => '复制完整哈希';

  @override
  String get gitLogLoading => '正在读取历史…';

  @override
  String get gitLogWorktree => '工作树';

  @override
  String gitLogWorktreeOf(String path) {
    return '工作树：$path';
  }

  @override
  String get gitLogFollowAgent => '跟随 AI 所在位置';

  @override
  String get gitLogAgentHere => 'AI 正在这里工作';

  @override
  String gitLogWorktreeAt(String name, String path) {
    return '已在工作树 $name 中签出\n$path';
  }

  @override
  String get gitLogMainWorktree => '主工作树';

  @override
  String get gitLogWorktreeMissing => '已不存在';

  @override
  String branchBarWorktree(String name, String path) {
    return '在工作树 $name 中\n$path';
  }

  @override
  String get gitCommitChanges => '更改';

  @override
  String get gitCommitUnversioned => '未纳入版本控制的文件';

  @override
  String get gitCommitConflicts => '合并冲突';

  @override
  String get gitCommitAmend => '修改上一次提交';

  @override
  String get gitCommitMessage => '提交信息';

  @override
  String get gitCommitButton => '提交';

  @override
  String get gitCommitAndPush => '提交并推送';

  @override
  String get gitCommitRollback => '回滚…';

  @override
  String gitCommitRollbackConfirm(int count) {
    return '回滚 $count 个文件的更改？';
  }

  @override
  String get gitCommitRollbackDetail => '这些文件将恢复到上次提交时的样子；尚未提交过的新文件会被删除。';

  @override
  String get gitCommitRollbackButton => '回滚';

  @override
  String get gitCommitShowDiff => '显示差异';

  @override
  String get gitCommitJumpToSource => '跳转到源';

  @override
  String get gitCommitAddToVcs => '添加到 VCS';

  @override
  String get gitCommitMarkResolved => '标记为已解决';

  @override
  String get gitCommitExpandAll => '全部展开';

  @override
  String get gitCommitCollapseAll => '全部折叠';

  @override
  String get gitCommitGroupByDirectory => '按目录分组';

  @override
  String get gitCommitEmptyMessage => '请填写提交信息。';

  @override
  String get gitCommitNothingSelected => '请勾选要提交的文件。';

  @override
  String get gitCommitNoChanges => '没有本地更改';

  @override
  String gitCommitSelected(int checked, int total) {
    return '已勾选 $checked/$total 个文件';
  }

  @override
  String get gitLogUndoCommit => '撤销提交';

  @override
  String get branchBarNewWorktree => '新建工作树…';

  @override
  String branchBarNewWorktreeFrom(String branch, String folder) {
    return '从“$branch”新建分支，放进“$folder”旁边的独立工作树：AI 在那里工作，你当前的签出不受影响';
  }

  @override
  String branchBarInWorktree(String name) {
    return '在工作树 $name';
  }

  @override
  String branchBarWorkIn(String path, String branch) {
    return '接下来请在 $path（分支 $branch）里工作：读写文件、运行命令都在这个目录进行。';
  }

  @override
  String get diffRevertChange => '回滚';

  @override
  String get diffRemoveChange => '删除';

  @override
  String get diffPreviousDifference => '上一处差异';

  @override
  String get diffNextDifference => '下一处差异';

  @override
  String diffDifferenceOf(int current, int count) {
    return '第 $current/$count 处';
  }

  @override
  String diffDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 处差异',
      zero: '没有差异',
    );
    return '$_temp0';
  }

  @override
  String get diffSettings => '查看设置';

  @override
  String get diffLayoutAuto => '够宽时并排';

  @override
  String get diffSideBySide => '并排查看';

  @override
  String get diffUnified => '单栏查看';

  @override
  String get diffIgnoreWhitespace => '忽略行首尾空白';

  @override
  String get diffWhitespaceNone => '不忽略空白';

  @override
  String get diffIgnoreAllWhitespace => '忽略所有空白';

  @override
  String get diffCollapseUnchanged => '折叠未改动的部分';

  @override
  String diffUnchangedLines(int count) {
    return '$count 行未改动';
  }

  @override
  String get diffHighlightCharacters => '按字符高亮';

  @override
  String get diffHighlightWords => '按词高亮';

  @override
  String get diffHighlightLines => '按行高亮';

  @override
  String get diffHighlightNone => '不高亮';

  @override
  String get diffGoToFile => '转到改动的文件';

  @override
  String get lineChangePrevious => '上一处改动';

  @override
  String get lineChangeNext => '下一处改动';

  @override
  String get lineChangeRollback => '回滚';

  @override
  String get lineChangeShowDiff => '显示差异';

  @override
  String get lineChangeCopy => '复制原来的内容';

  @override
  String get cmdNextChange => '转到下一处改动';

  @override
  String get cmdPreviousChange => '转到上一处改动';

  @override
  String get cmdShowNextChange => '显示下一处改动';

  @override
  String get cmdShowPreviousChange => '显示上一处改动';

  @override
  String get gitAnnotate => '用 Git Blame 注释';

  @override
  String get gitCloseAnnotations => '关闭注释';

  @override
  String get gitLogCopyPatch => '复制为补丁';

  @override
  String get gitLogCherryPick => '拣选到当前分支（Cherry-Pick）';

  @override
  String get gitLogCompareWithLocal => '与本地比较';

  @override
  String get gitLogResetToHere => '将当前分支重置到这里';

  @override
  String get gitLogResetSoft => 'Soft：改动留在暂存区';

  @override
  String get gitLogResetMixed => 'Mixed：改动留在工作区，不暂存';

  @override
  String get gitLogResetHard => 'Hard：丢弃改动';

  @override
  String get gitLogResetKeep => 'Keep：保留本地未提交的改动';

  @override
  String gitLogResetHardConfirm(String branch, String commit) {
    return '把“$branch”重置到 $commit，并丢弃之后的所有改动（不论是否已提交）？';
  }

  @override
  String get gitLogResetButton => '重置';

  @override
  String get gitLogRevertCommit => '还原提交（Revert）';

  @override
  String get gitLogEditMessage => '修改提交信息…';

  @override
  String get gitLogDropCommit => '删除提交';

  @override
  String gitLogDropConfirm(String commit, String subject) {
    return '从分支中拿掉 $commit“$subject”？';
  }

  @override
  String get gitLogDropButton => '删除';

  @override
  String get gitLogPushUpToHere => '推送到这里为止';

  @override
  String get gitLogNewTag => '新建标签…';

  @override
  String gitLogNewTagAt(String commit) {
    return '在 $commit 新建标签';
  }

  @override
  String get gitTagName => '标签名';

  @override
  String get gitTagMessage => '说明（可选，填了就是附注标签）';

  @override
  String get gitLogCreateTag => '创建标签';

  @override
  String get gitLogGoToParent => '转到父提交';

  @override
  String get gitLogGoToChild => '转到子提交';

  @override
  String gitLogComparedWithLocal(String commit) {
    return '$commit ↔ 本地';
  }

  @override
  String get gitLogNoDifferences => '与工作区没有差异';

  @override
  String get gitLogCopyHashes => '复制提交哈希';

  @override
  String gitLogCherryPickCount(int count) {
    return '拣选这 $count 个提交';
  }

  @override
  String get gitLogCompareCommits => '比较这两个提交';

  @override
  String gitLogRevertCommits(int count) {
    return '还原这 $count 个提交';
  }

  @override
  String gitLogSquashCommits(int count) {
    return '把这 $count 个提交合成一个（Squash）';
  }

  @override
  String gitLogCommitsSelected(int count) {
    return '已选 $count 个提交';
  }

  @override
  String get gitLogPaths => '路径';

  @override
  String get gitLogAllPaths => '所有路径';

  @override
  String gitLogCurrentFile(String path) {
    return '当前文件：$path';
  }

  @override
  String gitLogCurrentFolder(String path) {
    return '所在文件夹：$path';
  }

  @override
  String gitLogPathCount(int count) {
    return '$count 个路径';
  }

  @override
  String gitLogLinesOf(String file, int start, int end) {
    return '$file：第 $start–$end 行';
  }

  @override
  String get gitShowHistory => '显示历史';

  @override
  String get gitShowHistoryForSelection => '显示所选内容的历史';

  @override
  String get gitShowBranches => '显示分支';

  @override
  String get gitHideBranches => '隐藏分支';

  @override
  String get gitBranchesFilter => '筛选分支';

  @override
  String get gitBranchesHead => 'HEAD（当前分支）';

  @override
  String get gitBranchCheckout => '检出';

  @override
  String gitBranchNewFrom(String name) {
    return '从“$name”新建分支…';
  }

  @override
  String gitBranchCheckoutRebase(String current) {
    return '检出并变基到“$current”上';
  }

  @override
  String gitBranchCompare(String current) {
    return '与“$current”比较';
  }

  @override
  String get gitBranchDiffWorkingTree => '与工作区比较';

  @override
  String gitBranchRebaseOnto(String current, String name) {
    return '把“$current”变基到“$name”上';
  }

  @override
  String gitBranchMerge(String name, String current) {
    return '把“$name”合并到“$current”';
  }

  @override
  String gitBranchPullRebase(String current) {
    return '拉取到“$current”（变基）';
  }

  @override
  String gitBranchPullMerge(String current) {
    return '拉取到“$current”（合并）';
  }

  @override
  String get gitBranchUpdate => '更新';

  @override
  String get gitBranchPush => '推送';

  @override
  String gitBranchPushTo(String upstream) {
    return '推送到 $upstream';
  }

  @override
  String get gitBranchUpstream => '上游分支';

  @override
  String get gitBranchUnsetUpstream => '取消上游';

  @override
  String get gitBranchRename => '重命名…';

  @override
  String gitBranchRenameTitle(String name) {
    return '重命名分支“$name”';
  }

  @override
  String get gitBranchRenameButton => '重命名';

  @override
  String get gitBranchFavorite => '加入收藏';

  @override
  String get gitBranchUnfavorite => '取消收藏';

  @override
  String get gitBranchShowOnly => '日志里只看它';

  @override
  String get gitBranchDelete => '删除';

  @override
  String get gitTagDelete => '删除标签';

  @override
  String get gitBranchDeleteButton => '删除';

  @override
  String gitBranchDeleteRemoteConfirm(String name) {
    return '删除远程上的分支“$name”？';
  }

  @override
  String gitBranchNotMergedConfirm(String name) {
    return '“$name”有还没合并到其他分支的提交。仍然删除？';
  }

  @override
  String gitBranchDeleted(String name) {
    return '已删除分支“$name”。';
  }

  @override
  String gitTagDeleted(String name) {
    return '已删除标签“$name”。';
  }

  @override
  String get gitBranchRestore => '恢复';

  @override
  String gitBranchCompared(String name, String current, int ahead, int behind) {
    return '“$name”有 $ahead 个“$current”没有的提交；“$current”有 $behind 个它没有的提交。';
  }

  @override
  String get gitBranchCompareFiles => '查看改动的文件';

  @override
  String scmGraphRangeIn(String to, String from) {
    return '“$to”有而“$from”没有的提交';
  }

  @override
  String get gitBranchesRecent => '最近';

  @override
  String get gitBranchesSearch => '搜索分支和操作';

  @override
  String get gitUpdateProject => '更新项目';

  @override
  String get gitCommitEllipsis => '提交…';

  @override
  String get gitPushEllipsis => '推送…';

  @override
  String get gitNewBranchEllipsis => '新建分支…';

  @override
  String get gitCheckoutRevision => '检出标签或修订…';

  @override
  String get gitBranchesTitle => 'Git 分支';

  @override
  String get gitRevisionPlaceholder => '标签、分支或提交哈希';

  @override
  String get gitUpdateProjectDetail =>
      '把每个仓库的当前分支更新到它的上游：合并上游的新提交，或者把本分支自己的提交变基到上面。期间本地改动会先暂存（stash）。';

  @override
  String get gitUpdateMerge => '合并';

  @override
  String get gitUpdateRebase => '变基';

  @override
  String get gitDontAskAgain => '不再询问';

  @override
  String get gitPushTitle => '推送提交';

  @override
  String get gitPushTags => '推送标签';

  @override
  String get gitPushForce => '强制推送';

  @override
  String gitPushForceConfirm(String targets) {
    return '强制推送到 $targets？';
  }

  @override
  String get gitPushForceDetail =>
      '远程上的内容会被你推送的替换（with lease：只在远程还是上次获取时的样子才会覆盖，别人更新的提交不会丢）。';

  @override
  String get gitPushNothing => '没有要推送的提交';

  @override
  String get gitPushRemote => '远程';

  @override
  String get gitPushNew => '新分支';

  @override
  String get gitPushSelectCommit => '选一个提交，查看它的文件';

  @override
  String get gitPushEllipsisCommand => '推送…';

  @override
  String get gitOperationRebasing => '正在变基';

  @override
  String get gitOperationMerging => '正在合并';

  @override
  String get gitOperationCherryPicking => '正在 Cherry-pick';

  @override
  String get gitOperationReverting => '正在还原';

  @override
  String gitOperationConflicts(int count) {
    return '还剩 $count 个冲突';
  }

  @override
  String get gitOperationResolved => '冲突已解决';

  @override
  String get gitOperationContinue => '继续';

  @override
  String get gitOperationSkip => '跳过';

  @override
  String get gitOperationAbort => '中止';

  @override
  String gitOperationAbortConfirm(String what) {
    return '中止？$what会停下，已经做的会撤销。';
  }

  @override
  String get gitConflictAcceptCurrent => '采用当前的（Ours）';

  @override
  String get gitConflictAcceptIncoming => '采用传入的（Theirs）';

  @override
  String get gitConflictMerge => '合并…';

  @override
  String gitMergeTitle(String path) {
    return '合并 $path 的修订';
  }

  @override
  String get gitMergeOurs => '当前的（Ours）';

  @override
  String get gitMergeResult => '结果';

  @override
  String get gitMergeTheirs => '传入的（Theirs）';

  @override
  String gitMergeConflictsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还剩 $count 个冲突',
      zero: '冲突已全部解决',
    );
    return '$_temp0';
  }

  @override
  String gitMergeChangesApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已应用 $count 处无冲突的更改',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get gitMergePrevious => '上一个冲突';

  @override
  String get gitMergeNext => '下一个冲突';

  @override
  String get gitMergeApply => '应用';

  @override
  String get gitMergeAppend => '追加';

  @override
  String get gitMergeIgnore => '忽略';

  @override
  String get gitMergeAi => 'AI 合并';

  @override
  String get gitMergeAiAll => '用 AI 合并全部冲突';

  @override
  String gitMergeAiFailed(String error) {
    return 'AI 没能合并这个冲突：$error';
  }

  @override
  String get gitMergeAiNoAnswer => '回复里没有合并后的代码';

  @override
  String get gitMergeAcceptOurs => '采用当前的';

  @override
  String get gitMergeAcceptTheirs => '采用传入的';

  @override
  String gitMergeUnresolved(int count) {
    return '还有 $count 个冲突没解决。';
  }

  @override
  String get gitMergeUnresolvedDetail => '按现在的结果保存，并把文件标记为已解决？';

  @override
  String get gitMergeSaveAnyway => '保存并标记为已解决';

  @override
  String get gitMergeDiscard => '放弃这次合并的结果？';

  @override
  String get gitMergeDiscardButton => '放弃';

  @override
  String get gitDiffExcludeChange => '这处改动不提交';

  @override
  String get gitDiffIncludeChange => '提交这处改动';

  @override
  String get gitDiffExcludeLine => '这一行不提交';

  @override
  String get gitDiffIncludeLine => '提交这一行';

  @override
  String get gitChangelistActive => '当前';

  @override
  String get gitChangelistMoveTo => '移到其他变更列表';

  @override
  String get gitChangelistNew => '新建变更列表…';

  @override
  String get gitChangelistCreate => '新建';

  @override
  String get gitChangelistName => '变更列表名称';

  @override
  String get gitChangelistCommitOnly => '只提交这个变更列表';

  @override
  String get gitChangelistSetActive => '设为当前变更列表';

  @override
  String get gitChangelistRename => '重命名变更列表…';

  @override
  String get gitChangelistRenameButton => '重命名';

  @override
  String get gitChangelistDelete => '删除变更列表';

  @override
  String gitChangelistTurn(String request) {
    return 'AI：$request';
  }

  @override
  String get gitStashChangesTitle => '暂存改动（Stash）';

  @override
  String gitStashFilesTitle(int count) {
    return '暂存 $count 个文件（Stash）';
  }

  @override
  String get gitStashButton => '暂存';

  @override
  String get gitStashMessage => '说明（可不填）';

  @override
  String get gitStashUntracked => '包含未跟踪的文件';

  @override
  String get gitStashBase => '基准';

  @override
  String get gitStashApply => '应用';

  @override
  String get gitStashPop => '应用并删除（Pop）';

  @override
  String get gitStashAsBranch => '取出为新分支…';

  @override
  String get gitStashCopyMessage => '复制说明';

  @override
  String get gitStashDrop => '删除…';

  @override
  String gitStashDropConfirm(String ref) {
    return '删除 $ref？';
  }

  @override
  String get gitStashDropButton => '删除';

  @override
  String get gitStashClear => '清空 Stash…';

  @override
  String get gitStashClearConfirm => '删除全部 Stash？';

  @override
  String get gitStashClearButton => '清空';

  @override
  String get gitStashNone => '没有 Stash';

  @override
  String get gitStashTab => 'Stash';

  @override
  String get gitCommitTab => '提交';

  @override
  String get gitStashSelected => '暂存选中的文件…';

  @override
  String get gitCommitIgnored => '已忽略的文件';

  @override
  String get gitCommitShowIgnored => '显示已忽略的文件';

  @override
  String gitCommitLongSubject(int limit) {
    return '标题超过 $limit 个字符';
  }

  @override
  String get gitCommitNoBlankLine => '标题和正文之间要空一行';

  @override
  String get gitCommitMessageHistory => '提交信息历史 (Ctrl+M)';

  @override
  String get gitCommitNoMessageHistory => '还没有提交信息';

  @override
  String get gitCommitOptions => '提交选项';

  @override
  String get gitCommitAuthor => '作者…';

  @override
  String gitCommitAuthorIs(String author) {
    return '作者：$author';
  }

  @override
  String get gitCommitAuthorReset => '使用配置的作者';

  @override
  String get gitCommitAuthorPlaceholder => '姓名 <邮箱>';

  @override
  String get gitCommitSignOff => '签名提交 (Sign-off)';

  @override
  String get gitCommitRunHooks => '运行 Git 钩子';

  @override
  String get gitCommitSignedOff => '已签名';

  @override
  String get gitCommitNoHooks => '跳过钩子';

  @override
  String get gitLogInteractiveRebase => '从这里开始交互式变基…';

  @override
  String gitRebaseTitle(int count, String base) {
    return '变基 $count 个提交（从 $base 开始）';
  }

  @override
  String get gitRebasePick => '保留';

  @override
  String get gitRebaseReword => '改信息';

  @override
  String get gitRebaseEdit => '编辑';

  @override
  String get gitRebaseSquash => '压缩';

  @override
  String get gitRebaseFixup => '修正';

  @override
  String get gitRebaseDrop => '丢弃';

  @override
  String get gitRebaseMoveUp => '上移 (Alt+↑)';

  @override
  String get gitRebaseMoveDown => '下移 (Alt+↓)';

  @override
  String get gitRebaseMessage => '提交信息';

  @override
  String get gitRebaseStart => '开始变基';

  @override
  String get gitRebaseNothingBelow => '保留下来的最早一个提交不能压缩或修正：它下面没有提交可以并入。';

  @override
  String get gitRebaseStopped => '变基已暂停：修改这个提交或解决冲突后，点「继续」。';

  @override
  String get gitRebaseCleanUpWithAi => '让 AI 整理';

  @override
  String get gitRebaseCleanUpWithAiDetail => '由模型建议哪些提交该修正、压缩、改信息；开始变基前你可以逐条检查';

  @override
  String get gitRebaseAiPlanning => '整理中…（点击停止）';

  @override
  String get gitRebaseAiNoPlan => '模型的回答不是这些提交的变基列表。';

  @override
  String gitRebaseAiFailed(String error) {
    return 'AI 整理失败：$error';
  }

  @override
  String gitTagPushTo(String remote) {
    return '推送标签到 $remote';
  }

  @override
  String gitTagDeleteOn(String remote) {
    return '删除 $remote 上的标签';
  }

  @override
  String gitTagDeleteOnConfirm(String name, String remote) {
    return '删除 $remote 上的标签 $name？';
  }

  @override
  String get gitRemotesManage => '管理远程仓库…';

  @override
  String get gitRemotesTitle => 'Git 远程仓库';

  @override
  String get gitRemotesNone => '没有远程仓库';

  @override
  String get gitRemoteAdd => '添加远程仓库';

  @override
  String get gitRemoteEdit => '编辑远程仓库';

  @override
  String get gitRemoteRemove => '移除';

  @override
  String get gitRemoteName => '名称';

  @override
  String get gitRemoteUrl => 'URL';

  @override
  String gitRemoteRemoveConfirm(String name) {
    return '移除远程仓库 $name？';
  }

  @override
  String get gitRemoteRemoveDetail => '它的远程分支会一起移除；服务器上的内容不受影响。';

  @override
  String get gitCloneTitle => '从版本控制获取';

  @override
  String get gitCloneUrl => 'URL';

  @override
  String get gitCloneDirectory => '目录';

  @override
  String get gitCloneBrowse => '浏览…';

  @override
  String get gitCloneButton => '克隆';

  @override
  String get gitCloning => '正在克隆…';

  @override
  String get gitCloneCommand => '克隆仓库…';

  @override
  String get gitReviewWithAi => '用 AI 审查改动';

  @override
  String get gitReviewStop => '停止审查';

  @override
  String get gitReviewBeforeCommit => '提交前用 AI 审查';

  @override
  String get gitReviewRunning => '正在审查改动…';

  @override
  String get gitReviewClean => '没有发现问题';

  @override
  String gitReviewFound(int count) {
    return '发现 $count 个问题';
  }

  @override
  String get gitReviewCommitAnyway => '仍然提交';

  @override
  String get gitReviewCommitAndPushAnyway => '仍然提交并推送';

  @override
  String gitReviewFailed(String error) {
    return '审查失败：$error';
  }

  @override
  String get gitAskAiCommit => '问 AI 这个提交';

  @override
  String gitAskAiCommitPrompt(String id, String subject) {
    return '解释提交 $id（“$subject”）：改了什么、为什么改，以及有没有看起来有风险的地方。可以用 `git show $id` 查看。';
  }

  @override
  String gitAskAiCommits(int count) {
    return '问 AI 这 $count 个提交';
  }

  @override
  String gitAskAiCommitsPrompt(String ids) {
    return '解释提交 $ids：它们合起来改了什么，以及有没有看起来有风险的地方。可以用 `git show` 查看。';
  }

  @override
  String get gitAskAiHunk => '问 AI 这处改动';

  @override
  String gitAskAiHunkPrompt(String path, int line, String change) {
    return '关于 $path 第 $line 行的这处改动：解释它做了什么，有没有问题。\n\n```diff\n$change\n```';
  }

  @override
  String get gitAskAiChanges => '问 AI 这些改动';

  @override
  String gitAskAiChangesPrompt(String paths) {
    return '审查我在 $paths 中还没提交的改动（`git diff HEAD -- $paths`）：说明它们做了什么，指出有问题的地方。';
  }

  @override
  String get gitAskAiConflicts => '让 AI 解决冲突';

  @override
  String gitAskAiConflictsPrompt(String paths) {
    return '解决 $paths 中的合并冲突：保留双方各自的意图，然后告诉我你是怎么取舍的。不要暂存或提交。';
  }

  @override
  String get gitLogFixup => '用勾选的改动修正 (Fixup)';

  @override
  String get compareWith => '比较';

  @override
  String get compareWithClipboard => '剪贴板';

  @override
  String compareWithClipboardLabel(String name) {
    return '$name（剪贴板 ↔ 文件）';
  }

  @override
  String get gitCompareWithBranch => '分支或标签…';

  @override
  String get gitCompareWithRevision => '某个版本…';

  @override
  String get gitCompareWithBranchPlaceholder => '选择要与文件比较的分支或标签';

  @override
  String get gitCompareWithRevisionPlaceholder => '选择要比较的文件版本';

  @override
  String gitCompareLabel(String name, String other) {
    return '$name（$other ↔ 工作区）';
  }

  @override
  String get explorerSelectForCompare => '选择以进行比较';

  @override
  String explorerCompareWithSelected(String name) {
    return '与“$name”比较';
  }

  @override
  String compareFoldersSame(String original, String modified) {
    return '“$original”和“$modified”的文件完全相同。';
  }

  @override
  String compareFoldersPick(String original, String modified) {
    return '“$original”和“$modified”不同的文件';
  }

  @override
  String compareFoldersOnlyIn(String name) {
    return '只在“$name”里';
  }

  @override
  String get compareFoldersModified => '有改动';

  @override
  String get compareWithLocalHistory => '本地历史…';

  @override
  String get localHistoryShow => '查看本地历史';

  @override
  String localHistoryNone(String name) {
    return '“$name”还没有本地历史：保存文件时才会记录。';
  }

  @override
  String localHistoryPick(String name) {
    return '选择“$name”的一个版本来比较';
  }

  @override
  String localHistoryLabel(String name, String time) {
    return '$name（本地历史，$time）';
  }

  @override
  String get explorerCompareSelected => '比较所选文件';

  @override
  String compareFilesLabel(String original, String modified) {
    return '$original ↔ $modified';
  }
}
