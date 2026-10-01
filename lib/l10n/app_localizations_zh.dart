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
  String get languageSettingsDescription => 'Monad 的菜单、视图和消息所用的语言。更改立即生效。';

  @override
  String get languageSettingsFollowSystem => '跟随系统';

  @override
  String languageSettingsFollowSystemDetail(String language) {
    return '当前：$language';
  }

  @override
  String get languageSettingsEnglishName => '英语';

  @override
  String get languageSettingsSimplifiedChineseName => '简体中文';

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
  String interactionHintSkip(String keybinding) {
    return '$keybinding 跳过';
  }

  @override
  String get cmdCategoryChat => '聊天';

  @override
  String get cmdChatNewAgent => '新建智能体';

  @override
  String get cmdChatClosePane => '关闭窗格';

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
  String get cmdChatSearchAgents => '搜索智能体';

  @override
  String get cmdChatOpenIde => '在 Fast Ide 中打开';

  @override
  String get cmdChatFocusInput => '聚焦聊天输入';

  @override
  String get cmdChatFocusList => '聚焦聊天列表';

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
  String get cmdChatOpenModelPicker => '打开模型选择器';

  @override
  String get cmdChatAttachContext => '添加上下文…';

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
  String get cmdFind => '查找';

  @override
  String get cmdReplace => '替换';

  @override
  String get cmdSave => '保存';

  @override
  String get cmdSaveAll => '全部保存';

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
  String get menuOpenFolder => '打开文件夹…';

  @override
  String get menuCloseWindow => '关闭窗口';

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
  String get menuAboutMonad => '关于 Monad';

  @override
  String get windowShowSidebar => '显示侧边栏';

  @override
  String get windowHideSidebar => '隐藏侧边栏';

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
  String get agentUntitled => '新智能体';

  @override
  String get sidebarNewAgent => '新建智能体';

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
  String get sidebarDone => '已完成';

  @override
  String get sidebarArchived => '已归档';

  @override
  String get sidebarOpenFolder => '打开文件夹…';

  @override
  String get sidebarAgents => '智能体';

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
  String sidebarDeleteAgentMessageKernel(String title, String kernel) {
    return '“$title”及其对话将被删除，$kernel 中的记录也会一并删除。此操作无法撤销。';
  }

  @override
  String get sidebarSearchAgents => '搜索智能体…';

  @override
  String sidebarNewAgentIn(String project) {
    return '在 $project 中新建智能体';
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
  String get statusRunning => '运行中';

  @override
  String get statusDone => '已完成';

  @override
  String get statusFailed => '失败';

  @override
  String get statusGone => '已消失';

  @override
  String chatSubagentStatus(String status) {
    return '子智能体$status';
  }

  @override
  String get chatSubagentExplainer => '子智能体为主智能体工作：消息会发送到主对话中。';

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
  String get toolSending => '正在发送';

  @override
  String get toolSent => '已发送';

  @override
  String get toolUsing => '正在使用';

  @override
  String get toolUsed => '已使用';

  @override
  String imageChip(int number) {
    return '图片 $number';
  }

  @override
  String imageReferenceRemoved(int number) {
    return '[图片 $number]';
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
  String stepsFailed(int count) {
    return '$count 个失败';
  }

  @override
  String turnWorked(String duration) {
    return '已处理 $duration';
  }

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
  String get chatEmptyTitle => '规划、构建，无所不能';

  @override
  String get chatEmptyHint => '@ 添加上下文 · / 使用命令';

  @override
  String get activityCompacting => '正在压缩对话';

  @override
  String get activityPlanning => '正在规划下一步';

  @override
  String get activityMusings =>
      '冥思苦想\n琢磨一下\n慢慢酝酿\n深思熟虑\n文火慢炖\n入味中\n修修补补\n融会贯通\n反复掂量\n连点成线\n追一个直觉\n酝酿计划\n孵化方案\n权衡利弊\n理清头绪\n赶着一群 token\n召唤上下文\n网格化样条曲线\n请教小黄鸭\n看茶叶占卜\n在餐巾纸上打草稿\n在页边涂鸦\n眯眼看 diff\n数括号\n和编译器交朋友\n与类型系统谈判\n驯服边界情况\n追踪调用栈\n翻阅文档\n探索代码库\n把鸭子排成一排\n摇一摇魔法 8 号球\n预热神经元\n折叠思绪\n调整状态\n绑定 Monad\n提升进 Monad\n求问神谕\n搅一搅锅\n打磨计划';

  @override
  String get composerCommands => '命令';

  @override
  String get composerFilesAndContext => '文件、文件夹和上下文';

  @override
  String get composerPlaceholder => '规划、搜索、构建任何内容  ·  @ 提及  / 命令';

  @override
  String composerApprovalTitle(String agent) {
    return '$agent 应如何获得批准？';
  }

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
  String get stripUndoAll => '全部撤销';

  @override
  String get stripKeepAll => '全部保留';

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
  String get healthHideDetails => '隐藏详细信息';

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
  String get interactionKeepPlanningOption => '不，继续规划';

  @override
  String get interactionWhatShouldChange => '需要改什么？';

  @override
  String interactionStepOf(int step, int total) {
    return '$step / $total';
  }

  @override
  String get interactionSkip => '跳过';

  @override
  String get interactionKeepPlanning => '继续规划';

  @override
  String get interactionSubmit => '提交';

  @override
  String get interactionNext => '下一步';

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
  String todoCount(int done, int total) {
    return '待办 $done/$total';
  }

  @override
  String get messageQueued => '排队中';

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
  String get tabCopyPath => '复制路径';

  @override
  String get tabCopyRelativePath => '复制相对路径';

  @override
  String get tabRevealInExplorerView => '在资源管理器视图中显示';

  @override
  String get tabMoreActions => '更多操作…';

  @override
  String tabCloseNamed(String name) {
    return '关闭 $name';
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
  String get explorerTrashFailed => '无法通过废纸篓删除。是否改为永久删除?';

  @override
  String get explorerDeletePermanently => '永久删除';

  @override
  String get explorerPasteIntoAncestor => '要粘贴的文件是目标文件夹的上级';

  @override
  String get explorerNewFile => '新建文件...';

  @override
  String get explorerNewFolder => '新建文件夹...';

  @override
  String get explorerRevealInFinder => '在访达中显示';

  @override
  String get explorerFindInFolder => '在文件夹中查找...';

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
  String langNotInstalled(String id) {
    return '$id 未安装';
  }

  @override
  String langNeedsRuntime(String id, String runtime) {
    return '安装 $id 需要 $runtime，但未找到';
  }

  @override
  String langClickToInstall(String id) {
    return '单击以安装 $id';
  }

  @override
  String langNotOnPath(String id) {
    return '在 PATH 中找不到 $id';
  }

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
  String get wbLanguageServices => '语言服务';

  @override
  String get wbMonacoEditor => 'Monaco 编辑器';

  @override
  String get wbTextEditor => '文本编辑器';

  @override
  String get wbRetryLanguageServices => '重试语言服务';

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
  String get wbEndOfLine => '行尾序列';

  @override
  String get wbEolMixed => '混合';

  @override
  String get wbLanguageMode => '语言模式';

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
      other: 'Monad 无法识别上下文键 $keys: 此快捷键永远不会生效。',
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
    return 'Monad 无法识别按键“$key”: 此快捷键永远不会生效。';
  }

  @override
  String get kbNotSupported => '不支持';

  @override
  String get kbNotSupportedHover => 'Monad 没有此命令: 快捷键会保留，但不起作用。';

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
  String get dataDirChecking => '正在检查文件夹…';

  @override
  String get dataDirAlreadyHolds => '该文件夹中已有 Monad 数据';

  @override
  String get dataDirMoveBack => '将 Monad 的数据移回默认文件夹?';

  @override
  String get dataDirMoveHere => '将 Monad 的数据移到此文件夹?';

  @override
  String get dataDirUseAsIsDetail =>
      '重启后 Monad 将直接使用那里的数据；不会复制任何内容，当前文件夹中的数据保持不变。';

  @override
  String get dataDirCopyDetail => 'Monad 会将其设置、快捷键、语言服务器和状态复制到那里，并在重启后使用该文件夹。';

  @override
  String get dataDirOtherFiles => '该文件夹中还有其他文件: 它们会保留，与 Monad 自己的文件并存。';

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
  String get dataDirRestartTitle => '重启 Monad 以使用新的数据文件夹';

  @override
  String dataDirRestartDetail(String current, String next) {
    return 'Monad 在重启前会继续使用 $current。下次启动时将使用 $next，并询问是否移除旧文件夹中剩余的内容。';
  }

  @override
  String get dataDirTheNewFolder => '新文件夹';

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
      'Monad 存放你的设置、快捷键、语言服务器及其自身状态的位置。其他程序也会在此存放文件(如网页视图的缓存)；Monad 从不移动或删除这些文件。';

  @override
  String get dataDirCurrentFolder => '当前文件夹';

  @override
  String dataDirAfterRestart(String path) {
    return '重启后: $path';
  }

  @override
  String get dataDirChange => '更改…';

  @override
  String get dataDirResetDefault => '重置为默认';

  @override
  String dataDirEnvDecides(String variable) {
    return '文件夹由 $variable 决定；取消设置该变量后才能在此选择。';
  }

  @override
  String dataDirCannotWritePointer(String file, String error) {
    return '无法写入 $file: $error';
  }

  @override
  String get dataDirSettingUnreadable => '无法读取 Monad 的数据文件夹设置';

  @override
  String get dataDirCannotWrite => 'Monad 无法写入其数据文件夹';

  @override
  String get dataDirUnavailable => 'Monad 的数据文件夹不可用';

  @override
  String dataDirWhereEnv(String variable) {
    return '它由环境变量 $variable 设置。';
  }

  @override
  String dataDirWhereFixPointer(String file) {
    return '请修复或删除 $file 后重试；只有在你选择其他文件夹时 Monad 才会更改它。';
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
  String get dataDirRemoveOldTitle => '是否移除 Monad 留在之前文件夹中的数据?';

  @override
  String dataDirRemoveOldDetail(String current, String items) {
    return 'Monad 现在将数据存放在 $current。只会从之前的文件夹中移除它自己的项目($items)；该文件夹及其中的其他内容都会保留。';
  }

  @override
  String get dataDirRemove => '移除';

  @override
  String get dataDirKeep => '保留';

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
}
