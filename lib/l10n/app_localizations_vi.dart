// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get commonCancel => 'Hủy';

  @override
  String get commonClose => 'Đóng';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDelete => 'Xóa';

  @override
  String get commonRename => 'Đổi tên';

  @override
  String get commonCopy => 'Sao chép';

  @override
  String get commonCut => 'Cắt';

  @override
  String get commonPaste => 'Dán';

  @override
  String get commonUndo => 'Hoàn tác';

  @override
  String get commonRedo => 'Làm lại';

  @override
  String get commonSelectAll => 'Chọn tất cả';

  @override
  String get languageSettingsTitle => 'Khu vực & Ngôn ngữ';

  @override
  String get languageSettingsDisplayLanguage => 'Ngôn ngữ hiển thị';

  @override
  String get languageSettingsDescription =>
      'Ngôn ngữ dùng trong menu, các chế độ xem và thông báo của BaoCode. Thay đổi có hiệu lực ngay.';

  @override
  String languageSettingsFollowSystemCurrent(String language) {
    return 'Theo hệ thống ($language)';
  }

  @override
  String languageSettingsDisplayLanguageLabel(String name) {
    return 'Ngôn ngữ hiển thị: $name';
  }

  @override
  String get cmdCategoryFile => 'Tệp';

  @override
  String get cmdCategoryView => 'Xem';

  @override
  String get cmdCategoryTerminal => 'Terminal';

  @override
  String get cmdCategoryGo => 'Đi tới';

  @override
  String get cmdCategoryPreferences => 'Tùy chọn';

  @override
  String get cmdCategoryDeveloper => 'Nhà phát triển';

  @override
  String get cmdCategoryEditor => 'Trình chỉnh sửa';

  @override
  String get cmdCategoryHelp => 'Trợ giúp';

  @override
  String get cmdCategoryList => 'Danh sách';

  @override
  String get composerSetMode => 'Chọn chế độ';

  @override
  String get composerPickModel => 'Chọn mô hình';

  @override
  String get interactionHintChoose => 'Nhấn 1–9 để chọn';

  @override
  String interactionHintContinue(String keybinding) {
    return 'Nhấn $keybinding để tiếp tục';
  }

  @override
  String interactionHintBack(String keybinding) {
    return 'Nhấn $keybinding để quay lại';
  }

  @override
  String interactionHintSkip(String keybinding) {
    return 'Nhấn $keybinding để bỏ qua';
  }

  @override
  String get cmdCategoryChat => 'Trò chuyện';

  @override
  String get cmdCategoryTasks => 'Tác vụ';

  @override
  String get cmdChatNewAgent => 'Cuộc trò chuyện mới';

  @override
  String get cmdChatClosePane => 'Đóng khung';

  @override
  String get cmdChatCloseTab => 'Đóng cuộc trò chuyện';

  @override
  String get cmdChatNextAgent => 'Mở agent tiếp theo';

  @override
  String get cmdChatPreviousAgent => 'Mở agent trước đó';

  @override
  String cmdChatOpenAgentAtIndex(int index) {
    return 'Mở agent tại vị trí $index';
  }

  @override
  String cmdChatFocusPane(int index) {
    return 'Chuyển tiêu điểm đến khung $index';
  }

  @override
  String get cmdChatFocusNextPane => 'Chuyển tiêu điểm đến khung tiếp theo';

  @override
  String get cmdChatFocusPreviousPane => 'Chuyển tiêu điểm đến khung trước đó';

  @override
  String get cmdChatFocusPaneLeft => 'Chuyển tiêu điểm sang khung bên trái';

  @override
  String get cmdChatFocusPaneRight => 'Chuyển tiêu điểm sang khung bên phải';

  @override
  String get cmdChatFocusPaneUp => 'Chuyển tiêu điểm lên khung phía trên';

  @override
  String get cmdChatFocusPaneDown => 'Chuyển tiêu điểm xuống khung phía dưới';

  @override
  String get cmdChatNextPaneTab => 'Mở tab tiếp theo trong khung';

  @override
  String get cmdChatPreviousPaneTab => 'Mở tab trước đó trong khung';

  @override
  String get cmdChatTogglePaneTabs => 'Bật/tắt tab trong khung';

  @override
  String get workspacePaneTabs => 'Hiển thị dưới dạng tab';

  @override
  String get cmdChatSearch => 'Tìm kiếm';

  @override
  String get cmdChatSearchAgents => 'Tìm agent';

  @override
  String get cmdChatOpenIde => 'Mở trong Fast IDE';

  @override
  String get cmdChatFocusInput => 'Chuyển tiêu điểm đến ô nhập trò chuyện';

  @override
  String get cmdChatFocusList => 'Chuyển tiêu điểm đến danh sách trò chuyện';

  @override
  String get cmdChatFind => 'Tìm trong cuộc trò chuyện';

  @override
  String get cmdChatCancel => 'Hủy';

  @override
  String get cmdChatAcceptTool => 'Chấp nhận';

  @override
  String get cmdChatSkipTool => 'Bỏ qua';

  @override
  String get cmdChatToggleContextPanel => 'Bật/tắt bảng ngữ cảnh';

  @override
  String get cmdChatRenameAgent => 'Đổi tên agent';

  @override
  String get cmdChatCloseSubagent => 'Quay lại từ subagent';

  @override
  String get cmdChatSubmit => 'Gửi';

  @override
  String get cmdChatCancelEdit => 'Hủy chỉnh sửa';

  @override
  String get cmdChatShowPreviousPrompt => 'Xem prompt trước';

  @override
  String get cmdChatShowNextPrompt => 'Xem prompt tiếp theo';

  @override
  String get cmdChatAcceptPromptSuggestion => 'Chấp nhận prompt đề xuất';

  @override
  String get cmdChatOpenModePicker => 'Mở bộ chọn chế độ';

  @override
  String get cmdChatNextMode => 'Chuyển sang chế độ tiếp theo';

  @override
  String get cmdChatOpenModelPicker => 'Mở bộ chọn mô hình';

  @override
  String get cmdChatAttachContext => 'Thêm ngữ cảnh…';

  @override
  String get cmdChatAttachSelection => 'Thêm phần đã chọn vào cuộc trò chuyện';

  @override
  String get cmdChatPasteRaw => 'Dán dưới dạng văn bản thuần';

  @override
  String get cmdChatSelectNextSuggestion => 'Chọn gợi ý tiếp theo';

  @override
  String get cmdChatSelectPrevSuggestion => 'Chọn gợi ý trước đó';

  @override
  String get cmdChatAcceptSelectedSuggestion => 'Chấp nhận gợi ý đã chọn';

  @override
  String get cmdChatHideSuggestWidget => 'Ẩn gợi ý';

  @override
  String get cmdChatInteractionFocusNext =>
      'Chuyển tiêu điểm đến lựa chọn tiếp theo';

  @override
  String get cmdChatInteractionFocusPrevious =>
      'Chuyển tiêu điểm đến lựa chọn trước đó';

  @override
  String get cmdChatInteractionBack => 'Quay lại câu hỏi trước';

  @override
  String get cmdChatInteractionToggle => 'Bật/tắt lựa chọn';

  @override
  String get cmdChatInteractionAccept => 'Tiếp tục';

  @override
  String get cmdChatInteractionDismiss => 'Bỏ qua';

  @override
  String get cmdOpenFilePreserveFocus => 'Mở tệp nhưng giữ nguyên tiêu điểm';

  @override
  String ideSearchProject(String name) {
    return 'Tìm kiếm $name';
  }

  @override
  String get idePanelProblems => 'Vấn đề';

  @override
  String get idePanelReferences => 'Tham chiếu';

  @override
  String get idePanelTerminal => 'Terminal';

  @override
  String get cmdScmFocus => 'Chuyển tiêu điểm đến chế độ xem thay đổi';

  @override
  String get cmdScmAcceptInput => 'Chấp nhận nội dung nhập';

  @override
  String get cmdScmClearValidation => 'Xóa kết quả xác thực';

  @override
  String get cmdGitCheckout => 'Chuyển nhánh...';

  @override
  String get cmdScmClearInput => 'Xóa nội dung nhập';

  @override
  String get cmdCategoryGit => 'Git';

  @override
  String get cmdProblemsFocus =>
      'Chuyển tiêu điểm đến Vấn đề (lỗi, cảnh báo, thông tin)';

  @override
  String get cmdProblemsOpen => 'Mở';

  @override
  String get cmdProblemsCopyMessage => 'Sao chép thông báo';

  @override
  String get cmdReferencesNext => 'Đi đến tham chiếu tiếp theo';

  @override
  String get cmdReferencesPrevious => 'Đi đến tham chiếu trước đó';

  @override
  String get cmdCategoryReferences => 'Tham chiếu';

  @override
  String get cmdTerminalFocusFind => 'Tập trung Tìm';

  @override
  String get cmdTerminalHideFind => 'Ẩn Tìm';

  @override
  String get cmdTerminalToggleFindRegex => 'Chuyển đổi Tìm bằng Regex';

  @override
  String get cmdTerminalToggleFindWholeWord =>
      'Chuyển đổi Tìm bằng cách sử dụng toàn bộ từ';

  @override
  String get cmdTerminalToggleFindCaseSensitive =>
      'Chuyển đổi Tìm bằng cách sử dụng phân biệt chữ hoa chữ thường';

  @override
  String get cmdTerminalSearchWorkspace => 'Tìm kiếm không gian làm việc';

  @override
  String get cmdTerminalCopySelection => 'Sao chép lựa chọn';

  @override
  String get cmdTerminalCopyAndClearSelection => 'Sao chép và xóa lựa chọn';

  @override
  String get cmdTerminalPaste => 'Dán vào Active Terminal';

  @override
  String get cmdTerminalPasteSelection =>
      'Dán phần đã chọn vào Terminal hiện tại';

  @override
  String get cmdTerminalClearSelection => 'Xóa lựa chọn';

  @override
  String get cmdTerminalScrollDown => 'Cuộn xuống (Dòng)';

  @override
  String get cmdTerminalScrollDownPage => 'Cuộn xuống (Trang)';

  @override
  String get cmdTerminalScrollToBottom => 'Cuộn xuống dưới cùng';

  @override
  String get cmdTerminalScrollUp => 'Cuộn lên (Dòng)';

  @override
  String get cmdTerminalScrollUpPage => 'Cuộn lên (Trang)';

  @override
  String get cmdTerminalScrollToTop => 'Cuộn lên trên cùng';

  @override
  String get cmdTerminalSendSequence => 'Gửi trình tự';

  @override
  String get cmdTerminalKillAll => 'Đóng tất cả Terminal';

  @override
  String get cmdFindInFiles => 'Tìm trong Tệp';

  @override
  String get cmdReplaceInFiles => 'Thay thế trong tệp';

  @override
  String get cmdFocusNextSearchResult =>
      'Tập trung vào kết quả tìm kiếm tiếp theo';

  @override
  String get cmdFocusPreviousSearchResult =>
      'Tập trung vào kết quả tìm kiếm trước đó';

  @override
  String get cmdToggleSearchCaseSensitive =>
      'Chuyển đổi phân biệt chữ hoa chữ thường';

  @override
  String get cmdToggleSearchWholeWord => 'Chuyển đổi toàn bộ từ';

  @override
  String get cmdToggleSearchRegex => 'Chuyển đổi biểu thức chính quy';

  @override
  String get cmdToggleSearchPreserveCase => 'Chuyển đổi trường hợp bảo quản';

  @override
  String get cmdSearchFocusNextInput => 'Tập trung vào đầu vào tiếp theo';

  @override
  String get cmdSearchFocusPreviousInput =>
      'Tập trung vào dữ liệu đầu vào trước đó';

  @override
  String get cmdFocusSearchFromResults => 'Tập trung tìm kiếm từ kết quả';

  @override
  String get cmdSearchFocusList => 'Danh sách tập trung';

  @override
  String get cmdSearchOpenMatch => 'Trận đấu mở';

  @override
  String get cmdCloseReplaceWidget => 'Đóng Thay thế tiện ích';

  @override
  String get cmdCancelSearch => 'Hủy tìm kiếm';

  @override
  String get cmdToggleQueryDetails => 'Chuyển đổi chi tiết truy vấn';

  @override
  String get cmdCategoryQuickInput => 'Nhập nhanh';

  @override
  String get wbQuickEditors => 'Nhập tên của trình soạn thảo để mở nó.';

  @override
  String get quickOpenNoMatchingEditors => 'Không có người chỉnh sửa phù hợp';

  @override
  String get cmdQuickInputFocusNext => 'Tập trung tiếp theo';

  @override
  String get cmdQuickInputFocusPrevious => 'Tập trung trước đó';

  @override
  String get cmdQuickInputFocusNextPage => 'Tập trung vào trang tiếp theo';

  @override
  String get cmdQuickInputFocusPreviousPage => 'Tập trung vào trang trước';

  @override
  String get cmdQuickInputAccept => 'Chấp nhận';

  @override
  String get cmdQuickInputAcceptInBackground => 'Chấp nhận trong nền';

  @override
  String get cmdQuickInputHide => 'Trốn';

  @override
  String get cmdCloseQuickOpen => 'Đóng Mở nhanh';

  @override
  String get cmdAcceptSelectedQuickOpenItem => 'Chấp nhận mục mở nhanh đã chọn';

  @override
  String get cmdFocusQuickOpen => 'Tập trung mở nhanh';

  @override
  String get cmdQuickOpenSelectNext => 'Chọn Tiếp trong Mở nhanh';

  @override
  String get cmdQuickOpenSelectPrevious => 'Chọn Trước trong Mở nhanh';

  @override
  String get cmdQuickOpenNavigateNext => 'Điều hướng Tiếp theo trong Mở nhanh';

  @override
  String get cmdQuickOpenNavigatePrevious =>
      'Điều hướng trước đó trong Mở nhanh';

  @override
  String get cmdQuickOpenNavigateNextInFilePicker =>
      'Điều hướng Tiếp theo trong Bộ chọn Tệp';

  @override
  String get cmdQuickOpenNavigatePreviousInFilePicker =>
      'Điều hướng trước đó trong Bộ chọn tệp';

  @override
  String get cmdQuickOpenNavigateNextInEditorPicker =>
      'Điều hướng Tiếp theo trong Bộ chọn Trình soạn thảo';

  @override
  String get cmdQuickOpenNavigatePreviousInEditorPicker =>
      'Điều hướng phần trước trong Bộ chọn trình soạn thảo';

  @override
  String get cmdQuickOpenPreviousEditor => 'Mở nhanh trình soạn thảo trước đó';

  @override
  String get cmdShowAllEditors =>
      'Hiển thị tất cả người chỉnh sửa theo diện mạo';

  @override
  String get cmdShowEditorsInActiveGroup =>
      'Hiển thị người chỉnh sửa trong nhóm hoạt động theo người được sử dụng gần đây nhất';

  @override
  String get cmdShowAllEditorsByMostRecentlyUsed =>
      'Hiển thị tất cả người chỉnh sửa theo sử dụng gần đây nhất';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditor =>
      'Mở nhanh Trình chỉnh sửa được sử dụng gần đây trước đó';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditor =>
      'Mở nhanh Trình soạn thảo ít được sử dụng gần đây nhất';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditorInGroup =>
      'Mở nhanh Trình chỉnh sửa được sử dụng gần đây trước đó trong nhóm';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditorInGroup =>
      'Mở nhanh Trình soạn thảo ít được sử dụng gần đây nhất trong nhóm';

  @override
  String get cmdOpenPreviousEditorFromHistory =>
      'Mở nhanh Trình chỉnh sửa trước đó từ Lịch sử';

  @override
  String get cmdOpenNextRecentlyUsedEditor =>
      'Mở Tiếp theo Trình chỉnh sửa được sử dụng gần đây';

  @override
  String get cmdOpenPreviousRecentlyUsedEditor =>
      'Mở Trình chỉnh sửa được sử dụng gần đây trước đó';

  @override
  String get cmdOpenNextRecentlyUsedEditorInGroup =>
      'Mở tiếp theo Trình chỉnh sửa được sử dụng gần đây trong nhóm';

  @override
  String get cmdOpenPreviousRecentlyUsedEditorInGroup =>
      'Mở trình chỉnh sửa được sử dụng gần đây trước đó trong nhóm';

  @override
  String get cmdNextEditorInGroup => 'Mở Trình chỉnh sửa tiếp theo trong nhóm';

  @override
  String get cmdPreviousEditorInGroup =>
      'Mở Trình soạn thảo trước đó trong nhóm';

  @override
  String get cmdFirstEditorInGroup => 'Mở trình soạn thảo đầu tiên trong nhóm';

  @override
  String get cmdCloseEditorsInGroup => 'Đóng tất cả người chỉnh sửa trong nhóm';

  @override
  String get cmdCloseEditorsToTheLeft =>
      'Đóng người chỉnh sửa ở bên trái trong nhóm';

  @override
  String get cmdNavigateToLastEditLocation =>
      'Đi đến vị trí chỉnh sửa lần cuối';

  @override
  String get cmdNavigateLast => 'Đi trước';

  @override
  String get cmdOpenUserSettings => 'Mở cài đặt người dùng';

  @override
  String get cmdToggleMaximizedPanel => 'Chuyển đổi bảng điều khiển tối đa hóa';

  @override
  String get cmdFocusPanel => 'Tập trung vào bảng điều khiển';

  @override
  String get cmdClosePanel => 'Ẩn bảng điều khiển';

  @override
  String get cmdFocusSideBar => 'Tập trung vào thanh bên chính';

  @override
  String get cmdCloseSidebar => 'Ẩn thanh bên chính';

  @override
  String get cmdCloseChat => 'Ẩn trò chuyện';

  @override
  String get cmdFocusActiveEditorGroup => 'Nhóm biên tập viên tập trung';

  @override
  String get cmdFocusFirstEditorGroup => 'Nhóm soạn thảo tập trung đầu tiên';

  @override
  String get cmdFocusLastEditorGroup => 'Nhóm soạn thảo cuối cùng tập trung';

  @override
  String get cmdListFocusDown => 'Tập trung xuống';

  @override
  String get cmdListFocusUp => 'Tập trung lên';

  @override
  String get cmdListFocusPageDown => 'Tập trung trang xuống';

  @override
  String get cmdListFocusPageUp => 'Tập trung trang lên';

  @override
  String get cmdListFocusFirst => 'Tập trung đầu tiên';

  @override
  String get cmdListFocusLast => 'Tập trung cuối cùng';

  @override
  String get cmdListExpand => 'Mở rộng';

  @override
  String get cmdListCollapse => 'Thu gọn';

  @override
  String get cmdListSelect => 'Lựa chọn';

  @override
  String get cmdListToggleExpand => 'Chuyển đổi Mở rộng';

  @override
  String get cmdListExpandSelectionDown => 'Mở rộng lựa chọn xuống';

  @override
  String get cmdListExpandSelectionUp => 'Mở rộng lựa chọn lên';

  @override
  String get cmdListSelectAll => 'Chọn tất cả';

  @override
  String get cmdListClear => 'Xóa lựa chọn';

  @override
  String get cmdEditorCursorLeft => 'Con trỏ sang trái';

  @override
  String get cmdEditorCursorLeftSelect => 'Chọn con trỏ bên trái';

  @override
  String get cmdEditorCursorRight => 'Con trỏ phải';

  @override
  String get cmdEditorCursorRightSelect => 'Chọn con trỏ chuột phải';

  @override
  String get cmdEditorCursorUp => 'Con trỏ lên';

  @override
  String get cmdEditorCursorUpSelect => 'Con trỏ lên chọn';

  @override
  String get cmdEditorCursorDown => 'Con trỏ xuống';

  @override
  String get cmdEditorCursorDownSelect => 'Con trỏ xuống chọn';

  @override
  String get cmdEditorCursorPageUp => 'Con trỏ lên trang';

  @override
  String get cmdEditorCursorPageUpSelect => 'Con trỏ lên trang chọn';

  @override
  String get cmdEditorCursorPageDown => 'Con trỏ xuống trang';

  @override
  String get cmdEditorCursorPageDownSelect => 'Con trỏ xuống trang chọn';

  @override
  String get cmdEditorCursorHome => 'Trang chủ con trỏ';

  @override
  String get cmdEditorCursorHomeSelect => 'Con trỏ Trang chủ Chọn';

  @override
  String get cmdEditorCursorEnd => 'Kết thúc con trỏ';

  @override
  String get cmdEditorCursorEndSelect => 'Chọn cuối con trỏ';

  @override
  String get cmdEditorCursorLineStart => 'Bắt đầu dòng con trỏ';

  @override
  String get cmdEditorCursorLineStartSelect => 'Chọn bắt đầu dòng con trỏ';

  @override
  String get cmdEditorCursorLineEnd => 'Kết thúc dòng con trỏ';

  @override
  String get cmdEditorCursorLineEndSelect => 'Chọn cuối dòng con trỏ';

  @override
  String get cmdEditorCursorTop => 'Con trỏ hàng đầu';

  @override
  String get cmdEditorCursorTopSelect => 'Chọn đầu con trỏ';

  @override
  String get cmdEditorCursorBottom => 'Đáy con trỏ';

  @override
  String get cmdEditorCursorBottomSelect => 'Chọn dưới cùng con trỏ';

  @override
  String get cmdEditorCursorColumnSelectLeft => 'Chọn cột bên trái';

  @override
  String get cmdEditorCursorColumnSelectRight => 'Cột Chọn Phải';

  @override
  String get cmdEditorCursorColumnSelectUp => 'Cột Chọn Lên';

  @override
  String get cmdEditorCursorColumnSelectDown => 'Chọn cột xuống';

  @override
  String get cmdEditorCursorColumnSelectPageUp => 'Cột Chọn Trang Lên';

  @override
  String get cmdEditorCursorColumnSelectPageDown => 'Cột Chọn Trang Xuống';

  @override
  String get cmdEditorScrollLineUp => 'Cuộn dòng lên';

  @override
  String get cmdEditorScrollLineDown => 'Cuộn dòng xuống';

  @override
  String get cmdEditorScrollPageUp => 'Cuộn trang lên';

  @override
  String get cmdEditorScrollPageDown => 'Cuộn trang xuống';

  @override
  String get cmdEditorCancelSelection => 'Hủy lựa chọn';

  @override
  String get cmdEditorLineBreakInsert => 'Chèn ngắt dòng';

  @override
  String get cmdEditorTab => 'Thẻ';

  @override
  String get cmdEditorOutdent => 'Nhô ra';

  @override
  String get cmdEditorDeleteLeft => 'Xóa trái';

  @override
  String get cmdEditorDeleteRight => 'Xóa quyền';

  @override
  String get cmdEditorCursorWordLeft => 'Con trỏ từ trái';

  @override
  String get cmdEditorCursorWordLeftSelect => 'Chọn trái con trỏ từ';

  @override
  String get cmdEditorCursorWordStartLeft => 'Con trỏ Từ Bắt đầu Bên trái';

  @override
  String get cmdEditorCursorWordStartLeftSelect =>
      'Con trỏ Từ Bắt đầu Trái Chọn';

  @override
  String get cmdEditorCursorWordEndLeft => 'Con trỏ từ cuối bên trái';

  @override
  String get cmdEditorCursorWordEndLeftSelect =>
      'Con trỏ Từ Cuối Bên Trái Chọn';

  @override
  String get cmdEditorCursorWordRight => 'Con trỏ từ bên phải';

  @override
  String get cmdEditorCursorWordRightSelect => 'Con trỏ chọn từ phải';

  @override
  String get cmdEditorCursorWordStartRight => 'Con trỏ Từ Bắt đầu Ngay';

  @override
  String get cmdEditorCursorWordStartRightSelect =>
      'Con trỏ Bắt đầu từ bên phải Chọn';

  @override
  String get cmdEditorCursorWordEndRight => 'Con trỏ Từ Cuối Bên Phải';

  @override
  String get cmdEditorCursorWordEndRightSelect =>
      'Con trỏ Từ Cuối Bên Phải Chọn';

  @override
  String get cmdEditorCursorWordPartLeft => 'Phần con trỏ bên trái';

  @override
  String get cmdEditorCursorWordPartLeftSelect =>
      'Phần con trỏ từ bên trái chọn';

  @override
  String get cmdEditorCursorWordPartStartLeft =>
      'Con trỏ Từ Phần Bắt đầu Bên trái';

  @override
  String get cmdEditorCursorWordPartStartLeftSelect =>
      'Con trỏ Từ Phần Bắt đầu Bên trái Chọn';

  @override
  String get cmdEditorCursorWordPartRight => 'Phần con trỏ bên phải';

  @override
  String get cmdEditorCursorWordPartRightSelect =>
      'Con trỏ Word Phần bên phải Chọn';

  @override
  String get cmdEditorDeleteWordLeft => 'Xóa từ bên trái';

  @override
  String get cmdEditorDeleteWordRight => 'Xóa từ bên phải';

  @override
  String get cmdEditorDeleteWordStartLeft => 'Xóa từ bắt đầu bên trái';

  @override
  String get cmdEditorDeleteWordEndLeft => 'Xóa từ cuối bên trái';

  @override
  String get cmdEditorDeleteWordStartRight => 'Xóa từ Bắt đầu ngay';

  @override
  String get cmdEditorDeleteWordEndRight => 'Xóa từ cuối bên phải';

  @override
  String get cmdEditorDeleteWordPartLeft => 'Xóa phần từ còn lại';

  @override
  String get cmdEditorDeleteWordPartRight => 'Xóa phần Word bên phải';

  @override
  String get cmdEditorSmartSelectGrow => 'Mở rộng lựa chọn';

  @override
  String get cmdEditorFormat => 'Lựa chọn định dạng hoặc tài liệu';

  @override
  String get cmdEditorJumpToNextSnippetPlaceholder =>
      'Đi tới phần giữ chỗ đoạn tiếp theo';

  @override
  String get cmdEditorJumpToPrevSnippetPlaceholder =>
      'Chuyển đến phần giữ chỗ đoạn mã trước đó';

  @override
  String get cmdEditorLeaveSnippet => 'Để lại đoạn trích';

  @override
  String get cmdEditorLeaveEditorMessage => 'Loại bỏ tin nhắn';

  @override
  String get cmdEditorNextMatchFindAction => 'Tìm tiếp theo';

  @override
  String get cmdEditorPreviousMatchFindAction => 'Tìm trước đó';

  @override
  String get cmdEditorNextSelectionMatchFindAction => 'Tìm lựa chọn tiếp theo';

  @override
  String get cmdEditorPreviousSelectionMatchFindAction =>
      'Tìm lựa chọn trước đó';

  @override
  String get cmdEditorFindWithSelection => 'Tìm bằng lựa chọn';

  @override
  String get cmdEditorCloseFindWidget => 'Đóng Tìm tiện ích';

  @override
  String get cmdEditorToggleFindCaseSensitive => 'Chuyển đổi trường hợp khớp';

  @override
  String get cmdEditorToggleFindWholeWord => 'Chuyển đổi khớp toàn bộ từ';

  @override
  String get cmdEditorToggleFindRegex =>
      'Chuyển đổi Sử dụng biểu thức chính quy';

  @override
  String get cmdEditorReplaceOne => 'Thay thế một';

  @override
  String get cmdEditorReplaceAll => 'Thay thế tất cả';

  @override
  String get cmdEditorSelectAllMatches => 'Chọn tất cả các trận đấu';

  @override
  String get cmdEditorMarkerNext =>
      'Chuyển tới Vấn đề tiếp theo (Lỗi, Cảnh báo, Thông tin)';

  @override
  String get cmdEditorMarkerPrev =>
      'Chuyển đến Sự cố trước đó (Lỗi, Cảnh báo, Thông tin)';

  @override
  String get cmdEditorShowContextMenu =>
      'Hiển thị menu ngữ cảnh của trình soạn thảo';

  @override
  String get cmdEditorAcceptSelectedSuggestion => 'Chấp nhận đề xuất đã chọn';

  @override
  String get cmdEditorAcceptAlternativeSelectedSuggestion =>
      'Chấp nhận đề xuất đã chọn (Thay thế)';

  @override
  String get cmdEditorHideSuggestWidget => 'Ẩn tiện ích đề xuất';

  @override
  String get cmdEditorSelectNextSuggestion => 'Chọn Đề xuất tiếp theo';

  @override
  String get cmdEditorSelectPrevSuggestion => 'Chọn đề xuất trước đó';

  @override
  String get cmdEditorSelectNextPageSuggestion =>
      'Chọn Trang Đề xuất Tiếp theo';

  @override
  String get cmdEditorSelectPrevPageSuggestion => 'Chọn Trang Đề xuất Trước đó';

  @override
  String get cmdEditorToggleSuggestionDetails => 'Chuyển đổi chi tiết đề xuất';

  @override
  String get cmdEditorCloseParameterHints => 'Đóng gợi ý tham số';

  @override
  String get cmdEditorShowPrevParameterHint =>
      'Hiển thị gợi ý tham số trước đó';

  @override
  String get cmdEditorShowNextParameterHint =>
      'Hiển thị gợi ý tham số tiếp theo';

  @override
  String get cmdEditorAcceptRenameInput => 'Chấp nhận đổi tên';

  @override
  String get cmdEditorCancelRenameInput => 'Hủy Đổi tên';

  @override
  String get cmdEditorJoinLines => 'Tham gia dòng';

  @override
  String get cmdEditorDuplicateSelection => 'Lựa chọn trùng lặp';

  @override
  String get cmdEditorInsertCursorAtEndOfEachLineSelected =>
      'Thêm con trỏ vào cuối dòng';

  @override
  String get cmdEditorSmartSelectExpand => 'Mở rộng lựa chọn';

  @override
  String get cmdEditorSmartSelectShrink => 'Thu nhỏ lựa chọn';

  @override
  String get cmdEditorWordHighlightNext =>
      'Chuyển đến Đánh dấu biểu tượng tiếp theo';

  @override
  String get cmdEditorWordHighlightPrev =>
      'Đi tới Đánh dấu biểu tượng trước đó';

  @override
  String get cmdEditorFold => 'Nếp gấp';

  @override
  String get cmdEditorUnfold => 'Mở ra';

  @override
  String get cmdEditorToggleFold => 'Chuyển đổi gấp';

  @override
  String get cmdEditorFoldRecursively => 'Gấp đệ quy';

  @override
  String get cmdEditorUnfoldRecursively => 'Mở ra đệ quy';

  @override
  String get cmdEditorToggleFoldRecursively => 'Chuyển đổi đệ quy';

  @override
  String get cmdEditorFoldAll => 'Gấp tất cả';

  @override
  String get cmdEditorUnfoldAll => 'Mở ra tất cả';

  @override
  String get cmdEditorFoldAllBlockComments => 'Gấp tất cả các bình luận chặn';

  @override
  String get cmdEditorFoldAllMarkerRegions => 'Gấp tất cả các khu vực';

  @override
  String get cmdEditorUnfoldAllMarkerRegions => 'Mở ra tất cả các khu vực';

  @override
  String get cmdEditorFoldAllExcept => 'Gấp tất cả ngoại trừ đã chọn';

  @override
  String get cmdEditorUnfoldAllExcept => 'Mở ra tất cả ngoại trừ được chọn';

  @override
  String get cmdEditorGoToDeclaration => 'Đi tới Tuyên bố';

  @override
  String get cmdEditorReferenceSearchTrigger => 'Tham khảo Peek';

  @override
  String cmdEditorFoldLevel(int level) {
    return 'Mức gấp $level';
  }

  @override
  String get cmdShowAllCommands => 'Hiển thị tất cả các lệnh';

  @override
  String get cmdQuickOpen => 'Đi tới Tệp…';

  @override
  String get cmdGotoLine => 'Vào Dòng/Cột…';

  @override
  String get cmdChangeEol => 'Thay đổi trình tự cuối dòng';

  @override
  String get cmdFind => 'Tìm thấy';

  @override
  String get cmdReplace => 'Thay thế';

  @override
  String get cmdSave => 'Cứu';

  @override
  String get cmdSaveAll => 'Lưu tất cả';

  @override
  String get cmdToggleAutoSave => 'Chuyển đổi Tự động lưu';

  @override
  String get cmdCloseEditor => 'Đóng trình chỉnh sửa';

  @override
  String get cmdCloseOtherEditors => 'Đóng các biên tập viên khác';

  @override
  String get cmdCloseEditorsToTheRight => 'Đóng trình chỉnh sửa ở bên phải';

  @override
  String get cmdCloseSavedEditors => 'Đóng người chỉnh sửa đã lưu';

  @override
  String get cmdCloseAllEditors => 'Đóng tất cả người chỉnh sửa';

  @override
  String get cmdReopenClosedEditor => 'Mở lại trình chỉnh sửa đã đóng';

  @override
  String get cmdNextEditor => 'Mở Trình chỉnh sửa tiếp theo';

  @override
  String get cmdPreviousEditor => 'Mở trình soạn thảo trước đó';

  @override
  String cmdOpenEditorAtIndex(int index) {
    return 'Mở Trình chỉnh sửa tại Index $index';
  }

  @override
  String get cmdToggleSidebar => 'Chuyển đổi chế độ hiển thị thanh bên chính';

  @override
  String get cmdToggleChat => 'Chuyển đổi trò chuyện';

  @override
  String get cmdToggleFullScreen => 'Chuyển đổi toàn màn hình';

  @override
  String get cmdZoomIn => 'Phóng to';

  @override
  String get cmdZoomOut => 'Thu nhỏ';

  @override
  String get cmdZoomReset => 'Đặt lại thu phóng';

  @override
  String get cmdToggleWordWrap => 'Chuyển đổi gói từ';

  @override
  String get menuWordWrap => 'Gói từ';

  @override
  String get cmdToggleMinimap => 'Chuyển đổi bản đồ thu nhỏ';

  @override
  String get menuMinimap => 'Bản đồ nhỏ';

  @override
  String get cmdTogglePanel => 'Chuyển đổi chế độ hiển thị của bảng điều khiển';

  @override
  String get cmdToggleTerminal => 'Bật/tắt Terminal';

  @override
  String get cmdNewTerminal => 'Tạo Terminal mới';

  @override
  String get cmdKillTerminal => 'Đóng Terminal hiện tại';

  @override
  String get cmdRenameTerminal => 'Đổi tên...';

  @override
  String get cmdFocusNextTerminal => 'Tập trung vào nhóm Terminal tiếp theo';

  @override
  String get cmdFocusPreviousTerminal => 'Tập trung vào nhóm Terminal trước đó';

  @override
  String get cmdFocusTerminal => 'Terminal tập trung';

  @override
  String get cmdRunTask => 'Chạy tác vụ';

  @override
  String get cmdRunBuildTask => 'Chạy tác vụ xây dựng';

  @override
  String get cmdRunTestTask => 'Chạy thử nghiệm tác vụ';

  @override
  String get cmdRerunTask => 'Chạy lại nhiệm vụ cuối cùng';

  @override
  String get cmdRestartTask => 'Khởi động lại tác vụ đang chạy';

  @override
  String get cmdTerminateTask => 'Chấm dứt nhiệm vụ';

  @override
  String get cmdShowTaskLog => 'Hiển thị nhật ký tác vụ';

  @override
  String get cmdConfigureTask => 'Định cấu hình tác vụ';

  @override
  String get cmdShowExplorer => 'Hiển thị trình khám phá';

  @override
  String get cmdShowSearch => 'Hiển thị tìm kiếm';

  @override
  String get cmdShowSourceControl => 'Hiển thị quản lý mã nguồn';

  @override
  String get cmdShowExtensions => 'Hiển thị tiện ích mở rộng';

  @override
  String get cmdRevealActiveFileInExplorer =>
      'Hiển thị tệp đang hoạt động trong Chế độ xem Explorer';

  @override
  String get cmdRefreshExplorer => 'Làm mới Explorer';

  @override
  String get cmdCollapseExplorerFolders => 'Thu gọn thư mục trong Explorer';

  @override
  String get cmdCopyPathOfActiveFile =>
      'Sao chép đường dẫn của tệp đang hoạt động';

  @override
  String get cmdCopyRelativePathOfActiveFile =>
      'Sao chép đường dẫn tương đối của tệp đang hoạt động';

  @override
  String get cmdGotoSymbol => 'Đi tới Biểu tượng trong Trình chỉnh sửa...';

  @override
  String get cmdToggleProblems => 'Chuyển đổi vấn đề';

  @override
  String get cmdShowOutline => 'Hiển thị phác thảo';

  @override
  String get cmdNextProblemInFiles =>
      'Chuyển tới Sự cố tiếp theo trong tệp (Lỗi, Cảnh báo, Thông tin)';

  @override
  String get cmdPreviousProblemInFiles =>
      'Đi tới Sự cố trước đó trong Tệp (Lỗi, Cảnh báo, Thông tin)';

  @override
  String get cmdGoBack => 'Quay lại';

  @override
  String get cmdGoForward => 'Đi về phía trước';

  @override
  String get cmdColorTheme => 'Chủ đề màu sắc';

  @override
  String get cmdTurnOnFormatOnSave => 'Bật định dạng khi lưu';

  @override
  String get cmdTurnOffFormatOnSave => 'Tắt định dạng khi lưu';

  @override
  String get cmdRetryLanguageServices => 'Thử lại dịch vụ ngôn ngữ';

  @override
  String get cmdBackToChat => 'Quay lại Trò chuyện';

  @override
  String get cmdOpenSettings => 'Mở Cài đặt';

  @override
  String get cmdOpenKeyboardShortcuts => 'Mở phím tắt';

  @override
  String get cmdOpenLspSettings => 'Cài đặt máy chủ ngôn ngữ mở (JSON)';

  @override
  String get cmdJumpToBracket => 'Đi đến khung';

  @override
  String get cmdUndo => 'Hoàn tác';

  @override
  String get cmdRedo => 'Làm lại';

  @override
  String get cmdCut => 'Cắt';

  @override
  String get cmdCopy => 'Sao chép';

  @override
  String get cmdPaste => 'Dán';

  @override
  String get cmdSelectAll => 'Chọn tất cả';

  @override
  String get cmdToggleLineComment => 'Chuyển đổi dòng bình luận';

  @override
  String get cmdToggleBlockComment => 'Chuyển đổi chặn bình luận';

  @override
  String get cmdMoveLineUp => 'Di chuyển dòng lên';

  @override
  String get cmdMoveLineDown => 'Di chuyển dòng xuống';

  @override
  String get cmdCopyLineUp => 'Sao chép dòng lên';

  @override
  String get cmdCopyLineDown => 'Sao chép dòng xuống';

  @override
  String get cmdDeleteLine => 'Xóa dòng';

  @override
  String get cmdInsertLineBelow => 'Chèn dòng bên dưới';

  @override
  String get cmdInsertLineAbove => 'Chèn dòng trên';

  @override
  String get cmdIndentLine => 'Dòng thụt lề';

  @override
  String get cmdOutdentLine => 'Dòng nhô ra';

  @override
  String get cmdExpandLineSelection => 'Mở rộng lựa chọn dòng';

  @override
  String get cmdDeleteAllLeft => 'Xóa tất cả còn lại';

  @override
  String get cmdDeleteAllRight => 'Xóa tất cả quyền';

  @override
  String get cmdAddSelectionToNextFindMatch =>
      'Thêm lựa chọn vào tiếp theo Tìm kết quả phù hợp';

  @override
  String get cmdMoveSelectionToNextFindMatch =>
      'Di chuyển lựa chọn cuối cùng sang tiếp theo Tìm kết quả phù hợp';

  @override
  String get cmdSelectHighlights =>
      'Chọn tất cả các lần xuất hiện của Tìm trận đấu';

  @override
  String get cmdChangeAll => 'Thay đổi tất cả các lần xuất hiện';

  @override
  String get cmdInsertCursorAbove => 'Thêm con trỏ ở trên';

  @override
  String get cmdInsertCursorBelow => 'Thêm con trỏ bên dưới';

  @override
  String get cmdRemoveSecondaryCursors => 'Xóa con trỏ phụ';

  @override
  String get cmdCursorUndo => 'Hoàn tác con trỏ';

  @override
  String get cmdTransformToUppercase => 'Chuyển đổi sang chữ hoa';

  @override
  String get cmdTransformToLowercase => 'Chuyển đổi sang chữ thường';

  @override
  String get cmdDetectIndentation => 'Phát hiện thụt lề từ nội dung';

  @override
  String get cmdGoToDefinition => 'Đi tới Định nghĩa';

  @override
  String get cmdGoToTypeDefinition => 'Chuyển đến Định nghĩa loại';

  @override
  String get cmdGoToImplementations => 'Chuyển đến phần Triển khai';

  @override
  String get cmdGoToReferences => 'Đi tới Tài liệu tham khảo';

  @override
  String get cmdRenameSymbol => 'Đổi tên biểu tượng';

  @override
  String get cmdFormatDocument => 'Định dạng tài liệu';

  @override
  String get cmdFormatSelection => 'Lựa chọn định dạng';

  @override
  String get cmdQuickFix => 'Sửa nhanh...';

  @override
  String get cmdRefactor => 'Tái cấu trúc...';

  @override
  String get cmdSourceAction => 'Thao tác nguồn...';

  @override
  String get cmdTriggerSuggest => 'Đề xuất kích hoạt';

  @override
  String get cmdTriggerParameterHints => 'Gợi ý tham số kích hoạt';

  @override
  String get cmdShowHover => 'Hiển thị hoặc lấy nét khi di chuột';

  @override
  String get quickOpenRecentlyOpened => 'mới mở gần đây';

  @override
  String get quickOpenFiles => 'tệp';

  @override
  String get quickOpenLoadingFiles => 'Đang tải tệp…';

  @override
  String get quickOpenSearchingFiles => 'Đang tìm kiếm tệp…';

  @override
  String get quickOpenNoFiles => 'Không có tệp nào trong dự án này';

  @override
  String get quickOpenNoMatchingResults => 'Không có kết quả phù hợp';

  @override
  String quickOpenTooManyFiles(int count) {
    return 'Chỉ tìm kiếm các tệp $count đầu tiên: dự án này có nhiều hơn';
  }

  @override
  String get quickOpenRecentlyUsed => 'được sử dụng gần đây';

  @override
  String get quickOpenOtherCommands => 'các lệnh khác';

  @override
  String get quickOpenNoMatchingCommands => 'Không có lệnh phù hợp';

  @override
  String get gotoLineNoEditor =>
      'Trước tiên, hãy mở trình soạn thảo văn bản để đi tới một dòng.';

  @override
  String gotoLineCurrent(int line, int character, int lineCount) {
    return 'Dòng hiện tại: $line, Ký tự: $character. Nhập số dòng từ 1 đến $lineCount để điều hướng đến.';
  }

  @override
  String gotoLineLine(int line) {
    return 'Tới dòng $line.';
  }

  @override
  String gotoLineLineAndCharacter(int line, int character) {
    return 'Tới dòng $line và ký tự $character.';
  }

  @override
  String get menuFile => 'Tài liệu';

  @override
  String get menuEdit => 'Biên tập';

  @override
  String get menuView => 'Xem';

  @override
  String get menuHelp => 'Giúp đỡ';

  @override
  String get menuApplication => 'Menu ứng dụng';

  @override
  String get menuOpenFolder => 'Mở thư mục…';

  @override
  String get menuCloseWindow => 'Đóng cửa sổ';

  @override
  String get menuAutoSave => 'Tự động lưu';

  @override
  String get menuBackToChat => 'Quay lại Trò chuyện';

  @override
  String get menuShowSidebar => 'Hiển thị thanh bên';

  @override
  String get menuHideSidebar => 'Ẩn thanh bên';

  @override
  String get menuKeepOnTop => 'Luôn ở trên cùng';

  @override
  String get menuContextPanel => 'Bảng ngữ cảnh';

  @override
  String get menuAboutBaoCode => 'Giới thiệu về BảoCode';

  @override
  String get windowShowSidebar => 'Hiển thị thanh bên';

  @override
  String get windowHideSidebar => 'Ẩn thanh bên';

  @override
  String get chatTerminalHide => 'Ẩn Terminal';

  @override
  String get cmdToggleSidePanel => 'Chuyển đổi bảng điều khiển bên';

  @override
  String get cmdToggleSidePanelPosition =>
      'Chuyển đổi vị trí bảng điều khiển bên';

  @override
  String get cmdSidePanelChanges => 'Hiển thị các thay đổi của agent';

  @override
  String get cmdSidePanelFiles => 'Hiển thị tệp agent';

  @override
  String get cmdSidePanelUsage => 'Hiển thị cách sử dụng hội thoại';

  @override
  String get cmdSidePanelTerminal => 'Hiển thị Terminal agent';

  @override
  String get cmdSidePanelCloseTab => 'Đóng tab bảng điều khiển bên';

  @override
  String get sidePanelFiles => 'tệp';

  @override
  String get sidePanelTerminal => 'Phần cuối';

  @override
  String get browserOtherApp =>
      'Một phiên BaoCode khác đang kết nối với trình duyệt.';

  @override
  String get browserWatchTitle =>
      'Đang theo dõi thao tác của bạn trên trình duyệt';

  @override
  String get browserWatchHint =>
      'Hãy thực hiện thao tác trong tab BaoCode của trình duyệt. Khi xong, nhấn Hoàn tất ở đây hoặc nút BaoCode trên thanh công cụ trình duyệt.';

  @override
  String browserWatchSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã ghi nhận $count bước',
      one: 'Đã ghi nhận 1 bước',
      zero: 'Chưa ghi nhận bước nào',
    );
    return '$_temp0';
  }

  @override
  String get browserWatchCancel => 'Hủy';

  @override
  String get browserWatchDone => 'Hoàn tất';

  @override
  String browserWatchedStep(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'click': 'Đã nhấp',
      'input': 'Đã nhập',
      'key': 'Đã nhấn phím',
      'submit': 'Đã gửi',
      'navigate': 'Đã chuyển đến',
      'closed': 'Đã đóng tab',
      'other': 'Đã thao tác',
    });
    return '$_temp0';
  }

  @override
  String browserTraceReveal(String app) {
    return 'Hiển thị bản ghi thao tác trong $app (kéo vào bảng Performance của DevTools để xem chi tiết)';
  }

  @override
  String browserStepDone(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': 'Đã liệt kê các tab',
      'open': 'Đã mở',
      'navigate': 'Đã chuyển đến',
      'back': 'Đã quay lại',
      'forward': 'Đã đi tới',
      'reload': 'Đã tải lại',
      'snapshot': 'Đã đọc trang',
      'screenshot': 'Đã chụp màn hình',
      'click': 'Đã nhấp',
      'type': 'Đã nhập',
      'press': 'Đã nhấn phím',
      'scroll': 'Đã cuộn',
      'evaluate': 'Đã chạy mã',
      'close': 'Đã đóng tab',
      'console': 'Đã đọc console',
      'network': 'Đã liệt kê yêu cầu mạng',
      'request': 'Đã đọc yêu cầu',
      'performance': 'Đã phân tích hiệu năng',
      'recordStart': 'Đã bắt đầu ghi hiệu năng',
      'recordStop': 'Đã ghi dữ liệu hiệu năng',
      'emulate': 'Đã mô phỏng',
      'watch': 'Đã theo dõi thao tác của bạn',
      'act': 'Đã thao tác',
      'inspect': 'Đã kiểm tra',
      'sources': 'Đã đọc mã nguồn',
      'breakpoints': 'Đã đặt breakpoint',
      'debugger': 'Đã gỡ lỗi',
      'intercept': 'Đã chặn yêu cầu',
      'storage': 'Đã đọc dữ liệu trang',
      'dialog': 'Đã phản hồi hộp thoại',
      'coverage': 'Đã đo độ bao phủ',
      'memory': 'Đã đo bộ nhớ',
      'history': 'Đã đọc lịch sử gỡ lỗi',
      'other': 'Đã sử dụng trình duyệt',
    });
    return '$_temp0';
  }

  @override
  String browserStepRunning(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': 'Đang liệt kê các tab',
      'open': 'Đang mở',
      'navigate': 'Đang chuyển đến',
      'back': 'Đang quay lại',
      'forward': 'Đang đi tới',
      'reload': 'Đang tải lại',
      'snapshot': 'Đang đọc trang',
      'screenshot': 'Đang chụp màn hình',
      'click': 'Đang nhấp',
      'type': 'Đang nhập',
      'press': 'Đang nhấn phím',
      'scroll': 'Đang cuộn',
      'evaluate': 'Đang chạy mã',
      'close': 'Đang đóng tab',
      'console': 'Đang đọc console',
      'network': 'Đang liệt kê yêu cầu mạng',
      'request': 'Đang đọc yêu cầu',
      'performance': 'Đang phân tích hiệu năng',
      'recordStart': 'Đang bắt đầu ghi hiệu năng',
      'recordStop': 'Đang ghi dữ liệu hiệu năng',
      'emulate': 'Đang mô phỏng',
      'watch': 'Đang theo dõi thao tác của bạn',
      'act': 'Đang thao tác',
      'inspect': 'Đang kiểm tra',
      'sources': 'Đang đọc mã nguồn',
      'breakpoints': 'Đang đặt breakpoint',
      'debugger': 'Đang gỡ lỗi',
      'intercept': 'Đang chặn yêu cầu',
      'storage': 'Đang đọc dữ liệu trang',
      'dialog': 'Đang phản hồi hộp thoại',
      'coverage': 'Đang đo độ bao phủ',
      'memory': 'Đang đo bộ nhớ',
      'history': 'Đang đọc lịch sử gỡ lỗi',
      'other': 'Đang sử dụng trình duyệt',
    });
    return '$_temp0';
  }

  @override
  String sessionStepDone(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'new': 'Đã bắt đầu',
      'send': 'Đã giao việc cho',
      'wait': 'Đã chờ',
      'read': 'Đã đọc',
      'stop': 'Đã dừng',
      'changes': 'Đã kiểm tra thay đổi của',
      'list': 'Đã liệt kê các cuộc trò chuyện',
      'models': 'Đã kiểm tra các mô hình',
      'other': 'Đã điều phối',
    });
    return '$_temp0';
  }

  @override
  String sessionStepRunning(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'new': 'Đang bắt đầu',
      'send': 'Đang giao việc cho',
      'wait': 'Đang chờ',
      'read': 'Đang đọc',
      'stop': 'Đang dừng',
      'changes': 'Đang kiểm tra thay đổi của',
      'list': 'Đang liệt kê các cuộc trò chuyện',
      'models': 'Đang kiểm tra các mô hình',
      'other': 'Đang điều phối',
    });
    return '$_temp0';
  }

  @override
  String get sessionOpen => 'Mở cuộc trò chuyện';

  @override
  String sessionStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'running': 'Đang làm việc',
      'waiting': 'Đang chờ bạn',
      'done': 'Hoàn tất',
      'failed': 'Thất bại',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get sessionAnswer => 'Trả lời';

  @override
  String get sessionShowMore => 'Hiển thị thêm';

  @override
  String get sessionShowLess => 'Hiển thị ít hơn';

  @override
  String get sidePanelPlan => 'Kế hoạch';

  @override
  String get sidePanelOpenInFiles => 'Mở trong Tệp';

  @override
  String get sidePanelNoTerminals => 'Không có lệnh nền';

  @override
  String get sidePanelTaskCompleted => 'Hoàn thành';

  @override
  String get sidePanelTaskFailed => 'Thất bại';

  @override
  String get sidePanelWaitingOutput => 'Đang chờ đầu ra';

  @override
  String get sidePanelOutputUnavailable => 'Đầu ra không có sẵn';

  @override
  String get sidePanelShow => 'Hiển thị bảng điều khiển bên';

  @override
  String get sidePanelHide => 'Ẩn bảng điều khiển bên';

  @override
  String get chatLayout => 'Cách trình bày';

  @override
  String get chatLayoutSidebarChatPanel =>
      'Thanh bên · Trò chuyện · Bảng điều khiển';

  @override
  String get chatLayoutSidebarPanelChat =>
      'Thanh bên · Bảng điều khiển · Trò chuyện';

  @override
  String get chatLayoutPanelChatSidebar =>
      'Bảng điều khiển · Trò chuyện · Thanh bên';

  @override
  String get chatLayoutChatPanelSidebar =>
      'Trò chuyện · Bảng điều khiển · Thanh bên';

  @override
  String get sidePanelChanges => 'Thay đổi';

  @override
  String get sidePanelOpenFile => 'Mở trong bảng điều khiển bên';

  @override
  String get sidePanelOpenDiff =>
      'Hiển thị các thay đổi trong bảng điều khiển bên';

  @override
  String get sidePanelOpenInIde => 'Mở trong Fast Ide';

  @override
  String get sidePanelCloseTab => 'Đóng';

  @override
  String get sidePanelPreview => 'Xem trước';

  @override
  String get sidePanelSource => 'Nguồn';

  @override
  String get commandOpenDetails => 'Mở chi tiết';

  @override
  String get sidePanelNoOriginal =>
      'Tệp trước khi thay đổi của tác nhân không được biết: hiển thị nguyên trạng.';

  @override
  String get sidePanelUnchanged => 'Không có sự khác biệt';

  @override
  String get sidePanelDeleted => 'Agent đã xóa tệp này.';

  @override
  String get sidePanelTerminals => 'Terminal';

  @override
  String get sidePanelRevealInFiles => 'Tiết lộ trong tệp';

  @override
  String get sidePanelAddToChat => 'Thêm vào trò chuyện';

  @override
  String get termClearTask => 'Xóa';

  @override
  String get termClearEndedTasks => 'Xóa tất cả nhiệm vụ đã kết thúc';

  @override
  String get sidePanelBackgroundTasks => 'Tác vụ nền';

  @override
  String get sidePanelSelectFile => 'Chọn một tệp để xem trước nó';

  @override
  String get sidePanelSelectTerminal =>
      'Chọn một tác vụ nền để xem kết quả của nó';

  @override
  String get sidePanelNoFolder => 'Cuộc trò chuyện này không có thư mục dự án';

  @override
  String get sidePanelSearchFiles => 'Tìm kiếm tệp của dự án';

  @override
  String get sidePanelCloseSearch => 'Đóng tìm kiếm';

  @override
  String get sidePanelShowList => 'Hiển thị danh sách';

  @override
  String get sidePanelHideList => 'Ẩn danh sách';

  @override
  String get windowMinimize => 'Giảm thiểu';

  @override
  String get windowMaximize => 'Tối đa hóa';

  @override
  String get windowRestore => 'Khôi phục';

  @override
  String get windowClose => 'Đóng';

  @override
  String get aboutDescription =>
      'Các agent chạy Claude Code dưới dạng tiến trình cục bộ. Những hoạt động của chúng — tin nhắn, công cụ, diff và bảng điều khiển — được hiển thị tại đây.';

  @override
  String get agentUntitled => 'Trò chuyện mới';

  @override
  String agentImageTitle(String name) {
    return 'Hình ảnh: $name';
  }

  @override
  String get agentImageUntitled => 'Hình ảnh';

  @override
  String get chatTitleSummarize => 'Tóm tắt thành tiêu đề mới';

  @override
  String get chatTitleSummarizing => 'Tóm tắt…';

  @override
  String get chatTitleSummarizeFailed =>
      'Không có danh hiệu nào có thể có được. Thử lại';

  @override
  String get sidebarNewAgent => 'Cuộc trò chuyện mới';

  @override
  String get sidebarGroupingProject => 'Dự án';

  @override
  String get sidebarGroupingDate => 'Ngày';

  @override
  String get sidebarGroupingStatus => 'Trạng thái';

  @override
  String get sidebarByProject => 'Theo dự án';

  @override
  String get sidebarByDate => 'Theo ngày';

  @override
  String get sidebarByStatus => 'Theo trạng thái';

  @override
  String get sidebarProjectSortRecent => 'Hoạt động gần đây';

  @override
  String get sidebarProjectSortManual => 'Thủ công';

  @override
  String get sidebarTimeNow => 'vừa xong';

  @override
  String sidebarTimeMinutes(int count) {
    return '${count}m';
  }

  @override
  String sidebarTimeHours(int count) {
    return '${count}h';
  }

  @override
  String sidebarTimeDays(int count) {
    return '${count}d';
  }

  @override
  String sidebarTimeWeeks(int count) {
    return '${count}w';
  }

  @override
  String sidebarMonthDay(String month, int day) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': '$day thg 1',
      '2': '$day thg 2',
      '3': '$day thg 3',
      '4': '$day thg 4',
      '5': '$day thg 5',
      '6': '$day thg 6',
      '7': '$day thg 7',
      '8': '$day thg 8',
      '9': '$day thg 9',
      '10': '$day thg 10',
      '11': '$day thg 11',
      '12': '$day thg 12',
      'other': '$day/$month',
    });
    return '$_temp0';
  }

  @override
  String get sidebarPinned => 'Đã ghim';

  @override
  String get sidebarToday => 'Hôm nay';

  @override
  String get sidebarYesterday => 'Hôm qua';

  @override
  String get sidebarPrevious7Days => '7 ngày trước';

  @override
  String get sidebarOlder => 'Cũ hơn';

  @override
  String get sidebarNeedsInput => 'Cần phản hồi';

  @override
  String get sidebarRunning => 'Đang chạy';

  @override
  String get sidebarUnread => 'Chưa đọc';

  @override
  String sidebarHoverModel(String model) {
    return 'Mô hình: $model';
  }

  @override
  String get sidebarDone => 'Hoàn tất';

  @override
  String get sidebarArchived => 'Đã lưu trữ';

  @override
  String sidebarArchivedIn(String folder) {
    return '$folder · đã lưu trữ';
  }

  @override
  String get sidebarOpenFolder => 'Mở thư mục…';

  @override
  String get sidebarAgents => 'Agent';

  @override
  String get sidebarCollapseAll => 'Thu gọn tất cả';

  @override
  String get sidebarExpandAll => 'Mở rộng tất cả';

  @override
  String get sidebarNoMatchingAgents => 'Không có agent phù hợp';

  @override
  String get sidebarNoAgentsYet => 'Chưa có agent nào';

  @override
  String get sidebarHideArchived => 'Ẩn mục đã lưu trữ';

  @override
  String sidebarArchivedCount(int count) {
    return 'Đã lưu trữ · $count';
  }

  @override
  String get sidebarDeleteAgentTitle => 'Xóa agent?';

  @override
  String sidebarDeleteAgentMessage(String title) {
    return '“$title” và cuộc trò chuyện của agent này sẽ bị xóa.';
  }

  @override
  String get sidebarDeleteAgentsTitle => 'Xóa agent?';

  @override
  String sidebarDeleteAgentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count agent và các cuộc trò chuyện tương ứng sẽ bị xóa',
      one: 'Agent và cuộc trò chuyện của agent này sẽ bị xóa',
    );
    return '$_temp0, bao gồm cả dữ liệu trong kernel. Không thể hoàn tác.';
  }

  @override
  String sidebarDeleteAgentMessageKernel(String title, String kernel) {
    return '“$title” và cuộc trò chuyện của nó cũng sẽ bị xóa khỏi $kernel. Điều này không thể hoàn tác được.';
  }

  @override
  String get sidebarSearchAgents => 'Tìm agent…';

  @override
  String get ideChatHistory => 'Lịch sử agent';

  @override
  String get ideChatShowArchived => 'Hiển thị các agent lưu trữ';

  @override
  String get ideChatNoAgents => 'Không có agent trong dự án này';

  @override
  String sidebarNewAgentIn(String project) {
    return 'Cuộc trò chuyện mới trong $project';
  }

  @override
  String get newChatRemoteGroup => 'Xa';

  @override
  String get newChatOpenRemoteDetail => 'Một thư mục trên máy chủ qua SSH';

  @override
  String get newChatWorkingFolder => 'Thư mục để làm việc';

  @override
  String get newChatNoFolder => 'Không có thư mục';

  @override
  String get newChatNoFolderDetail => 'Hoạt động trong thư mục Desktop';

  @override
  String newChatOpenFrom(String app) {
    return 'Mở từ $app';
  }

  @override
  String get sidebarPin => 'Ghim';

  @override
  String get sidebarUnpin => 'Bỏ ghim';

  @override
  String get sidebarArchive => 'Lưu trữ';

  @override
  String get sidebarUnarchive => 'Bỏ lưu trữ';

  @override
  String sidebarPinCount(int count) {
    return 'Ghim $count agent';
  }

  @override
  String sidebarUnpinCount(int count) {
    return 'Bỏ ghim $count agent';
  }

  @override
  String sidebarArchiveCount(int count) {
    return 'Lưu trữ $count agent';
  }

  @override
  String sidebarUnarchiveCount(int count) {
    return 'Bỏ lưu trữ $count agent';
  }

  @override
  String sidebarDeleteCount(int count) {
    return 'Xóa $count agent…';
  }

  @override
  String get sidebarCopySessionId => 'Sao chép ID phiên';

  @override
  String sidebarOpenStash(int id) {
    return 'Mở Stash #$id';
  }

  @override
  String get sidebarFork => 'Tách nhánh';

  @override
  String get sidebarDetachAside => 'Tách khỏi cuộc trò chuyện';

  @override
  String sidebarDeleteAsidesToo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuộc trò chuyện /btw đi kèm cũng sẽ bị xóa.',
      one: 'Cuộc trò chuyện /btw đi kèm cũng sẽ bị xóa.',
    );
    return '$_temp0';
  }

  @override
  String get btwCommandDetail =>
      'Hỏi trong một cuộc trò chuyện riêng, bên cạnh cuộc trò chuyện này';

  @override
  String get forkCommandDetail =>
      'Phân nhánh cuộc trò chuyện này và mở bản sao';

  @override
  String get forkUnavailable =>
      'Cuộc trò chuyện này không thể được phân nhánh: trước tiên nó cần có một tin nhắn và agent của nó phải hỗ trợ việc phân nhánh.';

  @override
  String get sidebarFoldAsides => 'Ẩn các cuộc trò chuyện /btw';

  @override
  String sidebarUnfoldAsides(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hiện $count cuộc trò chuyện /btw của agent',
      one: 'Hiện cuộc trò chuyện /btw của agent',
    );
    return '$_temp0';
  }

  @override
  String sidebarShowMore(int count) {
    return 'Hiện thêm ($count)';
  }

  @override
  String get sidebarShowLess => 'Hiện ít hơn';

  @override
  String get sidebarNewAgentHere => 'Tạo cuộc trò chuyện tại đây';

  @override
  String sidebarRevealIn(String app) {
    return 'Hiển thị trong $app';
  }

  @override
  String get sidebarSortByTime => 'Sắp xếp theo thời gian';

  @override
  String get sidebarArchiveAll => 'Lưu trữ tất cả';

  @override
  String get sidebarUnarchiveAll => 'Bỏ lưu trữ tất cả';

  @override
  String get sidebarDeleteArchived => 'Xóa tất cả mục đã lưu trữ…';

  @override
  String get sidebarDeleteArchivedTitle => 'Xóa các agent đã lưu trữ?';

  @override
  String sidebarDeleteArchivedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count agent đã lưu trữ và các cuộc trò chuyện tương ứng sẽ bị xóa',
      one: 'Agent đã lưu trữ và cuộc trò chuyện tương ứng sẽ bị xóa',
    );
    return '$_temp0, bao gồm cả dữ liệu trong kernel. Không thể hoàn tác.';
  }

  @override
  String get sidebarRemoveFromList => 'Xóa khỏi danh sách';

  @override
  String get sidebarDropToPin => 'Thả vào đây để ghim';

  @override
  String get sidebarMoreActions => 'Thao tác khác…';

  @override
  String get sidebarChangeIcon => 'Đổi biểu tượng…';

  @override
  String sidebarProjectIcon(String project) {
    return 'Đổi biểu tượng của $project';
  }

  @override
  String get iconPickerEmoji => 'Biểu tượng cảm xúc';

  @override
  String get iconPickerIcons => 'Biểu tượng';

  @override
  String get iconPickerCustom => 'Phong tục';

  @override
  String get iconPickerRemove => 'Di dời';

  @override
  String get iconPickerSearch => 'Tìm kiếm…';

  @override
  String get iconPickerRandom => 'Ngẫu nhiên';

  @override
  String get iconPickerRecent => 'Gần đây';

  @override
  String get iconPickerNoResults => 'Không có kết quả';

  @override
  String get iconPickerDefaultColor => 'Màu mặc định';

  @override
  String get iconPickerUpload => 'Tải lên một hình ảnh';

  @override
  String get iconPickerUploadHint =>
      'Tải lên, thả hoặc dán hình ảnh: PNG, JPG, WebP, GIF hoặc SVG, tối đa 5 MB';

  @override
  String get iconPickerDropHere => 'Thả hình ảnh vào đây';

  @override
  String get iconPickerUploaded => 'Đã tải lên';

  @override
  String get iconPickerDeleteFromLibrary => 'Xóa khỏi Thư viện';

  @override
  String get iconPickerBrands => 'Logo';

  @override
  String get iconPickerSiteIcon => 'Sử dụng biểu tượng của trang web';

  @override
  String iconPickerSiteIconNone(String host) {
    return 'Không tìm thấy biểu tượng nào trên $host';
  }

  @override
  String get iconUploadTooLarge => 'Tệp lớn hơn 5 MB';

  @override
  String get iconUploadUnsupported =>
      'Không phải hình ảnh PNG, JPG, WebP, GIF hoặc SVG';

  @override
  String get iconUploadUnreadable => 'Không thể đọc được tệp';

  @override
  String get emojiGroupSmileys => 'Mặt cười & Cảm xúc';

  @override
  String get emojiGroupPeople => 'Con người & Cơ thể';

  @override
  String get emojiGroupAnimals => 'Động vật & Thiên nhiên';

  @override
  String get emojiGroupFood => 'Đồ ăn & Đồ uống';

  @override
  String get emojiGroupTravel => 'Du lịch & Địa điểm';

  @override
  String get emojiGroupActivities => 'Các hoạt động';

  @override
  String get emojiGroupObjects => 'Đối tượng';

  @override
  String get emojiGroupSymbols => 'Biểu tượng';

  @override
  String get emojiGroupFlags => 'Cờ';

  @override
  String get workspaceBackToChat => 'Quay lại trò chuyện';

  @override
  String get workspaceNotEnoughRoom => 'Không đủ chỗ trên màn hình này';

  @override
  String get workspaceWindowGrows => 'Cửa sổ phát triển để phù hợp';

  @override
  String get workspaceCopyPath => 'Sao chép đường dẫn';

  @override
  String workspaceOpenIn(String app) {
    return 'Mở trong $app';
  }

  @override
  String get workspaceChooseEditor => 'Chọn trình chỉnh sửa';

  @override
  String get workspaceFinder => 'Trình tìm kiếm';

  @override
  String get workspaceFileExplorer => 'Trình khám phá tệp';

  @override
  String get workspaceFileManager => 'Trình quản lý tệp';

  @override
  String get workspaceTerminalApp => 'Phần cuối';

  @override
  String get workspaceWindowsTerminal => 'Terminal Windows';

  @override
  String get workspaceKeepOnTopUnavailable =>
      'Giữ trên cùng có sẵn trong ứng dụng máy tính để bàn';

  @override
  String get workspaceUnpinWindow => 'Bỏ ghim cửa sổ';

  @override
  String get workspacePinWindow => 'Ghim cửa sổ lên trên';

  @override
  String get chatConversation => 'Cuộc hội thoại';

  @override
  String get chatBackEsc => 'Quay lại (Esc)';

  @override
  String get chatBack => 'Mặt sau';

  @override
  String get statusRunningInBackground => 'Chạy ở chế độ nền';

  @override
  String chatToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count công cụ',
      one: '1 công cụ',
    );
    return '$_temp0';
  }

  @override
  String chatTokens(String tokens) {
    return 'Mã thông báo $tokens';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get agentStateRunningInBackground => 'chạy ở chế độ nền';

  @override
  String get agentElapsedHint =>
      'Nó đã hoạt động được bao lâu: số lần nó được tiếp tục cộng lại';

  @override
  String get agentStateRunning => 'đang chạy';

  @override
  String get agentStateDone => 'xong';

  @override
  String get agentStateFailed => 'thất bại';

  @override
  String chatSubagentSemantics(String description, String status) {
    return 'Chất phụ $description, $status';
  }

  @override
  String get chatAgentMessageSent => 'đã gửi';

  @override
  String chatAgentMessageSemantics(String agent) {
    return 'Tin nhắn từ agent phụ $agent';
  }

  @override
  String get chatOpensItsConversation => 'Mở cuộc trò chuyện của nó';

  @override
  String get chatLoadEarlier => 'Tải tin nhắn trước đó';

  @override
  String get chatReload => 'Tải lại (tiếp tục ở nơi khác)';

  @override
  String get chatStop => 'Dừng lại';

  @override
  String get chatKeepRunningHint => 'Giữ nó chạy và để agent tiếp tục';

  @override
  String get chatBackground => 'Lý lịch';

  @override
  String get stepThinking => 'suy nghĩ';

  @override
  String get stepThought => 'Nghĩ';

  @override
  String get stepBriefly => 'ngắn gọn';

  @override
  String get toolReading => 'Đọc';

  @override
  String get toolRead => 'Đọc';

  @override
  String get toolGrepping => 'cắt xén';

  @override
  String get toolGrepped => 'đã cắt';

  @override
  String get toolListing => 'Danh sách';

  @override
  String get toolListed => 'Đã niêm yết';

  @override
  String get toolSearching => 'Tìm kiếm';

  @override
  String get toolSearched => 'Đã tìm kiếm';

  @override
  String get toolEditing => 'Chỉnh sửa';

  @override
  String get toolEdited => 'Đã chỉnh sửa';

  @override
  String get toolRunning => 'Đang chạy';

  @override
  String get toolRan => 'Chạy';

  @override
  String get toolFetching => 'Đang tìm nạp';

  @override
  String get toolFetched => 'Đã tìm nạp';

  @override
  String get toolAgent => 'Agent';

  @override
  String get toolUpdatingTodos => 'Cập nhật việc cần làm';

  @override
  String get toolUpdatedTodos => 'Việc cần làm đã cập nhật';

  @override
  String todoCount(int done, int total) {
    return 'Tất cả $done/$total';
  }

  @override
  String get todoAllDone => 'Tất cả đã xong';

  @override
  String get todoNone => 'Danh sách trống';

  @override
  String get todoAdded => 'Đã thêm việc cần làm';

  @override
  String get todoStarted => 'Đã bắt đầu việc cần làm';

  @override
  String get todoCompleted => 'Việc cần làm đã hoàn thành';

  @override
  String get todoRemoved => 'Việc cần làm đã bị xóa';

  @override
  String get todoUpdated => 'Việc cần làm đã cập nhật';

  @override
  String get todoChecked => 'Việc cần làm đã kiểm tra';

  @override
  String get toolSending => 'Nói';

  @override
  String get toolSent => 'Nói';

  @override
  String get toolAsking => 'hỏi';

  @override
  String get toolAsked => 'Yêu cầu';

  @override
  String get toolQuestionSkipped => 'Câu hỏi bị bỏ qua';

  @override
  String get toolUsing => 'sử dụng';

  @override
  String get toolUsed => 'Đã sử dụng';

  @override
  String get toolGeneratingImage => 'Tạo hình ảnh';

  @override
  String get toolGeneratedImage => 'Hình ảnh được tạo';

  @override
  String get toolImageFailed => 'Hình ảnh không được tạo';

  @override
  String get toolImageWaiting => 'Tạo hình ảnh';

  @override
  String get imagePickTitle => 'Chọn mô hình để tạo nó với';

  @override
  String get imagePickGenerate => 'Phát ra';

  @override
  String get imagePickDecline => 'Nhảy';

  @override
  String get imageSetDefault => 'Đặt làm mặc định';

  @override
  String get imageDefaultSet => 'Đặt làm mẫu hình ảnh mặc định';

  @override
  String get imageCopyPrompt => 'Sao chép lời nhắc';

  @override
  String get toolProposingGoal => 'Đề xuất mục tiêu';

  @override
  String get toolProposedGoal => 'Đề xuất mục tiêu';

  @override
  String get goalAdopt => 'Đặt làm mục tiêu';

  @override
  String get goalAdopted => 'Đặt mục tiêu';

  @override
  String get goalLabel => 'Mục tiêu';

  @override
  String get goalWorking => 'Đang tiến hành';

  @override
  String get goalWaiting => 'Chờ';

  @override
  String get goalNeedsYou => 'Đang chờ bạn';

  @override
  String get goalMet => 'Đã gặp';

  @override
  String get goalFailed => 'Không thể gặp được';

  @override
  String goalChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã kiểm tra $count lần',
      one: 'đã kiểm tra 1 lần',
    );
    return '$_temp0';
  }

  @override
  String get goalLastCheck => 'Kiểm tra lần cuối';

  @override
  String get goalEdit => 'Chỉnh sửa mục tiêu';

  @override
  String get goalClear => 'Mục tiêu rõ ràng';

  @override
  String get goalClearConfirm => 'Xóa mục tiêu này?';

  @override
  String get goalSet => 'Đặt mục tiêu';

  @override
  String get goalDismiss => 'Miễn nhiệm';

  @override
  String get goalStopsTurn => 'Dừng lượt này có hiệu lực ngay bây giờ';

  @override
  String imageChip(int number) {
    return 'Hình ảnh $number';
  }

  @override
  String imageReferenceRemoved(int number) {
    return '[Hình ảnh $number]';
  }

  @override
  String pastedTextChip(int number) {
    return 'Đã dán văn bản #$number';
  }

  @override
  String pastedTextGone(String path) {
    return 'Dán này không còn ở $path nữa.';
  }

  @override
  String pastedTextLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count dòng',
      one: '+1 dòng',
    );
    return '$_temp0';
  }

  @override
  String get imageCopy => 'Sao chép hình ảnh';

  @override
  String stepsRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã đọc $count tệp',
      one: 'đã đọc 1 tệp',
    );
    return '$_temp0';
  }

  @override
  String stepsSearched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã tìm $count mẫu',
      one: 'đã tìm 1 mẫu',
    );
    return '$_temp0';
  }

  @override
  String stepsListed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã liệt kê $count thư mục',
      one: 'đã liệt kê 1 thư mục',
    );
    return '$_temp0';
  }

  @override
  String stepsFetched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã tải $count trang',
      one: 'đã tải 1 trang',
    );
    return '$_temp0';
  }

  @override
  String stepsRan(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã chạy $count lệnh',
      one: 'đã chạy 1 lệnh',
    );
    return '$_temp0';
  }

  @override
  String stepsBrowsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã thực hiện $count bước trên trình duyệt',
      one: 'đã thực hiện 1 bước trên trình duyệt',
    );
    return '$_temp0';
  }

  @override
  String stepsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã dùng $count công cụ',
      one: 'đã dùng 1 công cụ',
    );
    return '$_temp0';
  }

  @override
  String get stepsSeparator => ', ';

  @override
  String stepsThought(String duration) {
    return 'nghĩ $duration';
  }

  @override
  String get turnCopy => 'Sao chép câu trả lời';

  @override
  String get turnFork => 'Ngã ba từ đây';

  @override
  String get turnCopied => 'Đã sao chép';

  @override
  String turnSpeed(String speed) {
    return '$speed tok/s';
  }

  @override
  String turnTokens(String tokens) {
    return 'Mã thông báo $tokens';
  }

  @override
  String turnTokensHint(String input, String output) {
    return 'Lần này: đọc $input (có cache), viết $output';
  }

  @override
  String get turnSpeedHint => 'Tốc độ đầu ra trung bình';

  @override
  String get turnOutputTokensHint => 'Viết cho đến lượt này';

  @override
  String get turnSpeedLiveHint =>
      'Tốc độ đầu ra, được lấy mẫu trong 2 giây qua';

  @override
  String get turnDurationHint => 'Thời gian ở lượt này diễn ra';

  @override
  String get turnCostHint => 'Chi phí của lượt này';

  @override
  String turnWorked(String duration) {
    return 'Đã làm việc cho $duration';
  }

  @override
  String turnStopped(String duration) {
    return 'Đã dừng sau $duration';
  }

  @override
  String get planCardLabel => 'Kế hoạch';

  @override
  String planCardRound(int round) {
    return 'v$round';
  }

  @override
  String get planDrafting => 'soạn thảo';

  @override
  String get planAwaiting => 'Sẵn sàng để bắt đầu';

  @override
  String get planApproved => 'Tán thành';

  @override
  String get planSentBack => 'Đã gửi lại';

  @override
  String get planStart => 'Bắt đầu';

  @override
  String get planStartHint =>
      'Thoát khỏi chế độ Plan và thực hiện kế hoạch này';

  @override
  String get planStartMessage => 'Thực hiện kế hoạch';

  @override
  String turnFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tệp',
      one: '1 tệp',
    );
    return '$_temp0';
  }

  @override
  String toolLines(String range) {
    return 'Dòng $range';
  }

  @override
  String get commandStarted => 'Đã bắt đầu';

  @override
  String get commandInBackground => 'ở chế độ nền';

  @override
  String get commandCopyCommand => 'Sao chép lệnh';

  @override
  String get commandCopyOutput => 'Sao chép đầu ra';

  @override
  String get commandMoveToBackground => 'Di chuyển đến nền';

  @override
  String get commandMore => 'Hơn';

  @override
  String get chatSubagent => 'chất phụ';

  @override
  String get chatLoadingHistory => 'Đang tải cuộc trò chuyện…';

  @override
  String get activityCompacting => 'Thu gọn cuộc trò chuyện';

  @override
  String get noticeCompacted => 'Cuộc trò chuyện được nén';

  @override
  String get noticeCompactedAuto => 'Cuộc hội thoại được nén tự động';

  @override
  String get noticeCompactedTooLong =>
      'Cuộc trò chuyện được thu gọn sớm: nhà cung cấp đã từ chối vì mô hình quá dài';

  @override
  String noticeCompactedTooLongWindow(String window) {
    return 'Cuộc hội thoại được thu gọn sớm: nhà cung cấp đã từ chối vì mô hình này quá dài, mất ít hơn tập ngữ cảnh $window';
  }

  @override
  String noticeCompactedTokens(String tokens) {
    return 'Mã thông báo $tokens';
  }

  @override
  String noticeCompactedFromTo(String before, String after) {
    return 'Mã thông báo $before → $after';
  }

  @override
  String get activityPlanning => 'Lên kế hoạch cho bước đi tiếp theo';

  @override
  String get activityMusings =>
      'suy ngẫm\nmì ống\nthấm qua\nSuy nghĩ\nĐun sôi\nướp\nmày mò\nGrokking\nSuy nghĩ kỹ lại\nKết nối các dấu chấm\nTheo đuổi linh cảm\nLập một kế hoạch\nẤp ủ một kế hoạch\nCân nhắc các lựa chọn\nGỡ rối chủ đề\nMã thông báo chăn gia súc\nBối cảnh triệu tập\nHỏi con vịt cao su\nĐọc lá trà\nPhác thảo trên khăn ăn\nViết nguệch ngoạc ở lề\nNheo mắt trước sự khác biệt\nĐếm dấu ngoặc đơn\nKết bạn với trình biên dịch\nĐàm phán với các loại\nTrường hợp cạnh tranh\nTruy tìm ngăn xếp\nLật qua các tài liệu\nĐánh vần cơ sở mã\nXếp hàng vịt\nLắc 8 quả bóng thần kỳ\nLàm nóng các tế bào thần kinh\ngấp suy nghĩ\nRàng buộc đơn nguyên\nHỏi nhà tiên tri\nKhuấy nồi\nĐánh bóng kế hoạch';

  @override
  String activityMusingsCommand(String name) {
    return 'Nheo mắt ở đầu ra của $name\nTiêu hóa những gì $name đã nói\nChọn qua đầu ra của $name\nGật đầu theo $name';
  }

  @override
  String activityMusingsCommandFailed(String name) {
    return 'Nhìn chằm chằm vào lỗi của $name\nHỏi $name có chuyện gì vậy\nGỡ rối khiếu nại của $name\nAn ủi $name';
  }

  @override
  String activityMusingsRead(String name) {
    return 'Đang xem $name\nĐang tìm hiểu $name\nĐang lần theo thông tin trong $name\nĐang đọc kỹ $name';
  }

  @override
  String activityMusingsEdit(String name) {
    return 'Chiêm ngưỡng $name mới\nKiểm tra kỹ $name\nHy vọng $name vẫn biên dịch\nXem lại $name một lần nữa';
  }

  @override
  String activityMusingsSearch(String name) {
    return 'Quét kết quả $name để tìm vàng\nLọc qua các trận đấu $name\nTheo dõi khách hàng tiềm năng $name';
  }

  @override
  String activityMusingsFolder(String name) {
    return 'Chọc phá $name\nĐiểm danh trong $name\nTăng kích thước $name';
  }

  @override
  String activityMusingsWeb(String name) {
    return 'Ghi chú từ $name\nTiêu hóa $name';
  }

  @override
  String activityMusingsAgent(String name) {
    return 'Phỏng vấn $name\nChấm bài tập về nhà của $name\nXem qua những phát hiện của $name';
  }

  @override
  String activityMusingsMcp(String name) {
    return 'Đang mở gói câu trả lời của $name\nXem những gì $name đã gửi lại';
  }

  @override
  String get activityMusingsBrowser =>
      'Nhìn vào trang\nNheo mắt nhìn ảnh chụp màn hình';

  @override
  String get activityMusingsImage =>
      'Chiêm ngưỡng hình ảnh tươi mới\nChú ý đến hình ảnh mới';

  @override
  String get activityMusingsDenied =>
      'Tìm cách khác\nĐi theo con đường ngắm cảnh';

  @override
  String get composerCommands => 'Lệnh';

  @override
  String get composerMentions => 'Tệp và cuộc trò chuyện';

  @override
  String get composerPlaceholder =>
      'Lập kế hoạch, tìm kiếm hoặc xây dựng bất cứ thứ gì  ·  kéo thả/dán tệp  / để xem lệnh';

  @override
  String composerApprovalTitle(String agent) {
    return '$agent cần xin quyền như thế nào?';
  }

  @override
  String get composerApprovalDefault => 'Yêu cầu phê duyệt';

  @override
  String get composerApprovalDefaultDetail =>
      'Hỏi trước khi sửa tệp hoặc chạy lệnh';

  @override
  String get composerApprovalAcceptEdits => 'Cho phép chỉnh sửa';

  @override
  String get composerApprovalAcceptEditsDetail =>
      'Tự do sửa tệp, nhưng phải hỏi trước khi chạy lệnh';

  @override
  String get composerApprovalAuto => 'Tự động phê duyệt';

  @override
  String get composerApprovalAutoDetail =>
      'Tự chạy thao tác an toàn, chặn thao tác có rủi ro';

  @override
  String get composerApprovalDontAsk => 'Không hỏi';

  @override
  String get composerApprovalDontAskDetail =>
      'Từ chối mọi thao tác chưa được phê duyệt trước';

  @override
  String get composerApprovalFullAccess => 'Toàn quyền truy cập';

  @override
  String get composerApprovalFullAccessDetail =>
      'Không kiểm tra: mọi chỉnh sửa và lệnh đều chạy mà không cần hỏi';

  @override
  String get composerContextUsage => 'Mức sử dụng ngữ cảnh';

  @override
  String get composerSend => 'Gửi  ↵';

  @override
  String get composerStop => 'Dừng';

  @override
  String get composerSettingContext => 'Ngữ cảnh';

  @override
  String get composerSettingEffort => 'Mức suy luận';

  @override
  String get composerNoResults => 'Không có kết quả';

  @override
  String stripOpen(String name) {
    return 'Mở $name';
  }

  @override
  String stripRunningElapsed(int seconds) {
    return 'Đang chạy · ${seconds}s';
  }

  @override
  String stripFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tệp đã thay đổi',
      one: '1 tệp đã thay đổi',
    );
    return '$_temp0';
  }

  @override
  String stripAgentsRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subagent đang chạy',
      one: '1 subagent đang chạy',
    );
    return '$_temp0';
  }

  @override
  String stripTasksRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tác vụ nền đang chạy',
      one: '1 tác vụ nền đang chạy',
    );
    return '$_temp0';
  }

  @override
  String get stripUndoAll => 'Hoàn tác tất cả';

  @override
  String get stripKeepAll => 'Giữ tất cả';

  @override
  String get stripKeep => 'Giữ';

  @override
  String get stripUndo => 'Hoàn tác';

  @override
  String get agentKeepFile => 'Giữ tệp';

  @override
  String get agentUndoFile => 'Hoàn tác tệp';

  @override
  String get agentPreviousChange => 'Thay đổi trước đó';

  @override
  String get agentNextChange => 'Thay đổi tiếp theo';

  @override
  String get agentMoreActions => 'Thêm hành động';

  @override
  String get stripChangeAdded => 'Đã thêm';

  @override
  String get stripChangeModified => 'Đã sửa đổi';

  @override
  String get stripChangeDeleted => 'Đã xóa';

  @override
  String get stripChangeConflict =>
      'Tệp đã thay đổi thêm sau khi agent chỉnh sửa, nên thao tác Hoàn tác không thể tự khôi phục thay đổi của agent. Hãy hoàn tác thủ công rồi giữ kết quả.';

  @override
  String get stripChangeUntracked =>
      'Không xác định được nội dung trước khi thay đổi (vì quá lớn để lưu hoặc agent không cung cấp). Bạn có thể giữ nguyên, nhưng không thể tự động hoàn tác.';

  @override
  String get stripChangesDiff => 'Thay đổi agent';

  @override
  String get usageUsed => 'Đã sử dụng';

  @override
  String get usageContextWindow => 'Cửa sổ ngữ cảnh';

  @override
  String usageTokensSummary(String used, String total, String percent) {
    return 'Mã thông báo $used / $total · $percent%';
  }

  @override
  String get usageReservedForCompaction => 'Dành riêng cho việc nén';

  @override
  String get usagePromptCache => 'Bộ nhớ đệm nhắc nhở';

  @override
  String usageCacheLast(String read, String written, String uncached) {
    return 'Yêu cầu cuối cùng: $read đã đọc · $written đã viết · $uncached không được lưu vào bộ nhớ đệm';
  }

  @override
  String usageCacheOverall(String percent) {
    return 'trò chuyện chính $percent%';
  }

  @override
  String usageCacheConversation(String read, String written, String percent) {
    return 'Cuộc trò chuyện chính: $read đã đọc · $written đã viết · $percent% đạt';
  }

  @override
  String get usageCacheExcludes =>
      'Không tính các tác nhân phụ, việc nén hoặc các yêu cầu phụ của CLI';

  @override
  String get usagePlanUsage => 'Lập kế hoạch sử dụng';

  @override
  String get usageThisSession => 'Phiên này';

  @override
  String get usageCheckingLimits => 'Đang kiểm tra giới hạn…';

  @override
  String get usageLimitsUnavailable =>
      'Giới hạn hiện không có sẵn; mở lại cái này sau để thử lại.';

  @override
  String get usageLimitsAfterMessage =>
      'Giới hạn cập nhật với cuộc trò chuyện; chúng hiển thị sau một tin nhắn.';

  @override
  String usageResets(String when) {
    return 'đặt lại $when';
  }

  @override
  String usageInMinutes(int minutes) {
    return 'trong ${minutes}m';
  }

  @override
  String usageInHours(int hours) {
    return 'trong ${hours}h';
  }

  @override
  String usageInHoursMinutes(int hours, int minutes) {
    return 'trong ${hours}h ${minutes}m';
  }

  @override
  String usageInDays(int days) {
    return 'trong ${days}d';
  }

  @override
  String usageInDaysHours(int days, int hours) {
    return 'trong ${days}d ${hours}h';
  }

  @override
  String healthStopped(String name) {
    return '$name đã dừng';
  }

  @override
  String healthFolderGone(String folder) {
    return 'Thư mục dự án đã biến mất: $folder';
  }

  @override
  String get healthHideDetails => 'Ẩn chi tiết';

  @override
  String get markdownDetails => 'Chi tiết';

  @override
  String get healthDetails => 'Chi tiết';

  @override
  String get healthRetry => 'Thử lại';

  @override
  String get interactionOther => 'Khác';

  @override
  String get interactionTypeYourAnswer => 'Nhập câu trả lời của bạn';

  @override
  String get interactionAllowOnce => 'Cho phép một lần';

  @override
  String get interactionDeny => 'Từ chối';

  @override
  String get interactionDenyHint =>
      'Thay vào đó, hãy cho agent biết phải làm gì';

  @override
  String interactionStepOf(int step, int total) {
    return '$step / $total';
  }

  @override
  String get interactionSkip => 'Nhảy';

  @override
  String get interactionSubmit => 'Nộp';

  @override
  String get interactionNext => 'Kế tiếp';

  @override
  String get interactionBack => 'Mặt sau';

  @override
  String get interactionCollapse => 'Thu gọn';

  @override
  String get interactionExpand => 'Mở rộng';

  @override
  String interactionMoreLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '… thêm $count dòng',
      one: '… thêm 1 dòng',
    );
    return '$_temp0';
  }

  @override
  String get mcpServers => 'máy chủ MCP';

  @override
  String mcpConnectedOf(int connected, int total) {
    return '$connected của $total được kết nối';
  }

  @override
  String get mcpRefresh => 'Làm cho khỏe lại';

  @override
  String get mcpNoServers =>
      'Không có máy chủ MCP nào được định cấu hình cho dự án này.';

  @override
  String get mcpConnected => 'Đã kết nối';

  @override
  String get mcpConnecting => 'Đang kết nối…';

  @override
  String get mcpFailed => 'Thất bại';

  @override
  String get mcpNeedsSignIn => 'Cần đăng nhập';

  @override
  String get mcpDisabled => 'Tàn tật';

  @override
  String get mcpReconnect => 'Kết nối lại';

  @override
  String get mcpSignIn => 'Đăng nhập';

  @override
  String get mcpEnable => 'Cho phép';

  @override
  String get mcpDisable => 'Vô hiệu hóa';

  @override
  String get mcpTest => 'Kiểm tra kết nối';

  @override
  String get mcpTestAll => 'Kiểm tra tất cả';

  @override
  String get mcpViewLog => 'Xem nhật ký';

  @override
  String mcpExitCode(int code) {
    return 'Đã thoát với mã $code';
  }

  @override
  String mcpTimedOut(int seconds) {
    return 'Không có câu trả lời trong vòng $seconds giây';
  }

  @override
  String get mcpLog => 'Đầu ra (stderr)';

  @override
  String get mcpNoLog => 'Nó không viết gì cả.';

  @override
  String get mcpSignInHint =>
      'Đăng nhập từ bảng máy chủ MCP của cuộc trò chuyện hoặc bằng /mcp.';

  @override
  String get mcpProbeNote =>
      'Bắt đầu và chào mừng với quá trình khởi tạo của MCP, khi `claude mcp list` kiểm tra nó.';

  @override
  String queuedMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tin nhắn chờ',
      one: '1 tin nhắn chờ',
    );
    return '$_temp0 · sẽ gửi khi agent hoàn tất';
  }

  @override
  String queuedImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ảnh',
      one: '1 ảnh',
    );
    return '$_temp0';
  }

  @override
  String get queuedEdit => 'Quay lại để chỉnh sửa';

  @override
  String get queuedSendNow => 'Dừng agent và gửi cái này ngay bây giờ';

  @override
  String get queuedRemove => 'Xóa khỏi hàng đợi';

  @override
  String get replySuggestionHint =>
      'Bấm để đưa nó vào đầu vào, bấm đúp để gửi nó';

  @override
  String get stopConfirmMessage => 'Dừng agent?';

  @override
  String stopConfirmDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tác vụ đang chạy nền cũng sẽ dừng.',
      one: 'Tác vụ đang chạy nền cũng sẽ dừng.',
    );
    return '$_temp0';
  }

  @override
  String get stopConfirmStop => 'Dừng lại';

  @override
  String get tabClose => 'Đóng';

  @override
  String get tabCloseOthers => 'Đóng phần khác';

  @override
  String get tabCloseToTheRight => 'Gần Bên Phải';

  @override
  String get tabCloseSaved => 'Đóng Đã lưu';

  @override
  String get tabCloseAll => 'Đóng tất cả';

  @override
  String get fileLinkOpen => 'Mở';

  @override
  String get fileLinkOpenInPanel => 'Mở trong bảng điều khiển bên';

  @override
  String get fileLinkPreview => 'Xem trước';

  @override
  String get fileLinkOpenInBrowser => 'Mở trong trình duyệt';

  @override
  String get tabCopyPath => 'Sao chép đường dẫn';

  @override
  String get tabCopyRelativePath => 'Sao chép đường dẫn tương đối';

  @override
  String get tabRevealInExplorerView => 'Hiển thị trong Chế độ xem Explorer';

  @override
  String get tabMoreActions => 'Thêm hành động…';

  @override
  String get markdownShowPreview => 'Xem trước';

  @override
  String get markdownShowSource => 'Giảm giá';

  @override
  String get markdownFindInSource =>
      'Tìm không có sẵn trong bản xem trước: hiển thị nguồn Markdown.';

  @override
  String markdownPasteFolder(String name) {
    return 'Không thể dán các thư mục vào tài liệu: $name';
  }

  @override
  String get markdownPasteLargeTitle => 'Sao chép một tệp lớn?';

  @override
  String markdownPasteLargeMessage(String name, String size) {
    return '$name là $size. Sao chép nó bên cạnh tài liệu?';
  }

  @override
  String get markdownPasteLargeConfirm => 'Sao chép';

  @override
  String markdownPasteFailed(String name, String error) {
    return 'Không thể dán $name: $error';
  }

  @override
  String get markdownPasteMoved =>
      'Tài liệu đã thay đổi trong khi dán: các liên kết đã được thêm vào cuối tài liệu.';

  @override
  String tabCloseNamed(String name) {
    return 'Đóng $name';
  }

  @override
  String tabDeleted(String name) {
    return '$name (đã xóa)';
  }

  @override
  String get commonDismiss => 'Bỏ qua';

  @override
  String layoutTogglePrimarySideBar(String keybinding) {
    return 'Chuyển đổi thanh bên chính ($keybinding)';
  }

  @override
  String layoutTogglePanel(String keybinding) {
    return 'Bảng chuyển đổi ($keybinding)';
  }

  @override
  String layoutToggleChat(String keybinding) {
    return 'Chuyển đổi trò chuyện ($keybinding)';
  }

  @override
  String get dialogCloseDialog => 'Đóng hộp thoại';

  @override
  String get menuDismissMenu => 'Loại bỏ menu';

  @override
  String get notificationsHide => 'Ẩn thông báo';

  @override
  String get notificationsNone => 'Không có thông báo';

  @override
  String get notificationsNoNew => 'Không có thông báo mới';

  @override
  String notificationsNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thông báo mới',
      one: '1 thông báo mới',
    );
    return '$_temp0';
  }

  @override
  String get notificationsCenterNoNew => 'KHÔNG CÓ THÔNG BÁO MỚI';

  @override
  String get notificationsCenterTitle => 'THÔNG BÁO';

  @override
  String get notificationsClearAll => 'Xóa tất cả thông báo';

  @override
  String get notificationsCollapse => 'Thu gọn thông báo';

  @override
  String get notificationsExpand => 'Mở rộng thông báo';

  @override
  String get notificationsMoreActions => 'Thêm hành động...';

  @override
  String get notificationsClear => 'Xóa thông báo';

  @override
  String notificationsSource(String source) {
    return 'Nguồn: $source';
  }

  @override
  String explorerCannotReadFolder(String error) {
    return 'Không thể đọc thư mục: $error';
  }

  @override
  String get explorerNameRequired => 'Tên tệp hoặc thư mục phải được cung cấp.';

  @override
  String get explorerNameStartsWithSlash =>
      'Tên tệp hoặc thư mục không thể bắt đầu bằng dấu gạch chéo.';

  @override
  String explorerNameExists(String name) {
    return 'Tệp hoặc thư mục $name đã tồn tại ở vị trí này. Vui lòng chọn một tên khác.';
  }

  @override
  String explorerNameInvalid(String name) {
    return 'Tên $name không hợp lệ làm tên tệp hoặc thư mục. Vui lòng chọn một tên khác.';
  }

  @override
  String get explorerNameWhitespace =>
      'Đã phát hiện khoảng trắng ở đầu hoặc cuối trong tên tệp hoặc thư mục.';

  @override
  String get explorerMoveToTrash => 'Chuyển vào Thùng rác';

  @override
  String explorerDeleteFolderUnsaved(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bạn đang xóa thư mục $name có thay đổi chưa lưu trong $count tệp. Bạn có muốn tiếp tục?',
      one:
          'Bạn đang xóa thư mục $name có thay đổi chưa lưu trong 1 tệp. Bạn có muốn tiếp tục?',
    );
    return '$_temp0';
  }

  @override
  String explorerDeleteFileUnsaved(String name) {
    return 'Bạn đang xóa $name với những thay đổi chưa được lưu. Bạn có muốn tiếp tục không?';
  }

  @override
  String get explorerChangesLost =>
      'Những thay đổi của bạn sẽ bị mất nếu bạn không lưu chúng.';

  @override
  String explorerConfirmDeleteFolder(String name) {
    return 'Bạn có chắc chắn muốn xóa \'$name\' và nội dung của nó không?';
  }

  @override
  String explorerConfirmDeleteFile(String name) {
    return 'Bạn có chắc chắn muốn xóa \'$name\' không?';
  }

  @override
  String get explorerRestoreFromTrash =>
      'Bạn có thể khôi phục tệp này từ Thùng rác.';

  @override
  String explorerConfirmPermanentDeleteFolder(String name) {
    return 'Bạn có chắc chắn muốn xóa vĩnh viễn \'$name\' và nội dung của nó không?';
  }

  @override
  String explorerConfirmPermanentDeleteFile(String name) {
    return 'Bạn có chắc chắn muốn xóa vĩnh viễn \'$name\' không?';
  }

  @override
  String get explorerIrreversible =>
      'Hành động này là không thể thay đổi được!';

  @override
  String get explorerRestoreWithUndo =>
      'Bạn có thể khôi phục tệp này bằng lệnh Hoàn tác.';

  @override
  String get explorerDeleteFilesUnsaved =>
      'Bạn đang xóa các tệp có những thay đổi chưa được lưu. Bạn có muốn tiếp tục không?';

  @override
  String explorerConfirmDeleteMultiple(int count) {
    return 'Bạn có chắc chắn muốn xóa các tệp/thư mục $count sau đây và nội dung của chúng không?';
  }

  @override
  String explorerConfirmPermanentDeleteMultiple(int count) {
    return 'Bạn có chắc chắn muốn xóa vĩnh viễn các tệp/thư mục $count sau đây cũng như nội dung của chúng không?';
  }

  @override
  String get explorerRestoreFilesFromTrash =>
      'Bạn có thể khôi phục các tệp này từ Thùng rác.';

  @override
  String get explorerRestoreFilesWithUndo =>
      'Bạn có thể khôi phục các tệp này bằng lệnh Hoàn tác.';

  @override
  String explorerMoreFilesNotShown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '...chưa hiện thêm $count tệp',
      one: '...chưa hiện thêm 1 tệp',
    );
    return '$_temp0';
  }

  @override
  String get explorerTrashFailed =>
      'Không thể xóa bằng Thùng rác. Thay vào đó, bạn có muốn xóa vĩnh viễn không?';

  @override
  String get explorerDeletePermanently => 'Xóa vĩnh viễn';

  @override
  String get explorerPasteIntoAncestor =>
      'Tệp cần dán là tệp gốc của thư mục đích';

  @override
  String explorerUploading(int done, int total) {
    return 'Đang tải tệp lên... $done/$total';
  }

  @override
  String explorerDownloading(int done, int total) {
    return 'Đang tải tệp... $done/$total';
  }

  @override
  String get explorerDownload => 'Tải xuống...';

  @override
  String explorerDownloadExists(String folder) {
    return 'Một số trong số chúng đã có trong $folder. Thay thế chúng?';
  }

  @override
  String get explorerDownloadReplace => 'Thay thế';

  @override
  String get explorerPreparingTransfer => 'Đang chuẩn bị tệp...';

  @override
  String composerCopyToHostFailed(String error) {
    return 'Không thể sao chép tệp sang máy từ xa: $error';
  }

  @override
  String get explorerNewFile => 'Tệp mới...';

  @override
  String get explorerNewFolder => 'Thư mục mới...';

  @override
  String get explorerRevealInFinder => 'Tiết lộ trong Finder';

  @override
  String get explorerFindInFolder => 'Tìm trong Thư mục...';

  @override
  String get explorerOpenInTerminal => 'Mở trong Terminal';

  @override
  String get explorerRename => 'Đổi tên...';

  @override
  String get findNoResults => 'Không có kết quả';

  @override
  String findMatchOf(String current, String total) {
    return '$current của $total';
  }

  @override
  String get findFind => 'Tìm thấy';

  @override
  String get findMatchCase => 'Hộp diêm';

  @override
  String get findWholeWord => 'Toàn bộ từ';

  @override
  String get findRegularExpression => 'Biểu thức chính quy';

  @override
  String get findPreviousMatch => 'Trận đấu trước';

  @override
  String get findNextMatch => 'Trận đấu tiếp theo';

  @override
  String get findClose => 'Đóng tìm';

  @override
  String get findReplace => 'Thay thế';

  @override
  String get findReplaceMatch => 'Thay thế trận đấu';

  @override
  String get findReplaceAll => 'Thay thế tất cả';

  @override
  String get findToggleReplace => 'Chuyển đổi thay thế';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get settingsSectionLanguage => 'Khu vực & Ngôn ngữ';

  @override
  String get settingsSectionKeyboard => 'Phím tắt';

  @override
  String get settingsSectionDataDirectory => 'Thư mục dữ liệu';

  @override
  String get settingsSectionGeneral => 'Chung';

  @override
  String get settingsGroupPreferences => 'Tùy chọn';

  @override
  String get settingsGroupAdvanced => 'Nâng cao';

  @override
  String get generalSettingsTitle => 'Chung';

  @override
  String get generalSettingsCommitAttribution => 'Ghi nhận tác giả commit';

  @override
  String get generalSettingsCommitAttributionDescription =>
      'Chọn tác giả được ghi trên commit và pull request do agent tạo. Chỉ áp dụng cho agent khởi chạy sau khi thay đổi; hiện mới hỗ trợ Claude Code.';

  @override
  String get generalSettingsClaudeCore => 'Bộ lõi';

  @override
  String get generalSettingsClaudeCoreDescription =>
      'Claude Code CLI: Chương trình riêng của Anthropic, với thao tác đăng nhập và thiết lập của máy này; chọn nó để sử dụng đăng ký Claude. Tích hợp sẵn: đi kèm với BaoCode và chỉ sử dụng các kiểu máy được thêm vào Cài đặt → Kiểu máy. Theo mặc định, CLI nơi máy này có Claude Code, nếu không thì có lõi tích hợp sẵn; CLI, được chọn ở nơi không có, sẽ được tải xuống cho bạn. Những thay đổi áp dụng cho các phiên mới.';

  @override
  String get generalSettingsClaudeCoreBuiltin => 'Tích hợp sẵn';

  @override
  String get generalSettingsClaudeCoreCli => 'Claude Code CLI';

  @override
  String get generalSettingsQueuedMessages =>
      'Tin nhắn gửi khi agent đang làm việc';

  @override
  String get generalSettingsQueuedMessagesDescription =>
      'Khi một tin nhắn được gửi trong khi agent vẫn đang làm việc được tiếp nhận. Áp dụng cho các tin nhắn được gửi sau khi thay đổi; Claude Code chỉ dành cho bây giờ.';

  @override
  String get generalSettingsQueuedAfterTurn => 'Sau tác vụ hiện tại';

  @override
  String get generalSettingsQueuedDuringTurn => 'Trong tác vụ hiện tại';

  @override
  String get generalSettingsPromptSuggestions => 'Đề xuất câu trả lời';

  @override
  String get generalSettingsPromptSuggestionsDescription =>
      'Sau mỗi lượt, hai hoặc ba gợi ý tin nhắn tiếp theo xuất hiện phía trên ô soạn: nhấp để đưa vào ô nhập và chỉnh sửa, nhấp đúp để gửi ngay; nhấn Tab khi ô nhập trống để chọn gợi ý đầu tiên. Agent tạo gợi ý ở cuối phản hồi mà không phát sinh yêu cầu bổ sung. Áp dụng từ tin nhắn tiếp theo.';

  @override
  String generalSettingsCommitAttributionLabel(String name) {
    return 'Ghi nhận tác giả commit: $name';
  }

  @override
  String get generalSettingsAttributionAgent => 'Theo agent';

  @override
  String get generalSettingsAttributionAgentDetail =>
      'Của riêng agent, ví dụ: Claude Code hoặc thuộc tính được đặt trong ~/.claude/settings.json của bạn.';

  @override
  String get generalSettingsAttributionNone => 'Không có';

  @override
  String get generalSettingsAttributionNoneDetail =>
      'Không thêm thông tin tác giả vào commit hoặc pull request.';

  @override
  String get settingsSectionNotifications => 'Thông báo';

  @override
  String get notificationsSettingsTitle => 'Thông báo';

  @override
  String get notificationsEnabled => 'Thông báo cho tôi khi agent cần tôi';

  @override
  String get notificationsEnabledDescription =>
      'Thông báo của hệ thống và âm thanh khi nhân viên hỏi bạn điều gì đó hoặc kết thúc. Biểu tượng của ứng dụng đếm số đặc vụ đang đợi bạn hoặc chưa thấy.';

  @override
  String get notificationsEvents => 'Thông báo khi có agent';

  @override
  String get notificationsEventNeedsInput => 'Cần ý kiến ​​đóng góp của bạn';

  @override
  String get notificationsEventNeedsInputDetail =>
      'Nó hỏi một câu hỏi để xin phép hoặc để kế hoạch của nó được phê duyệt.';

  @override
  String get notificationsEventFinished => 'Kết thúc một lượt';

  @override
  String get notificationsEventFinishedDetail =>
      'Đã xong và đang chờ tin nhắn tiếp theo của bạn.';

  @override
  String get notificationsWhen => 'Khi';

  @override
  String get notificationsWhenDescription =>
      'Có thông báo về agent bạn đang xem hay không, cửa sổ phía trước.';

  @override
  String get notificationsWhenUnfocused => 'Khi tôi không nhìn vào nó';

  @override
  String get notificationsWhenAlways => 'Luôn luôn';

  @override
  String notificationsWhenLabel(String name) {
    return 'Thông báo: $name';
  }

  @override
  String get notificationsSound => 'Âm thanh';

  @override
  String get notificationsSoundMicrowave => 'Đinh lò vi sóng';

  @override
  String get notificationsSoundManOhYeah => 'trời-ồ-vâng';

  @override
  String get notificationsSoundGulpGulpGulpGulp => 'ực ực ực ực';

  @override
  String get notificationsSoundNone => 'Không có';

  @override
  String get notificationsSoundChoose => 'Chọn một tệp…';

  @override
  String notificationsSoundLabel(String name) {
    return 'Âm thanh: $name';
  }

  @override
  String get notificationsSoundPlay => 'Chơi';

  @override
  String get traySettings => 'Khay';

  @override
  String get trayEnabledMacOS => 'Hiển thị biểu tượng trên thanh menu';

  @override
  String get trayEnabledWindows => 'Hiển thị biểu tượng trên khay hệ thống';

  @override
  String get trayEnabledDescription =>
      'Đóng cửa sổ sẽ ẩn nó ở đó và các tác nhân tiếp tục chạy; menu của nó hiển thị các đặc vụ đang chờ bạn và thoát khỏi ứng dụng.';

  @override
  String get trayShow => 'Hiển thị BảoCode';

  @override
  String get trayWaiting => 'Chờ đợi bạn';

  @override
  String trayWaitingCount(int count) {
    return '$count đang chờ';
  }

  @override
  String trayRunning(int count) {
    return '$count đang chạy';
  }

  @override
  String get trayQuit => 'Thoát khỏi BảoCode';

  @override
  String get attentionNeedsInput => 'Cần ý kiến ​​đóng góp của bạn';

  @override
  String get attentionFinished => 'Hoàn thành';

  @override
  String get attentionPlanReady => 'Kế hoạch đã sẵn sàng để xem xét';

  @override
  String get placeholderBinary =>
      'Tệp không được hiển thị trong trình soạn thảo văn bản vì nó ở dạng nhị phân hoặc sử dụng mã hóa văn bản không được hỗ trợ.';

  @override
  String placeholderTooLarge(String size) {
    return 'Tệp không được hiển thị trong trình soạn thảo văn bản vì nó rất lớn ($size).';
  }

  @override
  String get placeholderNotFound =>
      'Không thể mở trình chỉnh sửa vì không tìm thấy tệp.';

  @override
  String get placeholderUnexpected =>
      'Không thể mở trình chỉnh sửa do xảy ra lỗi không mong muốn.';

  @override
  String get placeholderOpenAnyway => 'Vẫn mở';

  @override
  String get changeOpenWith => 'Mở bằng';

  @override
  String get openInDefaultApp => 'Mở trong ứng dụng mặc định';

  @override
  String openInDefaultAppFailed(String name) {
    return 'Không thể mở \'$name\' trong ứng dụng mặc định.';
  }

  @override
  String get placeholderTryAgain => 'Thử lại';

  @override
  String fileErrorConflict(String path) {
    return 'tệp đã thay đổi trên đĩa. Mở lại trước khi lưu: $path';
  }

  @override
  String fileErrorNotFound(String path) {
    return 'Không tìm thấy tệp: $path';
  }

  @override
  String fileErrorBinary(String path) {
    return 'Không thể chỉnh sửa tệp nhị phân: $path';
  }

  @override
  String fileErrorTooLarge(String path) {
    return 'Không thể chỉnh sửa các tệp trên 5 MB: $path';
  }

  @override
  String fileErrorExists(String name) {
    return 'Tệp hoặc thư mục $name đã tồn tại ở vị trí này.';
  }

  @override
  String get themeDefaultLight => 'Ánh sáng mặc định';

  @override
  String get themeDefaultDark => 'Mặc định tối';

  @override
  String get themeLightThemes => 'chủ đề ánh sáng';

  @override
  String get themeDarkThemes => 'chủ đề đen tối';

  @override
  String get themeHighContrastThemes => 'chủ đề có độ tương phản cao';

  @override
  String get themeAuto => 'Tự động';

  @override
  String get themeFollowSystem => 'Theo dõi hệ thống';

  @override
  String get themeSelectPlaceholder => 'Chọn chủ đề màu';

  @override
  String get dateNow => 'Hiện nay';

  @override
  String dateAgo(String time) {
    return '$time trước';
  }

  @override
  String dateIn(String time) {
    return 'trong $time';
  }

  @override
  String dateSeconds(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giây',
      one: '$count giây',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giây',
      one: '$count giây',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateMinutes(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phút',
      one: '$count phút',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phút',
      one: '$count phút',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateHours(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giờ',
      one: '$count giờ',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giờ',
      one: '$count giờ',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateDays(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ngày',
      one: '$count ngày',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ngày',
      one: '$count ngày',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateWeeks(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tuần',
      one: '$count tuần',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tuần',
      one: '$count tuần',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateMonths(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tháng',
      one: '$count tháng',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thêm',
      one: '$count mo',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateYears(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count năm',
      one: '$count năm',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count năm',
      one: '$count năm',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String get commonRefresh => 'Làm mới';

  @override
  String get commonMoreActions => 'Thao tác khác...';

  @override
  String get commonCollapseAll => 'Thu gọn tất cả';

  @override
  String get commonYes => 'Có';

  @override
  String get gitStatusIndexModified => 'Chỉ mục đã sửa đổi';

  @override
  String get gitStatusModified => 'Đã sửa đổi';

  @override
  String get gitStatusIndexAdded => 'Đã thêm chỉ mục';

  @override
  String get gitStatusIndexDeleted => 'Đã xóa chỉ mục';

  @override
  String get gitStatusDeleted => 'Đã xóa';

  @override
  String get gitStatusIndexRenamed => 'Chỉ mục được đổi tên';

  @override
  String get gitStatusIndexCopied => 'Đã sao chép chỉ mục';

  @override
  String get gitStatusUntracked => 'Không bị theo dõi';

  @override
  String get gitStatusIgnored => 'Đã bỏ qua';

  @override
  String get gitStatusIntentToAdd => 'Ý định thêm';

  @override
  String get gitStatusIntentToRename => 'Ý định đổi tên';

  @override
  String get gitStatusTypeChanged => 'Loại đã thay đổi';

  @override
  String get gitStatusBothDeleted => 'Xung đột: Cả hai đã bị xóa';

  @override
  String get gitStatusAddedByUs => 'Xung đột: Được thêm bởi chúng tôi';

  @override
  String get gitStatusDeletedByThem => 'Xung đột: Bị họ xóa';

  @override
  String get gitStatusAddedByThem => 'Xung đột: Được thêm bởi họ';

  @override
  String get gitStatusDeletedByUs => 'Xung đột: Đã bị xóa bởi chúng tôi';

  @override
  String get gitStatusBothAdded => 'Xung đột: Cả hai được thêm vào';

  @override
  String get gitStatusBothModified => 'Xung đột: Cả hai đều được sửa đổi';

  @override
  String get gitIgnoredInGit => 'Bị bỏ qua trong Git';

  @override
  String get gitBlameNotCommittedYet => 'Chưa cam kết';

  @override
  String get gitContainsEmphasizedItems => 'Chứa các mục được nhấn mạnh';

  @override
  String get gitChangeIndex => 'chỉ mục';

  @override
  String get gitChangeWorkingTree => 'Cây làm việc';

  @override
  String get gitChangeDeleted => 'Đã xóa';

  @override
  String get gitChangeTheirs => 'của họ';

  @override
  String get gitChangeOurs => 'của chúng tôi';

  @override
  String get gitChangeUntracked => 'Không bị theo dõi';

  @override
  String get gitChangeIntentToAdd => 'Có ý định thêm';

  @override
  String get gitChangeTypeChanged => 'Loại đã thay đổi';

  @override
  String get scmTitle => 'quản lý mã nguồn';

  @override
  String get scmNoProviders =>
      'Không có nhà cung cấp quản lý mã nguồn nào được đăng ký.';

  @override
  String get scmInstallGit =>
      'Cài đặt Git, một hệ thống quản lý mã nguồn phổ biến, để theo dõi các thay đổi mã và cộng tác với những người khác.';

  @override
  String get scmNoRepository =>
      'Thư mục hiện đang mở không có kho lưu trữ Git. Bạn có thể khởi tạo một kho lưu trữ sẽ kích hoạt các tính năng quản lý mã nguồn do Git cung cấp.';

  @override
  String get scmInitializeRepository => 'Khởi tạo kho lưu trữ';

  @override
  String get scmChanges => 'Thay đổi';

  @override
  String scmTooManyChanges(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Kho lưu trữ này có quá nhiều thay đổi: chỉ $countString đầu tiên được hiển thị và các thay đổi về tệp không còn làm mới chúng nữa. Sử dụng Làm mới để đọc lại chúng.';
  }

  @override
  String get scmGroupMerge => 'Hợp nhất các thay đổi';

  @override
  String get scmGroupStaged => 'Thay đổi theo giai đoạn';

  @override
  String get scmGraph => 'đồ thị';

  @override
  String get scmCommit => 'Commit';

  @override
  String get scmCommitChanges => 'Commit thay đổi';

  @override
  String get scmCommitAmend => 'Commit (sửa commit trước)';

  @override
  String get scmCommitStaged => 'Commit các thay đổi đã stage';

  @override
  String get scmCommitAll => 'commit tất cả';

  @override
  String get scmCommitStagedAmend => 'commit đã đã stage (Sửa đổi)';

  @override
  String get scmCommitAllAmend => 'commit tất cả (Sửa đổi)';

  @override
  String get scmUndoLastCommit => 'Hoàn tác commit cuối cùng';

  @override
  String get scmGraphBranches => 'Các nhánh hiển thị';

  @override
  String get scmGraphCurrentBranch => 'Nhánh hiện tại';

  @override
  String get scmGraphAllBranches => 'Tất cả nhánh';

  @override
  String get scmGoToCurrent => 'Đi tới mục lịch sử hiện tại';

  @override
  String get scmViewAndSort => 'Xem & Sắp xếp';

  @override
  String get scmViewAsList => 'Xem dưới dạng danh sách';

  @override
  String get scmViewAsTree => 'Xem dưới dạng cây';

  @override
  String get scmSortByName => 'Sắp xếp các thay đổi theo tên';

  @override
  String get scmSortByPath => 'Sắp xếp các thay đổi theo đường dẫn';

  @override
  String get scmSortByStatus => 'Sắp xếp các thay đổi theo trạng thái';

  @override
  String get scmStageChanges => 'Thay đổi giai đoạn';

  @override
  String get scmUnstageChanges => 'Thay đổi không giai đoạn';

  @override
  String get scmDiscardChanges => 'Hủy thay đổi';

  @override
  String get scmStageAllMerge => 'Giai đoạn tất cả các thay đổi hợp nhất';

  @override
  String get scmStageAll => 'Giai đoạn tất cả các thay đổi';

  @override
  String get scmUnstageAll => 'Bỏ qua tất cả các thay đổi';

  @override
  String get scmDiscardAll => 'Hủy bỏ tất cả thay đổi';

  @override
  String get scmOpenFile => 'Mở tệp';

  @override
  String get scmOpenChanges => 'Mở Thay đổi';

  @override
  String get scmOpenFileHead => 'Mở tệp (ĐẦU)';

  @override
  String get scmAddToGitignore => 'Thêm vào .gitignore';

  @override
  String get scmInput => 'Đầu vào quản lý mã nguồn';

  @override
  String scmMessagePlaceholder(String keybinding) {
    return 'Tin nhắn ($keybinding để commit)';
  }

  @override
  String scmMessagePlaceholderBranch(String keybinding, String branch) {
    return 'Thông báo ($keybinding để commit về \"$branch\")';
  }

  @override
  String get scmGenerateCommitMessage => 'Tạo thông báo commit';

  @override
  String get scmCancelGenerateCommitMessage => 'Hủy tạo thông báo commit';

  @override
  String get scmNoChangesToGenerate =>
      'Không có thay đổi nào để tạo thông báo commit.';

  @override
  String get scmPublishBranch => 'Đẩy nhánh lên remote';

  @override
  String scmPublishBranchNamed(String branch) {
    return 'Đẩy nhánh “$branch” lên remote';
  }

  @override
  String scmPublishingBranchNamed(String branch) {
    return 'Đang đẩy nhánh “$branch” lên remote...';
  }

  @override
  String get scmSyncChanges => 'Đồng bộ hóa các thay đổi';

  @override
  String get scmSynchronizeChanges => 'Đồng bộ hóa các thay đổi';

  @override
  String get scmSynchronizingChanges => 'Đang đồng bộ hóa các thay đổi...';

  @override
  String get scmFetch => 'Tìm về';

  @override
  String get scmFetchFromAllRemotes => 'Tìm nạp từ tất cả các điều khiển từ xa';

  @override
  String get scmPull => 'Pull';

  @override
  String get scmPush => 'Push';

  @override
  String scmPullCommits(int count, String upstream) {
    return 'Kéo các commit $count từ $upstream';
  }

  @override
  String scmPushCommits(int count, String upstream) {
    return 'Push $count commit $upstream';
  }

  @override
  String scmPullPushCommits(int behind, int ahead, String upstream) {
    return 'Kéo $behind và đẩy $ahead commit giữa $upstream';
  }

  @override
  String scmConfirmSync(String upstream) {
    return 'Hành động này sẽ kéo và đẩy các commit từ và tới \"$upstream\".';
  }

  @override
  String get scmDontShowAgain => 'Được rồi, đừng hiển thị nữa';

  @override
  String get scmNoRemotes => 'Kho mã nguồn chưa cấu hình remote để đẩy lên.';

  @override
  String get scmProvideMessage => 'Vui lòng cung cấp thông báo commit';

  @override
  String get scmNoStagedChanges =>
      'Không có thay đổi theo giai đoạn nào để commit.\n\nBạn có muốn thực hiện tất cả các thay đổi của mình và commit trực tiếp không?';

  @override
  String get scmAlways => 'Luôn luôn';

  @override
  String get scmNever => 'Không bao giờ';

  @override
  String get scmNoChangesToCommit => 'Không có thay đổi nào để commit.';

  @override
  String get scmCreateEmptyCommit => 'Tạo commit trống';

  @override
  String get scmCantUndo =>
      'Không thể hoàn tác vì HEAD không trỏ đến bất kỳ commit nào.';

  @override
  String get scmConfirmUndoMerge =>
      'commit cuối cùng là commit hợp nhất. Bạn có chắc chắn muốn hoàn tác nó không?';

  @override
  String get scmUndoMergeCommit => 'Hoàn tác commit hợp nhất';

  @override
  String get scmIrreversibleFile =>
      'Đây là điều KHÔNG THỂ ĐẢO NGƯỢC!\ntệp này sẽ MẤT MÃI nếu bạn tiếp tục.';

  @override
  String get scmIrreversibleFiles =>
      'Đây là điều KHÔNG THỂ ĐẢO NGƯỢC!\nNhững tệp này sẽ bị MẤT MÃI MÃI nếu bạn tiếp tục.';

  @override
  String get scmIrreversibleWorkingSet =>
      'Đây là điều KHÔNG THỂ ĐẢO NGƯỢC!\nBộ công việc hiện tại của bạn sẽ MẤT MÃI nếu bạn tiếp tục.';

  @override
  String scmConfirmDeleteUntracked(String name) {
    return 'Bạn có chắc chắn muốn XÓA tệp không bị theo dõi sau: \'$name\' không?';
  }

  @override
  String scmConfirmDeleteUntrackedCount(int count) {
    return 'Bạn có chắc chắn muốn XÓA các tệp $count không bị theo dõi không?';
  }

  @override
  String get scmRestoreFilesFromTrash =>
      'Bạn có thể khôi phục các tệp này từ Thùng rác.';

  @override
  String get scmDeleteFile => 'Xóa tệp';

  @override
  String scmDeleteAllFiles(int count) {
    return 'Xóa tất cả các tệp $count';
  }

  @override
  String scmConfirmRestore(String name) {
    return 'Bạn có chắc chắn muốn khôi phục \'$name\' không?';
  }

  @override
  String scmConfirmRestoreAll(int count) {
    return 'Bạn có chắc chắn muốn khôi phục TẤT CẢ các tệp $count không?';
  }

  @override
  String scmConfirmDiscard(String name) {
    return 'Bạn có chắc chắn muốn hủy các thay đổi trong \'$name\' không?';
  }

  @override
  String scmConfirmDiscardAll(int count) {
    return 'Bạn có chắc chắn muốn loại bỏ TẤT CẢ các thay đổi trong tệp $count không?';
  }

  @override
  String get scmRestoreFile => 'Khôi phục tệp';

  @override
  String scmRestoreAllFiles(int count) {
    return 'Khôi phục tất cả các tệp $count';
  }

  @override
  String get scmDiscardFile => 'Hủy tệp';

  @override
  String scmDiscardAllFiles(int count) {
    return 'Loại bỏ tất cả các tệp $count';
  }

  @override
  String scmDiscardTrackedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hủy thay đổi của tất cả $count tệp được theo dõi',
      one: 'Hủy thay đổi của 1 tệp được theo dõi',
    );
    return '$_temp0';
  }

  @override
  String get scmCopyCommitHash => 'Sao chép hàm băm commit';

  @override
  String get scmCopyCommitMessage => 'Sao chép tin nhắn commit';

  @override
  String get scmIncomingChanges => 'Những thay đổi sắp tới';

  @override
  String get scmOutgoingChanges => 'Thay đổi đi';

  @override
  String scmCommitDate(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String period,
  ) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'tháng 1',
      '2': 'tháng 2',
      '3': 'tháng 3',
      '4': 'tháng 4',
      '5': 'tháng 5',
      '6': 'tháng 6',
      '7': 'tháng 7',
      '8': 'tháng 8',
      '9': 'tháng 9',
      '10': 'tháng 10',
      '11': 'tháng 11',
      '12': 'tháng 12',
      'other': 'tháng $month',
    });
    String _temp1 = intl.Intl.selectLogic(period, {'am': 'SA', 'other': 'CH'});
    return '$_temp0 ngày $day năm $year lúc $hour:$minute $_temp1';
  }

  @override
  String get gitCheckoutBranchTag => 'Checkout nhánh/tag...';

  @override
  String get gitSelectBranchOrTag => 'Chọn nhánh hoặc tag để checkout';

  @override
  String get gitSelectBranchDetached =>
      'Chọn nhánh để checkout ở chế độ detached';

  @override
  String get gitCreateBranch => 'Tạo chi nhánh mới...';

  @override
  String get gitCreateBranchFrom => 'Tạo chi nhánh mới từ...';

  @override
  String get gitCheckoutDetached => 'Checkout ở chế độ detached...';

  @override
  String get gitBranches => 'nhánh';

  @override
  String get gitRemoteBranches => 'nhánh xa';

  @override
  String get gitTags => 'thẻ';

  @override
  String gitRemoteBranchAt(String commit) {
    return 'Chi nhánh từ xa tại $commit';
  }

  @override
  String gitTagAt(String commit) {
    return 'Gắn thẻ tại $commit';
  }

  @override
  String get gitSelectRefToBranchFrom => 'Chọn một ref để tạo chi nhánh từ đó';

  @override
  String get gitBranchName => 'Tên chi nhánh';

  @override
  String get gitProvideBranchName => 'Vui lòng cung cấp tên chi nhánh mới';

  @override
  String gitBranchExists(String name) {
    return 'Nhánh \"$name\" đã tồn tại';
  }

  @override
  String gitNewBranchWillBe(String name) {
    return 'Chi nhánh mới sẽ là \"$name\"';
  }

  @override
  String get timelineCopyCommitId => 'Sao chép ID commit';

  @override
  String get timelineNoEditor =>
      'Trình chỉnh sửa đang hoạt động không thể cung cấp thông tin về dòng thời gian.';

  @override
  String get timelineNotConfigured =>
      'Không có thông tin dòng thời gian được cung cấp. quản lý mã nguồn chưa được định cấu hình.';

  @override
  String timelineLoading(String name) {
    return 'Đang tải dòng thời gian cho $name...';
  }

  @override
  String get timelineNone => 'Không có thông tin dòng thời gian được cung cấp.';

  @override
  String get timelineLoadMore => 'Tải thêm';

  @override
  String timelineYou(String time) {
    return 'Bạn, $time';
  }

  @override
  String get commonExpandAll => 'Mở rộng tất cả';

  @override
  String get searchTitle => 'Tìm kiếm';

  @override
  String get searchClearResults => 'Xóa kết quả tìm kiếm';

  @override
  String searchMatchCase(String keybinding) {
    return 'Hộp đựng diêm ($keybinding)';
  }

  @override
  String searchMatchWholeWord(String keybinding) {
    return 'Khớp toàn bộ từ ($keybinding)';
  }

  @override
  String searchUseRegExp(String keybinding) {
    return 'Sử dụng biểu thức chính quy ($keybinding)';
  }

  @override
  String searchPreserveCase(String keybinding) {
    return 'Hộp bảo quản ($keybinding)';
  }

  @override
  String get searchReplace => 'Thay thế';

  @override
  String get searchReplaceAll => 'Thay thế tất cả';

  @override
  String searchReplaceKeys(String keybinding) {
    return 'Thay thế ($keybinding)';
  }

  @override
  String searchReplaceAllKeys(String keybinding) {
    return 'Thay thế tất cả ($keybinding)';
  }

  @override
  String get searchDismiss => 'Miễn nhiệm';

  @override
  String searchDismissKeys(String keybinding) {
    return 'Loại bỏ ($keybinding)';
  }

  @override
  String get searchCopyAll => 'Sao chép tất cả';

  @override
  String get searchToggleReplace => 'Chuyển đổi Thay thế';

  @override
  String get searchToggleDetails => 'Chuyển đổi chi tiết tìm kiếm';

  @override
  String get searchFilesToInclude => 'tệp để bao gồm';

  @override
  String get searchFilesToExclude => 'tệp cần loại trừ';

  @override
  String get searchIncludeExample => 'ví dụ. *.ts, src/**/bao gồm';

  @override
  String get searchExcludeExample => 'ví dụ. *.ts, src/**/loại trừ';

  @override
  String get searchUseExcludeSettings =>
      'Sử dụng Cài đặt loại trừ và bỏ qua tệp';

  @override
  String get searchLimitHit =>
      'Tập kết quả chỉ chứa một tập hợp con của tất cả các kết quả phù hợp. Hãy cụ thể hơn trong tìm kiếm của bạn để thu hẹp kết quả.';

  @override
  String searchResultCount(int matches, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      matches,
      locale: localeName,
      other: '$matches kết quả',
      one: '1 kết quả',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files tệp',
      one: '1 tệp',
    );
    return '$_temp0 trong $_temp1';
  }

  @override
  String searchNoResultsIncludeExclude(String include, String exclude) {
    return 'Không tìm thấy kết quả nào trong \'$include\' ngoại trừ \'$exclude\'';
  }

  @override
  String searchNoResultsInclude(String include) {
    return 'Không tìm thấy kết quả nào trong \'$include\'';
  }

  @override
  String searchNoResultsExclude(String exclude) {
    return 'Không tìm thấy kết quả nào ngoại trừ \'$exclude\'';
  }

  @override
  String get searchNoResults =>
      'Không tìm thấy kết quả nào. Xem lại cài đặt của bạn để biết các loại trừ được định cấu hình và kiểm tra các tệp gitignore của bạn';

  @override
  String searchOccurrences(int occurrences, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      occurrences,
      locale: localeName,
      other: '$occurrences lần xuất hiện',
      one: '1 lần xuất hiện',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files tệp',
      one: '1 tệp',
    );
    return '$_temp0 trong $_temp1';
  }

  @override
  String searchConfirmReplace(String counts) {
    return 'Thay thế $counts?';
  }

  @override
  String searchConfirmReplaceWith(String counts, String value) {
    return 'Thay thế $counts bằng \'$value\'?';
  }

  @override
  String searchReplaced(String counts) {
    return 'Đã thay thế $counts.';
  }

  @override
  String searchReplacedWith(String counts, String value) {
    return 'Đã thay thế $counts bằng \'$value\'.';
  }

  @override
  String get extTitle => 'Tiện ích mở rộng';

  @override
  String get extTitleInstalled => 'Tiện ích mở rộng: Đã cài đặt';

  @override
  String get extTitleRecommended => 'Tiện ích mở rộng: Được đề xuất';

  @override
  String get extTitleMarketplace => 'Tiện ích mở rộng: Thị trường';

  @override
  String get extFilter => 'Bộ lọc tiện ích mở rộng...';

  @override
  String get extInstalled => 'Đã cài đặt';

  @override
  String get extRecommended => 'Khuyến khích';

  @override
  String get extClearSearch => 'Xóa kết quả tìm kiếm tiện ích mở rộng';

  @override
  String get extSearchPlaceholder =>
      'Tiện ích mở rộng tìm kiếm trong Marketplace';

  @override
  String get extNoneFound => 'Không tìm thấy tiện ích mở rộng nào.';

  @override
  String get extInstall => 'Cài đặt';

  @override
  String get extUninstall => 'Gỡ cài đặt';

  @override
  String get extInstalling => 'Đang cài đặt';

  @override
  String get extUninstalling => 'Gỡ cài đặt';

  @override
  String get extManage => 'Quản lý';

  @override
  String get extCopyId => 'Sao chép ID tiện ích mở rộng';

  @override
  String extInstallError(String id, String error) {
    return 'Lỗi khi cài đặt tiện ích mở rộng \'$id\'. $error';
  }

  @override
  String extUninstallError(String id, String error) {
    return 'Lỗi khi gỡ cài đặt tiện ích mở rộng \'$id\'. $error';
  }

  @override
  String get extLanguageServer => 'Máy chủ ngôn ngữ';

  @override
  String extLanguageServerFor(String languages) {
    return 'Máy chủ ngôn ngữ cho $languages';
  }

  @override
  String extMissingRuntime(String id, String runtime) {
    return 'Cài đặt \'$id\' cần $runtime, không tìm thấy. Cài đặt $runtime, sau đó thử lại.';
  }

  @override
  String extUnavailable(String id) {
    return 'Không tìm thấy \'$id\' trên PATH và không thể cài đặt tự động.';
  }

  @override
  String langStarting(String id) {
    return '$id: đang bắt đầu…';
  }

  @override
  String langStartingTooltip(String id) {
    return 'Đang khởi động $id';
  }

  @override
  String langRunning(String id) {
    return '$id đang chạy';
  }

  @override
  String langError(String id) {
    return '$id đã báo lỗi';
  }

  @override
  String langWarning(String id) {
    return '$id đã báo cáo cảnh báo';
  }

  @override
  String get langClickForDetails => 'Nhấp vào nhật ký và cài đặt';

  @override
  String get langViewLog => 'Xem nhật ký';

  @override
  String get langOpenLspSettings => 'Mở cài đặt LSP';

  @override
  String get langServerLogLabel => 'Nhật ký LSP';

  @override
  String langNoLogOutput(String id) {
    return 'Chưa có đầu ra nhật ký nào từ $id.';
  }

  @override
  String langServerInitializing(String id) {
    return '$id vẫn đang khởi tạo (nhấp vào thanh trạng thái để biết chi tiết)';
  }

  @override
  String langServerImportError(String id) {
    return '$id không tải được dự án (nhấp vào thanh trạng thái để biết chi tiết)';
  }

  @override
  String langRestarting(String id) {
    return '$id: đang khởi động lại…';
  }

  @override
  String get langClickToRestart => 'Bấm để khởi động lại ngay bây giờ';

  @override
  String langFailed(String id) {
    return '$id không thành công';
  }

  @override
  String get langClickToRetry => 'Bấm để thử lại';

  @override
  String langInstallingItem(String id) {
    return 'Đang cài đặt $id…';
  }

  @override
  String langInstallingTooltip(String id) {
    return 'Đang cài đặt $id';
  }

  @override
  String langNoneFound(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': 'Không tìm thấy định nghĩa',
      'typeDefinition': 'Không tìm thấy định nghĩa kiểu',
      'implementation': 'Không tìm thấy phần triển khai',
      'other': 'Không tìm thấy tham chiếu',
    });
    return '$_temp0';
  }

  @override
  String langNoneFoundFor(String kind, String word) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': 'Không tìm thấy định nghĩa cho \'$word\'',
      'typeDefinition': 'Không tìm thấy định nghĩa kiểu cho \'$word\'',
      'implementation': 'Không tìm thấy phần triển khai cho \'$word\'',
      'other': 'Không tìm thấy tham chiếu cho \'$word\'',
    });
    return '$_temp0';
  }

  @override
  String get langNavigationUnavailable =>
      'Không có máy chủ ngôn ngữ nào có sẵn để điều hướng mã trong tệp này.';

  @override
  String langNavigationInstall(String id) {
    return 'Cài đặt máy chủ ngôn ngữ \'$id\' để bật điều hướng mã trong tệp này.';
  }

  @override
  String get langReferences => 'Tài liệu tham khảo';

  @override
  String langReferencesTo(String word) {
    return 'Tham chiếu đến \'$word\'';
  }

  @override
  String get langDefinitions => 'định nghĩa';

  @override
  String get langTypeDefinitions => 'Định nghĩa loại';

  @override
  String get langImplementations => 'Triển khai';

  @override
  String get langCantRename => 'Phần tử không thể được đổi tên.';

  @override
  String langRenameFailed(String error) {
    return 'Đổi tên không thành công: $error';
  }

  @override
  String get langNoResult => 'Không có kết quả.';

  @override
  String get langRenameCancelled =>
      'Việc đổi tên đã bị hủy vì tài liệu đã thay đổi.';

  @override
  String get langRenameNotApplied => 'Không thể áp dụng đổi tên.';

  @override
  String get langNoSelectionFormatter =>
      'Không có định dạng cho các lựa chọn trong tệp này.';

  @override
  String get langNoFormatter => 'Không có định dạng cho tệp này.';

  @override
  String langNoFormatterInstall(String id, String language) {
    return 'Không có định dạng cho tệp này. Cài đặt máy chủ ngôn ngữ \'$id\' để định dạng tệp $language.';
  }

  @override
  String get langNoRefactorings => 'Không có khả năng tái cấu trúc nào';

  @override
  String get langNoSourceActions => 'Không có tác vụ nguồn nào';

  @override
  String get langNoCodeActions => 'Không có hành động mã nào';

  @override
  String get langCodeActionNotApplied => 'Không thể áp dụng hành động mã.';

  @override
  String get langShowCodeActions => 'Hiển thị hành động mã';

  @override
  String get langLoading => 'Đang tải...';

  @override
  String get langNoSuggestions => 'Không có gợi ý.';

  @override
  String get langPreferred => 'Ưu tiên';

  @override
  String get langRenameHint => 'Enter để đổi tên, Escape để hủy';

  @override
  String get symbolsNoEditor =>
      'Để đi tới một biểu tượng, trước tiên hãy mở trình soạn thảo văn bản có thông tin về biểu tượng.';

  @override
  String get symbolsLoading => 'Đang tải biểu tượng…';

  @override
  String get symbolsNone => 'Không có biểu tượng soạn thảo';

  @override
  String get symbolsNoMatching => 'Không có ký hiệu soạn thảo phù hợp';

  @override
  String get outlineTitle => 'NỘI DUNG';

  @override
  String get outlineNoEditor =>
      'Trình chỉnh sửa đang hoạt động không thể cung cấp thông tin phác thảo.';

  @override
  String get outlineNoSymbols =>
      'Không tìm thấy biểu tượng nào trong tài liệu.';

  @override
  String get outlineLoading => 'Đang tải ký hiệu tài liệu…';

  @override
  String get panelProblems => 'VẤN ĐỀ';

  @override
  String get panelReferences => 'TÀI LIỆU THAM KHẢO';

  @override
  String get panelTerminal => 'PHẦN CUỐI';

  @override
  String get panelClose => 'Đóng bảng điều khiển';

  @override
  String get panelTerminalUnavailable => 'Terminal không có sẵn.';

  @override
  String get problemsNone =>
      'Không có vấn đề nào được phát hiện trong không gian làm việc.';

  @override
  String problemsPosition(int line, int column) {
    return '[Ln $line, Col $column]';
  }

  @override
  String referencesPosition(int line, int column) {
    return 'Ln $line, Col $column';
  }

  @override
  String get referencesNone =>
      'Chưa có tài liệu tham khảo nào: sử dụng Chuyển đến Tài liệu tham khảo (⇧F12).';

  @override
  String referencesSummary(String title, int count, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kết quả',
      one: '1 kết quả',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files tệp',
      one: '1 tệp',
    );
    return '$title — $_temp0 trong $_temp1';
  }

  @override
  String get termRename => 'Đổi tên...';

  @override
  String get termKillTerminal => 'Đóng Terminal';

  @override
  String get termKillOtherTerminals => 'Đóng các Terminal khác';

  @override
  String get termKillAllTerminals => 'Đóng tất cả Terminal';

  @override
  String get termStopAllTasks => 'Dừng tất cả các tác vụ đang chạy';

  @override
  String get termRunInNewTerminal => 'Chạy trong Terminal mới';

  @override
  String get termNoTerminals => 'Không có Terminal';

  @override
  String get termNewTerminal => 'Nhà ga mới';

  @override
  String termNewTerminalKeys(String keybinding) {
    return 'Nhà ga mới ($keybinding)';
  }

  @override
  String get termLaunchProfile => 'Khởi chạy hồ sơ...';

  @override
  String termProfileDefault(String name) {
    return '$name (Mặc định)';
  }

  @override
  String get termSelectDefaultProfile => 'Chọn hồ sơ mặc định';

  @override
  String get termSelectProfileToCreate => 'Chọn cấu hình Terminal để tạo';

  @override
  String get termChooseDefaultProfile =>
      'Chọn cấu hình Terminal mặc định của bạn';

  @override
  String get termProfilesGroup => 'hồ sơ';

  @override
  String get termProfilesDetected => 'phát hiện';

  @override
  String get cmdTerminalNewWithProfile => 'Tạo Terminal mới (Có hồ sơ)';

  @override
  String get termKill => 'Đóng';

  @override
  String termKillKeys(String keybinding) {
    return 'Đóng ($keybinding)';
  }

  @override
  String get termRenameEmpty =>
      'Không cung cấp tên sẽ đặt lại nó về giá trị mặc định';

  @override
  String get termRenameLabel =>
      'Nhập tên Terminal. Nhấn Enter để xác nhận hoặc Escape để hủy.';

  @override
  String get termRerunCommand => 'Chạy lại lệnh';

  @override
  String get termCopyCommand => 'Sao chép lệnh';

  @override
  String get termCopyOutput => 'Sao chép đầu ra';

  @override
  String get termClear => 'Xóa';

  @override
  String get termPasteAsOneLine => 'Dán dưới dạng một dòng';

  @override
  String termPasteConfirm(int count) {
    return 'Bạn có chắc chắn muốn dán dòng văn bản $count vào Terminal không?';
  }

  @override
  String get commonSave => 'Lưu';

  @override
  String get commonDontSave => 'Không lưu';

  @override
  String wbConfirmSave(String name) {
    return 'Bạn có muốn lưu những thay đổi bạn đã thực hiện đối với $name không?';
  }

  @override
  String wbHeadNotAvailable(String name) {
    return 'Phiên bản HEAD của \"$name\" không có sẵn.';
  }

  @override
  String wbRecommendServer(String id, String language) {
    return 'Bạn có muốn cài đặt máy chủ ngôn ngữ \'$id\' được đề xuất cho ngôn ngữ $language không?';
  }

  @override
  String get wbDontShowAgainServer =>
      'Không hiển thị lại cho máy chủ ngôn ngữ này';

  @override
  String get wbQuickCommands => 'Nhập tên lệnh để chạy.';

  @override
  String get wbQuickSymbols => 'Nhập tên của biểu tượng để đi đến.';

  @override
  String get wbQuickFiles =>
      'Tìm kiếm tệp theo tên (thêm : để đi đến một dòng hoặc > để chạy lệnh)';

  @override
  String get quickInputEntry =>
      'Nhấn \'Enter\' để xác nhận thông tin nhập của bạn hoặc \'Escape\' để hủy';

  @override
  String quickInputEntryWithPrompt(String prompt) {
    return '$prompt (Nhấn \'Enter\' để xác nhận hoặc \'Escape\' để hủy)';
  }

  @override
  String wbChordWaiting(String chord) {
    return '($chord) đã được nhấn. Đang chờ phím hợp âm thứ hai...';
  }

  @override
  String wbChordNotCommand(String chord, String keypress) {
    return 'Tổ hợp phím ($chord, $keypress) không phải là lệnh.';
  }

  @override
  String get wbExplorer => 'Nhà thám hiểm';

  @override
  String get wbSearchFiles => 'Tìm kiếm tệp';

  @override
  String wbPendingChanges(int count) {
    return '$count đang chờ thay đổi';
  }

  @override
  String get wbOutline => 'phác thảo';

  @override
  String get wbTimeline => 'Dòng thời gian';

  @override
  String get wbPinTimeline => 'Ghim dòng thời gian hiện tại';

  @override
  String get wbUnpinTimeline => 'Bỏ ghim dòng thời gian hiện tại';

  @override
  String get wbNoProblems => 'Không có vấn đề gì';

  @override
  String wbProblemCounts(int errors, int warnings) {
    return 'Lỗi: $errors, Cảnh báo: $warnings';
  }

  @override
  String wbProblemCountsInfos(int errors, int warnings, int infos) {
    return 'Lỗi: $errors, Cảnh báo: $warnings, Thông tin: $infos';
  }

  @override
  String wbSelectedCount(int count) {
    return '(Đã chọn $count)';
  }

  @override
  String wbSelectedLines(int lines, int count) {
    return '(Các dòng $lines, đã chọn $count)';
  }

  @override
  String get wbGoToLineColumn => 'Đi tới Dòng/Cột';

  @override
  String wbSpaces(int size) {
    return 'Không gian: $size';
  }

  @override
  String wbTabSize(int size) {
    return 'Kích thước tab: $size';
  }

  @override
  String get wbIndentation => 'Thụt lề';

  @override
  String get wbEncoding => 'Mã hóa';

  @override
  String get wbEolMixed => 'Hỗn hợp';

  @override
  String get wbSelectEol => 'Chọn trình tự cuối dòng';

  @override
  String get wbEditorReadOnly =>
      'Trình chỉnh sửa mã đang hoạt động ở chế độ chỉ đọc.';

  @override
  String get wbLanguageMode => 'Chế độ ngôn ngữ';

  @override
  String get shownImage => 'Hình ảnh';

  @override
  String get shownReadOnly => 'Chỉ đọc';

  @override
  String get languageModeAuto => 'Tự động phát hiện';

  @override
  String get languageModePlaceholder => 'Chọn chế độ ngôn ngữ';

  @override
  String get languageModeChange => 'Thay đổi chế độ ngôn ngữ';

  @override
  String get editorCommandPalette => 'Bảng lệnh...';

  @override
  String get editorStartTyping => 'Bắt đầu nhập…';

  @override
  String editorEditLanguage(String language) {
    return 'Chỉnh sửa $language…';
  }

  @override
  String get workspaceClosePane => 'Đóng ngăn';

  @override
  String workspaceCloseBackTo(String title) {
    return 'Đóng khung, quay lại $title';
  }

  @override
  String workspaceCovers(String title) {
    return 'Trên $title, hiển thị lại sau khi quá trình này kết thúc';
  }

  @override
  String workspaceCovered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuộc trò chuyện con',
      one: '1 cuộc trò chuyện con',
    );
    return '$_temp0';
  }

  @override
  String get workspaceLoadingProjects => 'Đang tải dự án…';

  @override
  String get workspaceDesktopOnly =>
      'Agent chạy trong ứng dụng máy tính để bàn';

  @override
  String get workspaceDesktopOnlyDetail =>
      'Claude Code chạy như một tiến trình cục bộ mà trình duyệt không thể khởi động.';

  @override
  String get workspaceOpenProjectFolder => 'Mở một thư mục dự án';

  @override
  String get workspaceOpenProjectFolderDetail =>
      'Các phiên Claude Code của nó hiển thị trên thanh bên; agent mới chạy trong đó.';

  @override
  String settingsFileError(String file, String error) {
    return '$file không thể được áp dụng: $error. Những gì được đọc lần cuối từ nó vẫn có hiệu lực cho đến khi nó được sửa.';
  }

  @override
  String get cmdLastEditorInGroup => 'Mở Trình chỉnh sửa cuối cùng trong nhóm';

  @override
  String get cmdToggleFormatOnSave => 'Chuyển đổi định dạng khi lưu';

  @override
  String get cmdToggleGitBlameEditorDecoration =>
      'Chuyển đổi trang trí trình chỉnh sửa Git Blame';

  @override
  String get kbSourceDefault => 'Mặc định';

  @override
  String get kbSourceUser => 'người dùng';

  @override
  String get kbKeymap => 'Sơ đồ bàn phím';

  @override
  String kbKeymapLabel(String name) {
    return 'Sơ đồ bàn phím: $name';
  }

  @override
  String get kbNone => 'Không có';

  @override
  String get kbImport => 'Nhập từ Mã VS/Con trỏ…';

  @override
  String kbWhenNotParse(String error) {
    return 'Mệnh đề khi không phân tích cú pháp ($error): liên kết phím này không bao giờ được áp dụng.';
  }

  @override
  String kbUnknownContextKeys(int count, String keys) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'BaoCode không biết các phím ngữ cảnh $keys: việc liên kết phím này không bao giờ được áp dụng.',
      one:
          'BaoCode không biết khóa ngữ cảnh $keys: việc liên kết phím này không bao giờ được áp dụng.',
    );
    return '$_temp0';
  }

  @override
  String kbChangeFailed(String error) {
    return 'Không thể thay đổi tổ hợp phím ($error). Vui lòng mở keybind.json và kiểm tra lỗi.';
  }

  @override
  String get kbCopyCommandId => 'Sao chép ID lệnh';

  @override
  String get kbCopyCommandTitle => 'Sao chép tiêu đề lệnh';

  @override
  String get kbChangeKeybindingEllipsis => 'Thay đổi liên kết phím…';

  @override
  String get kbAddKeybindingEllipsis => 'Thêm liên kết phím…';

  @override
  String get kbChangeKeybinding => 'Thay đổi liên kết phím';

  @override
  String get kbAddKeybinding => 'Thêm liên kết phím';

  @override
  String get kbRemoveKeybinding => 'Xóa liên kết phím';

  @override
  String get kbResetKeybinding => 'Đặt lại liên kết phím';

  @override
  String get kbChangeWhen => 'Thay đổi khi biểu thức';

  @override
  String get kbShowSame => 'Hiển thị các tổ hợp phím giống nhau';

  @override
  String get kbRecordingPlaceholder => 'Phím ghi âm. Nhấn Escape để thoát';

  @override
  String get kbSearchPlaceholder => 'Nhập để tìm kiếm trong tổ hợp phím';

  @override
  String get kbSearchLabel => 'Tìm kiếm tổ hợp phím';

  @override
  String kbRecordKeys(String keybinding) {
    return 'Phím ghi ($keybinding)';
  }

  @override
  String get kbRecordingKeys => 'Phím ghi âm';

  @override
  String get kbColumnCommand => 'Yêu cầu';

  @override
  String get kbColumnKeybinding => 'Liên kết phím';

  @override
  String get kbColumnWhen => 'Khi';

  @override
  String get kbColumnSource => 'Nguồn';

  @override
  String get kbWhenLabel => 'Khi biểu hiện';

  @override
  String get kbNoneFound => 'Không tìm thấy tổ hợp phím nào';

  @override
  String kbCannotReadKey(String key) {
    return 'BaoCode không thể đọc được key “$key”: liên kết phím này không bao giờ được áp dụng.';
  }

  @override
  String get kbNotSupported => 'Không được hỗ trợ';

  @override
  String get kbNotSupportedHover =>
      'BaoCode không có lệnh này: keybind được giữ nguyên nhưng không làm gì cả.';

  @override
  String get kbPressKeys => 'Nhấn tổ hợp phím mong muốn rồi nhấn Enter.';

  @override
  String get kbChordTo => 'hợp âm để';

  @override
  String kbExistingCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các lệnh hiện có của $count có liên kết phím này',
      one: '1 lệnh hiện có có tổ hợp phím này',
    );
    return '$_temp0';
  }

  @override
  String get dataDirFullPath => 'Chọn một đường dẫn đầy đủ.';

  @override
  String get dataDirInUse => 'Đây là thư mục đang được sử dụng.';

  @override
  String get dataDirInsideCurrent =>
      'Thư mục mới không thể nằm trong thư mục đang sử dụng.';

  @override
  String get dataDirContainsCurrent =>
      'Thư mục mới không thể chứa thư mục đang sử dụng.';

  @override
  String dataDirCannotMake(String error) {
    return 'Không thể tạo thư mục: $error';
  }

  @override
  String dataDirNotThere(String path) {
    return 'Thư mục $path không có ở đó.';
  }

  @override
  String dataDirNotFolder(String path) {
    return '$path không phải là một thư mục.';
  }

  @override
  String dataDirNotWritable(String path) {
    return 'Không thể ghi tệp bằng $path.';
  }

  @override
  String get dataDirRevealInFileExplorer => 'Tiết lộ trong File Explorer';

  @override
  String get dataDirRevealInFileManager => 'Hiển thị trong Trình quản lý tệp';

  @override
  String get dataDirChecking => 'Đang kiểm tra thư mục…';

  @override
  String get dataDirAlreadyHolds => 'Thư mục đã chứa dữ liệu BaoCode';

  @override
  String get dataDirMoveBack =>
      'Di chuyển dữ liệu của BaoCode về thư mục mặc định?';

  @override
  String get dataDirMoveHere =>
      'Di chuyển dữ liệu của BaoCode vào thư mục này?';

  @override
  String get dataDirUseAsIsDetail =>
      'Sau khi khởi động lại, BaoCode sử dụng dữ liệu ở đó; không có gì được sao chép và thư mục hiện tại sẽ giữ nguyên của bạn.';

  @override
  String get dataDirCopyDetail =>
      'BaoCode sao chép các cài đặt, tổ hợp phím, máy chủ ngôn ngữ và trạng thái ở đó, đồng thời sử dụng thư mục đó sau khi khởi động lại.';

  @override
  String get dataDirOtherFiles =>
      'Thư mục chứa các tệp khác: chúng ở lại, bên cạnh chính BaoCode.';

  @override
  String get dataDirUseItsData => 'Sử dụng dữ liệu của nó';

  @override
  String get dataDirCopyAndSwitch => 'Sao chép và chuyển đổi';

  @override
  String get dataDirCopying => 'Đang sao chép…';

  @override
  String dataDirCopyingProgress(int done, int total) {
    return 'Đang sao chép… $done của các tệp $total';
  }

  @override
  String dataDirMoveFailed(String error) {
    return 'Không thể di chuyển dữ liệu: $error';
  }

  @override
  String dataDirMoveInUse(String path) {
    return '$path đang được chương trình khác sử dụng. Hãy đóng chương trình đó rồi thử lại.';
  }

  @override
  String get dataDirRestartTitle =>
      'Khởi động lại BaoCode để sử dụng thư mục dữ liệu mới';

  @override
  String dataDirRestartDetail(String current, String next) {
    return 'BaoCode tiếp tục sử dụng $current cho đến khi khởi động lại. Lần khởi động tiếp theo sử dụng $next và đề nghị loại bỏ những gì còn sót lại trong lần khởi động cũ.';
  }

  @override
  String get dataDirTheNewFolder => 'thư mục mới';

  @override
  String get quitConfirmMessage => 'Thoát khỏi BaoCode?';

  @override
  String get quitConfirmDetail =>
      'Các agent và Terminal đang chạy sẽ bị dừng lại.';

  @override
  String get quitConfirmQuit => 'Từ bỏ';

  @override
  String get dataDirQuitNow => 'Thoát ngay';

  @override
  String get dataDirLater => 'Sau đó';

  @override
  String dataDirSetByEnv(String variable) {
    return 'Được đặt bởi biến môi trường $variable.';
  }

  @override
  String dataDirSetIn(String file) {
    return 'Đặt trong $file.';
  }

  @override
  String get dataDirDefaultLocation => 'Vị trí mặc định.';

  @override
  String dataDirTemporaryDefault(String file) {
    return 'Vị trí mặc định, chỉ lần này: thư mục được đặt trong $file không khả dụng.';
  }

  @override
  String get dataDirTitle => 'Thư mục dữ liệu';

  @override
  String get dataDirDescription =>
      'Nơi BaoCode lưu giữ các cài đặt, tổ hợp phím, máy chủ ngôn ngữ và trạng thái riêng của nó. Các chương trình khác cũng giữ các tệp ở đó (bộ nhớ đệm của chế độ xem web); BaoCode không bao giờ di chuyển hoặc loại bỏ những thứ đó.';

  @override
  String get dataDirCurrentFolder => 'Thư mục hiện tại';

  @override
  String get dataDirNewFolder => 'Thư mục mới';

  @override
  String dataDirAfterRestart(String path) {
    return 'Sau khi khởi động lại: $path';
  }

  @override
  String get dataDirChange => 'Thay đổi…';

  @override
  String get dataDirResetDefault => 'Đặt lại về mặc định';

  @override
  String dataDirEnvDecides(String variable) {
    return '$variable quyết định thư mục; bỏ đặt nó để chọn một ở đây.';
  }

  @override
  String dataDirCannotWritePointer(String file, String error) {
    return 'Không thể viết $file: $error';
  }

  @override
  String get dataDirSettingUnreadable =>
      'Không đọc được cài đặt thư mục dữ liệu của BaoCode';

  @override
  String get dataDirCannotWrite =>
      'BaoCode không thể ghi vào thư mục dữ liệu của nó';

  @override
  String get dataDirUnavailable => 'Thư mục dữ liệu của BaoCode không có sẵn';

  @override
  String dataDirWhereEnv(String variable) {
    return 'Nó được thiết lập bởi biến môi trường $variable.';
  }

  @override
  String dataDirWhereFixPointer(String file) {
    return 'Sửa hoặc xóa $file và thử lại; BaoCode chỉ thay đổi nó nếu bạn chọn thư mục khác.';
  }

  @override
  String dataDirWherePointer(String file) {
    return 'Nó được đặt trong $file. Nếu nó nằm trên một ổ đĩa chưa được kết nối, hãy kết nối nó và thử lại.';
  }

  @override
  String dataDirDefaultIs(String path) {
    return 'Thư mục mặc định là $path.';
  }

  @override
  String get dataDirRetry => 'Thử lại';

  @override
  String get dataDirUseDefaultOnce => 'Sử dụng thư mục mặc định lần này';

  @override
  String get dataDirChooseAnother => 'Chọn thư mục khác…';

  @override
  String get dataDirRemoveOldTitle =>
      'Xóa dữ liệu BaoCode còn sót lại trong thư mục trước đó?';

  @override
  String dataDirRemoveOldDetail(String current, String items) {
    return 'BaoCode hiện giữ dữ liệu của nó trong $current. Chỉ các mục của chính nó mới bị xóa khỏi thư mục trước đó ($items); thư mục và mọi thứ khác trong đó vẫn ở đó.';
  }

  @override
  String get dataDirRemove => 'Di dời';

  @override
  String get dataDirKeep => 'Giữ';

  @override
  String get dataDirRemoveOldInUse => 'Không thể xóa một số dữ liệu cũ';

  @override
  String dataDirRemoveOldInUseDetail(String items) {
    return 'Các tệp trong $items đang được sử dụng, có thể bởi một chương trình khác. Mọi thứ khác đã bị xóa; BaoCode đề nghị loại bỏ phần còn lại vào lần khởi động tiếp theo.';
  }

  @override
  String get impTitle => 'Nhập tổ hợp phím';

  @override
  String get impImport => 'Nhập khẩu';

  @override
  String get impNothingFound =>
      'Không tìm thấy tổ hợp phím hoặc sơ đồ bàn phím nào của Visual Studio Code, Cursor, Windsurf hoặc VSCodium.';

  @override
  String get impKeybindingsFrom => 'Tổ hợp phím từ';

  @override
  String impKeybindingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tổ hợp phím $count',
      one: '1 phím bấm',
    );
    return '$_temp0';
  }

  @override
  String get impImportAs => 'Nhập dưới dạng';

  @override
  String get impMerge => 'Hợp nhất với các tổ hợp phím của tôi';

  @override
  String get impMergeDetail => 'Thêm những cái bạn không có sau của bạn.';

  @override
  String get impReplace => 'Thay thế tổ hợp phím của tôi';

  @override
  String get impReplaceDetail =>
      'Sao chép tệp như nó vốn có, bình luận cũng vậy. Của bạn được giữ dưới dạng keybinds.json.bak.';

  @override
  String impAlsoUse(String name) {
    return 'Đồng thời nhập và sử dụng $name';
  }

  @override
  String impInstalledIn(String products) {
    return 'Được cài đặt trong $products';
  }

  @override
  String impImportedFrom(String source) {
    return 'Được nhập từ $source';
  }

  @override
  String impApplied(int supported) {
    return 'Đã áp dụng $supported';
  }

  @override
  String impAppliedUnsupported(int supported, int unsupported) {
    String _temp0 = intl.Intl.pluralLogic(
      unsupported,
      locale: localeName,
      other: 'Các lệnh $unsupported',
      one: '1 lệnh',
    );
    return 'Áp dụng $supported, $_temp0 chưa được hỗ trợ';
  }

  @override
  String impDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các tổ hợp phím $count mà bạn đã có đã bị bỏ qua.',
      one: '1 tổ hợp phím bạn đã có đã bị bỏ qua.',
    );
    return '$_temp0';
  }

  @override
  String impBackup(String path) {
    return 'Các tổ hợp phím trước đây của bạn: $path';
  }

  @override
  String get impNotSupportedYet => 'Chưa được hỗ trợ';

  @override
  String get impNotSupportedDetail =>
      'Chúng nằm trong keybinds.json và hoạt động sau khi ứng dụng có lệnh của chúng.';

  @override
  String impKeymapBuiltIn(String name) {
    return 'Sơ đồ bàn phím: $name được tích hợp sẵn và hiện đang được sử dụng.';
  }

  @override
  String impKeymapImported(String name) {
    return 'Sơ đồ bàn phím: $name đã được nhập và hiện đang được sử dụng.';
  }

  @override
  String impKeybindingsError(String error) {
    return 'Không thể nhập tổ hợp phím: $error';
  }

  @override
  String impKeymapError(String name, String error) {
    return 'Không thể nhập $name: $error';
  }

  @override
  String get explorerNoFolderTitle => 'Không có thư mục nào được mở';

  @override
  String get explorerNoFolder => 'Bạn chưa mở một thư mục.';

  @override
  String get explorerOpenFolder => 'Mở thư mục';

  @override
  String get ideSearchOpenFiles => 'Tìm kiếm tệp đang mở';

  @override
  String get ideWelcomeRecent => 'Gần đây';

  @override
  String get ideStartRecent => 'dự án gần đây';

  @override
  String ideStartViewAll(int count) {
    return 'Xem tất cả ($count)';
  }

  @override
  String get ideOpenRecentPlaceholder => 'Chọn thư mục hoặc tệp để mở';

  @override
  String get ideRecentFolders => 'thư mục';

  @override
  String get ideRecentFiles => 'tệp';

  @override
  String get ideNoRecent => 'Không có thư mục hoặc tệp nào được mở gần đây';

  @override
  String get ideClearRecentConfirm =>
      'Bạn có muốn xóa tất cả các tệp và thư mục đã mở gần đây không?';

  @override
  String get ideClearRecentDetail =>
      'Hành động này là không thể thay đổi được!';

  @override
  String get ideClearRecent => 'Xóa';

  @override
  String get ideChatNoFolder =>
      'Mở một tệp hoặc thư mục để trò chuyện với nhân viên về nó.';

  @override
  String ideCannotOpen(String path, String error) {
    return 'Không thể mở $path: $error';
  }

  @override
  String get cmdNewUntitledFile => 'Tệp văn bản mới';

  @override
  String get cmdOpenFile => 'Mở tệp...';

  @override
  String get cmdOpenFolder => 'Mở thư mục...';

  @override
  String get cmdOpenRecent => 'Mở Gần đây...';

  @override
  String get cmdSaveAs => 'Lưu dưới dạng...';

  @override
  String get cmdMarkdownShowPreview => 'Mở bản xem trước';

  @override
  String get cmdMarkdownShowSource => 'Hiển thị nguồn';

  @override
  String get cmdCloseFolder => 'Đóng thư mục';

  @override
  String get cmdClearRecentlyOpened => 'Xóa Đã mở gần đây...';

  @override
  String cmdInstallShellCommand(String name) {
    return 'Cài đặt lệnh \'$name\' trong PATH';
  }

  @override
  String cmdUninstallShellCommand(String name) {
    return 'Gỡ cài đặt lệnh \'$name\' khỏi PATH';
  }

  @override
  String get cmdCategoryWorkspaces => 'Không gian làm việc';

  @override
  String get cmdCategoryShellCommand => 'Lệnh Shell';

  @override
  String shellCommandInstalled(String name) {
    return 'Lệnh Shell \'$name\' được cài đặt thành công trong PATH.';
  }

  @override
  String shellCommandUninstalled(String name) {
    return 'Lệnh Shell \'$name\' được gỡ cài đặt thành công khỏi PATH.';
  }

  @override
  String shellCommandOccupied(String path, String name) {
    return '$path đã chạy lệnh \'$name\' của ứng dụng khác. Thay thế nó bằng BaoCode?';
  }

  @override
  String get shellCommandReplace => 'Thay thế';

  @override
  String shellCommandFailed(String name, String error) {
    return 'Không thể cài đặt lệnh shell \'$name\': $error';
  }

  @override
  String shellCommandUninstallFailed(String name, String error) {
    return 'Không thể gỡ cài đặt lệnh shell \'$name\': $error';
  }

  @override
  String get generalSettingsMainWindow => 'Mở khi khởi động';

  @override
  String get generalSettingsMainWindowDescription =>
      'BaoCode mở ra những gì: tác nhân hoặc cửa sổ IDE (như Restore Windows nói), không bao giờ cả hai. Theo mặc định, nó ở vị trí nào khi nó thoát lần cuối.';

  @override
  String generalSettingsMainWindowLabel(String name) {
    return 'Mở khi ra mắt: $name';
  }

  @override
  String get generalSettingsMainWindowChat => 'Luôn mở Agent';

  @override
  String get generalSettingsMainWindowIde => 'Luôn mở IDE';

  @override
  String get generalSettingsMainWindowLast => 'Khôi phục phiên trước';

  @override
  String get generalSettingsWindows => 'Cửa sổ';

  @override
  String get generalSettingsIde => 'Fast IDE';

  @override
  String get explorerExcludeSetting => 'Các tệp và thư mục ẩn';

  @override
  String get explorerExcludeSettingDescription =>
      'Các tệp và thư mục mà trình khám phá không hiển thị, được phân tách bằng dấu phẩy: tên (`node_modules`, `*.log`) khớp ở mọi nơi, đường dẫn (`build/**`, `src/generated`) khớp trong thư mục.';

  @override
  String get explorerExcludeSettingPlaceholder =>
      'ví dụ. .git, node_modules, *.log';

  @override
  String get claudePathSetting => 'Con đường';

  @override
  String get claudePathSettingDescription =>
      'Trống: Claude Code mới nhất trên máy này, được tải xuống nếu không có. Một đường dẫn: luôn là đường dẫn đó, ví dụ: một cái bạn đã xây dựng. (claudeCode.path)';

  @override
  String get claudePathSettingHint => 'Tự động';

  @override
  String get claudePathChecking => 'Đang kiểm tra…';

  @override
  String claudePathInUse(String path, String version) {
    return 'Đang sử dụng: $path ($version)';
  }

  @override
  String claudePathInUseUnknown(String path) {
    return 'Đang sử dụng: $path';
  }

  @override
  String claudePathInUseDownloaded(String version) {
    return 'Đang sử dụng: Claude Code $version, do BaoCode tải về';
  }

  @override
  String get claudePathMissing =>
      'Chưa tìm thấy gì: với Claude Code CLI được chọn, nó sẽ được tải xuống khi cuộc trò chuyện đầu tiên bắt đầu.';

  @override
  String get generalSettingsIdeWindows => 'Cửa sổ Fast IDE';

  @override
  String get generalSettingsIdeWindowsDescription =>
      'Nơi Fast Ide mở ra: trong cửa sổ chính thay cho cuộc trò chuyện, mỗi lần một thư mục hoặc trong các cửa sổ riêng, mỗi thư mục một cửa sổ (Cửa sổ mới, ⇧⌘N / Ctrl+Shift+N, mở một cửa sổ trống). Áp dụng ngay lập tức. (window.ideWindows)';

  @override
  String get generalSettingsIdeWindowsSeparate => 'Cửa sổ riêng';

  @override
  String get generalSettingsIdeWindowsMain => 'Trong cửa sổ chính';

  @override
  String generalSettingsWindowLabel(String setting, String name) {
    return '$setting: $name';
  }

  @override
  String get generalSettingsOpenFolders => 'Mở thư mục trong cửa sổ mới';

  @override
  String get generalSettingsOpenFoldersDescription =>
      'Cho dù thư mục được mở từ cửa sổ (Mở thư mục…, Mở gần đây) sẽ có một cửa sổ mới. Theo mặc định, nó thay thế cái hiện tại, trừ khi ⌘/Ctrl được giữ. (window.openFoldersInNewWindow)';

  @override
  String get generalSettingsOpenFiles => 'Mở tệp trong cửa sổ mới';

  @override
  String get generalSettingsOpenFilesDescription =>
      'Liệu tệp được mở từ cửa sổ có có cửa sổ mới hay không. Theo mặc định, nó sẽ mở trong cái hiện tại. (window.openFilesInNewWindow)';

  @override
  String get generalSettingsOpenOn => 'Trong cửa sổ mới';

  @override
  String get generalSettingsOpenOff => 'Trong cửa sổ hiện tại';

  @override
  String get generalSettingsRestoreWindows => 'Khôi phục cửa sổ';

  @override
  String get generalSettingsRestoreWindowsDescription =>
      'Các cửa sổ IDE mở lại khi khởi chạy, vị trí của chúng. (window.restoreWindows)';

  @override
  String get generalSettingsRestoreAll => 'Tất cả cửa sổ';

  @override
  String get generalSettingsRestoreOne => 'Cửa sổ hoạt động gần nhất';

  @override
  String get generalSettingsRestoreFolders => 'Các cửa sổ có thư mục';

  @override
  String get generalSettingsRestoreNone => 'Không khôi phục';

  @override
  String get generalSettingsNewWindowDimensions => 'Kích thước cửa sổ mới';

  @override
  String get generalSettingsNewWindowDimensionsDescription =>
      'Kích thước của một cửa sổ mới. (window.newWindowDimensions)';

  @override
  String get generalSettingsDimensionsDefault => 'Mặc định';

  @override
  String get generalSettingsDimensionsInherit =>
      'Theo cửa sổ hoạt động gần nhất';

  @override
  String get generalSettingsDimensionsMaximized => 'Phóng to';

  @override
  String get generalSettingsDimensionsFullscreen => 'Toàn màn hình';

  @override
  String get generalSettingsConfirmBeforeClose => 'Xác nhận trước khi đóng';

  @override
  String get generalSettingsConfirmBeforeCloseDescription =>
      'Việc đóng cửa sổ có được yêu cầu trước hay không, ngay cả khi không có gì chưa được lưu. (window.confirmBeforeClose)';

  @override
  String get generalSettingsConfirmNever => 'Không bao giờ';

  @override
  String get generalSettingsConfirmKeyboard => 'Khi đóng bằng bàn phím';

  @override
  String get generalSettingsConfirmAlways => 'Luôn luôn';

  @override
  String get cmdNewWindow => 'Cửa sổ mới';

  @override
  String get cmdCloseWindow => 'Đóng cửa sổ';

  @override
  String get cmdSwitchWindow => 'Chuyển đổi cửa sổ...';

  @override
  String get cmdShowChatWindow => 'Hiển thị cửa sổ trò chuyện';

  @override
  String get windowChatTitle => 'Trò chuyện';

  @override
  String get windowWelcomeTitle => 'Chào mừng';

  @override
  String get windowConfirmClose => 'Bạn có chắc chắn muốn đóng cửa sổ không?';

  @override
  String get windowTerminateTerminals =>
      'Bạn có muốn chấm dứt các tiến trình đang chạy trong terminal của cửa sổ không?';

  @override
  String get windowTerminate => 'Chấm dứt';

  @override
  String windowSaveChanges(int count) {
    return 'Bạn có muốn lưu các thay đổi vào các tệp $count sau không?';
  }

  @override
  String get windowSaveAll => 'Lưu tất cả';

  @override
  String get windowCurrent => 'Hiện hành';

  @override
  String get windowSwitchPlaceholder => 'Chọn một cửa sổ để chuyển sang';

  @override
  String get windowCycle => 'Chu kỳ qua Windows';

  @override
  String get windowMenuWindows => 'cửa sổ';

  @override
  String get windowOpened => 'Đã mở';

  @override
  String get generalSettingsShellCommand => 'Lệnh shell';

  @override
  String generalSettingsShellCommandDescription(String location) {
    return 'Mở file và thư mục trong BaoCode từ terminal: \'code <path>\'. Được cài đặt tại $location.';
  }

  @override
  String get generalSettingsShellCommandInstalled => 'Đã cài đặt';

  @override
  String get generalSettingsShellCommandNotInstalled => 'Chưa cài đặt';

  @override
  String get generalSettingsShellCommandOccupied =>
      'Lệnh đang được ứng dụng khác sử dụng';

  @override
  String get generalSettingsShellCommandInstall => 'Cài đặt';

  @override
  String get generalSettingsShellCommandUninstall => 'Gỡ cài đặt';

  @override
  String get menuMore => 'Hơn…';

  @override
  String get sidebarSearch => 'Tìm kiếm';

  @override
  String get sidebarCustomize => 'Kỹ năng';

  @override
  String get sidebarOpenProject => 'Dự án mở';

  @override
  String get palettePlaceholder =>
      'Tìm kiếm tác nhân, cuộc hội thoại, tệp, hành động…';

  @override
  String get paletteFilterAll => 'Tất cả';

  @override
  String get paletteFilterAgents => 'Agent';

  @override
  String get paletteFilterFiles => 'tệp';

  @override
  String get paletteFilterActions => 'hành động';

  @override
  String get paletteFilterSettings => 'Cài đặt';

  @override
  String get paletteRecentAgents => 'Agent gần đây';

  @override
  String get paletteRecentActions => 'Hành động gần đây';

  @override
  String get paletteMessages => 'Trong cuộc trò chuyện';

  @override
  String paletteFilesIn(String project) {
    return 'Các tệp trong $project';
  }

  @override
  String get paletteSearching => 'Đang tìm kiếm…';

  @override
  String get paletteNoResults => 'Không có kết quả';

  @override
  String get paletteNoProject => 'Mở một dự án để tìm kiếm các tệp của nó';

  @override
  String get paletteTypeToSearch => 'Nhập để tìm kiếm';

  @override
  String get paletteHintSelect => 'Lựa chọn';

  @override
  String get paletteHintOpen => 'Mở';

  @override
  String get paletteHintChangeFilter => 'Thay đổi bộ lọc';

  @override
  String get customizeTitle => 'Tùy chỉnh';

  @override
  String get customizeSearchPlaceholder => 'Tìm kiếm plugin, kỹ năng, MCP…';

  @override
  String get customizeKindPlugins => 'Plugin';

  @override
  String get customizeKindMcps => 'MCP';

  @override
  String get customizeKindSkills => 'Kỹ năng';

  @override
  String get customizeKindSubagents => 'Chất phụ';

  @override
  String get customizeKindRules => 'Quy tắc';

  @override
  String get customizeKindMemory => 'Ký ức';

  @override
  String get customizeKindCommands => 'Lệnh';

  @override
  String get customizeKindHooks => 'móc';

  @override
  String get customizeScopeUser => 'người dùng';

  @override
  String get customizeScopeProject => 'Dự án';

  @override
  String get customizeScopeLocal => 'Địa phương';

  @override
  String get customizeScopePlugin => 'Đã cài đặt';

  @override
  String get customizeUserOnly => 'Chỉ người dùng';

  @override
  String get customizeNew => 'Mới';

  @override
  String get customizeEmpty => 'Chưa có gì ở đây';

  @override
  String get customizeNoMatches => 'Không có kết quả phù hợp';

  @override
  String get customizeUnsupported =>
      'Tùy chỉnh Claude Code cần có ứng dụng dành cho máy tính để bàn.';

  @override
  String get customizeSave => 'Cứu';

  @override
  String get customizeRevert => 'Hoàn nguyên';

  @override
  String get customizeSaved => 'Đã lưu';

  @override
  String get customizeUnsaved => 'Những thay đổi chưa được lưu';

  @override
  String get customizeEdit => 'Biên tập';

  @override
  String get customizeReadOnly => 'Chỉ đọc: Claude Code giữ chính tệp này.';

  @override
  String get customizeEnabled => 'Đã bật';

  @override
  String get customizeDisabled => 'Tàn tật';

  @override
  String get customizeLinkUnreachable =>
      'Chưa được tải: đây là liên kết mà hệ thống không thể theo dõi. Cài đặt kỹ năng dưới dạng thư mục thực hoặc liên kết lại.';

  @override
  String get customizeBack => 'Mặt sau';

  @override
  String get customizeClose => 'Đóng Tùy chỉnh';

  @override
  String customizeDeleteTitle(String name) {
    return 'Xóa $name?';
  }

  @override
  String customizeDeleteMessage(String path) {
    return 'Thao tác này sẽ xóa $path và không thể hoàn tác.';
  }

  @override
  String customizeNewTitle(String kind) {
    return '$kind mới';
  }

  @override
  String get customizeNameHint => 'tên';

  @override
  String get customizeNameInvalid =>
      'Bắt đầu bằng một chữ cái hoặc chữ số; không có khoảng trắng hoặc / \\ : * ? \" < > | (tối đa 64)';

  @override
  String get customizeNameUnofficial =>
      'Chính thức là chữ thường, chữ số và - chỉ; Claude.ai có thể từ chối nó';

  @override
  String get customizeNameTaken => 'Một cái tên đó đã tồn tại';

  @override
  String get customizeCreate => 'Tạo nên';

  @override
  String customizeLoadFailed(String error) {
    return 'Không thể đọc: $error';
  }

  @override
  String customizeSaveFailed(String error) {
    return 'Không thể lưu: $error';
  }

  @override
  String get settingsBack => 'Mặt sau';

  @override
  String get settingsSearch => 'Cài đặt tìm kiếm';

  @override
  String get customizeScopeSynced => 'Đã đồng bộ hóa từ Claude.ai';

  @override
  String get customizeSyncedReadOnly =>
      'Chỉ đọc: được đồng bộ hóa từ claude.ai, sẽ ghi lại những thay đổi được thực hiện ở đây.';

  @override
  String customizeEditFile(String file) {
    return 'Chỉnh sửa $file';
  }

  @override
  String get customizeEmptyPlugins =>
      'Không có cài đặt nào. Cài đặt plugin bằng /plugin trong Claude Code.';

  @override
  String get customizeEmptyMemory =>
      'Chưa có gì được ghi nhớ. Claude Code lưu những gì nó biết về bạn và dự án này tại đây khi nó hoạt động (bộ nhớ tự động) và đọc lại trong các cuộc trò chuyện sau này.';

  @override
  String get customizeEmptyMcpsUser =>
      'Chưa có. Thêm một cái với: claude mcp add --scope user <name> -- <command>';

  @override
  String get customizeEmptyMcpsLocal =>
      'Chưa có. Thêm một cái với claude mcp add, chạy trong dự án.';

  @override
  String get customizeEmptyMcpsProject =>
      'Chưa có. Các máy chủ được chia sẻ với dự án sẽ nằm trong .mcp.json của nó.';

  @override
  String customizeEmptyHooks(String file) {
    return 'Chưa có. Móc đi dưới \"móc\" trong $file.';
  }

  @override
  String get customizeConnectorReadOnly =>
      'Chỉ đọc: trình kết nối claude.ai, được quản lý trong cài đặt của claude.ai, trong Trình kết nối.';

  @override
  String get settingsSectionModels => 'Mô hình';

  @override
  String get modelsTitle => 'Mô hình';

  @override
  String get modelsDefault => 'Mô hình mặc định cho phiên mới';

  @override
  String get modelsDefaultDescription =>
      'Nếu không thiết lập, phiên mới dùng mô hình được chọn gần nhất.';

  @override
  String get modelsDefaultLast => 'Được chọn gần nhất';

  @override
  String modelsChoiceLabel(String label, String value) {
    return '$label: $value';
  }

  @override
  String get modelsBuiltinName => 'Claude Code (cấu hình trên máy này)';

  @override
  String get modelsBuiltinDefault => 'Mặc định của Claude Code';

  @override
  String get modelsBuiltinBadge => 'Tích hợp sẵn';

  @override
  String get modelsBuiltinDescription =>
      'Giữ nguyên tài khoản đăng nhập và cấu hình của bạn';

  @override
  String get modelsProviders => 'Nguồn mô hình (upstream)';

  @override
  String modelsEnableProvider(String name) {
    return 'Hiển thị $name trong bộ chọn mô hình';
  }

  @override
  String get modelsFeaturedWhy => 'Vì sao tôi thấy nội dung này?';

  @override
  String get modelsFeaturedNote =>
      'Những dịch vụ này được BaoCode liệt kê chính thức';

  @override
  String get modelsFeaturedNoteHow =>
      'Thêm tính năng nhập bằng một nhấp để được liệt kê miễn phí';

  @override
  String get modelsFeaturedNoteLink => 'Đề xuất dịch vụ của tôi';

  @override
  String modelsImportTitle(String host) {
    return 'Nhập nguồn mô hình từ $host';
  }

  @override
  String get modelsImportProtocol => 'Giao thức';

  @override
  String get modelsImportUrl => 'URL gốc';

  @override
  String get modelsImportKeyLabel => 'Khóa API';

  @override
  String get modelsImportListedBadge => 'Được liệt kê chính thức';

  @override
  String get modelsImportNoKey => 'chưa có, thêm sau';

  @override
  String modelsImportExisting(String name) {
    return 'Bạn đã có nguồn mô hình này: $name.';
  }

  @override
  String get modelsImportNamePlaceholder => 'Tên';

  @override
  String get modelsImportAdd => 'Nhập các mô hình';

  @override
  String get modelsImportFinish => 'Nhập';

  @override
  String get modelsImportWithoutModels => 'Nhập mà không lấy mô hình';

  @override
  String get modelsImportPreparing => 'Đang chuẩn bị danh sách mô hình…';

  @override
  String modelsImportUpdateKey(String name) {
    return 'Cập nhật khóa của $name';
  }

  @override
  String modelsImportOpenExisting(String name) {
    return 'Mở $name';
  }

  @override
  String get modelsImportAsNew => 'Thêm thành nguồn mô hình mới';

  @override
  String get modelsImportInvalid => 'Không thể sử dụng liên kết nhập này';

  @override
  String get modelsImportInvalidDetail =>
      'Liên kết cần có URL gốc (HTTP hoặc HTTPS) và giao thức mà BaoCode hỗ trợ. Hãy yêu cầu dịch vụ cung cấp liên kết mới hoặc tự thêm nguồn mô hình trong Cài đặt → Mô hình.';

  @override
  String get modelsAddProvider => 'Thêm nguồn mô hình';

  @override
  String get modelsMagpieJoin => 'Kết nối magpie';

  @override
  String get modelsMagpieBadge => 'Đồng bộ từ magpie';

  @override
  String get modelsMagpieGateway => 'Gateway magpie';

  @override
  String get modelsMagpieGatewayDescription =>
      'Các mô hình, tài khoản và định tuyến được thiết lập trong Magpie và danh sách này tuân theo nó. Các nhóm định tuyến mới, mô hình hình ảnh và mô hình chim ác là cung cấp cho Claude Code được bật khi chúng xuất hiện; đánh dấu vào bất kỳ cái nào khác bên dưới.';

  @override
  String get modelsMagpieRunning => 'Đang chạy';

  @override
  String get modelsMagpieNotRunning => 'magpie chưa chạy';

  @override
  String get modelsMagpieNotRunningDetail =>
      'Hãy mở magpie hoặc chạy lệnh magpie serve. Các phiên dùng mô hình từ magpie sẽ lỗi cho đến khi dịch vụ chạy.';

  @override
  String get modelsMagpieSync => 'Đồng bộ mô hình';

  @override
  String get modelsNewProviderName => 'Nguồn mô hình mới';

  @override
  String get modelsProviderNoUrl => 'Chưa có URL gốc';

  @override
  String modelsModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mô hình',
      one: '1 mô hình',
      zero: 'chưa có mô hình',
    );
    return '$_temp0';
  }

  @override
  String get modelsAccounts => 'Tài khoản';

  @override
  String get modelsAccountsDescription =>
      'Đăng nhập bằng ChatGPT để dùng mô hình Codex theo hạn mức của gói bạn có. Nếu có nhiều tài khoản, các yêu cầu được phân phối theo phương thức cân bằng tải bên dưới; khi một tài khoản hết hạn mức, hệ thống chuyển sang tài khoản tiếp theo.';

  @override
  String get modelsAccountsDescriptionAntigravity =>
      'Đăng nhập bằng Google để dùng các mô hình Antigravity (Gemini, Claude) theo hạn mức gói của bạn, trên bộ lõi tích hợp sẵn của BaoCode. Mỗi nhóm mô hình có hạn mức riêng; nếu tài khoản hết hạn mức của một nhóm, chỉ các mô hình thuộc nhóm đó mới chuyển sang tài khoản tiếp theo. Google có thể đình chỉ tài khoản nếu phát hiện dùng ngoài Antigravity: chỉ sử dụng tài khoản mà bạn chấp nhận rủi ro bị mất quyền truy cập.';

  @override
  String get modelsAccountsNone => 'Chưa có tài khoản';

  @override
  String modelsAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tài khoản',
      one: '1 tài khoản',
      zero: 'chưa có tài khoản',
    );
    return '$_temp0';
  }

  @override
  String get modelsAddAccount => 'Thêm tài khoản';

  @override
  String get modelsAddAccountDescription =>
      'Mở trang đăng nhập ChatGPT trong trình duyệt.';

  @override
  String get modelsAccountsImport => 'Nhập';

  @override
  String get modelsAccountsImportTitle => 'Nhập tài khoản';

  @override
  String get modelsAccountsImportFile => 'Chọn tệp…';

  @override
  String get modelsAccountsImportDescription =>
      'Nhập thông tin xác thực tài khoản dưới dạng JSON hoặc chọn tệp JSON.';

  @override
  String get modelsAccountsPaste => 'Nhập JSON…';

  @override
  String get modelsAccountsPastePlaceholder =>
      'Nhập hoặc dán thông tin xác thực JSON vào đây.';

  @override
  String get modelsAccountsImportConfirm =>
      'Nhập các thông tin xác thực ChatGPT này?';

  @override
  String get modelsAccountsImportConfirmDetail =>
      'BaoCode sẽ lưu thông tin xác thực an toàn mà không sửa tệp gốc hoặc tự làm mới token khi nhập. Việc làm mới sau này có thể thay đổi refresh token và buộc công cụ ban đầu phải đăng nhập lại. Chỉ nhập thông tin xác thực của tài khoản mà bạn được phép sử dụng.';

  @override
  String get modelsAccountsImportFailed =>
      'Không thể đọc hoặc nhập thông tin xác thực.';

  @override
  String modelsAccountsImportSummary(int count) {
    return 'Số tài khoản đã nhập: $count';
  }

  @override
  String modelsAccountsImportKept(int count) {
    return 'Đã tồn tại, giữ nguyên trạng thái đăng nhập: $count';
  }

  @override
  String modelsAccountsImportItemFailed(int index, String error) {
    return 'Mục $index: $error';
  }

  @override
  String get modelsAccountSigningIn => 'Đang chờ đăng nhập…';

  @override
  String get modelsAccountSigningInDetail =>
      'Hoàn tất đăng nhập trong trình duyệt. Nếu trang không tự mở, hãy sao chép liên kết rồi mở thủ công.';

  @override
  String get modelsAccountCopyLink => 'Sao chép liên kết';

  @override
  String modelsAccountSignInFailed(String error) {
    return 'Đăng nhập thất bại: $error';
  }

  @override
  String get modelsRefreshQuota => 'Làm mới tất cả hạn mức';

  @override
  String modelsAccountRefreshQuota(String name) {
    return 'Làm mới hạn mức của $name';
  }

  @override
  String get modelsAccountRemove => 'Xóa tài khoản';

  @override
  String modelsAccountRemoveConfirm(String name) {
    return 'Xóa “$name”?';
  }

  @override
  String get modelsAccountRemoveDetail =>
      'Thông tin đăng nhập của tài khoản này sẽ bị xóa khỏi máy.';

  @override
  String modelsAccountEnable(String name) {
    return 'Sử dụng $name';
  }

  @override
  String get modelsAccountDisabled => 'Đã tắt';

  @override
  String get modelsAccountLimited => 'Đã hết hạn mức';

  @override
  String get modelsAccountQuotaUnknown => 'Chưa xác định được hạn mức';

  @override
  String get modelsQuotaShortWindow => 'Chu kỳ ngắn';

  @override
  String get modelsQuotaLongWindow => 'Chu kỳ dài';

  @override
  String modelsQuotaLastUpdated(String time) {
    return 'Cập nhật lần cuối $time';
  }

  @override
  String get modelsQuotaWeek => 'Hằng tuần';

  @override
  String modelsQuotaHours(int count) {
    return '$count giờ';
  }

  @override
  String modelsQuotaDays(int count) {
    return '$count ngày';
  }

  @override
  String modelsQuotaUsed(int percent) {
    return 'Đã dùng $percent%';
  }

  @override
  String modelsQuotaRemaining(int percent) {
    return 'Còn $percent%';
  }

  @override
  String quotaBarWindowLeft(String window, int percent) {
    return '$window $percent% còn lại';
  }

  @override
  String quotaBarAvailable(int count, int total) {
    return '$count/$total có sẵn';
  }

  @override
  String quotaBarAllOut(String time) {
    return 'Tất cả tài khoản đã hết hạn ngạch · quay lại $time';
  }

  @override
  String quotaBarBackAt(String time) {
    return 'Hết hạn ngạch · quay lại $time';
  }

  @override
  String get quotaBarNone => 'Không thể sử dụng tài khoản';

  @override
  String get quotaBarThisChat => 'Cuộc trò chuyện này';

  @override
  String get quotaBarRefresh => 'Làm mới dữ liệu hạn ngạch';

  @override
  String modelsQuotaResetsIn(String time) {
    return 'đặt lại sau $time';
  }

  @override
  String modelsQuotaResetsAt(String time) {
    return 'đặt lại lúc $time';
  }

  @override
  String modelsQuotaCredits(String credits) {
    return 'Tín dụng: $credits';
  }

  @override
  String modelsDurationMinutes(int count) {
    return '$count phút';
  }

  @override
  String modelsDurationHours(int hours, int minutes) {
    return '$hours giờ $minutes phút';
  }

  @override
  String get modelsBalance => 'Cân bằng tải';

  @override
  String get modelsBalanceRoundRobin => 'Luân phiên';

  @override
  String get modelsBalanceRoundRobinDescription =>
      'Mỗi cuộc trò chuyện mới dùng tài khoản tiếp theo và tiếp tục dùng tài khoản đó (để giữ cache).';

  @override
  String get modelsBalanceFillFirst => 'Dùng hết từng tài khoản';

  @override
  String get modelsBalanceFillFirstDescription =>
      'Dùng tài khoản đầu tiên đến khi hết hạn mức rồi mới chuyển sang tài khoản tiếp theo.';

  @override
  String get modelsBalanceMostRemaining => 'Ưu tiên hạn mức còn nhiều nhất';

  @override
  String get modelsBalanceMostRemainingDescription =>
      'Mỗi cuộc trò chuyện mới dùng tài khoản còn nhiều hạn mức nhất.';

  @override
  String get modelsAccountPortBusy =>
      'Cổng 1455, nơi đăng nhập trở lại, được sử dụng bởi một chương trình khác (proxy trong Docker hoặc đăng nhập Codex CLI). Đăng nhập vào trình duyệt hoàn toàn giống nhau: trang kết thúc sẽ không tải được hoặc hiển thị nội dung khác. Sao chép địa chỉ đầy đủ của trang đó và dán nó vào bên dưới.';

  @override
  String get modelsAccountPortBusyAntigravity =>
      'Cổng 51121, cổng đăng nhập quay trở lại, được sử dụng bởi một chương trình khác (chính Anti Gravity hoặc đăng nhập proxy). Đăng nhập vào trình duyệt hoàn toàn giống nhau: trang kết thúc sẽ không tải được hoặc hiển thị nội dung khác. Sao chép địa chỉ đầy đủ của trang đó và dán nó vào bên dưới.';

  @override
  String get modelsAccountCallback => 'Địa chỉ sau khi đăng nhập';

  @override
  String get modelsAccountCallbackDetail =>
      'Nếu trình duyệt không tự quay lại, hãy dán địa chỉ trang cuối cùng tại đây.';

  @override
  String get modelsProtocolAnthropic => 'Tương thích Anthropic';

  @override
  String get modelsConnection => 'Kết nối';

  @override
  String get modelsName => 'Tên';

  @override
  String get modelsIcon => 'Biểu tượng';

  @override
  String get modelsIconDescription =>
      'Đưa các mô hình của nó vào bộ chọn mô hình: logo của nhà sản xuất, biểu tượng của trang web hoặc hình ảnh của riêng bạn. Không được đặt, logo của nhà sản xuất có tên URL cơ sở.';

  @override
  String get modelsIconChange => 'Đổi biểu tượng';

  @override
  String get modelsProtocol => 'Giao thức';

  @override
  String get modelsProtocolDescription =>
      'API của OpenAI đi qua proxy cục bộ, dịch thuật các yêu cầu và câu trả lời của Claude Code.';

  @override
  String get modelsBaseUrl => 'URL gốc';

  @override
  String get modelsBaseUrlAnthropicHint =>
      'Không có /v1, vì ANTHOPIC_BASE_URL: Claude Code thêm /v1/messages.';

  @override
  String get modelsBaseUrlOpenAIHint =>
      'Như các tài liệu ngược dòng nó; không có phiên bản trong đường dẫn của nó (…/v1), /v1 sẽ được thêm vào.';

  @override
  String get modelsCustomUrls => 'URL tùy chỉnh';

  @override
  String get modelsCustomUrlsDescription =>
      'Nơi các mô hình được liệt kê và các cuộc hội thoại diễn ra được tạo từ URL cơ sở. Khi thượng nguồn có ở nơi khác thì đưa đầy đủ ở đây.';

  @override
  String get modelsModelsUrl => 'URL danh sách mô hình';

  @override
  String get modelsModelsUrlDescription =>
      'Kiểm tra kết nối và tìm nạp các mô hình NHẬN nó. Trống, màu xám (từ URL cơ sở) sẽ được sử dụng.';

  @override
  String get modelsEndpointUrl => 'URL endpoint';

  @override
  String get modelsEndpointUrlDescription =>
      'Mọi cuộc trò chuyện đều được ĐĂNG lên đó. Trống, màu xám (từ URL cơ sở) sẽ được sử dụng. Mô hình của loại điểm cuối khác vẫn đi theo URL cơ sở.';

  @override
  String get modelsEndpointUrlAnthropicDescription =>
      'Mọi cuộc trò chuyện đều được ĐĂNG lên đó, Claude Code thông qua proxy địa phương. Trống, màu xám (từ URL cơ sở) sẽ được sử dụng. Mô hình của loại điểm cuối khác vẫn đi theo URL cơ sở.';

  @override
  String get modelsApiKey => 'Khóa API';

  @override
  String get modelsApiKeyDescription =>
      'Được lưu trong kho khóa hệ thống, không phải trong settings.json.';

  @override
  String get modelsApiKeyShow => 'Hiện khóa';

  @override
  String get modelsApiKeyHide => 'Ẩn khóa';

  @override
  String modelsApiKeyError(String error) {
    return 'Không thể lưu khóa: $error';
  }

  @override
  String get modelsTest => 'Kiểm tra kết nối';

  @override
  String get modelsTesting => 'Đang kết nối…';

  @override
  String modelsTestOk(int count) {
    return 'Đã kết nối: nguồn mô hình cung cấp $count mô hình.';
  }

  @override
  String modelsTestFailed(String error) {
    return 'Không thể kết nối: $error';
  }

  @override
  String get modelsModelsGroup => 'Mô hình';

  @override
  String get modelsModelsDescription =>
      'Những mô hình được đánh dấu sẽ xuất hiện trong bộ chọn mô hình.';

  @override
  String get modelsFetch => 'Lấy từ nguồn mô hình…';

  @override
  String get modelsAddModel => 'Thêm mô hình…';

  @override
  String get modelsSearch => 'Tìm mô hình';

  @override
  String get modelsNone =>
      'Chưa có mô hình: lấy từ nguồn mô hình hoặc tự thêm.';

  @override
  String get modelsNoMatch => 'Không tìm thấy mô hình phù hợp.';

  @override
  String get modelsMissing => 'Không còn ở upstream';

  @override
  String get modelsMissingTooltip =>
      'Nguồn mô hình không còn liệt kê mô hình này; BaoCode vẫn giữ lại cho đến khi bạn xóa.';

  @override
  String modelsRemoveMissing(int count) {
    return 'Xóa mô hình không còn ($count)';
  }

  @override
  String modelsRemoveMissingConfirm(int count) {
    return 'Xóa $count mô hình không còn được nguồn liệt kê?';
  }

  @override
  String get modelsCustom => 'Thủ công';

  @override
  String modelsShowAll(int count) {
    return 'Hiện tất cả ($count)';
  }

  @override
  String get modelsShowChecked => 'Chỉ hiện mục đã chọn';

  @override
  String get modelsNoneChecked =>
      'Chưa chọn mô hình nào: hiện tất cả để lựa chọn.';

  @override
  String get modelsEdit => 'Chỉnh sửa…';

  @override
  String get modelsDuplicate => 'Nhân bản…';

  @override
  String get modelsRemove => 'Xóa';

  @override
  String get modelsMore => 'Thao tác khác';

  @override
  String get modelsTestModel => 'Kiểm tra';

  @override
  String get modelsTestModels => 'Kiểm tra tất cả';

  @override
  String get modelsTestModelFailed => 'Thất bại';

  @override
  String modelsTestFirstText(String seconds) {
    return 'Token đầu tiên: $seconds giây';
  }

  @override
  String modelsTestTotal(String seconds) {
    return 'Tổng thời gian: $seconds giây';
  }

  @override
  String modelsEnableModel(String name) {
    return 'Hiển thị $name';
  }

  @override
  String get modelsRoles => 'Vai trò';

  @override
  String get modelsRolesDescription =>
      'Mô hình Claude Code sử dụng cho từng phần công việc. Nếu không đặt, mô hình đang chọn sẽ được dùng. Các vai trò ngoài mô hình chính có thể dùng nguồn mô hình khác; proxy cục bộ của BaoCode sẽ chuyển tiếp yêu cầu đến đúng nguồn.';

  @override
  String get modelsRoleUnset => 'Chưa thiết lập';

  @override
  String get modelsRoleMain => 'Mô hình chính';

  @override
  String get modelsRoleMainDescription =>
      'Được dùng khi mô hình đã chọn cho phiên ở nguồn này không còn khả dụng.';

  @override
  String get modelsRoleOpus => 'Nhóm Opus';

  @override
  String get modelsRoleOpusDescription =>
      'ANTHOPIC_DEFAULT_OPUS_MODEL: “opus” nghĩa là gì, như trong chế độ Plan.';

  @override
  String get modelsRoleSonnet => 'Nhóm Sonnet';

  @override
  String get modelsRoleSonnetDescription =>
      'ANTHOPIC_DEFAULT_SONNET_MODEL: “sonnet” nghĩa là gì.';

  @override
  String get modelsRoleHaiku => 'Nhóm Haiku';

  @override
  String get modelsRoleHaikuDescription =>
      'ANTHOPIC_DEFAULT_HAIKU_MODEL: Công việc nền tảng của Claude Code và chức danh của các đặc vụ.';

  @override
  String get modelsRoleHaikuWarning =>
      'Không được đặt, công việc nền sẽ chạy trên mô hình đã chọn, có thể chậm hơn và tốn nhiều chi phí hơn. Chọn một mô hình nhỏ, nhanh.';

  @override
  String get modelsRoleSubagent => 'Subagent';

  @override
  String get modelsRoleSubagentDescription =>
      'CLAUDE_CODE_SUBAGENT_MODEL: mô hình mà mọi tác nhân phụ chạy trên đó, Khám phá và Kế hoạch tích hợp cũng như những mô hình được xác định là kế thừa, dựa trên định nghĩa của nó hoặc tên cuộc gọi của tác nhân.';

  @override
  String get modelsRoleMissing =>
      'Mô hình này không còn thuộc nguồn mô hình của nó; các yêu cầu gửi đến sẽ thất bại.';

  @override
  String get modelsAdvanced => 'Trình độ cao';

  @override
  String get modelsAuth => 'Xác thực';

  @override
  String get modelsAuthDescription =>
      'Chìa khóa được gửi như thế nào. Tự động: x-api-key tới api.anthropic.com, mã thông báo mang ở nơi khác.';

  @override
  String get modelsAuthAuto => 'Tự động';

  @override
  String get modelsNonessential =>
      'Vô hiệu hóa lưu lượng truy cập không cần thiết';

  @override
  String get modelsNonessentialDescription =>
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: không có phép đo từ xa, báo cáo lỗi hoặc kiểm tra cập nhật, những điều mà các thượng nguồn khác ngoài Anthropic không trả lời.';

  @override
  String get modelsPreserveThinking => 'Gửi lại lý do';

  @override
  String get modelsPreserveThinkingDescription =>
      'Phát lại lý do của mô hình (reasoning_content) trong các yêu cầu sau này, như DeepSeek và những người khác mong muốn.';

  @override
  String get modelsPromptCacheKey => 'Khóa bộ đệm nhắc nhở';

  @override
  String get modelsPromptCacheKeyDescription =>
      'Gửi nhắc_cache_key riêng của mỗi cuộc trò chuyện, do đó, luồng lên (hoặc một chuyển tiếp ở phía trước một số cuộc trò chuyện) sẽ định tuyến các yêu cầu của nó đến nơi lưu trữ những yêu cầu trước đó. Tắt cho dòng ngược dòng từ chối trường.';

  @override
  String get modelsEnv => 'Môi trường bổ sung';

  @override
  String get modelsEnvDescription =>
      'Một KEY=GIÁ TRỊ một dòng, được cấp cho Claude Code sau các cài đặt ở trên.';

  @override
  String get modelsHeaders => 'Tiêu đề tùy chỉnh';

  @override
  String get modelsHeadersDescription =>
      'Một tên: Đánh giá một dòng, được gửi theo mọi yêu cầu tới thượng nguồn này. Các giá trị có thể sử dụng biến CLAUDE_SESSION_ID (phiên của cuộc hội thoại này) và ANTHOPIC_MODEL (mô hình được yêu cầu), mỗi giá trị nằm giữa hai dấu ngoặc nhọn; qua giao thức Anthropic trực tiếp, cả hai đều hoạt động như được viết, vì vậy chỉ các giá trị cố định mới hoạt động ở đó. Tiêu đề xác thực (Ủy quyền, x-api-key) bị bỏ qua ở đây: khóa được đặt ở trên.';

  @override
  String get modelsDuplicateProvider => 'Sao chép ngược dòng';

  @override
  String get modelsDuplicateProviderDescription =>
      'Một bản sao của phiên bản ngược dòng này, cùng với các kiểu máy, cài đặt và khóa của nó.';

  @override
  String modelsDuplicateName(String name) {
    return '$name Sao chép';
  }

  @override
  String get modelsDelete => 'Xóa thượng nguồn';

  @override
  String get modelsDeleteDescription =>
      'Loại bỏ nó và chìa khóa của nó khỏi móc khóa.';

  @override
  String modelsDeleteConfirm(String name) {
    return 'Xóa “$name”?';
  }

  @override
  String get modelsDeleteDetail =>
      'Các phiên trên mô hình của nó sẽ quay trở lại phiên của Claude Code khi chúng bắt đầu vào lần tiếp theo.';

  @override
  String modelsFetchTitle(String name) {
    return 'Kiểu mẫu của $name';
  }

  @override
  String get modelsFetchLoading => 'Hỏi ngược dòng…';

  @override
  String modelsFetchFailed(String error) {
    return 'Không thể tìm nạp các mô hình: $error';
  }

  @override
  String get modelsFetchEmpty => 'Ngược dòng liệt kê không có mô hình.';

  @override
  String get modelsFetchSelectAll => 'Chọn tất cả';

  @override
  String get modelsFetchSelectNone => 'Chọn Không có';

  @override
  String modelsFetchSelected(int count, int total) {
    return 'Đã kiểm tra $count của $total';
  }

  @override
  String get modelsFetchNew => 'Mới';

  @override
  String get modelsFetchApply => 'Áp dụng';

  @override
  String get modelsRetry => 'Thử lại';

  @override
  String get modelsAddTitle => 'Thêm mô hình';

  @override
  String get modelsEditTitle => 'Chỉnh sửa mô hình';

  @override
  String get modelsModelId => 'Mã mẫu';

  @override
  String get modelsModelIdHint => 'Như tên thượng nguồn của nó, ví dụ: gpt-5';

  @override
  String get modelsModelIdTaken => 'Thượng nguồn này đã có mô hình đó rồi.';

  @override
  String get modelsModelLabel => 'Tên hiển thị';

  @override
  String get modelsModelLabelHint => 'Không bắt buộc';

  @override
  String get modelsContextWindow => 'Bối cảnh mặc định';

  @override
  String get modelsContextWindowHint =>
      'Mã thông báo, ví dụ: 128K; 200K khi trống';

  @override
  String get modelsContextInvalid => 'Một số mã thông báo, ví dụ: 200K.';

  @override
  String get modelsEffortOptions => 'nỗ lực tư duy';

  @override
  String get modelsEffortOptionsDescription =>
      'Được cung cấp trong bộ chọn mô hình; Phương tiện được chọn trừ khi phương tiện khác được chọn.';

  @override
  String get modelsEffortAddHint => 'ví dụ. tối thiểu';

  @override
  String get modelsEffortInvalid => 'Chỉ chữ cái, chữ số và dấu gạch ngang.';

  @override
  String get modelsContextOptions => 'Độ dài ngữ cảnh';

  @override
  String get modelsContextOptionsDescription =>
      'Được cung cấp trong bộ chọn mô hình; bối cảnh mặc định nằm trong số đó.';

  @override
  String get modelsContextAddHint => 'ví dụ. 128K';

  @override
  String get modelsOptionAdd => 'Thêm vào';

  @override
  String modelsOptionRemove(String name) {
    return 'Xóa $name';
  }

  @override
  String get modelsOptionsReset => 'Đặt lại về mặc định';

  @override
  String get modelsOptionsNone => 'Không có: không được cung cấp.';

  @override
  String get modelsNoImages => 'Không chụp ảnh';

  @override
  String get modelsKind => 'Dùng cho';

  @override
  String get modelsKindChat => 'Cuộc trò chuyện';

  @override
  String get modelsKindImage => 'Tạo hình ảnh (API hình ảnh)';

  @override
  String get modelsKindImageChat => 'Tạo hình ảnh (trong một cuộc trò chuyện)';

  @override
  String get modelsKindDescription =>
      'Các mô hình hình ảnh không được cung cấp trong bộ chọn mô hình: các nhân viên tạo hình ảnh với chúng thông qua công cụ generate_image.';

  @override
  String get modelsEndpoint => 'Điểm cuối';

  @override
  String modelsEndpointUpstream(String protocol) {
    return 'Là thượng nguồn ($protocol)';
  }

  @override
  String get modelsEndpointDescription =>
      'Các yêu cầu của mô hình này sẽ chuyển đến API nào, tại URL cơ sở của thượng nguồn và với khóa của nó: trên một rơle phục vụ một số mô hình, các mô hình Claude của nó tại Anthropic và GPT của nó tại Phản hồi.';

  @override
  String get modelsModelEndpointUrlDescription =>
      'Nơi đầy đủ các yêu cầu của mô hình này. Ngoài loại điểm cuối: cho biết cách thực hiện yêu cầu, đây chỉ là nơi yêu cầu được thực hiện. Trống, cái màu xám được sử dụng.';

  @override
  String get modelsImageBadge => 'Hình ảnh';

  @override
  String get modelsImage => 'Mô hình hình ảnh';

  @override
  String get modelsImageDescription =>
      'Những tác nhân nào tạo ra các bức ảnh bằng (công cụ generate_image), trừ khi bạn yêu cầu họ làm một tác vụ khác; hỏi mỗi lần, bạn chọn nó trong cuộc trò chuyện. Bật mô hình hình ảnh trong danh sách ngược dòng.';

  @override
  String get modelsImageFirst => 'Hỏi mỗi lần';

  @override
  String get modelsImageNone => 'Không có gì được bật';

  @override
  String get modelsSave => 'Cứu';

  @override
  String get modelsManage => 'Quản lý mô hình…';

  @override
  String modelsFallbackHint(String picked, String fallback) {
    return '$picked đã gắn cờ một tin nhắn nên Claude Code sẽ trả lời trên $fallback. Chuyển trở lại từ menu.';
  }

  @override
  String modelsFallbackSwitchBack(String name) {
    return 'Chuyển về $name';
  }

  @override
  String get modelsAuxiliary => 'Mô hình phụ trợ';

  @override
  String get modelsAuxiliaryDescription =>
      'Được sử dụng cho công việc phụ trợ, chẳng hạn như tạo tiêu đề cuộc trò chuyện và thông báo commit. Tự động: mô hình của phiên (đối với thông báo commit, mặc định của phiên mới); thượng nguồn theo cấp Haiku của nó.';

  @override
  String get modelsAuxiliaryAuto => 'Tự động';

  @override
  String get modelsAuxiliaryBuiltin =>
      'Claude Code Haiku (thiết lập của máy này)';

  @override
  String get settingsSectionUpdates => 'Cập nhật';

  @override
  String get updatesSettingsTitle => 'Cập nhật';

  @override
  String get updatesSettingsDescription =>
      'BaoCode kiểm tra phiên bản mới trên baocode.dev.';

  @override
  String get updateCurrentVersion => 'Phiên bản hiện tại';

  @override
  String updateLastChecked(String time) {
    return 'Kiểm tra lần cuối $time';
  }

  @override
  String get updateNeverChecked => 'Chưa kiểm tra';

  @override
  String get updateCheckNow => 'Kiểm tra cập nhật';

  @override
  String get updateChecking => 'Đang kiểm tra cập nhật…';

  @override
  String get updateUpToDate => 'BaoCode đã ở phiên bản mới nhất.';

  @override
  String updateAvailable(String version) {
    return 'Đã có BaoCode $version.';
  }

  @override
  String updateReady(String version) {
    return 'Đã tải xuống BaoCode $version. Khởi động lại để cập nhật.';
  }

  @override
  String updateDownloading(String version) {
    return 'Đang tải BaoCode $version…';
  }

  @override
  String updateDownloadingProgress(String version, int percent) {
    return 'Đang tải BaoCode $version… $percent%';
  }

  @override
  String updateMandatory(String version) {
    return 'Phiên bản BaoCode này không còn được hỗ trợ. Hãy cập nhật lên $version để tiếp tục sử dụng.';
  }

  @override
  String get updateRestartNow => 'Khởi động lại để cập nhật';

  @override
  String get updateLater => 'Để sau';

  @override
  String get updateSkip => 'Bỏ qua phiên bản này';

  @override
  String get updateSkippedNote =>
      'Bạn đã bỏ qua phiên bản này nên sẽ không được gợi ý lại, nhưng vẫn có thể cài tại đây.';

  @override
  String updateFailed(String error) {
    return 'Không thể cập nhật BaoCode: $error';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Không thể kiểm tra bản cập nhật: $error';
  }

  @override
  String get updateDisabled => 'Đã tắt cập nhật (update.mode là \"none\").';

  @override
  String get updateUnsupported =>
      'Bản dựng BaoCode này không hỗ trợ tự cập nhật.';

  @override
  String updateManual(String reason) {
    return 'Không thể tự cập nhật BaoCode ở đây ($reason). Hãy tải phiên bản mới từ baocode.dev.';
  }

  @override
  String get updateOpenDownloadPage => 'Mở trang tải xuống';

  @override
  String updateUnfinished(String version, String current) {
    return 'Chưa cài đặt BaoCode $version; phiên bản hiện tại vẫn là $current. Hãy thử lại tại Cài đặt > Cập nhật hoặc tải từ baocode.dev.';
  }

  @override
  String get updateShowLog => 'Xem nhật ký cài đặt';

  @override
  String get updateReleaseNotes => 'Ghi chú phát hành';

  @override
  String updateReleaseNotesFor(String version) {
    return 'Điểm mới trong $version';
  }

  @override
  String get updateMode => 'Chế độ cập nhật';

  @override
  String get updateModeDescription =>
      'Thiết lập BaoCode có tự kiểm tra phiên bản mới hay không (update.mode).';

  @override
  String updateModeLabel(String name) {
    return 'Chế độ cập nhật: $name';
  }

  @override
  String get updateModeDefault => 'Tự động';

  @override
  String get updateModeManual => 'Thủ công';

  @override
  String get updateModeNone => 'Tắt';

  @override
  String get diagnosticsTitle => 'Nhật ký chẩn đoán';

  @override
  String get diagnosticsDescription =>
      'Gửi nhật ký lỗi của BaoCode cũng như các báo cáo về sự cố và treo mà hệ thống lưu giữ cho các nhà phát triển để giúp tìm ra vấn đề. Không có gì được gửi cho đến khi bạn tải lên.';

  @override
  String get diagnosticsUpload => 'Tải lên…';

  @override
  String get diagnosticsDialogTitle => 'Tải lên nhật ký chẩn đoán';

  @override
  String get diagnosticsNotePlaceholder =>
      'Lưu ý (tùy chọn): điều gì đã xảy ra và cách khắc phục sự cố đó';

  @override
  String diagnosticsFiles(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tệp nhật ký $count',
      one: '1 tệp nhật ký',
    );
    return '$_temp0 ($size) sẽ được tải lên.';
  }

  @override
  String get diagnosticsNoFiles =>
      'Chưa có nhật ký nào: chỉ có ghi chú và chi tiết phiên bản được tải lên.';

  @override
  String diagnosticsDumps(int count, String size) {
    return 'Bao gồm các kết xuất bộ nhớ bị treo ($count, $size)';
  }

  @override
  String get diagnosticsDumpsDetail =>
      'Kết xuất bộ nhớ có thể chứa các phần của tệp và đường dẫn đang mở. Hơn 10 MB, chỉ bao gồm những cái mới nhất.';

  @override
  String get diagnosticsPrivacy =>
      'Thư mục nhà của bạn được viết là ~. Phiên bản, hệ thống và ngôn ngữ của ứng dụng được gửi cùng với nhật ký chứ không phải ID cài đặt của thống kê sử dụng. Giữ trên máy chủ trong 90 ngày.';

  @override
  String get diagnosticsSend => 'Tải lên';

  @override
  String get diagnosticsUploading => 'Đang tải lên…';

  @override
  String get diagnosticsUploaded => 'Đã tải lên. ID báo cáo:';

  @override
  String get diagnosticsUploadedDetail =>
      'Đưa ID này cho các nhà phát triển của BaoCode để họ có thể tìm thấy các nhật ký này.';

  @override
  String diagnosticsOmittedDumps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các kết xuất bộ nhớ cũ hơn của $count là',
      one: '1 kết xuất bộ nhớ cũ hơn là',
    );
    return '$_temp0 còn sót lại: trên 10 MB.';
  }

  @override
  String get diagnosticsCopyId => 'Sao chép giấy tờ tùy thân';

  @override
  String get diagnosticsCopied => 'Đã sao chép';

  @override
  String get diagnosticsRetry => 'Thử lại';

  @override
  String get diagnosticsTooLarge =>
      'Nhật ký có dung lượng trên 10 MB và không thể tải lên.';

  @override
  String get diagnosticsRateLimited =>
      'Quá nhiều tải lên ngay bây giờ. Hãy thử lại sau.';

  @override
  String diagnosticsRefused(int status) {
    return 'Máy chủ không chấp nhận nhật ký (HTTP $status).';
  }

  @override
  String diagnosticsServerError(String status) {
    return 'Máy chủ không thể lấy nhật ký ($status). Hãy thử lại sau.';
  }

  @override
  String diagnosticsFailed(String error) {
    return 'Không thể tải lên: $error';
  }

  @override
  String get cmdCheckForUpdates => 'Kiểm tra cập nhật...';

  @override
  String get settingsSectionAppearance => 'Giao diện';

  @override
  String get settingsAppearanceKeywords => 'chủ đề màu sắc màu tối ánh sáng';

  @override
  String get appearanceSettingsTitle => 'Giao diện';

  @override
  String get appearanceSettingsColorTheme => 'Chủ đề màu sắc';

  @override
  String get appearanceSettingsColorThemeDescription =>
      'Màu sắc của trò chuyện, IDE và Terminal.';

  @override
  String appearanceSettingsColorThemeDescriptionWithKey(String key) {
    return 'Màu sắc của trò chuyện, IDE và Terminal. Trong Tùy chọn: Chủ đề màu sắc ($key), di chuyển qua từng chủ đề để xem trước.';
  }

  @override
  String appearanceSettingsColorThemeLabel(String theme) {
    return 'Chủ đề màu sắc: $theme';
  }

  @override
  String get appearanceSettingsChatWidth => 'Độ rộng cuộc trò chuyện';

  @override
  String get appearanceSettingsChatWidthDescription =>
      'Độ rộng của cuộc trò chuyện, hộp nhập tin nhắn và trang cài đặt trong cửa sổ rộng.';

  @override
  String get appearanceSettingsChatWidthDefault => 'Mặc định';

  @override
  String get appearanceSettingsChatWidthFull => 'Toàn chiều rộng';

  @override
  String appearanceSettingsChatWidthLabel(String width) {
    return 'Độ rộng cuộc trò chuyện: $width';
  }

  @override
  String get appearanceSettingsAgentLoader => 'Agent đang làm việc';

  @override
  String get appearanceSettingsAgentLoaderDescription =>
      'Hiển thị cạnh agent trong thanh bên, tab và tìm kiếm khi agent đang làm việc hoặc tác vụ nền do agent khởi chạy vẫn còn chạy.';

  @override
  String get appearanceSettingsSubagentLoader => 'Subagent đang chạy';

  @override
  String get appearanceSettingsSubagentLoaderDescription =>
      'Hiển thị trên thẻ subagent trong cuộc trò chuyện và dòng phía trên ô nhập khi subagent đang chạy.';

  @override
  String appearanceSettingsLoaderLabel(String what, String style) {
    return '$what: $style';
  }

  @override
  String get appearanceSettingsLoaderSpeed => 'Tốc độ';

  @override
  String appearanceSettingsLoaderSpeedLabel(String what, String speed) {
    return 'Tốc độ $what: $speed';
  }

  @override
  String get loaderStyleSnake => 'Rắn';

  @override
  String get loaderStyleStack => 'Ngăn xếp và dọn dẹp';

  @override
  String get loaderStyleTwinkle => 'lấp lánh';

  @override
  String get loaderStyleFill => 'Điền và làm trống';

  @override
  String get loaderStylePulse => 'Xung vuông';

  @override
  String get loaderStyleRipple => 'gợn sóng chéo';

  @override
  String get loaderStyleSweep => 'Quét chéo';

  @override
  String get loaderStyleRain => 'mưa pixel';

  @override
  String get loaderStyleChecker => 'Bàn cờ';

  @override
  String get loaderStyleSpinner => 'Máy quay';

  @override
  String get loaderStyleTwinSpinner => 'Máy quay đôi';

  @override
  String get loaderStyleCorners => 'Góc';

  @override
  String get loaderStyleDots => 'chấm nảy';

  @override
  String get loaderStyleEqualizer => 'Bộ chỉnh âm';

  @override
  String get loaderStyleBar => 'Thanh tiến trình';

  @override
  String get loaderStyleScan => 'Dòng quét';

  @override
  String get loaderStyleHourglass => 'Đồng hồ cát';

  @override
  String get loaderStyleBreathe => 'Thở';

  @override
  String get loaderStyleCircle => 'Nhẫn (cổ điển)';

  @override
  String get appearanceSettingsUserMessageStyle => 'Tin nhắn của bạn';

  @override
  String get appearanceSettingsUserMessageStyleDescription =>
      'Cách hiển thị tin nhắn bạn gửi: toàn chiều rộng và giữ tin nhắn đang đọc ở đầu khi cuộn, hoặc dạng bong bóng ở bên phải, cuộn đi cùng nội dung.';

  @override
  String get appearanceSettingsUserMessageStyleSticky =>
      'Toàn chiều rộng, ghim ở đầu';

  @override
  String get appearanceSettingsUserMessageStyleBubble => 'Bong bóng trò chuyện';

  @override
  String appearanceSettingsUserMessageStyleLabel(String style) {
    return 'Tin nhắn của bạn: $style';
  }

  @override
  String get appearanceSettingsEditDetail => 'Chỉnh sửa tệp';

  @override
  String get appearanceSettingsEditDetailDescription =>
      'Cách hiển thị các thay đổi tệp do agent thực hiện: thẻ chi tiết luôn mở hoặc dòng tóm tắt có thể mở rộng.';

  @override
  String get appearanceSettingsEditDetailCard => 'Thẻ hiển thị thay đổi';

  @override
  String get appearanceSettingsEditDetailCompact => 'Thu gọn';

  @override
  String appearanceSettingsEditDetailLabel(String detail) {
    return 'Chỉnh sửa tệp: $detail';
  }

  @override
  String get appearanceSettingsReplyScroll => 'Khi nhận phản hồi';

  @override
  String get appearanceSettingsReplyScrollDescription =>
      'Vị trí cuộn trong cuộc trò chuyện khi phản hồi đang được tạo: theo dõi nội dung mới ở cuối hoặc giữ tại đầu phản hồi để đọc. Nếu cuộn xuống cuối, chế độ theo dõi sẽ hoạt động lại.';

  @override
  String get appearanceSettingsReplyScrollFollow => 'Tự động';

  @override
  String get appearanceSettingsReplyScrollStart => 'Giữ ở đầu phản hồi';

  @override
  String appearanceSettingsReplyScrollLabel(String choice) {
    return 'Khi nhận phản hồi: $choice';
  }

  @override
  String get appearanceSettingsMinimap => 'Minimap cuộc trò chuyện';

  @override
  String get appearanceSettingsMinimapDescription =>
      'Bản đồ thu nhỏ của toàn bộ cuộc trò chuyện bên cạnh nội dung, hiển thị vị trí đọc hiện tại khi cuộn; nhấp hoặc kéo để điều hướng. Minimap thay cho thanh cuộn và ẩn khi cửa sổ quá hẹp. Khi tắt, thanh cuộn sẽ xuất hiện.';

  @override
  String get appearanceSettingsWindowBlur => 'Hiệu ứng làm mờ cửa sổ';

  @override
  String get appearanceSettingsWindowBlurDescription =>
      'Hiệu ứng làm mờ hệ thống dưới cửa sổ (material của thanh bên trên macOS, acrylic trên Windows 11), giúp nhìn thấy nội dung phía sau qua thanh bên và cuộc trò chuyện. Khi tắt, cửa sổ không trong suốt.';

  @override
  String get appearanceSettingsSidebarTimes => 'Thời gian trong thanh bên';

  @override
  String get appearanceSettingsSidebarTimesDescription =>
      'Hiển thị thời điểm hoạt động gần nhất của mỗi agent trong thanh bên. Khi tắt, thông tin chỉ xuất hiện lúc di chuột.';

  @override
  String get appearanceSettingsMinimapGlass => 'Độ mờ kính';

  @override
  String get appearanceSettingsMinimapGlassDescription =>
      'Độ rõ của hiệu ứng kính lỏng trên vị trí hiện tại trong minimap: màu phủ, bóng và ánh sáng. Ở 0%, chỉ vùng đang xem nổi bật.';

  @override
  String appearanceSettingsMinimapGlassLabel(String opacity) {
    return 'Độ mờ kính minimap: $opacity';
  }

  @override
  String get appearanceSettingsMinimapElasticity => 'Độ đàn hồi kính';

  @override
  String get appearanceSettingsMinimapElasticityDescription =>
      'Mức độ co giãn của hiệu ứng kính lỏng khi theo dõi thao tác cuộn và trở về trạng thái ban đầu khi dừng.';

  @override
  String appearanceSettingsMinimapElasticityLabel(String level) {
    return 'Độ đàn hồi kính minimap: $level';
  }

  @override
  String get minimapElasticityOff => 'Tắt';

  @override
  String get minimapElasticitySubtle => 'tinh tế';

  @override
  String get minimapElasticityMedium => 'Trung bình';

  @override
  String get minimapElasticityBouncy => 'nảy';

  @override
  String get appearanceSettingsMinimapSide => 'Vị trí minimap';

  @override
  String get appearanceSettingsMinimapSideDescription =>
      'Chọn phía hiển thị minimap cạnh cuộc trò chuyện. Ở bên phải, minimap thay thanh cuộn bên dưới các nút của bảng bên.';

  @override
  String appearanceSettingsMinimapSideLabel(String side) {
    return 'Vị trí minimap: $side';
  }

  @override
  String get minimapSideLeft => 'Bên trái';

  @override
  String get minimapSideRight => 'Phải';

  @override
  String get appearanceSettingsCodeFont => 'Phông chữ mã nguồn';

  @override
  String get appearanceSettingsCodeFontDescription =>
      'Phông chữ hiển thị mã trong trình chỉnh sửa, Terminal, trò chuyện và phần xem trước. Nhập tên phông theo thứ tự, phân tách bằng dấu phẩy hoặc chọn cấu hình có sẵn.';

  @override
  String get appearanceSettingsCodeFontDefault => 'Mặc định';

  @override
  String get appearanceSettingsCodeFontField => 'Các họ phông chữ';

  @override
  String appearanceSettingsCodeFontLabel(String font) {
    return 'Phông chữ mã nguồn: $font';
  }

  @override
  String get appearanceSettingsCodeSize => 'Kích thước chữ mã nguồn';

  @override
  String get appearanceSettingsCodeSizeDescription =>
      'Kích thước chữ mã trong trình chỉnh sửa IDE, danh sách tệp và thay đổi của bảng bên ở tỷ lệ giao diện 100%. Phóng to giao diện sẽ thay đổi kích thước tương ứng. Mã trong trò chuyện theo cỡ giao diện, còn Terminal có cỡ riêng.';

  @override
  String appearanceSettingsCodeSizeLabel(String size) {
    return 'Kích thước chữ mã nguồn: $size';
  }

  @override
  String get appearanceSettingsLigatures => 'Ghép ký tự phông chữ';

  @override
  String get appearanceSettingsLigaturesDescription =>
      'Hiển thị các chuỗi như => và != thành một ký tự ghép nếu phông hỗ trợ. Không áp dụng cho Terminal.';

  @override
  String get appearanceSettingsWordWrap => 'Tự ngắt dòng';

  @override
  String get appearanceSettingsWordWrapDescription =>
      'Tự ngắt dòng dài theo độ rộng trình chỉnh sửa. Có thể thay đổi bằng menu ngữ cảnh hoặc Command Palette (Toggle Word Wrap). Không áp dụng cho tệp dài hơn 5.000 dòng.';

  @override
  String get appearanceSettingsCodeMinimap => 'Minimap mã nguồn';

  @override
  String get appearanceSettingsCodeMinimapDescription =>
      'Bản đồ thu nhỏ của tệp ở bên phải trình chỉnh sửa mã. Ẩn khi khung quá hẹp. Có thể bật/tắt trong menu ngữ cảnh tab hoặc Command Palette (Toggle Minimap).';

  @override
  String get appearanceSettingsUiScale => 'Kích thước giao diện';

  @override
  String get appearanceSettingsUiScaleDescription =>
      'Phóng to toàn bộ giao diện (văn bản, biểu tượng và khoảng cách) cùng mã nguồn; chữ Terminal cũng phóng theo nếu đang đặt theo kích thước giao diện. Chữ trong trình chỉnh sửa dựa trên cỡ chữ mã nguồn.';

  @override
  String appearanceSettingsUiScaleLabel(String percent) {
    return 'Kích thước giao diện: $percent%';
  }

  @override
  String get appearanceSettingsTerminalSize => 'Cỡ chữ Terminal';

  @override
  String get appearanceSettingsTerminalSizeDescription =>
      'Kích thước chữ trong Terminal. Mặc định theo kích thước giao diện, nhưng có thể đặt riêng.';

  @override
  String get appearanceSettingsTerminalSizeFollow =>
      'Theo kích thước giao diện';

  @override
  String get appearanceSettingsTerminalSizeCustom => 'Tùy chỉnh';

  @override
  String get appearanceSettingsTerminalSizeValue => 'Kích thước tùy chỉnh';

  @override
  String appearanceSettingsTerminalSizeLabel(String size) {
    return 'Cỡ chữ Terminal: $size';
  }

  @override
  String get generalSettingsContextMenuFinder => 'Menu ngữ cảnh Finder';

  @override
  String get generalSettingsContextMenuExplorer =>
      'Menu ngữ cảnh File Explorer';

  @override
  String get generalSettingsContextMenuDescription =>
      'Thêm “Mở bằng BaoCode” (agent mới) và “Mở bằng Fast IDE” (cửa sổ IDE mới) vào menu ngữ cảnh của tệp, thư mục và vùng trống trong thư mục.';

  @override
  String get generalSettingsContextMenuMacNote =>
      'Cài đặt của Finder nằm trong phần tiện ích mở rộng ở Cài đặt hệ thống, nơi bạn cũng có thể bật hoặc tắt tiện ích BaoCode.';

  @override
  String get generalSettingsContextMenuOn => 'Bật';

  @override
  String get generalSettingsContextMenuOff => 'Tắt';

  @override
  String get generalSettingsContextMenuUnsupported =>
      'Bản dựng này không có tiện ích Finder.';

  @override
  String get generalSettingsContextMenuTurnOn => 'Bật';

  @override
  String get generalSettingsContextMenuTurnOff => 'Tắt';

  @override
  String get generalSettingsContextMenuSystemSettings => 'Cài đặt hệ thống…';

  @override
  String generalSettingsContextMenuFailed(String error) {
    return 'Không thể thay đổi menu ngữ cảnh: $error';
  }

  @override
  String contextMenuOpenWith(String name) {
    return 'Mở bằng $name';
  }

  @override
  String get cmdOpenRemoteFolder => 'Mở dự án từ xa...';

  @override
  String get cmdOpenRemoteFile => 'Mở tệp từ xa...';

  @override
  String get remoteHostPlaceholder =>
      'Chọn máy chủ, thêm máy chủ hoặc nhập user@host[:port]';

  @override
  String remoteConnectTo(String host) {
    return 'Kết nối với $host';
  }

  @override
  String get remoteNoHosts =>
      'Chưa có máy chủ nào: thêm một máy chủ hoặc nhập user@host';

  @override
  String get remoteInvalidHost =>
      'Không phải là máy chủ: không có dấu cách và không bắt đầu bằng \'-\'';

  @override
  String remoteConnecting(String host) {
    return 'Đang kết nối với $host...';
  }

  @override
  String remoteConnectFailed(String host) {
    return 'Không thể kết nối với $host';
  }

  @override
  String remoteConnectionLost(String host) {
    return 'Kết nối với $host bị mất và tự nó được thử lại. Những gì bạn gửi sẽ đợi cho đến khi nó quay trở lại';
  }

  @override
  String get remoteRetry => 'Thử lại';

  @override
  String remoteSignInTitle(String host) {
    return 'Đăng nhập vào $host';
  }

  @override
  String get remoteSignInRefused =>
      'Điều đó đã không được chấp nhận. Hãy thử lại.';

  @override
  String get remoteSignInRemember =>
      'Ghi nhớ trên máy tính này (trong móc khóa hệ thống)';

  @override
  String get remoteSignInConnect => 'Kết nối';

  @override
  String get remoteParentFolder => 'Thư mục gốc';

  @override
  String remoteListFailed(String path) {
    return 'Không thể liệt kê $path';
  }

  @override
  String remoteReadingFolder(String path) {
    return 'Đang đọc $path…';
  }

  @override
  String get remoteFileHostPlaceholder =>
      'Chọn một máy chủ để duyệt các tệp của nó';

  @override
  String get remoteRecentFiles => 'tệp từ xa gần đây';

  @override
  String remoteOpenFileOn(String host) {
    return 'Mở tệp trên $host...';
  }

  @override
  String remoteStatusActions(String host) {
    return 'Nhấp vào máy chủ và hành động của $host';
  }

  @override
  String remoteStatus(String kind, String host) {
    return '$kind: $host';
  }

  @override
  String remoteStatusConnecting(String kind, String host) {
    return '$kind: $host (đang kết nối...)';
  }

  @override
  String remoteStatusReconnecting(String kind, String host) {
    return '$kind: $host (đang kết nối lại...)';
  }

  @override
  String remoteStatusFailed(String kind, String host) {
    return '$kind: $host (đã ngắt kết nối)';
  }

  @override
  String remoteStatusDown(String kind, String host) {
    return '$kind: $host (đã ngắt kết nối, đang thử lại...)';
  }

  @override
  String remoteStatusInstalling(String kind, String host, int percent) {
    return '$kind: $host (cài đặt Claude Code $percent%)';
  }

  @override
  String remoteStatusInstallingUnsized(String kind, String host) {
    return '$kind: $host (cài đặt Claude Code...)';
  }

  @override
  String remoteInstallingClaude(String host) {
    return 'Đang cài đặt Claude Code trên $host…';
  }

  @override
  String remoteInstallingClaudeProgress(String host, int percent) {
    return 'Cài đặt Claude Code trên $host… $percent%';
  }

  @override
  String localDownloadingClaude(int percent) {
    return 'Đang tải xuống Claude Code… $percent%';
  }

  @override
  String remoteUploadingClaude(String host, int percent) {
    return 'Đang gửi Claude Code tới $host… $percent%';
  }

  @override
  String remoteStatusTooltip(String kind, String host) {
    return 'Đã kết nối với $host qua $kind';
  }

  @override
  String remoteStatusSystem(String platform) {
    return 'Hệ thống: $platform';
  }

  @override
  String remoteStatusTooltipLost(String host) {
    return 'Mất kết nối với $host: nhấp để kết nối lại ngay';
  }

  @override
  String remoteStatusTooltipResuming(String host) {
    return 'Kết nối với $host bị mất và được tạo lại: các Terminal của nó và Claude Code vẫn tiếp tục chạy ở đó trong khi đó. Bấm để kết nối lại ngay bây giờ';
  }

  @override
  String get remoteReconnect => 'Kết nối lại';

  @override
  String remoteProjectTooltip(String kind, String host) {
    return 'Trên $host, trên $kind';
  }

  @override
  String quitConfirmRemote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Các phiên và Terminal $count trên máy chủ từ xa cũng sẽ kết thúc.',
      one: '1 phiên hoặc Terminal trên máy chủ từ xa cũng sẽ kết thúc.',
    );
    return '$_temp0';
  }

  @override
  String get updateButton => 'Cập nhật';

  @override
  String get tipsSetupTitle => 'Thiết Lập BaoCode';

  @override
  String tipsSetupCount(int done, int total) {
    return '$done/$total';
  }

  @override
  String tipsSetupEntry(int done, int total) {
    return 'Cài đặt $done/$total';
  }

  @override
  String get tipsHide => 'Trốn';

  @override
  String get tipsTurnOn => 'Bật';

  @override
  String get tipsDismiss => 'Đóng';

  @override
  String get tipsDone => 'Xong';

  @override
  String get tipsDontShowAgain => 'Đừng hiển thị lại';

  @override
  String tipsFailed(String title, String error) {
    return 'Không thể bật $title: $error';
  }

  @override
  String tipsUpdated(String version, String features) {
    return 'BaoCode đã được cập nhật thành $version. Mới: $features.';
  }

  @override
  String get tipsListSeparator => ', ';

  @override
  String get tipsSettingsTitle => 'Khuyến khích';

  @override
  String get tipsSettingsDescription =>
      'Các tính năng chưa được bật. Hiển thị Hướng dẫn Thiết lập mang lại danh sách kiểm tra thiết lập; \"workbench.tips.enabled\": false trong settings.json sẽ tắt mẹo.';

  @override
  String get tipContextMenuBody =>
      'Mở tệp và thư mục trong BaoCode từ menu ngữ cảnh của chúng.';

  @override
  String tipShellCommandTitle(String name) {
    return 'Lệnh \'$name\'';
  }

  @override
  String tipShellCommandBody(String name) {
    return 'Mở các thư mục trong BaoCode từ Terminal: $name <path>.';
  }

  @override
  String get tipImportKeybindingsTitle => 'Nhập tổ hợp phím';

  @override
  String get tipImportKeybindingsBody =>
      'Mang tổ hợp phím của bạn từ Mã VS hoặc Con trỏ đến.';

  @override
  String get tipColorThemeBody =>
      'Chọn màu của cuộc trò chuyện, IDE và Terminal.';

  @override
  String get cmdShowSetupGuide => 'Hiển thị hướng dẫn thiết lập';

  @override
  String get cmdStarOnGitHub => 'Sao BaoCode trên GitHub';

  @override
  String get starPromptMessage => 'Bạn có thích BaoCode không?';

  @override
  String get starPromptDetail =>
      'BaoCode là mã nguồn mở và miễn phí. Nếu điều đó giúp ích cho bạn thì một ngôi sao trên GitHub sẽ giúp người khác tìm thấy nó.';

  @override
  String get starPromptStar => 'Sao trên GitHub';

  @override
  String get starPromptLater => 'Có lẽ sau này';

  @override
  String get cmdResetFeatureTips => 'Đặt lại mẹo về tính năng';

  @override
  String get newChatWorkspaceGroup => 'Không gian làm việc';

  @override
  String newChatWorkspaceDetail(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Thư mục $count',
      one: '1 thư mục',
    );
    return '$_temp0 · $names';
  }

  @override
  String newChatHostProjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dự án $count',
      one: '1 dự án',
    );
    return '$_temp0';
  }

  @override
  String get newChatPickRemoteFolder => 'Chọn thư mục…';

  @override
  String get newChatPickRemoteFolderDetail => 'Mở một thư mục trên máy chủ này';

  @override
  String get newChatCreateWorkspace => 'Tạo không gian làm việc…';

  @override
  String get newChatCreateWorkspaceDetail => 'Làm việc trên nhiều thư mục';

  @override
  String newChatAddFolderTo(String name) {
    return 'Thêm thư mục vào $name…';
  }

  @override
  String get newChatAddFolderToDetail => 'Agent của nó cũng làm việc ở đó';

  @override
  String newChatProjectAddedFolders(String path, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thêm thư mục',
      one: '1 thư mục nữa',
    );
    return '$path · $_temp0';
  }

  @override
  String get workspaceCreateTitle => 'Tạo không gian làm việc';

  @override
  String get workspaceEditTitle => 'Chỉnh sửa không gian làm việc';

  @override
  String get workspaceName => 'Tên';

  @override
  String get workspaceNameHint => 'Không gian làm việc của tôi';

  @override
  String get workspaceFolders => 'Thư mục';

  @override
  String get workspaceFoldersDescription =>
      'Các tác nhân làm việc trong không gian làm việc này có thể đọc và thay đổi các tệp trong các thư mục này.';

  @override
  String workspaceFoldersEmpty(String app) {
    return 'Chưa có thư mục nào. Thêm dự án hoặc thư mục từ $app.';
  }

  @override
  String get workspaceNoFolders => 'Thêm ít nhất một thư mục.';

  @override
  String get workspaceAddProject => 'Thêm từ dự án';

  @override
  String workspaceAddFolder(String app) {
    return 'Thêm từ $app…';
  }

  @override
  String get workspaceNoProjects => 'Không có dự án nào để thêm';

  @override
  String workspaceRemoveFolder(String name) {
    return 'Xóa $name';
  }

  @override
  String get workspaceCreate => 'Tạo nên';

  @override
  String workspaceHover(String folders) {
    return 'Không gian làm việc: $folders';
  }

  @override
  String get sidebarEditWorkspace => 'Chỉnh sửa không gian làm việc…';

  @override
  String get sidebarDeleteWorkspace => 'Xóa không gian làm việc';

  @override
  String get sidebarEditProject => 'Chỉnh sửa dự án…';

  @override
  String get sidebarAddFolder => 'Thêm thư mục…';

  @override
  String get projectEditTitle => 'Chỉnh sửa dự án';

  @override
  String get projectLocation => 'Vị trí';

  @override
  String get projectLocationDescription =>
      'Đã di chuyển hoặc đổi tên thư mục? Hãy trỏ dự án vào đây và các cuộc trò chuyện của dự án sẽ tiếp tục diễn ra. Bản thân thư mục không được di chuyển.';

  @override
  String get projectFoldersDescription =>
      'Các nhân viên làm việc trong dự án này cũng có thể đọc và thay đổi các tệp trong các thư mục được thêm vào dự án. Các cuộc trò chuyện đã bắt đầu sẽ nhìn thấy chúng khi chúng bắt đầu lại.';

  @override
  String projectChooseFolder(String app) {
    return 'Chọn trong $app…';
  }

  @override
  String get projectFolderNotFound => 'Không có thư mục tại đường dẫn này.';

  @override
  String get projectRelocateBusy =>
      'Một agent của dự án này vẫn đang làm việc hoặc đang mở trong một cửa sổ riêng. Thay đổi vị trí của nó sau khi hoàn tất.';

  @override
  String get projectRelocateFailed =>
      'Không thể di chuyển các cuộc trò chuyện của dự án này.';

  @override
  String get projectRelocating => 'Đang di chuyển cuộc trò chuyện…';

  @override
  String ideWorkspaceTitle(String name) {
    return '$name (Không gian làm việc)';
  }

  @override
  String get ideAddFolderToWorkspace => 'Thêm thư mục vào không gian làm việc…';

  @override
  String get ideRemoveFolderFromWorkspace =>
      'Xóa thư mục khỏi không gian làm việc';

  @override
  String get ideEmptyWorkspace =>
      'Không gian làm việc này chưa có thư mục nào.';

  @override
  String get scmRepositories => 'Kho lưu trữ';

  @override
  String get cmdCreateWorkspace => 'Tạo không gian làm việc...';

  @override
  String get settingsSectionNetwork => 'Mạng';

  @override
  String get settingsNetworkKeywords => 'proxy http https xung đột mạng vpn';

  @override
  String get networkSettingsTitle => 'Mạng';

  @override
  String get networkSettingsDescription =>
      'Làm thế nào BaoCode và Claude Code bắt đầu tiếp cận internet.';

  @override
  String get networkProxy => 'ủy quyền';

  @override
  String get networkProxyDescription =>
      'Proxy cho BaoCode và Claude Code (http.proxyMode). Proxy hệ thống tuân theo cài đặt của hệ thống, chẳng hạn như proxy hệ thống của Clash. Phiên mới có sự thay đổi; khởi động lại một cái đang chạy cho nó.';

  @override
  String networkProxyLabel(String name) {
    return 'Proxy: $name';
  }

  @override
  String get networkProxySystem => 'Proxy hệ thống';

  @override
  String get networkProxyManual => 'Thủ công';

  @override
  String get networkProxyOff => 'Không có ủy quyền';

  @override
  String get networkProxyUrl => 'Địa chỉ proxy';

  @override
  String get networkProxyUrlDescription =>
      'Proxy HTTP, chẳng hạn như cổng của Clash: http://127.0.0.1:7890 (http.proxy). SOCKS không được hỗ trợ.';

  @override
  String networkProxyUrlInvalid(String url) {
    return 'Không phải địa chỉ proxy HTTP: $url. Nhập một cái như http://127.0.0.1:7890.';
  }

  @override
  String get networkProxyStatus => 'Đang sử dụng';

  @override
  String get networkProxyStatusChecking => 'Đang phát hiện…';

  @override
  String networkProxyStatusSystem(String server) {
    return 'Proxy hệ thống $server';
  }

  @override
  String networkProxyStatusEnvironment(String server) {
    return '$server, từ môi trường (HTTPS_PROXY): hệ thống chưa đặt proxy';
  }

  @override
  String networkProxyStatusManual(String server) {
    return '$server';
  }

  @override
  String get networkProxyStatusManualMissing => 'Nhập địa chỉ của proxy.';

  @override
  String get networkProxyStatusNone => 'Trực tiếp: hệ thống không có bộ proxy.';

  @override
  String get networkProxyStatusOff => 'Trực tiếp.';

  @override
  String get networkProxyStatusAutoConfig =>
      'Trực tiếp: hệ thống đặt proxy bằng tệp tự động cấu hình (PAC), mà BaoCode không tuân theo. Bật proxy hệ thống của Clash hoặc nhập địa chỉ theo cách thủ công.';

  @override
  String get networkProxyRefresh => 'Phát hiện lại';

  @override
  String get networkTest => 'Kiểm tra kết nối';

  @override
  String get networkTestDescription =>
      'Tiếp cận các trang web này thông qua proxy đang sử dụng: mỗi câu trả lời có trả lời hay không và tốc độ nhanh như thế nào (thời gian của kết nối mới, cho đến khi câu trả lời bắt đầu).';

  @override
  String get networkTesting => 'Đang thử nghiệm…';

  @override
  String get networkTestRun => 'Chạy thử nghiệm';

  @override
  String get networkTestRunAgain => 'Kiểm tra lại';

  @override
  String get networkTestIdle => 'Chưa được kiểm tra';

  @override
  String networkTestMs(int ms) {
    return '$ms ms';
  }

  @override
  String get networkTestUnreachable => 'Không thể truy cập';

  @override
  String networkTestSummary(int reached, int total) {
    return '$reached trong số các trang web $total có thể truy cập được.';
  }

  @override
  String get networkFailureTimeout => 'Đã hết thời gian';

  @override
  String get networkFailureRefused => 'Kết nối bị từ chối';

  @override
  String get networkFailureReset => 'Đặt lại kết nối';

  @override
  String get networkFailureDns => 'Tra cứu DNS không thành công';

  @override
  String get networkFailureTls => 'TLS không thành công';

  @override
  String get networkFailureProxyAuth => 'Proxy cần đăng nhập';

  @override
  String get networkFailureOther => 'Không thể kết nối';

  @override
  String get networkTestHintRefused =>
      'Không có câu trả lời nào tại địa chỉ của proxy: hãy kiểm tra xem Clash (hoặc proxy) có đang chạy không.';

  @override
  String get networkTestHintOffline =>
      'Không có câu trả lời về trang web: hãy kiểm tra kết nối mạng của máy tính này và proxy.';

  @override
  String get networkTestHintBlocked =>
      'Chỉ có câu trả lời của Baidu: proxy không giúp những người khác vượt qua được. Kiểm tra proxy ở trên hoặc chế độ và quy tắc của Clash.';

  @override
  String get extsCapabilityFull => 'Hỗ trợ đầy đủ';

  @override
  String get extsCapabilityFullDetail =>
      'Tất cả các chủ đề về màu sắc hoặc biểu tượng tệp của nó đều được áp dụng.';

  @override
  String get extsCapabilityPartial => 'Được hỗ trợ một phần';

  @override
  String get extsCapabilityPartialDetail =>
      'Các chủ đề của nó được áp dụng; phần còn lại không có tác dụng gì trong BaoCode.';

  @override
  String extsEngineIncompatible(String current, String requested) {
    return 'Cần Mã VS $requested; đây là $current.';
  }

  @override
  String get extsEngineMissing => 'Nó không cho biết nó cần Mã VS nào.';

  @override
  String extsEngineInvalid(String requested) {
    return 'Công cụ không hợp lệ \'$requested\'.';
  }

  @override
  String extsEngineCompatible(String engine) {
    return 'Yêu cầu Mã VS $engine.';
  }

  @override
  String get extsTitleUpdates => 'Cập nhật';

  @override
  String get extsTitleOpenVsx => 'Mở VSX';

  @override
  String get extsUpdates => 'Cập nhật';

  @override
  String get extsCheckForUpdates => 'Kiểm tra cập nhật';

  @override
  String get extsMoreActions => 'Thêm hành động...';

  @override
  String get extsInstallFromVsix => 'Cài đặt từ VSIX...';

  @override
  String get extsSearchPlaceholder => 'Tìm kiếm tiện ích mở rộng VSX mở';

  @override
  String extsSearchFailed(String error) {
    return 'Không thể tìm kiếm Mở VSX: $error';
  }

  @override
  String get extsLoadMore => 'Tải thêm';

  @override
  String extsUpdateTo(String version) {
    return 'Cập nhật lên $version';
  }

  @override
  String get extsUpdating => 'Đang cập nhật...';

  @override
  String get extsEnable => 'Cho phép';

  @override
  String get extsDisable => 'Vô hiệu hóa';

  @override
  String get extsDisabled => 'Tàn tật';

  @override
  String get extsSwitchToPreRelease => 'Chuyển sang phiên bản tiền phát hành';

  @override
  String get extsSwitchToRelease => 'Chuyển sang phiên bản phát hành';

  @override
  String get extsInstallPreRelease => 'Cài đặt phiên bản tiền phát hành';

  @override
  String extsInstallVersion(String version) {
    return 'Cài đặt $version';
  }

  @override
  String get extsPreRelease => 'Trước khi phát hành';

  @override
  String get extsVerifiedPublisher => 'Nhà xuất bản đã được xác minh';

  @override
  String extsDownloads(String count) {
    return 'Tải xuống $count';
  }

  @override
  String extsLoadFailed(String error) {
    return 'Không thể tải nó: $error';
  }

  @override
  String get extsVersion => 'Phiên bản';

  @override
  String get extsPreReleaseToggle => 'Trước khi phát hành';

  @override
  String get extsLatestVersion => 'Mới nhất';

  @override
  String get extsTabDetails => 'Chi tiết';

  @override
  String get extsTabFeatures => 'Đặc trưng';

  @override
  String get extsTabChangelog => 'Nhật ký thay đổi';

  @override
  String get extsNoReadme => 'Tiện ích mở rộng này không có README.';

  @override
  String get extsNoChangelog =>
      'Tiện ích mở rộng này không có nhật ký thay đổi.';

  @override
  String get extsContributions => 'Đóng góp';

  @override
  String get extsNoContributions => 'Phần mở rộng này không đóng góp gì cả.';

  @override
  String get extsActivationEvents => 'Sự kiện kích hoạt';

  @override
  String get extsApiProposals => 'Đề xuất API';

  @override
  String get extsCompatibility => 'Khả năng tương thích';

  @override
  String get extsInformation => 'Thông tin';

  @override
  String get extsInfoIdentifier => 'Mã định danh';

  @override
  String get extsInfoVersion => 'Phiên bản';

  @override
  String get extsInfoLatest => 'Mới nhất';

  @override
  String get extsInfoLastUpdated => 'Cập nhật lần cuối';

  @override
  String get extsInfoEngine => 'Mã VS';

  @override
  String get extsInfoPlatform => 'Nền tảng';

  @override
  String get extsInfoLicense => 'Giấy phép';

  @override
  String get extsInfoRepository => 'Kho lưu trữ';

  @override
  String get extsInfoCategories => 'Thể loại';

  @override
  String get extsInfoLocation => 'Vị trí';

  @override
  String get extsVsixTitle => 'Cài đặt tiện ích mở rộng VSIX';

  @override
  String extsVsixInvalid(String name, String error) {
    return '$name không phải là VSIX hợp lệ: $error';
  }

  @override
  String extsVsixPlatformMismatch(String platform, String current) {
    return 'Nó được xây dựng cho $platform, không phải cho $current.';
  }

  @override
  String extsVsixReplaces(String version) {
    return 'Nó thay thế phiên bản $version.';
  }

  @override
  String extsPlatformCompatible(String platform) {
    return 'Nền tảng: $platform';
  }

  @override
  String get extsPlatformUniversal => 'phổ quát';

  @override
  String extsPageTitle(String name) {
    return 'Tiện ích mở rộng: $name';
  }

  @override
  String get themeSelectIconThemePlaceholder =>
      'Chọn chủ đề biểu tượng tệp (Phím lên/xuống để xem trước)';

  @override
  String get themeIconThemeBuiltIn => 'Tích hợp sẵn';

  @override
  String get extsCapabilityUnsupported => 'Không được hỗ trợ';

  @override
  String get extsCapabilityUnsupportedDetail =>
      'Nó không có chủ đề màu sắc hoặc biểu tượng tệp: BaoCode chỉ sử dụng chủ đề từ tiện ích mở rộng.';

  @override
  String get extsFindingCode => 'Mã của nó không chạy.';

  @override
  String extsFindingContribution(String name) {
    return 'Không được sử dụng: $name';
  }

  @override
  String get extsPopularThemes => 'Chủ đề phổ biến';

  @override
  String get extsTabThemes => 'Chủ đề';

  @override
  String get extsTabLanguageServers => 'Máy chủ ngôn ngữ';

  @override
  String get sidebarAllHosts => 'Tất cả';

  @override
  String get sidebarThisMachine => 'Máy tính này';

  @override
  String get sidebarSwitchHost => 'Chuyển đổi giữa máy tính này và máy chủ SSH';

  @override
  String get sidebarAddSshHost => 'Thêm máy chủ SSH...';

  @override
  String sidebarOpenFolderOn(String host) {
    return 'Mở thư mục trên $host...';
  }

  @override
  String sidebarNoProjectsOn(String host) {
    return 'Chưa có dự án nào trên $host.';
  }

  @override
  String get sidebarHostConnected => 'Đã kết nối';

  @override
  String get sidebarHostConnecting => 'Đang kết nối...';

  @override
  String get sidebarHostDisconnected => 'Đã ngắt kết nối';

  @override
  String get sidebarHostDown => 'Đã ngắt kết nối, đang thử lại...';

  @override
  String get sidebarHostIdle => 'Không được kết nối';

  @override
  String get sidebarDisconnectHost => 'Ngắt kết nối';

  @override
  String get sidebarRemoveHost => 'Xóa máy chủ';

  @override
  String sidebarRemoveHostTitle(String host) {
    return 'Xóa $host?';
  }

  @override
  String get sidebarRemoveHostMessage =>
      'Các dự án của máy chủ này sẽ được xóa khỏi thanh bên. Các cuộc trò chuyện vẫn được giữ và sẽ xuất hiện lại khi máy chủ được thêm trở lại.';

  @override
  String get sidebarRemove => 'Di dời';

  @override
  String sidebarElsewhereNeedsYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Agent $count trên máy khác cần bạn',
      one: '1 nhân viên trên máy khác cần bạn',
    );
    return '$_temp0';
  }

  @override
  String get sidebarRenameHost => 'Đổi tên máy chủ';

  @override
  String get sidebarEditHost => 'Chỉnh sửa kết nối...';

  @override
  String get explorerNoPermission => 'Không có quyền đọc thư mục này';

  @override
  String fileErrorAccessDenied(String path) {
    return 'Quyền bị từ chối: $path';
  }

  @override
  String get remoteAddedHosts => 'Đã thêm';

  @override
  String explorerUndoCreateChanged(String name) {
    return '$name đã thay đổi kể từ khi nó được tạo ra. Vẫn xóa nó?';
  }

  @override
  String get settingsSectionMobile => 'Di động';

  @override
  String get settingsMobileKeywords =>
      'điện thoại iphone android ios cặp mã qr từ xa lan';

  @override
  String get mobileSettingsDescription =>
      'Theo dõi và điều khiển các tác nhân của máy tính này từ BaoCode trên điện thoại của bạn: trực tiếp trên cùng một mạng, qua internet thông qua một lỗ được đục lỗ trên các bộ định tuyến giữa chúng hoặc thông qua rơle của BaoCode khi cả hai đều không hoạt động. Những gì diễn ra giữa chúng đều được mã hóa nối đầu; rơle không thể đọc được nó.';

  @override
  String get mobileAllow => 'Cho phép điện thoại kết nối';

  @override
  String get mobileAllowDescription =>
      'Điện thoại được ghép nối với máy tính này có thể kết nối với nó mọi lúc mọi nơi.';

  @override
  String get mobileStatus => 'Trạng thái';

  @override
  String get mobileStatusOff => 'Tắt';

  @override
  String get mobileStatusStarting => 'Bắt đầu…';

  @override
  String mobileStatusFailed(String error) {
    return 'Không thể khởi động: $error';
  }

  @override
  String get mobileRelay => 'Rơle';

  @override
  String get mobileRelayDescription =>
      'Những điện thoại không thể kết nối trực tiếp với máy tính này sẽ đi qua một máy tính. Nó chỉ truyền đi những gì đã bị phong ấn giữa hai người. Không có gì để cài đặt trên điện thoại: điện thoại sẽ học chúng khi được ghép nối và lặp lại mỗi lần kết nối.';

  @override
  String get mobilePair => 'Ghép nối điện thoại';

  @override
  String get mobilePairDescription =>
      'Quét mã bằng BaoCode trên điện thoại (Tôi → Máy tính được ghép nối → Ghép nối máy tính) hoặc chọn máy tính này trong Máy tính lân cận ở đó.';

  @override
  String get mobilePairShow => 'Hiển thị mã QR';

  @override
  String get mobilePairCancel => 'Hủy bỏ';

  @override
  String get mobilePairNewCode => 'Mã mới';

  @override
  String get mobilePairCopyLink => 'Sao chép liên kết';

  @override
  String get mobilePairQrHint =>
      'Click để sao chép link, để dán vào điện thoại';

  @override
  String get mobileGetApp => 'Tải ứng dụng điện thoại';

  @override
  String get mobileGetAppDescription =>
      'Quét bằng camera điện thoại: tải về tương tự như trên baocode.dev.';

  @override
  String get mobileGetAndroidDetail => 'APK; nó luôn cập nhật';

  @override
  String get mobileGetIos => 'iPhone và iPad';

  @override
  String get mobileGetIosDetail => 'Bản beta, trên TestFlight';

  @override
  String mobileGetOpen(String url) {
    return 'Bấm để mở $url';
  }

  @override
  String get mobilePairCopied => 'Đã sao chép';

  @override
  String mobilePairExpires(int minutes) {
    return 'Tốt cho $minutes phút, một lần. Điện thoại không quét được có thể dán link thay thế.';
  }

  @override
  String get mobilePairExpired => 'Mã này đã hết hạn.';

  @override
  String mobilePairVerifyTitle(String name) {
    return 'So sánh với $name';
  }

  @override
  String get mobilePairVerifyBody =>
      'Kiểm tra xem điện thoại có hiển thị mã giống nhau không, sau đó xác nhận trên điện thoại.';

  @override
  String get mobilePairMismatch => 'Mã không khớp';

  @override
  String mobilePaired(String name) {
    return 'Được ghép nối với $name.';
  }

  @override
  String get mobilePhones => 'Điện thoại được ghép nối';

  @override
  String get mobilePhonesNone => 'Chưa có điện thoại nào được ghép nối.';

  @override
  String get mobilePhoneConnected => 'Đã kết nối';

  @override
  String mobilePhoneLastSeen(String time) {
    return 'Kết nối lần cuối $time';
  }

  @override
  String get mobilePhoneRemove => 'Di dời';

  @override
  String get mobileThisComputerKey => 'Chìa khóa của máy tính này';

  @override
  String get mobileThisComputerKeyDescription =>
      'Điện thoại cũng hiển thị điều đó: cùng một phím trên cả hai nghĩa là không có ai ở giữa.';

  @override
  String get mobileDiscoverable => 'Tìm trên Mạng cục bộ';

  @override
  String get mobileDiscoverableDescription =>
      'Các điện thoại được ghép nối với máy tính này sẽ tìm thấy nó trên mạng cục bộ, ngay cả sau khi địa chỉ của nó thay đổi; trong khi bạn ghép nối một thiết bị, các điện thoại mới sẽ liệt kê thiết bị đó trong Máy tính ở gần.';

  @override
  String get mobilePairNearbyHint =>
      'Điện thoại trên mạng này cũng có thể chọn máy tính này trong Máy tính lân cận.';

  @override
  String mobilePairRequestTitle(String name) {
    return '$name muốn ghép nối';
  }

  @override
  String get mobilePairRequestBody =>
      'Nó tìm thấy máy tính này ở gần đây. Chỉ cho phép nếu điện thoại hiển thị cùng một mã.';

  @override
  String get mobilePairAllow => 'Cho phép';

  @override
  String mobileStatusOnline(String relay) {
    return 'Bật, có thể truy cập thông qua $relay';
  }

  @override
  String get mobileStatusNoRelay =>
      'TRÊN; chưa có rơ-le nào nên chỉ có điện thoại trên cùng mạng mới có thể kết nối';

  @override
  String mobileStatusDenied(String reason) {
    return 'Bật, nhưng rơle đã tắt máy tính này: $reason';
  }

  @override
  String get mobileRelayInvalid =>
      'Không phải là địa chỉ chuyển tiếp; một cái trông giống như https://relay.example.com';

  @override
  String get mobileRelayCustom => 'Phong tục';

  @override
  String get mobileRelayCustomAddress => 'Địa chỉ tùy chỉnh';

  @override
  String get mobileRelayCustomDescription =>
      'Địa chỉ rơle bạn tự chạy (baocode-relay).';

  @override
  String get mobileRelayInUse => 'Đang sử dụng';

  @override
  String get mobileRelayMoveUp => 'Di chuyển lên';

  @override
  String get mobileRelayMoveDown => 'Di chuyển xuống';

  @override
  String get mobileRelayRemove => 'Di dời';

  @override
  String get mobileRelayAdd => 'Thêm Rơle';

  @override
  String get mobileRelayAddPick => 'Chọn…';

  @override
  String get mobileRelayMode => 'Làm sao';

  @override
  String get mobileRelayModeAuto => 'Tự động';

  @override
  String get mobileRelayModeAutoDescription =>
      'Rơle của BaoCode, gần nhất có câu trả lời.';

  @override
  String get mobileRelayModePinned => 'Danh sách của bạn';

  @override
  String get mobileRelayModePinnedDescription =>
      'Các rơ-le mà bạn liệt kê theo thứ tự: tiếp theo khi không thể liên lạc được và quay lại cái trước đó khi có thể. BaoCode\'s hoặc địa chỉ tùy chỉnh.';

  @override
  String get mobileRelayModeDirect => 'Chỉ trực tiếp';

  @override
  String get mobileRelayModeDirectDescription =>
      'Không có rơle: điện thoại kết nối thẳng với máy tính này. Nó cần một địa chỉ công cộng hoặc cổng bên dưới được chuyển tiếp tới nó.';

  @override
  String get mobileDirectPort => 'Cổng trực tiếp';

  @override
  String get mobileDirectPortDescription =>
      'Các điện thoại có cổng UDP kết nối tới. Chuyển tiếp nó tới máy tính này tại bộ định tuyến và cho phép nó vào tường lửa.';

  @override
  String get mobileDirectPortInvalid => 'Một cổng từ 1024 đến 65535.';

  @override
  String get mobileDirectAddress => 'Địa chỉ trực tiếp';

  @override
  String get mobileDirectAddressDescription =>
      'Nó đi kèm với mã ghép nối và trong mọi kết nối sau đó.';

  @override
  String get mobileDirectAddressNone =>
      'Chưa có địa chỉ công cộng: hãy kiểm tra lại khi máy tính này trực tuyến hoặc chuyển tiếp cổng tới nó nếu nó ở phía sau bộ định tuyến.';

  @override
  String get mobileStatusDirect => 'Bật, chỉ trực tiếp';

  @override
  String get mobilePathLan => 'Cùng một mạng';

  @override
  String get mobilePathDirect => 'Trực tiếp';

  @override
  String get mobilePathRelay => 'Thông qua rơle';

  @override
  String mobilePathRtt(int ms) {
    return '$ms ms';
  }

  @override
  String get mobileLegacyPhone =>
      'Cần ghép nối lại: đã ghép nối trước khi kết nối được xây dựng lại';

  @override
  String get mobileLegacyRepair => 'Ghép nối lại';

  @override
  String get settingsSectionStash => 'Stash';

  @override
  String get settingsSectionBuiltinCore => 'Bộ lõi tích hợp';

  @override
  String get settingsBuiltinCoreKeywords =>
      'Tác nhân hướng dẫn nhắc nhở hệ thống lõi tích hợp';

  @override
  String get builtinCoreSettingsTitle => 'Lõi tích hợp';

  @override
  String get builtinCoreSettingsDescription =>
      'Tùy chỉnh lời nhắc hệ thống được sử dụng bởi lõi tích hợp của BaoCode. Những thay đổi áp dụng cho các cuộc hội thoại mới; bot giữ lời nhắc của riêng họ.';

  @override
  String get builtinCoreSystemPromptGroup => 'Lời nhắc hệ thống';

  @override
  String get builtinCoreSystemPromptMode => 'Cách thức';

  @override
  String builtinCoreSystemPromptModeLabel(String mode) {
    return 'Lời nhắc hệ thống: $mode';
  }

  @override
  String get builtinCoreModeDefault => 'Mặc định';

  @override
  String get builtinCoreModeAppend => 'Nối vào mặc định';

  @override
  String get builtinCoreModeReplace => 'Thay thế mặc định';

  @override
  String get builtinCoreModeDefaultDetail =>
      'Sử dụng các hướng dẫn cốt lõi mặc định của BaoCode.';

  @override
  String get builtinCoreModeAppendDetail =>
      'Giữ các hướng dẫn cốt lõi mặc định và thêm văn bản của bạn vào cuối.';

  @override
  String get builtinCoreModeReplaceDetail =>
      'Thay thế các hướng dẫn cốt lõi mặc định trong khi vẫn giữ bộ nhớ tự động, kiểu đầu ra, CLAUDE.md và các quy tắc định dạng.';

  @override
  String get builtinCoreAppendLabel => 'Hướng dẫn bổ sung';

  @override
  String get builtinCoreAppendPlaceholder =>
      'Viết hướng dẫn để thêm vào lời nhắc hệ thống mặc định…';

  @override
  String get builtinCoreReplaceLabel => 'Hướng dẫn cốt lõi tùy chỉnh';

  @override
  String get builtinCoreReplacePlaceholder =>
      'Viết lời nhắc hệ thống thay thế các hướng dẫn cốt lõi mặc định…';

  @override
  String get builtinCoreLoadDefault => 'Tải mặc định';

  @override
  String get builtinCoreResetDefault => 'Đặt lại về mặc định';

  @override
  String get builtinCoreDefaultPromptTitle => 'Lời nhắc hệ thống mặc định';

  @override
  String get builtinCoreDefaultPromptDescription =>
      'Các hướng dẫn cốt lõi tích hợp được sử dụng khi không đặt thay thế, để tham khảo.';

  @override
  String get builtinCoreCopyDefault => 'Sao chép';

  @override
  String get builtinCoreCopiedDefault => 'Đã sao chép';

  @override
  String get settingsSectionCustomize => 'Tùy chỉnh';

  @override
  String get settingsCustomizeKeywords =>
      'kỹ năng tác nhân con quy tắc lệnh tác nhân claude bộ nhớ hooks mcp plugin';

  @override
  String get stashTitle => 'cất giữ';

  @override
  String get stashHeading => 'cất giữ';

  @override
  String get stashNew => 'Kho mới';

  @override
  String get stashLinkOpen => 'Mở liên kết';

  @override
  String get stashLinkEdit => 'Chỉnh sửa liên kết';

  @override
  String get stashLinkCopy => 'Sao chép địa chỉ liên kết';

  @override
  String get stashLinkRemove => 'Xóa liên kết';

  @override
  String get stashFormatMenu => 'Định dạng';

  @override
  String get stashDraft => 'Bản nháp';

  @override
  String get stashCodeChip => 'Mã số';

  @override
  String get stashTableChip => 'Bàn';

  @override
  String stashLines(int count) {
    return 'Các dòng $count';
  }

  @override
  String get stashNewButton => 'Mới';

  @override
  String get stashNewTooltip => 'Kho mới';

  @override
  String get stashPlaceholder => 'Hãy ghi lại…';

  @override
  String get stashHintNew => 'Mới';

  @override
  String get stashProjectTooltip => 'Dự án nó nói về';

  @override
  String get stashNoProject => 'Không có dự án';

  @override
  String get stashFormatBold => 'In đậm';

  @override
  String get stashFormatItalic => 'Nghiêng';

  @override
  String get stashFormatStrike => 'Gạch ngang';

  @override
  String get stashFormatUnderline => 'gạch chân';

  @override
  String get stashFormatCode => 'Mã số';

  @override
  String get stashFormatLink => 'liên kết';

  @override
  String get stashFormatColor => 'Màu văn bản và nền';

  @override
  String get stashFormatHeading1 => 'Tiêu đề 1';

  @override
  String get stashFormatHeading2 => 'Tiêu đề 2';

  @override
  String get stashFormatHeading3 => 'Tiêu đề 3';

  @override
  String get stashFormatBullets => 'Danh sách có dấu đầu dòng';

  @override
  String get stashFormatNumbers => 'Danh sách đánh số';

  @override
  String get stashFormatTasks => 'danh sách nhiệm vụ';

  @override
  String get stashFormatQuote => 'Trích dẫn';

  @override
  String get stashFormatCodeBlock => 'Khối mã';

  @override
  String get markdownTableInsertRowAbove => 'Chèn hàng phía trên';

  @override
  String get markdownTableInsertRowBelow => 'Chèn hàng bên dưới';

  @override
  String get markdownTableDeleteRow => 'Xóa hàng';

  @override
  String get markdownTableInsertColumnLeft => 'Chèn cột bên trái';

  @override
  String get markdownTableInsertColumnRight => 'Chèn cột bên phải';

  @override
  String get markdownTableDeleteColumn => 'Xóa cột';

  @override
  String get markdownTableAlignLeft => 'Căn trái';

  @override
  String get markdownTableAlignCenter => 'Căn giữa';

  @override
  String get markdownTableAlignRight => 'Căn phải';

  @override
  String get markdownTableDuplicateRow => 'Hàng trùng lặp';

  @override
  String get markdownTableMoveRowUp => 'Di chuyển hàng lên';

  @override
  String get markdownTableMoveRowDown => 'Di chuyển hàng xuống';

  @override
  String get markdownTableClearRow => 'Xóa hàng';

  @override
  String get markdownTableDuplicateColumn => 'cột trùng lặp';

  @override
  String get markdownTableMoveColumnLeft => 'Di chuyển cột sang trái';

  @override
  String get markdownTableMoveColumnRight => 'Di chuyển cột sang phải';

  @override
  String get markdownTableClearColumn => 'Xóa cột';

  @override
  String get markdownTableDeleteTable => 'Xóa bảng';

  @override
  String get stashFormatClear => 'Xóa định dạng';

  @override
  String get stashPolish => 'Đánh bóng';

  @override
  String get stashPolishing => 'Đánh bóng…';

  @override
  String get stashPolishHint =>
      'Theo cách nói của bạn, AI có làm cho việc lựa chọn trở nên rõ ràng hơn mà không cần thêm cấu trúc không';

  @override
  String get composerPolish => 'Tăng cường lời nhắc';

  @override
  String get composerPolishing => 'Tăng cường…';

  @override
  String get composerPolishHint =>
      'Nâng cao lời nhắc: mô hình phụ trợ giúp thông điệp trở thành lời nhắc rõ ràng, cụ thể hơn cho agent, điền vào những gì bạn còn mơ hồ; hình ảnh, tệp, mã và liên kết vẫn giữ nguyên; Hoàn tác sẽ lấy lại nó';

  @override
  String composerPolishFailed(String error) {
    return 'Không thể nâng cao lời nhắc: $error';
  }

  @override
  String get generalSettingsComposerPolish => 'Nút cải thiện prompt';

  @override
  String get generalSettingsComposerPolishDescription =>
      'Nút trong hộp nhập tin nhắn dùng mô hình phụ trợ để làm rõ và cụ thể hóa prompt trước khi gửi.';

  @override
  String get generalSettingsLiveTurnStats => 'Tốc độ và thời gian trực tiếp';

  @override
  String get generalSettingsLiveTurnStatsDescription =>
      'Khi agent làm việc, hiện thời gian đã chạy, tốc độ sinh và số token ngay dưới phản hồi, cập nhật liên tục. Thông số vẫn được hiển thị sau khi lượt hoàn tất.';

  @override
  String usageLimitScheduled(String time) {
    return 'Đã đạt đến giới hạn sử dụng · tự động tiếp tục sau khi đặt lại ở $time';
  }

  @override
  String usageLimitTomorrow(String time) {
    return 'ngày mai $time';
  }

  @override
  String get resumeAfterResetPrompt =>
      'Giới hạn sử dụng đã được đặt lại. Tiếp tục nơi bạn đã dừng lại.';

  @override
  String get resumeAfterLimitToggle => 'Tiếp tục sau khi đặt lại giới hạn';

  @override
  String stashPolishFailed(String error) {
    return 'Không thể đánh bóng: $error';
  }

  @override
  String get stashLinkTitle => 'liên kết';

  @override
  String get stashRemove => 'Di dời';

  @override
  String get stashEdit => 'Biên tập';

  @override
  String get stashFormulaTitle => 'Công thức (TeX)';

  @override
  String get stashTableTitle => 'Bảng (Đánh dấu)';

  @override
  String get stashCodeTitle => 'Khối mã';

  @override
  String stashBigFileTitle(String name) {
    return '“$name” có dung lượng trên 200 MB';
  }

  @override
  String get stashBigFileDetail =>
      'Liên kết đến vị trí của nó hoặc sao chép nó vào kho lưu trữ?';

  @override
  String get stashBigFileLink => 'liên kết';

  @override
  String get stashBigFileCopy => 'Sao chép';

  @override
  String get stashSearchPlaceholder =>
      'Tìm kiếm các kho lưu trữ và văn bản trong ảnh của chúng';

  @override
  String get stashAiSearch => 'Tìm kiếm AI';

  @override
  String get stashAiSearchHint =>
      'Tìm kho theo ý nghĩa của chúng chứ không chỉ theo lời nói của chúng. Hỏi mô hình: nó có giá.';

  @override
  String stashAiResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'AI đã tìm thấy $count',
      one: 'AI đã tìm thấy 1',
      zero: 'AI không tìm thấy gì',
    );
    return '$_temp0';
  }

  @override
  String get stashAiClear => 'Xóa';

  @override
  String stashAiSearchFailed(String error) {
    return 'Tìm kiếm AI không thành công: $error';
  }

  @override
  String get stashAiNoAnswer =>
      'Mô hình không đưa ra câu trả lời có thể sử dụng được.';

  @override
  String get aiModelAuxiliary => 'Tương tự như mô hình phụ trợ';

  @override
  String get aiModelFirst =>
      'Chọn một mô hình trước: Các hành động AI sẽ sử dụng mô hình đó từ đó trở đi';

  @override
  String get aiModelNone => 'chưa có ai được chọn';

  @override
  String aiModelTooltip(String model) {
    return 'Mô hình cho hành động AI: $model';
  }

  @override
  String get stashFilterAnyTime => 'Bất cứ lúc nào';

  @override
  String get stashFilterAnyProject => 'Bất kỳ dự án nào';

  @override
  String get stashFilterAnyStatus => 'Bất kỳ trạng thái nào';

  @override
  String get stashFilterOpen => 'Chưa xong';

  @override
  String get stashGroupPinned => 'Đã ghim';

  @override
  String get stashGroupToday => 'Hôm nay';

  @override
  String get stashGroupYesterday => 'Hôm qua';

  @override
  String get stashGroupWeek => '7 ngày qua';

  @override
  String get stashGroupMonth => '30 ngày qua';

  @override
  String get stashGroupEarlier => 'Trước đó';

  @override
  String get stashGroupDone => 'Xong';

  @override
  String get stashStatus => 'Trạng thái';

  @override
  String get stashStatusCollected => 'Đã sưu tầm';

  @override
  String get stashStatusRequirement => 'Yêu cầu';

  @override
  String get stashStatusImplementing => 'Thực hiện';

  @override
  String get stashStatusDone => 'Xong';

  @override
  String stashEmpty(String hotkey) {
    return 'Chưa có gì được cất giữ.\nNhấn $hotkey trong bất kỳ ứng dụng nào để ghi lại điều gì đó.';
  }

  @override
  String get stashEmptyNoHotkey =>
      'Chưa có gì được cất giữ.\nBấm vào + để viết một cái; đặt một phím tắt trong Cài đặt để ghi lại một phím tắt từ bất kỳ ứng dụng nào.';

  @override
  String get stashNoMatch => 'Không có trận đấu nào.';

  @override
  String get stashPin => 'Ghim';

  @override
  String get stashUnpin => 'Bỏ ghim';

  @override
  String get stashOpenInPanel => 'Mở trong Bảng nổi';

  @override
  String get stashLinkProject => 'Liên kết tới dự án';

  @override
  String get stashMerge => 'Hợp nhất';

  @override
  String stashMergeTitle(String stashes) {
    return 'Hợp nhất $stashes?';
  }

  @override
  String stashMergeDetail(String target) {
    return 'Văn bản của họ lần lượt đi vào $target; những người khác đi, số lượng của họ dẫn đến nó.';
  }

  @override
  String stashMergeSuggestion(String stashes) {
    return '$stashes trông giống như vậy.';
  }

  @override
  String get stashDismiss => 'Miễn nhiệm';

  @override
  String get stashDelete => 'Xóa bỏ';

  @override
  String stashDeleteOne(String stash) {
    return 'Xóa $stash?';
  }

  @override
  String stashDeleteMany(int count) {
    return 'Xóa kho lưu trữ $count?';
  }

  @override
  String get stashDeleteDetail =>
      'Hình ảnh và tệp của họ đi cùng với họ. Điều này không thể hoàn tác được.';

  @override
  String stashPicked(int count) {
    return '$count đã chọn';
  }

  @override
  String get stashMarkDone => 'Đánh dấu xong';

  @override
  String get stashReopen => 'Mở lại';

  @override
  String get stashClearPicked => 'Xóa lựa chọn';

  @override
  String get stashClose => 'Đóng kho';

  @override
  String get stashCloseDetail => 'Đóng';

  @override
  String get stashMore => 'Hơn';

  @override
  String get stashExpand => 'Làm rõ';

  @override
  String get stashExpandHint =>
      'AI đọc ghi chú của bạn một cách rõ ràng, điền vào những gì hình ảnh và tệp của nó hiển thị, không thêm cấu trúc; nó thay thế văn bản và Hoàn tác sẽ lấy lại văn bản đó';

  @override
  String get stashClarifying => 'Làm rõ…';

  @override
  String get stashCancelClarify => 'Dừng làm rõ';

  @override
  String get stashClarifyFailedShort => 'Không làm rõ';

  @override
  String get stashClarifyChanged =>
      'Ghi chú đã thay đổi trong khi nó đang được làm rõ nên không có gì được thay thế. Hãy thử lại.';

  @override
  String get stashRetry => 'Thử lại';

  @override
  String stashExpandFailed(String error) {
    return 'Không thể làm rõ ghi chú: $error';
  }

  @override
  String get stashImplement => 'Triển khai trong BaoCode';

  @override
  String get stashImplementHow => 'Agent nên làm việc như thế nào?';

  @override
  String get stashImplementHowDetail =>
      'Trong một cây công việc git mới (một nhánh của chính nó, bản sao làm việc của bạn chưa được xử lý) hoặc trực tiếp trong dự án.';

  @override
  String get stashImplementWorktree => 'Cây làm việc mới';

  @override
  String get stashImplementDirect => 'Trực tiếp';

  @override
  String stashImplementStarter(String stash) {
    return 'Vui lòng triển khai những gì $stash yêu cầu.';
  }

  @override
  String get stashImplementInWorktree =>
      'Đầu tiên hãy tạo một cây công việc git mới trên một nhánh mới cho công việc này và thực hiện nó ở đó; cho tôi biết chi nhánh khi hoàn thành.';

  @override
  String get stashImplementInPlace =>
      'Làm việc trực tiếp trong dự án này, trên chi nhánh hiện tại.';

  @override
  String get stashImplementComplete =>
      'Khi hoàn thành, đánh dấu nó là xong trong Stash.';

  @override
  String get stashThreads => 'Cuộc trò chuyện';

  @override
  String get stashThreadSource => 'Được lưu ý trong cuộc trò chuyện này';

  @override
  String get stashThreadNoReply => 'Chưa có trả lời';

  @override
  String get stashThreadGone => 'Không còn trong danh sách';

  @override
  String get stashOpenThread => 'Mở';

  @override
  String stashProjectSuggestion(String project) {
    return 'AI cho rằng đây là về $project.';
  }

  @override
  String get stashLinkIt => 'liên kết';

  @override
  String get stashSettingsDescription =>
      'Một ghi chú được ghi lại từ bất kỳ ứng dụng nào, trong một bảng điều khiển nổi, để chuyển thành tác phẩm sau này.';

  @override
  String get stashSettingsHotkey => 'Phím tắt';

  @override
  String stashSettingsHotkeyCurrent(String hotkey) {
    return '$hotkey hiển thị bảng điều khiển từ bất kỳ ứng dụng nào.';
  }

  @override
  String get stashSettingsHotkeyNone =>
      'Không có phím tắt: bảng chỉ hiển thị từ trang Stash.';

  @override
  String get stashSettingsHotkeyTaken =>
      'Một ứng dụng khác giữ phím tắt này; chọn cái khác.';

  @override
  String get stashSettingsHotkeyHelp =>
      'Nhấp, sau đó nhấn các phím mới; Escape giữ nó, Xóa xóa nó.';

  @override
  String get stashHotkeyPress => 'Nhấn phím…';

  @override
  String get stashHotkeyRefused =>
      'Cần một công cụ sửa đổi bằng một chữ cái, chữ số hoặc khóa chung';

  @override
  String get stashHotkeyNone => 'Không có';

  @override
  String get stashHotkeyClear => 'Xóa';

  @override
  String stashHotkeySuggested(String hotkey) {
    return 'Sử dụng $hotkey';
  }

  @override
  String get stashHotkeyGlobal => 'Hiển thị bảng Stash';

  @override
  String get stashHotkeyGlobalHint =>
      'Phím tắt chung: hoạt động từ mọi ứng dụng.';

  @override
  String get stashHotkeyTooltip =>
      'Phím tắt của bảng điều khiển; bấm vào để thay đổi';

  @override
  String get stashSettingsDirectory => 'Vị trí';

  @override
  String get stashSettingsDirectoryChange => 'Thay đổi…';

  @override
  String get stashSettingsDirectoryReset => 'Mặc định';

  @override
  String get stashSettingsDirectoryRestart =>
      'Có hiệu lực sau khi BaoCode khởi động lại.';

  @override
  String get stashAll => 'Tất cả';

  @override
  String get stashAllTooltip => 'Hiển thị mọi kho lưu trữ';

  @override
  String get stashHintSave => 'Cứu';

  @override
  String get stashHintClose => 'Đóng';

  @override
  String get stashSaved => 'Đã lưu';

  @override
  String get stashFilter => 'Lọc';

  @override
  String get stashSort => 'Loại';

  @override
  String get stashSortManual => 'Tùy chỉnh (kéo để đặt hàng)';

  @override
  String get stashSortUpdated => 'Chỉnh sửa lần cuối';

  @override
  String get stashSortCreated => 'Được tạo lần cuối';

  @override
  String get stashSortNumber => 'Con số';

  @override
  String get stashOpen => 'Mở';

  @override
  String stashCount(int count) {
    return 'Kho lưu trữ $count';
  }

  @override
  String get stashFormatMore => 'Hơn';

  @override
  String get branchBarSwitch => 'Chuyển nhánh';

  @override
  String get branchBarSearch => 'Tìm kiếm nhánh';

  @override
  String get branchBarCreate => 'Tạo chi nhánh…';

  @override
  String branchBarCreateFrom(String branch) {
    return 'Tạo một nhánh từ “$branch”';
  }

  @override
  String branchBarCreateIn(String folder) {
    return 'Tạo một nhánh trong “$folder”';
  }

  @override
  String get branchBarCreateButton => 'Tạo nên';

  @override
  String get branchBarDetached => 'ĐẦU tách rời';

  @override
  String branchBarFailed(String branch) {
    return 'Không thể chuyển sang “$branch”';
  }

  @override
  String get branchBarNotRepository => 'Không phải kho lưu trữ Git';

  @override
  String get branchBarWorkspace => 'Các nhánh của thư mục';

  @override
  String get settingsSectionAccounts => 'Tài khoản Git';

  @override
  String get settingsAccountsKeywords =>
      'GitHub GitLab vấn đề đăng nhập mã thông báo đăng nhập pull request yêu cầu hợp nhất';

  @override
  String get accountsDescription =>
      'Đăng nhập vào GitHub, GitLab hoặc Gitee để xem trạng thái của sự cố và lấy các yêu cầu được liên kết trong Stash, nhập sự cố dưới dạng kho lưu trữ và trả lời chúng sau khi bạn xác nhận.';

  @override
  String get accountsSignedIn => 'Đã đăng nhập';

  @override
  String get accountsAdd => 'Thêm tài khoản';

  @override
  String get accountsKeptLocally =>
      'Mã thông báo được lưu giữ trong móc khóa của máy tính này và chỉ được gửi đến GitHub, GitLab hoặc Gitee mà chúng dành cho. Không có gì được đăng mà không có xác nhận của bạn.';

  @override
  String get accountsGitHubHosts =>
      'github.com hoặc GitHub Enterprise của công ty bạn';

  @override
  String get accountsGitLabHosts =>
      'gitlab.com hoặc GitLab tự quản lý (http:// hoặc https://, với cổng của nó)';

  @override
  String get accountsGiteeHosts =>
      'gitee.com, với mã thông báo truy cập cá nhân';

  @override
  String get accountsGitCodeHosts =>
      'gitcode.com, với mã thông báo truy cập cá nhân';

  @override
  String get accountsSignInBrowser => 'Đăng nhập bằng trình duyệt';

  @override
  String get accountsSignInToken => 'Sử dụng mã thông báo…';

  @override
  String get accountsViaBrowser => 'đăng nhập bằng trình duyệt';

  @override
  String get accountsViaToken => 'đã đăng nhập bằng mã thông báo';

  @override
  String get accountsSignOut => 'Đăng xuất';

  @override
  String accountsSignOutTitle(String login, String forge) {
    return 'Đăng xuất khỏi tài khoản $forge $login?';
  }

  @override
  String accountsSignOutDetail(String forge) {
    return 'Mã thông báo sẽ bị xóa khỏi máy tính này. Để thu hồi hoàn toàn quyền truy cập của BaoCode, hãy thu hồi nó trong cài đặt $forge của bạn.';
  }

  @override
  String accountsRevoke(String forge) {
    return 'Đăng xuất và mở cài đặt $forge';
  }

  @override
  String accountsTokenTitle(String forge) {
    return 'Đăng nhập vào $forge bằng mã thông báo';
  }

  @override
  String get accountsSignIn => 'Đăng nhập';

  @override
  String get accountsHost => 'Máy chủ';

  @override
  String get accountsToken => 'Mã thông báo';

  @override
  String get accountsTokenGitHubScopes =>
      'Mã thông báo cổ điển có phạm vi repo và đọc:người dùng hoặc mã thông báo chi tiết có quyền truy cập đọc và ghi đối với các vấn đề và pull request.';

  @override
  String get accountsTokenGitLabScopes =>
      'Mã thông báo truy cập cá nhân có phạm vi api.';

  @override
  String get accountsTokenGiteeScopes =>
      'Mã thông báo truy cập cá nhân có phạm vi user_info, dự án, pull_requests, vấn đề và ghi chú.';

  @override
  String get accountsTokenGitCodeScopes =>
      'Mã thông báo truy cập cá nhân có thể đọc thông tin người dùng của bạn cũng như đọc và ghi các kho lưu trữ, các vấn đề và pull request.';

  @override
  String accountsTokenCreate(String host) {
    return 'Tạo Token trên $host';
  }

  @override
  String get accountsTokenRefused =>
      'Mã thông báo không được chấp nhận. Kiểm tra xem nó đã hoàn thành và chưa hết hạn.';

  @override
  String get accountsCertificateTitle => 'Chứng chỉ không đáng tin cậy';

  @override
  String accountsCertificateDetail(
    String host,
    String issuer,
    String fingerprint,
  ) {
    return 'Không thể xác minh chứng chỉ $host ($issuer).\n\nDấu vân tay SHA-256:\n$fingerprint\n\nViệc tin tưởng nó sẽ cho phép BaoCode tiếp cận máy chủ này và chỉ chứng chỉ có dấu vân tay này mới được chấp nhận. Bạn được hỏi lại nếu chứng chỉ thay đổi.';
  }

  @override
  String get accountsCertificateTrust => 'Tin tưởng và tiếp tục';

  @override
  String accountsBrowserTitle(String forge) {
    return 'Đăng nhập vào $forge';
  }

  @override
  String accountsBrowserDetail(String host) {
    return 'Nhập mã này vào $host để BaoCode truy cập vào tài khoản của bạn:';
  }

  @override
  String get accountsCopyAndOpen => 'Sao chép mã và mở trình duyệt';

  @override
  String get accountsOpenAgain => 'Đã sao chép · Mở lại';

  @override
  String get accountsBrowserStarting => 'Đang nhận mã…';

  @override
  String get accountsBrowserWaiting =>
      'Đang chờ bạn ủy quyền trên trình duyệt…';

  @override
  String get accountsRetry => 'Thử lại';

  @override
  String get forgeStateOpen => 'Mở';

  @override
  String get forgeStateDraft => 'Bản nháp';

  @override
  String get forgeStateClosed => 'Đã đóng';

  @override
  String get forgeStateMerged => 'Đã hợp nhất';

  @override
  String get forgeChecksPassed => 'Kiểm tra đã được thông qua';

  @override
  String get forgeChecksFailed => 'Kiểm tra không thành công';

  @override
  String get forgeChecksRunning => 'Kiểm tra đang chạy';

  @override
  String get stashIssues => 'Sự cố và pull request';

  @override
  String stashIssueClosedBanner(String tag) {
    return '$tag đã bị đóng. Việc cất giấu này cũng đã xong rồi phải không?';
  }

  @override
  String stashIssueOpenBanner(String tag) {
    return 'Việc lưu trữ này đã hoàn tất, nhưng $tag vẫn mở.';
  }

  @override
  String get stashIssueReplyClose => 'Trả lời và đóng…';

  @override
  String stashIssueNotSignedIn(String forge) {
    return 'Đăng nhập vào $forge để xem trạng thái của nó';
  }

  @override
  String get stashIssueSignIn => 'Đăng nhập…';

  @override
  String get stashIssueFailed => 'Không thể làm mới';

  @override
  String get stashIssueOpen => 'Mở trong trình duyệt';

  @override
  String get stashIssueCopy => 'Sao chép liên kết';

  @override
  String get stashIssueComment => 'Bình luận…';

  @override
  String get stashIssueClose => 'Đóng vấn đề…';

  @override
  String get stashIssueUnlink => 'Hủy liên kết';

  @override
  String stashWriteFixedIn(String pulls) {
    return 'Đã sửa lỗi trong $pulls.';
  }

  @override
  String stashWriteTitle(String tag) {
    return 'Bình luận về $tag';
  }

  @override
  String stashWriteCloseTitle(String tag) {
    return 'Đóng $tag';
  }

  @override
  String get stashWriteSend => 'Bình luận';

  @override
  String get stashWriteSendClose => 'Bình luận và Đóng';

  @override
  String get stashWriteCloseOnly => 'Đóng vấn đề';

  @override
  String get stashWriteSendAnyway => 'Vẫn gửi';

  @override
  String get stashWritePlaceholder => 'Viết bình luận (Markdown)';

  @override
  String get stashWriteAlsoClose => 'Đóng vấn đề quá';

  @override
  String get stashWriteSensitive =>
      'Có vẻ như nó có đường dẫn trên máy tính này hoặc các bí mật mà mọi người có thể nhìn thấy sự cố sẽ thấy:';

  @override
  String stashWriteAs(String login, String host) {
    return 'Được đăng với tên $login trên $host.';
  }

  @override
  String stashWriteFailed(String error) {
    return 'Chưa gửi: $error';
  }

  @override
  String get stashImport => 'Nhập từ Vấn đề…';

  @override
  String get stashImportTitle => 'Vấn đề nhập khẩu';

  @override
  String get stashImportAction => 'Nhập khẩu';

  @override
  String stashImportCount(int count) {
    return 'Nhập $count';
  }

  @override
  String get stashImportPaste => 'Dán một vấn đề hoặc kéo liên kết yêu cầu';

  @override
  String get stashImportAdd => 'Thêm vào';

  @override
  String get stashImportNotALink =>
      'Không phải vấn đề về GitHub, GitLab hoặc Gitee hoặc liên kết pull request.';

  @override
  String stashImportSignIn(String forge) {
    return 'Đăng nhập vào $forge trong Cài đặt → Tài khoản để liệt kê các vấn đề.';
  }

  @override
  String get stashImportRepo => 'Kho lưu trữ';

  @override
  String get stashImportAssigned => 'Đã giao cho tôi';

  @override
  String get stashImportCreated => 'Được tạo bởi tôi';

  @override
  String get stashImportAll => 'Tất cả đều mở';

  @override
  String get stashImportSearch => 'Tìm kiếm';

  @override
  String get stashImportLoading => 'Đang tải…';

  @override
  String get stashImportNoRepos =>
      'Không có dự án nào có điều khiển từ xa GitHub, GitLab hoặc Gitee. Dán liên kết vấn đề ở trên.';

  @override
  String get stashImportNone => 'Không có vấn đề mở ở đây.';

  @override
  String stashImportKnown(int id) {
    return 'trong Stash #$id';
  }

  @override
  String sidebarOpenPull(String tag) {
    return 'Mở $tag';
  }

  @override
  String get stashGroupOthers => 'Người khác';

  @override
  String stashFilterProjects(int count) {
    return 'Dự án $count';
  }

  @override
  String get stashFilterJoiner => ', ';

  @override
  String get stashWelcomeTitle => 'Gặp gỡ Stash';

  @override
  String get stashWelcomeLead =>
      'Hãy ghi lại mọi thứ ngay khi chúng đến với bạn, giao chúng cho agent khi bạn đã sẵn sàng và xem từng việc diễn ra như thế nào.';

  @override
  String get stashWelcomeNoteTitle => 'Hãy ghi chú nó xuống';

  @override
  String get stashWelcomeAgentTitle => 'Đưa nó cho một agent';

  @override
  String get stashWelcomeAgent =>
      'Nhấp vào Thực hiện trong BaoCode hoặc đề cập đến nó trong cuộc trò chuyện; cuộc trò chuyện và kho lưu trữ vẫn được liên kết.';

  @override
  String get stashWelcomeTrackTitle => 'Xem nó diễn ra thế nào';

  @override
  String get stashWelcomeTrack =>
      'Các thẻ hiển thị trực tiếp cuộc trò chuyện và đồng bộ các issue, pull request liên kết trên GitHub, GitLab và Gitee.';

  @override
  String get stashWelcomeStart => 'Bắt đầu';

  @override
  String get stashWelcomeNoteBody =>
      'Bạn có thể thêm văn bản, ảnh chụp màn hình và liên kết; mỗi mục được đánh số riêng như một issue.';

  @override
  String get stashWelcomeHotkeyTitle => 'Đặt lối tắt để ghi chú mọi thứ';

  @override
  String get stashWelcomeHotkeySetTitle => 'Bộ phím tắt';

  @override
  String get stashWelcomeHotkey =>
      'Nhấn nó trong bất kỳ ứng dụng nào và bảng Stash xuất hiện, sẵn sàng để nhập. Bấm vào hộp bên dưới và nhấn các phím bạn muốn.';

  @override
  String stashWelcomeHotkeySet(String hotkey) {
    return 'Nhấn $hotkey trong bất kỳ ứng dụng nào để ghi chú điều gì đó. Thay đổi nó ở đây hoặc trong Cài đặt → Cất giữ bất cứ lúc nào.';
  }

  @override
  String get stashWelcomeHotkeyLater =>
      'Bạn cũng có thể thiết lập nó sau trong Cài đặt → Stash.';

  @override
  String get settingsSectionBrowser => 'Trình duyệt';

  @override
  String get settingsBrowserKeywords =>
      'Agent tab trang web Brave Arc Edge tiện ích mở rộng Chrome';

  @override
  String get browserSettingsDescription =>
      'Hãy để các agent sử dụng trình duyệt của riêng bạn, đăng nhập với tư cách là bạn: mở các trang, đọc chúng, nhấp và nhập các tab bạn chia sẻ với họ. Bạn có thể xem từng bước trong bảng điều khiển bên.';

  @override
  String get browserSettingsUnsupported =>
      'Trình duyệt chỉ khả dụng trên macOS, Windows và Linux.';

  @override
  String get browserSettingsEnabled => 'Cho phép agent sử dụng trình duyệt';

  @override
  String get browserSettingsEnabledDescription =>
      'Khi tắt, các tác nhân không có công cụ trình duyệt và tiện ích mở rộng sẽ ngắt kết nối.';

  @override
  String get browserSettingsStatus => 'Trạng thái';

  @override
  String get browserSettingsStatusDescription =>
      'Agent sử dụng trình duyệt được đánh dấu Đang sử dụng; chọn cái khác để chuyển đổi.';

  @override
  String get browserSettingsNotInstalled =>
      'Chưa có trình duyệt nào được kết nối';

  @override
  String get browserSettingsNotInstalledDescription =>
      'Cài đặt tiện ích mở rộng theo cách bên dưới, sau đó mở trình duyệt: tiện ích mở rộng này sẽ tự động kết nối.';

  @override
  String get browserSettingsNotRunning =>
      'Không có trình duyệt nào được kết nối';

  @override
  String get browserSettingsNotRunningDescription =>
      'Mở trình duyệt có tiện ích mở rộng của BaoCode: nó tự động kết nối.';

  @override
  String get browserSettingsSandboxed =>
      'Trình duyệt Snap và Flatpak không thể kết nối';

  @override
  String get browserSettingsSandboxedDescription =>
      'Hộp cát của họ ngăn không cho trình trợ giúp của BaoCode chạy. Thay vào đó, hãy cài đặt trình duyệt từ gói .deb hoặc .rpm của riêng nó, chẳng hạn như Google Chrome từ google.com/chrome.';

  @override
  String browserSettingsConnected(String browser) {
    return 'Đã kết nối $browser';
  }

  @override
  String browserSettingsIncompatible(String browser) {
    return '$browser: phiên bản tiện ích mở rộng không khớp';
  }

  @override
  String browserSettingsExtensionVersion(String version) {
    return 'Tiện ích mở rộng $version';
  }

  @override
  String get browserSettingsUse => 'Sử dụng trình duyệt này';

  @override
  String get browserSettingsUsing => 'Đang sử dụng';

  @override
  String get browserSettingsChosenMissing =>
      'Trình duyệt đã chọn chưa được kết nối';

  @override
  String browserSettingsChosenMissingDescription(String path, String browser) {
    return '$path: các tác nhân sử dụng $browser cho đến khi kết nối lại.';
  }

  @override
  String get browserSettingsExtensionOld =>
      'Phần mở rộng đã lỗi thời. Từ cửa hàng, nó sẽ tự động cập nhật hoặc nhấp vào Cập nhật trong chrome://extensions; được cài đặt thủ công, tải lại zip xuống, thay thế nội dung của thư mục và nhấp vào tải lại.';

  @override
  String get browserSettingsAppOld =>
      'Tiện ích mở rộng mới hơn BaoCode này. Cập nhật BaoCode.';

  @override
  String get browserSettingsNoFileAccess => 'Quyền truy cập tệp bị tắt';

  @override
  String get browserSettingsNoFileAccessDescription =>
      'Nhân viên không thể mở tệp HTML cục bộ hoặc tải tệp lên. Trong chrome://extensions, nhấp vào Chi tiết trên BaoCode và bật Cho phép truy cập URL tệp.';

  @override
  String get browserSettingsInstall => 'Nhận tiện ích mở rộng';

  @override
  String get browserSettingsStore => 'Cửa hàng Chrome trực tuyến';

  @override
  String get browserSettingsStoreDescription =>
      'Khuyến khích. Cập nhật tự động; hoạt động trong Chrome, Edge, Brave, Arc và các trình duyệt Chrome khác.';

  @override
  String get browserSettingsStoreOpen => 'Mở cửa hàng';

  @override
  String get browserSettingsUnpacked =>
      'Cài đặt thủ công (Chế độ nhà phát triển)';

  @override
  String get browserSettingsUnpackedDescription =>
      'Giải nén nó vào một thư mục bạn sẽ giữ. Trong chrome://extensions, bật Chế độ nhà phát triển ở trên cùng bên phải, nhấp vào Tải giải nén và chọn thư mục. Nó không tự động cập nhật.';

  @override
  String get browserSettingsUnpackedDownload => 'Tải xuống Zip';

  @override
  String get browserSettingsOpen => 'Cài đặt trình duyệt';

  @override
  String get browserHistoryTitle => 'Lịch sử gỡ lỗi';

  @override
  String get browserHistoryDescription =>
      'Những gì các tab được chia sẻ với BaoCode thực hiện sẽ được giữ nguyên như cũ, không cần ghi lại: các trang, yêu cầu, lỗi và cảnh báo trên bảng điều khiển. Nhân viên nhìn lại khi bạn hỏi (“nó không thành công khi tôi lưu”). Được lưu giữ trên máy tính này; cookie và mã thông báo thì không.';

  @override
  String get browserHistoryDetailed => 'Lịch sử chi tiết';

  @override
  String get browserHistoryDetailedDescription =>
      'Đồng thời lưu giữ nội dung yêu cầu và phản hồi, những gì bạn làm (nhấp và nhập, không bao giờ nhập mật khẩu) và mọi thông báo trên bảng điều khiển. Tốn nhiều không gian hơn.';

  @override
  String browserHistorySize(String size) {
    return 'Sử dụng $size';
  }

  @override
  String get browserHistoryClear => 'Xóa';

  @override
  String get browserHistoryClearConfirm => 'Xóa lịch sử gỡ lỗi?';

  @override
  String get browserHistoryClearDetail =>
      'Các trang, yêu cầu và thông báo trên bảng điều khiển được lưu giữ sẽ bị xóa. Điều này không thể hoàn tác được.';

  @override
  String browserHistoryTooLarge(String size) {
    return 'Lịch sử gỡ lỗi của trình duyệt mất $size';
  }

  @override
  String get browserHistoryTooLargeDetail =>
      'Xóa nó hoặc xem nó trong Cài đặt → Trình duyệt.';

  @override
  String get browserHistoryOpenSettings => 'Cài đặt trình duyệt';

  @override
  String get browserWelcomeTitle =>
      'Agent có thể sử dụng trình duyệt của bạn bây giờ';

  @override
  String get browserWelcomeLead =>
      'Với tiện ích mở rộng BaoCode, agent có thể mở trang, đọc, nhấp và nhập nội dung ngay trong Chrome của bạn, với phiên đăng nhập hiện tại.';

  @override
  String get browserWelcomeSharedTitle => 'Chỉ các tab bạn chia sẻ';

  @override
  String get browserWelcomeShared =>
      'Chúng hoạt động riêng trong nhóm tab BaoCode màu vàng; các tab khác vẫn là của bạn.';

  @override
  String get browserWelcomeWatchTitle => 'Xem nó hoạt động';

  @override
  String get browserWelcomeWatch =>
      'Bảng điều khiển bên hiển thị trang trực tiếp khi nhân viên sử dụng nó. Tiếp quản bất cứ lúc nào.';

  @override
  String get browserWelcomeShowTitle => 'Hiển thị nó một lần';

  @override
  String get browserWelcomeShow =>
      'Hãy yêu cầu một nhân viên xem, tự mình thực hiện việc đó trên trình duyệt và nhân viên đó sẽ thấy từng bước bạn đã thực hiện.';

  @override
  String get browserWelcomeInstallTitle => 'Thêm phần mở rộng';

  @override
  String get browserWelcomeInstall =>
      'Dành cho Chrome, Edge, Brave và Arc. Nó tự kết nối và nó chuyển sang màu xanh lục.';

  @override
  String get browserWelcomeTurnedOff =>
      'Trình duyệt bị tắt trong Cài đặt → Trình duyệt.';

  @override
  String browserWelcomeConnected(String browser) {
    return '$browser được kết nối';
  }

  @override
  String get browserWelcomeTry =>
      'Hãy thử nói với nhân viên hỗ trợ: “Mở baocode.dev và xem trang tải xuống.”';

  @override
  String get browserWelcomeUnpacked => 'Zip chế độ nhà phát triển';

  @override
  String get browserWelcomeDone => 'Hiểu rồi';

  @override
  String get cmdBrowserWelcome => 'Kết nối trình duyệt của bạn...';

  @override
  String get cmdStashWelcome => 'Gặp Stash...';

  @override
  String get cmdModelWelcome => 'Thiết lập một mô hình...';

  @override
  String get modelWelcomeTitle => 'Chọn một mô hình để bắt đầu';

  @override
  String get modelWelcomeLead =>
      'BaoCode điều hành các agent của bạn theo mô hình bạn chọn. Thêm một dịch vụ ngược dòng, một dịch vụ có khóa API và các mô hình của nó đã sẵn sàng để sử dụng.';

  @override
  String get modelWelcomeAnyTitle => 'Bất kỳ thượng nguồn nào';

  @override
  String get modelWelcomeAny =>
      'API của Anthropic, Hoàn thành hoặc Phản hồi trò chuyện của OpenAI hoặc dịch vụ nói một trong số chúng, chẳng hạn như OpenRouter hoặc DeepSeek.';

  @override
  String get modelWelcomeKeysTitle => 'Chìa khóa của bạn luôn ở bên bạn';

  @override
  String get modelWelcomeKeys =>
      'Các khóa được lưu trong chuỗi khóa hệ thống và các yêu cầu sẽ đi thẳng từ máy tính này lên thượng nguồn.';

  @override
  String get modelWelcomeSwitchTitle => 'Chuyển đổi bất cứ lúc nào';

  @override
  String get modelWelcomeSwitch =>
      'Thêm nhiều nội dung ngược dòng hơn bất cứ khi nào bạn muốn và chọn mô hình cho mỗi cuộc hội thoại dưới đầu vào của nó.';

  @override
  String get modelWelcomeStepTitle => 'Thêm thượng nguồn đầu tiên của bạn';

  @override
  String get modelWelcomeStep =>
      'Địa chỉ và khóa của nó, sau đó là mẫu máy sẽ sử dụng. Một số dịch vụ cũng có thể thêm dịch vụ của chúng chỉ bằng một cú nhấp chuột từ Cài đặt → Kiểu máy.';

  @override
  String get modelWelcomeReadyTitle => 'Sẵn sàng để đi';

  @override
  String modelWelcomeReady(String model) {
    return 'Cuộc trò chuyện mới bắt đầu trên $model. Chọn một cái khác dưới đầu vào bất cứ lúc nào.';
  }

  @override
  String get modelWelcomeLater =>
      'Bạn cũng có thể thêm một cái sau trong Cài đặt → Kiểu máy.';

  @override
  String get modelWelcomeSkip => 'Sau đó';

  @override
  String get modelWelcomeStart => 'Bắt đầu trò chuyện';

  @override
  String get healthNoModel =>
      'Chọn một mô hình để bắt đầu: thêm một mô hình ngược dòng và các mô hình của nó đã sẵn sàng để sử dụng.';

  @override
  String get modelSetUp => 'Thiết lập một mô hình';

  @override
  String get remoteAddServer => 'Thêm máy chủ SSH...';

  @override
  String get remoteEditServer => 'Biên tập';

  @override
  String get settingsSectionSsh => 'Máy chủ SSH';

  @override
  String get settingsSshKeywords =>
      'ssh máy chủ từ xa máy chủ nhảy pháo đài lõi mật khẩu';

  @override
  String get sshSettingsDescription =>
      'Các dự án từ xa của máy chủ kết nối với: địa chỉ của chúng, cách chúng đăng nhập, máy chủ nhảy và lõi mà mỗi dự án chạy.';

  @override
  String get sshSettingsServers => 'Máy chủ';

  @override
  String get sshSettingsServersDescription =>
      'Những thứ được thêm vào trong ứng dụng và máy chủ mà thanh bên có.';

  @override
  String get sshSettingsNone => 'Chưa có máy chủ';

  @override
  String get sshSettingsAdd => 'Thêm máy chủ…';

  @override
  String get sshSettingsEdit => 'Biên tập…';

  @override
  String get sshSettingsConnect => 'Kết nối';

  @override
  String get sshSettingsDisconnect => 'Ngắt kết nối';

  @override
  String sshSettingsDisconnectTitle(String host) {
    return 'Ngắt kết nối khỏi $host?';
  }

  @override
  String get sshSettingsDisconnectDetail =>
      'Các cuộc hội thoại và Terminal đang chạy ở đó kết thúc.';

  @override
  String sshSettingsCore(String core) {
    return 'Cốt lõi: $core';
  }

  @override
  String sshSettingsVia(String host) {
    return 'thông qua $host';
  }

  @override
  String get sshSettingsTyped => 'Như đã gõ';

  @override
  String get sshSettingsConfigHosts => 'Máy chủ của ~/.ssh/config';

  @override
  String get sshSettingsConfigHostsDescription =>
      'Đã thay đổi trong tệp đó; cốt lõi của họ là Tự động.';

  @override
  String get sshSettingsOpenConfig => 'Mở tệp';

  @override
  String get sshServerAddTitle => 'Thêm máy chủ SSH';

  @override
  String get sshServerAddSubtitle =>
      'Đã lưu vào danh sách từ xa: kết nối với nó chỉ bằng một cú nhấp chuột.';

  @override
  String sshServerEditTitle(String name) {
    return 'Chỉnh sửa $name';
  }

  @override
  String get sshServerHost => 'Chủ nhà';

  @override
  String get sshServerHostPlaceholder =>
      'Tên miền hoặc IP; user@host:port được chia nhỏ';

  @override
  String get sshServerPort => 'Cảng';

  @override
  String get sshServerUser => 'người dùng';

  @override
  String get sshServerName => 'Tên (tùy chọn)';

  @override
  String get sshServerNamePlaceholder => 'ví dụ. Sản xuất';

  @override
  String get sshServerAuth => 'Đăng nhập bằng';

  @override
  String get sshServerAuthPassword => 'Mật khẩu';

  @override
  String get sshServerAuthKey => 'Khóa riêng';

  @override
  String get sshServerAuthAuto => 'Tự động';

  @override
  String get sshServerAuthAutoHint =>
      'Giống như ssh thực hiện trong terminal: ssh-agent, các khóa trong ~/.ssh, ~/.ssh/config. Mật khẩu được yêu cầu nếu máy chủ muốn.';

  @override
  String get sshServerPasswordHint =>
      'Được giữ trong móc khóa hệ thống. Để trống để được hỏi khi kết nối.';

  @override
  String get sshServerPasswordKept => 'Đã lưu: để trống để giữ lại';

  @override
  String get sshServerKeyPlaceholder =>
      'Đường dẫn của khóa riêng, ví dụ: ~/.ssh/id_ed25519';

  @override
  String get sshServerKeyBrowse => 'Duyệt...';

  @override
  String get sshServerKeysFound => 'Các khóa trong ~/.ssh';

  @override
  String get sshServerKeyHint =>
      'Nếu khóa có cụm mật khẩu, nó sẽ được yêu cầu khi kết nối.';

  @override
  String get sshServerCore => 'Cốt lõi';

  @override
  String get sshServerCoreAuto => 'Tự động';

  @override
  String get sshServerCoreAutoHint =>
      'Claude Code CLI của máy chủ nếu có, nếu không thì có lõi tích hợp.';

  @override
  String get sshServerCoreBuiltinHint =>
      'Cốt lõi riêng của BaoCode: nó chạy trên thượng nguồn của Cài đặt → Mô hình.';

  @override
  String get sshServerCoreCliHint =>
      'Claude Code CLI của máy chủ, được cài đặt ở đó nếu không có.';

  @override
  String get sshServerJump => 'Máy chủ nhảy (tùy chọn)';

  @override
  String get sshServerNoJump => 'Không: kết nối trực tiếp';

  @override
  String get sshServerSaveConnect => 'Lưu và kết nối';

  @override
  String get sshServerSave => 'Cứu';

  @override
  String get sshServerHostRequired => 'Nhập tên miền hoặc IP của máy chủ';

  @override
  String get sshServerHostInvalid =>
      'Không có dấu cách và không bắt đầu bằng \'-\'';

  @override
  String get sshServerPortInvalid => 'Một cổng từ 1 đến 65535';

  @override
  String get sshServerKeyRequired => 'Chọn tệp khóa riêng';

  @override
  String get sshServerKeyMissing => 'Không có tệp như vậy';

  @override
  String get remoteForgetHostKey => 'Xóa khóa cũ và kết nối';

  @override
  String remoteForgetHostKeyTitle(String host) {
    return 'Xóa key cũ của $host?';
  }

  @override
  String get remoteForgetHostKeyDetail =>
      'Chỉ khi bạn biết máy chủ đã được cài đặt lại hoặc khóa của nó đã thay đổi: nếu không thì ai đó có thể đứng giữa bạn và nó. Chìa khóa hiện có được chấp nhận ở lần kết nối tiếp theo.';

  @override
  String get remoteForgetHostKeyButton => 'Xóa và kết nối';

  @override
  String get remoteFailNoSsh =>
      'Không có ssh trên máy tính này: cài đặt ứng dụng khách OpenSSH.';

  @override
  String get remoteFailAuth =>
      'Máy chủ từ chối đăng nhập: kiểm tra người dùng, mật khẩu hoặc khóa.';

  @override
  String get remoteFailCancelled => 'Đăng nhập đã bị hủy.';

  @override
  String get remoteFailHostKey =>
      'Khóa của máy chủ không được biết và cấu hình ssh của bạn cho biết không chấp nhận khóa mới (StrictHostKeyChecking).';

  @override
  String get remoteFailHostKeyChanged =>
      'Khóa của máy chủ đã thay đổi kể từ lần kết nối cuối cùng: nó đã được cài đặt lại hoặc có ai đó ở giữa.';

  @override
  String get remoteFailUnreachable =>
      'Không thể truy cập máy chủ: kiểm tra địa chỉ, cổng và mạng.';

  @override
  String get remoteFailWsl =>
      'WSL không thể khởi động bản phân phối này: hãy kiểm tra xem WSL đã được cài đặt chưa và bản phân phối đó có được liệt kê bởi wsl --list hay không.';

  @override
  String get channelSetupTitle => 'Chào mừng đến với BaoCode';

  @override
  String get channelSetupLead =>
      'Hoàn tất quá trình thiết lập lần đầu của bạn trên baocode.dev. Mất khoảng 10 giây.';

  @override
  String get channelSetupStepTitle =>
      'Hoàn tất thiết lập trong trình duyệt của bạn';

  @override
  String get channelSetupStep =>
      'BaoCode mở baocode.dev trong trình duyệt của bạn. Khi trang thông báo đã hoàn tất, BaoCode sẽ tự động tiếp tục.';

  @override
  String get channelSetupWaitingTitle => 'Đang chờ trình duyệt của bạn…';

  @override
  String get channelSetupWaiting =>
      'Khi trang thông báo đã hoàn tất, BaoCode sẽ tự động tiếp tục. Đóng trang do nhầm lẫn? Mở nó lại.';

  @override
  String get channelSetupOpenFailedTitle => 'Trình duyệt của bạn không mở';

  @override
  String get channelSetupOpenFailed =>
      'Sao chép địa chỉ này và mở nó trong trình duyệt của bạn. Khi trang thông báo đã hoàn tất, BaoCode sẽ tự động tiếp tục.';

  @override
  String get channelSetupAddressCopied => 'Đã sao chép';

  @override
  String get channelSetupOffline =>
      'Không thể truy cập baocode.dev. Bạn cần trực tuyến để hoàn tất quá trình thiết lập.';

  @override
  String get channelSetupRetry => 'Thử lại';

  @override
  String get channelSetupDoneTitle => 'Thiết lập hoàn tất';

  @override
  String get channelSetupOpen => 'Hoàn tất thiết lập trong trình duyệt';

  @override
  String get channelSetupOpenAgain => 'Mở lại trang';

  @override
  String get channelSetupNoResponse => 'Trình duyệt không phản hồi?';

  @override
  String get channelSetupPasteLead =>
      'Nếu trang hiển thị liên kết, hãy sao chép và dán vào đây:';

  @override
  String get channelSetupPasteConfirm => 'ĐƯỢC RỒI';

  @override
  String get channelSetupLinkInvalid =>
      'Đó không phải là liên kết từ trang. Sao chép toàn bộ liên kết hiển thị ở đó.';

  @override
  String get channelSetupLinkOther =>
      'Liên kết đó dành cho một bản cài đặt BaoCode khác. Sử dụng trang BaoCode này đã mở.';

  @override
  String get channelSetupTrouble => 'Gặp rắc rối?';

  @override
  String get channelSetupOnceTitle => 'Chỉ một lần';

  @override
  String get channelSetupOnce =>
      'Sau khi hoàn tất, thông tin này sẽ không hiển thị lại, kể cả sau khi cập nhật.';

  @override
  String get channelSetupPrivateTitle => 'Không có gì cá nhân';

  @override
  String get channelSetupPrivate =>
      'Trang này chỉ cho BaoCode biết bạn biết đến nó từ đâu, chẳng hạn như video hoặc trang web.';

  @override
  String get channelSetupFindingTitle => 'Đang chuẩn bị kênh của bạn…';

  @override
  String get channelSetupFinding => 'Chỉ một lát thôi.';

  @override
  String get channelSetupSiteOfflineTitle => 'Không thể truy cập baocode.dev';

  @override
  String get channelSetupSiteOffline =>
      'BaoCode cần online mới đọc được kênh của bạn. Kiểm tra kết nối của bạn và thử lại.';

  @override
  String get channelSetupUnavailableTitle => 'Kênh này không có sẵn';

  @override
  String get channelSetupUnavailable =>
      'Kênh của trình cài đặt này chưa được thiết lập tài khoản. Nếu bạn đã tải xuống qua kênh khác, hãy xác nhận bạn đến từ đâu trong trình duyệt của mình; nếu không hãy liên hệ với người đã cung cấp cho bạn trình cài đặt hoặc tải xuống phiên bản tiêu chuẩn từ baocode.dev.';

  @override
  String get channelSetupConfirmAgain => 'Xác nhận trong trình duyệt';

  @override
  String channelWelcomeTitle(String channel) {
    return 'Chào mừng đến với $channel';
  }

  @override
  String channelWelcomeText(String channel) {
    return 'Đăng nhập vào tài khoản $channel của bạn để bắt đầu.';
  }

  @override
  String get channelWelcomeSignIn => 'Đăng nhập';

  @override
  String get channelWelcomeSigningIn => 'Đăng nhập vào cửa sổ đã mở…';

  @override
  String get channelWelcomePreparing => 'Đang chuẩn bị…';

  @override
  String channelWelcomeFailed(String error) {
    return 'Không thể hoàn tất đăng nhập: $error';
  }

  @override
  String get channelAccountTitle => 'Tài khoản';

  @override
  String get channelAccountBalance => 'Sự cân bằng';

  @override
  String get channelAccountRefresh => 'Làm cho khỏe lại';

  @override
  String get channelAccountSignOut => 'Đăng xuất';

  @override
  String get channelAccountSignOutTitle => 'Đăng xuất?';

  @override
  String channelAccountSignOutDetail(String channel) {
    return 'Bạn sẽ cần đăng nhập lại vào $channel để tiếp tục sử dụng BaoCode.';
  }

  @override
  String get channelAccountOpenSite => 'Mở trang web';

  @override
  String get channelAccountDefaultModel =>
      'Mô hình mặc định cho các cuộc trò chuyện mới';

  @override
  String get channelAccountNoModels =>
      'Chìa khóa đang sử dụng không đạt được bất kỳ mô hình nào.';

  @override
  String get channelAccountKeys => 'Khóa API của tôi';

  @override
  String get channelAccountCreateKey => 'Tạo khóa';

  @override
  String get channelAccountKeyName => 'Tên';

  @override
  String get channelAccountKeyGroup => 'Nhóm';

  @override
  String get channelAccountUseKey => 'Sử dụng khóa này';

  @override
  String get channelAccountInUse => 'Đang sử dụng';

  @override
  String get channelAccountNoKeys => 'Chưa có khóa API nào.';

  @override
  String get channelAccountSignedOut => 'Bạn chưa đăng nhập.';

  @override
  String get channelAccountUnavailable =>
      'Kênh này không có sẵn. Liên hệ với người đã cung cấp cho bạn trình cài đặt.';

  @override
  String channelAccountFailed(String error) {
    return 'Đã xảy ra lỗi: $error';
  }

  @override
  String channelAccountBlocked(String site, String request) {
    return '$site từ chối kết nối của máy tính này ($request); tường lửa của nó có thể đang chặn IP của mạng hoặc proxy của bạn. Hãy thử mạng khác hoặc truy cập $site mà không cần proxy.';
  }

  @override
  String get settingsSectionAbout => 'Giới thiệu';

  @override
  String get aboutTagline =>
      'Giao diện người dùng máy tính để bàn tuyệt vời, dễ sử dụng dành cho Claude Code, được tích hợp sẵn IDE nhanh một phần nghìn giây.';

  @override
  String aboutVersion(String version, int build) {
    return 'Phiên bản $version ($build)';
  }

  @override
  String aboutRepository(String repository) {
    return '$repository · mã nguồn mở và miễn phí, theo GPL-3.0';
  }

  @override
  String get aboutWebsite => 'Trang web';

  @override
  String get aboutChangelog => 'Nhật ký thay đổi';

  @override
  String get aboutChangelogDetail => 'Mỗi phiên bản đã thay đổi điều gì';

  @override
  String get aboutFeedback => 'Báo cáo sự cố';

  @override
  String get aboutFeedbackDetail =>
      'Mở một vấn đề trên GitHub hoặc xem những vấn đề khác đã được mở';

  @override
  String get aboutOpen => 'Mở';

  @override
  String get aboutDeviceId => 'ID thiết bị';

  @override
  String get aboutCopy => 'Sao chép';

  @override
  String get stashSettingsIssueSync => 'Các vấn đề dưới dạng kho lưu trữ';

  @override
  String get stashSettingsIssueSyncDescription =>
      'Một dự án là kho lưu trữ Git trên GitHub, GitLab hoặc Gitee (đã đăng nhập trong Tài khoản): các vấn đề mở của nó là các kho lưu trữ, mỗi lần một lần, được lưu giữ theo cả hai cách. Một kho đã bị xóa hoặc hủy liên kết khỏi vấn đề của nó sẽ không quay trở lại.';

  @override
  String get stashIssueSyncMine => 'Chỉ những người được tôi giao hoặc mở';

  @override
  String get stashIssueSyncOff => 'Tắt: chỉ những cái được nhập hoặc xuất bản';

  @override
  String get stashIssueLocal => 'Chỉ địa phương';

  @override
  String get stashIssueAllow => 'Cho phép xuất bản dưới dạng vấn đề';

  @override
  String get stashIssueNotPublished => 'Chưa phải là vấn đề';

  @override
  String stashIssuePublishTo(String repo) {
    return 'Đăng thành issue của $repo…';
  }

  @override
  String get stashIssueKeepLocal => 'Giữ nó ở địa phương';

  @override
  String get stashIssuePush => 'Đẩy các thay đổi đối với vấn đề…';

  @override
  String get stashIssuePushShort => 'Push';

  @override
  String get stashIssueTakeRemote =>
      'Loại bỏ các thay đổi cục bộ, sử dụng vấn đề';

  @override
  String get stashIssueUnlinkOwn => 'Hủy liên kết, giữ nó cục bộ';

  @override
  String stashIssueConflict(String tag) {
    return '$tag cũng được thay đổi trong lò rèn. Phiên bản nào để giữ?';
  }

  @override
  String get stashIssueKeepMine => 'Giữ của tôi (đẩy)';

  @override
  String get stashIssueKeepTheirs => 'Sử dụng vấn đề';

  @override
  String stashIssueChangedHere(String tag) {
    return 'Những thay đổi ở đây chưa có trên $tag.';
  }

  @override
  String get stashIssueDiscard => 'Loại bỏ';

  @override
  String stashIssuePublishTitle(String repo) {
    return 'Đăng thành issue của $repo';
  }

  @override
  String stashIssuePushTitle(String tag) {
    return 'Đẩy các thay đổi sang $tag';
  }

  @override
  String get stashIssuePublish => 'Xuất bản';

  @override
  String get stashIssueNoText => '(không có mô tả)';

  @override
  String stashIssuePicturesGitHub(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Các ảnh $count được tải lên nhánh $branch của kho lưu trữ để issue hiển thị chúng.',
      one:
          '1 ảnh được tải lên nhánh $branch của kho lưu trữ để vấn đề hiển thị nó.',
    );
    return '$_temp0';
  }

  @override
  String stashIssuePicturesGitLab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hình ảnh $count được tải lên dự án để vấn đề hiển thị chúng.',
      one: '1 hình ảnh được tải lên dự án, để vấn đề hiển thị.',
    );
    return '$_temp0';
  }

  @override
  String get stashImplementShort => 'Thực hiện';

  @override
  String stashImplementIssue(String issue) {
    return 'Đó là vấn đề $issue: pull request sẽ cho biết nó đã khắc phục được sự cố.';
  }

  @override
  String get stashIssueSyncAll => 'Tất cả các vấn đề mở';

  @override
  String get stashIssueChecking => 'Đang tìm kiếm kho lưu trữ của nó…';

  @override
  String get stashIssueRefresh => 'Làm mới ngay bây giờ';

  @override
  String get stashIssuePublishButton => 'Xuất bản dưới dạng vấn đề';

  @override
  String get stashIssuePushButton => 'Đẩy để phát hành';

  @override
  String get stashIssueLoading => 'Đang tải…';

  @override
  String get stashSyncing => 'Sự cố đồng bộ hóa…';

  @override
  String stashSyncingRepo(String repo, int index, int total) {
    return 'Đang đồng bộ hóa các sự cố của $repo ($index/$total)…';
  }

  @override
  String get stashSyncTooltip => 'Sự cố đồng bộ hóa hiện nay';

  @override
  String stashSyncTooltipLast(String time) {
    return 'Sự cố đồng bộ hóa hiện tại · cuối cùng lúc $time';
  }

  @override
  String stashSyncFailed(String repo, String error) {
    return 'Không thể đồng bộ hóa các sự cố của $repo: $error';
  }

  @override
  String stashSyncSignIn(String forge, String repo, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Đăng nhập vào $forge để biết các vấn đề về $repo và $count, có thêm kho lưu trữ để lưu trữ.',
      one: 'Đăng nhập vào $forge để các vấn đề của $repo được lưu trữ.',
    );
    return '$_temp0';
  }

  @override
  String get stashSyncingEmpty => 'Đang đồng bộ hóa các vấn đề của dự án…';

  @override
  String get stashFilterAnyIssue => 'Bất kỳ nguồn nào';

  @override
  String get stashFilterIssue => 'Vấn đề';

  @override
  String get stashFilterNotIssue => 'Chỉ địa phương';

  @override
  String get stashImplementEmpty =>
      'Viết cái gì đó trước rồi triển khai trong BaoCode';

  @override
  String stashIssueDuplicateBanner(String issue, String stash) {
    return '$issue, của kho $stash được sáp nhập vào kho này, vẫn đang mở. Đóng nó như một bản sao?';
  }

  @override
  String get stashIssueCloseDuplicate => 'Đóng dưới dạng trùng lặp…';

  @override
  String get stashIssueDuplicateNoIssue =>
      'Hợp nhất vào một ghi chú khác; đóng như một bản sao.';

  @override
  String get stashNewsOpened => 'Vấn đề mới';

  @override
  String get stashNewsChanged => 'Đã thay đổi trên lò rèn';

  @override
  String get stashNewsCommented => 'Bình luận mới';

  @override
  String get stashNewsClosed => 'Đóng cửa lò rèn';

  @override
  String get stashNewsReopened => 'Mở lại lò rèn';

  @override
  String stashNewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cập nhật $count',
      one: '1 bản cập nhật',
    );
    return '$_temp0';
  }

  @override
  String get stashNewsCountTooltip =>
      'Chỉ hiển thị các thông tin cập nhật về bạn: các vấn đề của bạn và các pull request, những vấn đề được giao cho bạn hoặc đặt tên cho bạn';

  @override
  String get stashNewsCountTooltipOn =>
      'Chỉ hiển thị các thông tin cập nhật về bạn; bấm vào cho tất cả';

  @override
  String get stashFilterNews => 'Về bạn';

  @override
  String get stashMarkAllSeen => 'Đánh dấu tất cả là đã thấy';

  @override
  String stashIssueComments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bình luận $count',
      one: '1 bình luận',
    );
    return '$_temp0';
  }

  @override
  String get stashIssueDiscussion => 'Cuộc thảo luận';

  @override
  String stashIssueDiscussionAll(int count, String forge) {
    return 'Xem tất cả $count trên $forge';
  }

  @override
  String get stashIssueDiscussionFailed => 'Không thể tải nhận xét.';

  @override
  String get stashIssueDiscussionLoading => 'Đang tải nhận xét…';

  @override
  String stashDeleteAndClose(String issue) {
    return 'Xóa và đóng $issue…';
  }

  @override
  String stashDeleteOpenIssue(String issue) {
    return 'Vấn đề $issue của nó vẫn mở trên lò rèn trừ khi cũng bị đóng.';
  }

  @override
  String stashIssueInSync(String issue) {
    return 'Tương tự với $issue';
  }

  @override
  String stashIssueSyncedAt(String time) {
    return 'đã đồng bộ hóa $time';
  }

  @override
  String get stashIssueNotPushed => 'Đã thay đổi ở đây, chưa được đẩy';

  @override
  String get stashIssueRemoteNewer => 'Đã thay đổi trên lò rèn';

  @override
  String get stashIssueBothChanged => 'Đã thay đổi cả ở đây và trên lò rèn';

  @override
  String get stashIssueDiscussionEmpty => 'Chưa có bình luận nào';

  @override
  String get stashNewsMerged => 'Đã hợp nhất pull request';

  @override
  String get stashNewsChangesRequested => 'Đã yêu cầu thay đổi';

  @override
  String get stashNewsChecksFailed => 'Kiểm tra không thành công';

  @override
  String get stashNewsMarked => 'Đã đánh dấu là chưa đọc';

  @override
  String stashNewsOther(String news) {
    return '$news (không phải về bạn)';
  }

  @override
  String stashNewsSidebar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cập nhật về bạn',
      one: '1 cập nhật về bạn',
    );
    return '$_temp0';
  }

  @override
  String get stashFilterAllNews => 'Mọi cập nhật';

  @override
  String get stashMarkSeen => 'Đánh dấu là đã đọc';

  @override
  String get stashMarkUnseen => 'Đánh dấu là chưa đọc';

  @override
  String stashPullChecksFailedBanner(String pull) {
    return 'Việc kiểm tra $pull không thành công.';
  }

  @override
  String stashPullChangesBanner(String pull) {
    return 'Các thay đổi đã được yêu cầu trên $pull.';
  }

  @override
  String stashPullMergedBanner(String pull) {
    return '$pull đã được hợp nhất. Việc này cũng được thực hiện à?';
  }

  @override
  String get stashPullFix => 'Sửa chữa trong cuộc trò chuyện của nó';

  @override
  String get stashPullView => 'Xem';

  @override
  String stashPullFixChecks(String pull) {
    return 'Việc kiểm tra $pull không thành công. Tìm ra những gì không thành công và sửa chữa nó.';
  }

  @override
  String stashPullFixChanges(String pull) {
    return 'Các thay đổi đã được yêu cầu trên $pull. Đọc đánh giá và thực hiện chúng.';
  }

  @override
  String stashWriteManyTitle(int count) {
    return 'Bình luận về các vấn đề của $count';
  }

  @override
  String stashWriteCloseManyTitle(int count) {
    return 'Đóng các vấn đề về $count';
  }

  @override
  String stashDeleteOpenIssues(int count, String issues) {
    return 'Các vấn đề $issues của họ vẫn được mở trên lò rèn trừ khi cũng bị đóng.';
  }

  @override
  String stashDeleteAndCloseMany(int count) {
    return 'Xóa và đóng các vấn đề về $count…';
  }

  @override
  String get gitLogRepository => 'Kho lưu trữ';

  @override
  String get gitLogSearch => 'Tìm kiếm tin nhắn; tách một số bằng |';

  @override
  String get gitLogClearSearch => 'Xóa tìm kiếm';

  @override
  String get gitLogUser => 'người dùng';

  @override
  String get gitLogAllUsers => 'Tất cả người dùng';

  @override
  String get gitLogMe => 'Tôi';

  @override
  String get gitLogDate => 'Ngày';

  @override
  String get gitLogAnyDate => 'Bất cứ lúc nào';

  @override
  String get gitLogLastDay => '24 giờ qua';

  @override
  String get gitLogLastWeek => '7 ngày qua';

  @override
  String get gitLogLastMonth => '30 ngày qua';

  @override
  String get gitLogLastYear => 'Năm ngoái';

  @override
  String get gitLogHighlight => 'Điểm nổi bật';

  @override
  String get gitLogHighlightNone => 'Không có gì';

  @override
  String get gitLogHighlightMine => 'commit của tôi';

  @override
  String get gitLogClearFilters => 'Xóa bộ lọc';

  @override
  String get gitLogCheckout => 'Checkout tới...';

  @override
  String get gitLogSortTopo => 'Thứ tự tôpô';

  @override
  String get gitLogSortDate => 'Thứ tự ngày';

  @override
  String get gitLogLocalBranches => 'nhánh địa phương';

  @override
  String get gitLogRemoteBranches => 'nhánh từ xa';

  @override
  String get gitLogTags => 'Thẻ';

  @override
  String get gitLogBackToLog => 'Quay lại nhật ký';

  @override
  String get gitLogNoCommits => 'Không có commit phù hợp.';

  @override
  String get gitLogLocalChanges => 'Thay đổi cục bộ';

  @override
  String gitLogLocalChangesCount(int count) {
    return 'Thay đổi cục bộ ($count)';
  }

  @override
  String get gitLogSelectCommit => 'Chọn một commit để xem chi tiết của nó.';

  @override
  String get gitLogParents => 'Phụ huynh: ';

  @override
  String gitLogFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các tệp $count',
      one: '1 tệp',
    );
    return '$_temp0';
  }

  @override
  String get gitLogInNoBranch => 'Không có chi nhánh nào có commit này.';

  @override
  String gitLogInBranches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các nhánh $count',
      one: '1 nhánh',
    );
    return 'TRONG $_temp0';
  }

  @override
  String get gitLogList => 'Danh sách';

  @override
  String get gitLogTree => 'Cây';

  @override
  String get gitLogFilterFiles => 'Lọc các tệp (* và ? khớp với bất kỳ)';

  @override
  String get gitLogCopyPath => 'Sao chép đường dẫn';

  @override
  String get gitLogCopyRelativePath => 'Sao chép đường dẫn tương đối';

  @override
  String get gitLogBinary => 'nhị phân';

  @override
  String get gitLogPreviousFile => 'Tệp trước';

  @override
  String get gitLogNextFile => 'Tệp tiếp theo';

  @override
  String get gitLogOpenInEditor => 'Mở trong Trình chỉnh sửa';

  @override
  String get checkpointsTitle => 'Điểm kiểm tra';

  @override
  String get checkpointsDescription =>
      'Ảnh chụp nhanh của các agent dự án làm việc, được lưu giữ để hoàn tác các thay đổi của họ. Cuộc trò chuyện sẽ được sắp xếp gọn gàng sau 30 ngày kể từ lần cuối cùng nó thay đổi bất cứ điều gì.';

  @override
  String checkpointsSize(String size) {
    return 'Sử dụng $size';
  }

  @override
  String get checkpointsMeasuring => 'Đo…';

  @override
  String get checkpointsClear => 'Xóa';

  @override
  String get checkpointsClearing => 'Đang xóa…';

  @override
  String get checkpointsClearConfirm => 'Xóa các điểm kiểm tra?';

  @override
  String get checkpointsClearDetail =>
      'Các tác nhân thay đổi được thực hiện trong các cuộc hội thoại chưa mở sẽ không thể hoàn tác được nữa. Các tệp vẫn giữ nguyên như cũ.';

  @override
  String gitLogToday(String time) {
    return 'Hôm nay $time';
  }

  @override
  String gitLogYesterday(String time) {
    return 'Hôm qua $time';
  }

  @override
  String get gitLogCheckoutRevision => 'Kiểm tra bản sửa đổi';

  @override
  String get gitLogNewBranch => 'Chi nhánh mới…';

  @override
  String gitLogNewBranchAt(String commit) {
    return 'Chi nhánh mới tại $commit';
  }

  @override
  String gitLogCheckoutBranch(String branch) {
    return 'Checkout “$branch”';
  }

  @override
  String get gitLogCopyHash => 'Sao chép toàn bộ hàm băm';

  @override
  String get gitLogCopyRefNames => 'Sao chép tên chi nhánh hoặc thẻ';

  @override
  String gitLogCopyName(String name) {
    return 'Sao chép \'$name\'';
  }

  @override
  String get gitLogLoading => 'Đang tải lịch sử…';

  @override
  String get gitLogWorktree => 'Cây làm việc';

  @override
  String gitLogWorktreeOf(String path) {
    return 'Cây làm việc: $path';
  }

  @override
  String get gitLogFollowAgent => 'Theo dõi agent';

  @override
  String get gitLogAgentHere => 'Agent làm việc ở đây';

  @override
  String gitLogWorktreeAt(String name, String path) {
    return 'Đã kiểm tra trong cây công việc $name\n$path';
  }

  @override
  String get gitLogMainWorktree => 'cây công việc chính';

  @override
  String get gitLogWorktreeMissing => 'mất tích';

  @override
  String branchBarWorktree(String name, String path) {
    return 'Trong cây công việc $name\n$path';
  }

  @override
  String get gitCommitChanges => 'Thay đổi';

  @override
  String get gitCommitUnversioned => 'Tệp không được phiên bản';

  @override
  String get gitCommitConflicts => 'Hợp nhất xung đột';

  @override
  String get gitCommitAmend => 'sửa đổi';

  @override
  String get gitCommitMessage => 'Tin nhắn commit';

  @override
  String get gitCommitButton => 'Commit';

  @override
  String get gitCommitAndPush => 'commit và đẩy';

  @override
  String get gitCommitRollback => 'Quay lại…';

  @override
  String gitCommitRollbackConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các tệp $count',
      one: '1 tệp',
    );
    return 'Lùi lại những thay đổi của $_temp0?';
  }

  @override
  String get gitCommitRollbackDetail =>
      'Họ quay trở lại cách họ đã cam kết lần cuối; các tệp chưa được cam kết sẽ bị xóa.';

  @override
  String get gitCommitRollbackButton => 'Khôi phục';

  @override
  String get gitCommitShowDiff => 'Hiển thị sự khác biệt';

  @override
  String get gitCommitJumpToSource => 'Chuyển đến nguồn';

  @override
  String get gitCommitAddToVcs => 'Thêm vào VCS';

  @override
  String get gitCommitMarkResolved => 'Đánh dấu đã giải quyết';

  @override
  String get gitCommitExpandAll => 'Mở rộng tất cả';

  @override
  String get gitCommitCollapseAll => 'Thu gọn tất cả';

  @override
  String get gitCommitEmptyMessage => 'Nhập một tin nhắn commit.';

  @override
  String get gitCommitNothingSelected => 'Kiểm tra các tệp để commit.';

  @override
  String get gitCommitNoChanges => 'Không có thay đổi cục bộ';

  @override
  String gitCommitSelected(int checked, int total) {
    return 'Đã kiểm tra $checked của các tệp $total';
  }

  @override
  String get gitLogUndoCommit => 'Hoàn tác commit';

  @override
  String get branchBarNewWorktree => 'Cây làm việc mới…';

  @override
  String branchBarNewWorktreeFrom(String branch, String folder) {
    return 'Một nhánh mới từ “$branch”, trong một cây làm việc riêng bên cạnh “$folder”: agent làm việc ở đó, quá trình checkout của bạn vẫn như cũ';
  }

  @override
  String branchBarInWorktree(String name) {
    return 'Trong cây công việc $name';
  }

  @override
  String branchBarWorkIn(String path, String branch) {
    return 'Từ giờ trở đi, hãy làm việc trong $path (nhánh $branch): đọc và chỉnh sửa các tệp và chạy các lệnh ở đó.';
  }

  @override
  String get diffRevertChange =>
      'Hoàn tác thay đổi này (quay lại phía bên trái)';

  @override
  String get diffRemoveChange => 'Hoàn tác thay đổi này (xóa các dòng đã thêm)';

  @override
  String get diffPreviousDifference => 'Sự khác biệt trước đó';

  @override
  String get diffNextDifference => 'Sự khác biệt tiếp theo';

  @override
  String diffDifferenceOf(int current, int count) {
    return '$current của $count';
  }

  @override
  String diffDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count khác biệt',
      one: '1 khác biệt',
      zero: 'Không có khác biệt',
    );
    return '$_temp0';
  }

  @override
  String get diffSettings => 'Cài đặt người xem';

  @override
  String get diffLayoutAuto => 'Bên Nhau Khi Đủ Rộng';

  @override
  String get diffSideBySide => 'Trình xem cạnh nhau';

  @override
  String get diffUnified => 'Trình xem hợp nhất';

  @override
  String get gitDetailsLayout => 'Chi tiết Vị trí';

  @override
  String get gitDetailsLayoutAuto => 'Đúng Khi Đủ Rộng';

  @override
  String get gitDetailsLayoutBeside => 'Phải';

  @override
  String get gitDetailsLayoutBelow => 'Đáy';

  @override
  String get diffIgnoreWhitespace => 'Bỏ qua khoảng trắng ở cuối dòng';

  @override
  String get diffWhitespaceNone => 'Đừng bỏ qua khoảng trắng';

  @override
  String get diffIgnoreAllWhitespace => 'Bỏ qua tất cả khoảng trắng';

  @override
  String get diffCollapseUnchanged => 'Thu gọn các mảnh không thay đổi';

  @override
  String diffUnchangedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dòng không thay đổi',
      one: '1 dòng không thay đổi',
    );
    return '$_temp0';
  }

  @override
  String get diffGoToFile => 'Đi đến tệp đã thay đổi';

  @override
  String get lineChangePrevious => 'Thay đổi trước đó';

  @override
  String get lineChangeNext => 'Thay đổi tiếp theo';

  @override
  String get lineChangeRollback => 'Khôi phục';

  @override
  String get lineChangeShowDiff => 'Hiển thị sự khác biệt';

  @override
  String get lineChangeCopy => 'Sao chép dòng gốc';

  @override
  String get cmdNextChange => 'Đi tới Thay đổi tiếp theo';

  @override
  String get cmdPreviousChange => 'Đi tới Thay đổi trước đó';

  @override
  String get cmdShowNextChange => 'Hiển thị thay đổi tiếp theo';

  @override
  String get cmdShowPreviousChange => 'Hiển thị thay đổi trước đó';

  @override
  String get gitAnnotate => 'Chú thích với Git Blame';

  @override
  String get gitCloseAnnotations => 'Đóng chú thích';

  @override
  String get gitLogCopyPatch => 'Sao chép dưới dạng Bản vá';

  @override
  String get gitLogCherryPick => 'Cherry-Hái';

  @override
  String get gitLogCompareWithLocal => 'So sánh với địa phương';

  @override
  String get gitLogResetToHere => 'Đặt lại chi nhánh hiện tại về đây';

  @override
  String get gitLogResetSoft => 'Mềm mại: giữ các thay đổi theo giai đoạn';

  @override
  String get gitLogResetMixed =>
      'Hỗn hợp: giữ nguyên các thay đổi, không dàn dựng';

  @override
  String get gitLogResetHard => 'Cứng: loại bỏ các thay đổi';

  @override
  String get gitLogResetKeep => 'Keep: giữ những thay đổi cục bộ';

  @override
  String gitLogResetHardConfirm(String branch, String commit) {
    return 'Đặt lại “$branch” thành $commit và loại bỏ mọi thay đổi kể từ đó, đã commit hay chưa?';
  }

  @override
  String get gitLogResetButton => 'Cài lại';

  @override
  String get gitLogRevertCommit => 'Hoàn nguyên commit';

  @override
  String get gitLogEditMessage => 'Chỉnh sửa tin nhắn commit…';

  @override
  String get gitLogDropCommit => 'Bỏ commit';

  @override
  String gitLogDropConfirm(String commit, String subject) {
    return 'Đưa $commit “$subject” ra khỏi chi nhánh?';
  }

  @override
  String get gitLogDropButton => 'Làm rơi';

  @override
  String get gitLogPushUpToHere => 'Đẩy tất cả lên đây';

  @override
  String get gitLogNewTag => 'Thẻ mới…';

  @override
  String gitLogNewTagAt(String commit) {
    return 'Thẻ mới tại $commit';
  }

  @override
  String get gitTagName => 'Tên thẻ';

  @override
  String get gitTagMessage => 'Tin nhắn (tùy chọn: thẻ có chú thích)';

  @override
  String get gitLogCreateTag => 'Tạo thẻ';

  @override
  String get gitLogGoToParent => 'Đi đến commit của Phụ huynh';

  @override
  String get gitLogGoToChild => 'Chuyển đến commit trẻ em';

  @override
  String gitLogComparedWithLocal(String commit) {
    return '$commit ↔ Địa phương';
  }

  @override
  String get gitLogNoDifferences => 'Không có sự khác biệt so với cây làm việc';

  @override
  String get gitLogCopyHashes => 'Sao chép băm commit';

  @override
  String gitLogCherryPickCount(int count) {
    return 'commit Cherry-Pick $count';
  }

  @override
  String get gitLogCompareCommits => 'So sánh các commit';

  @override
  String gitLogRevertCommits(int count) {
    return 'Hoàn nguyên các commit $count';
  }

  @override
  String gitLogSquashCommits(int count) {
    return 'Squash $count commit thành một';
  }

  @override
  String gitLogCommitsSelected(int count) {
    return '$count commit đã chọn';
  }

  @override
  String get gitLogPaths => 'Đường dẫn';

  @override
  String get gitLogAllPaths => 'Tất cả các đường dẫn';

  @override
  String gitLogCurrentFile(String path) {
    return 'Tệp hiện tại: $path';
  }

  @override
  String gitLogCurrentFolder(String path) {
    return 'Thư mục của nó: $path';
  }

  @override
  String gitLogPathCount(int count) {
    return 'Đường dẫn $count';
  }

  @override
  String gitLogLinesOf(String file, int start, int end) {
    return '$file: các đường $start–$end';
  }

  @override
  String get gitShowHistory => 'Hiển thị lịch sử';

  @override
  String get gitShowHistoryForSelection => 'Hiển thị lịch sử lựa chọn';

  @override
  String get gitShowBranches => 'Hiển thị nhánh';

  @override
  String get gitHideBranches => 'Ẩn nhánh';

  @override
  String get gitBranchesFilter => 'Lọc nhánh';

  @override
  String get gitBranchesHead => 'HEAD (Chi nhánh hiện tại)';

  @override
  String get gitBranchCheckout => 'Checkout';

  @override
  String gitBranchNewFrom(String name) {
    return 'Chi nhánh mới từ “$name”…';
  }

  @override
  String gitBranchCheckoutRebase(String current) {
    return 'checkout và Rebase vào “$current”';
  }

  @override
  String gitBranchCompare(String current) {
    return 'So sánh với “$current”';
  }

  @override
  String get gitBranchDiffWorkingTree =>
      'Hiển thị sự khác biệt với cây làm việc';

  @override
  String gitBranchRebaseOnto(String current, String name) {
    return 'Rebase “$current” lên “$name”';
  }

  @override
  String gitBranchMerge(String name, String current) {
    return 'Hợp nhất “$name” thành “$current”';
  }

  @override
  String gitBranchPullRebase(String current) {
    return 'Kéo vào “$current” bằng Rebase';
  }

  @override
  String gitBranchPullMerge(String current) {
    return 'Kéo vào “$current” bằng cách sử dụng Hợp nhất';
  }

  @override
  String get gitBranchUpdate => 'Cập nhật';

  @override
  String get gitBranchPush => 'Push';

  @override
  String gitBranchPushTo(String upstream) {
    return 'Đẩy tới $upstream';
  }

  @override
  String get gitBranchUpstream => 'Thượng nguồn';

  @override
  String get gitBranchUnsetUpstream => 'Bỏ đặt ngược dòng';

  @override
  String get gitBranchRename => 'Đổi tên…';

  @override
  String gitBranchRenameTitle(String name) {
    return 'Đổi tên chi nhánh “$name”';
  }

  @override
  String get gitBranchRenameButton => 'Đổi tên';

  @override
  String get gitBranchFavorite => 'Thêm vào mục yêu thích';

  @override
  String get gitBranchUnfavorite => 'Xóa khỏi Mục yêu thích';

  @override
  String get gitBranchShowOnly => 'Chỉ hiển thị điều này trong nhật ký';

  @override
  String get gitBranchDelete => 'Xóa bỏ';

  @override
  String get gitTagDelete => 'Xóa thẻ';

  @override
  String get gitBranchDeleteButton => 'Xóa bỏ';

  @override
  String gitBranchDeleteRemoteConfirm(String name) {
    return 'Xóa nhánh “$name” trên điều khiển từ xa của nó?';
  }

  @override
  String gitBranchNotMergedConfirm(String name) {
    return '“$name” đã commit không sáp nhập vào chi nhánh nào khác. Vẫn xóa nó đi?';
  }

  @override
  String gitBranchDeleted(String name) {
    return 'Đã xóa nhánh “$name”.';
  }

  @override
  String gitTagDeleted(String name) {
    return 'Đã xóa thẻ “$name”.';
  }

  @override
  String get gitBranchRestore => 'Khôi phục';

  @override
  String gitBranchCompared(String name, String current, int ahead, int behind) {
    return '“$name” có $ahead commit “$current” không có; “$current” có $behind nhưng không có.';
  }

  @override
  String get gitBranchCompareFiles => 'Hiển thị các tệp đã thay đổi';

  @override
  String scmGraphRangeIn(String to, String from) {
    return 'commit trong “$to” Không có trong “$from”';
  }

  @override
  String get gitBranchesRecent => 'Gần đây';

  @override
  String get gitBranchesSearch => 'Tìm kiếm các nhánh và hành động';

  @override
  String get gitUpdateProject => 'Cập nhật dự án';

  @override
  String get gitCommitEllipsis => 'Làm…';

  @override
  String get gitPushEllipsis => 'Xô…';

  @override
  String get gitNewBranchEllipsis => 'Chi nhánh mới…';

  @override
  String get gitCheckoutRevision => 'Thẻ checkout hoặc bản sửa đổi…';

  @override
  String get gitBranchesTitle => 'Nhánh Git';

  @override
  String get gitRevisionPlaceholder => 'Thẻ, nhánh hoặc hàm băm commit';

  @override
  String get gitUpdateProjectDetail =>
      'Đưa nhánh hiện tại của mỗi kho lưu trữ lên thượng nguồn của nó: hợp nhất các commit mới của nó vào hoặc khởi động lại nhánh của chính nhánh đó vào chúng. Trong khi đó, những thay đổi cục bộ được lưu trữ.';

  @override
  String get gitUpdateMerge => 'Hợp nhất';

  @override
  String get gitUpdateRebase => 'Rebase';

  @override
  String get gitDontAskAgain => 'Đừng hỏi lại';

  @override
  String get gitPushTitle => 'Đẩy commit';

  @override
  String get gitPushTags => 'Thẻ đẩy';

  @override
  String get gitPushForce => 'Lực đẩy';

  @override
  String gitPushForceConfirm(String targets) {
    return 'Buộc đẩy tới $targets?';
  }

  @override
  String get gitPushForceDetail =>
      'Những gì ở đó sẽ được thay thế bằng những gì bạn Đẩy (với hợp đồng thuê: chỉ được tìm nạp lần cuối, vì vậy các commit mới hơn của không ai bị mất).';

  @override
  String get gitPushNothing => 'Không có gì để đẩy';

  @override
  String get gitPushRemote => 'Xa';

  @override
  String get gitPushNew => 'mới';

  @override
  String get gitPushSelectCommit => 'Chọn một commit để xem các tệp của nó';

  @override
  String get gitPushEllipsisCommand => 'Xô…';

  @override
  String get gitOperationRebasing => 'Khởi động lại';

  @override
  String get gitOperationMerging => 'Sáp nhập';

  @override
  String get gitOperationCherryPicking => 'Hái anh đào';

  @override
  String get gitOperationReverting => 'Hoàn nguyên';

  @override
  String gitOperationConflicts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Còn $count xung đột',
      one: 'Còn 1 xung đột',
    );
    return '$_temp0';
  }

  @override
  String get gitOperationResolved => 'xung đột được giải quyết';

  @override
  String get gitOperationContinue => 'Tiếp tục';

  @override
  String get gitOperationSkip => 'Nhảy';

  @override
  String get gitOperationAbort => 'Hủy bỏ';

  @override
  String gitOperationAbortConfirm(String what) {
    return 'Hủy bỏ? $what dừng lại và những gì nó đã làm cho đến nay sẽ được hoàn tác.';
  }

  @override
  String get gitConflictAcceptCurrent => 'Chấp nhận hiện tại (của chúng tôi)';

  @override
  String get gitConflictAcceptIncoming => 'Chấp nhận thư đến (của họ)';

  @override
  String get gitConflictMerge => 'Hợp nhất…';

  @override
  String gitMergeTitle(String path) {
    return 'Hợp nhất các bản sửa đổi cho $path';
  }

  @override
  String get gitMergeOurs => 'Hiện tại (của chúng tôi)';

  @override
  String get gitMergeResult => 'Kết quả';

  @override
  String get gitMergeTheirs => 'Đang đến (của họ)';

  @override
  String gitMergeConflictsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Còn $count xung đột',
      one: 'Còn 1 xung đột',
      zero: 'Đã giải quyết tất cả xung đột',
    );
    return '$_temp0';
  }

  @override
  String gitMergeChangesApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các thay đổi $count được áp dụng mà không có xung đột',
      one: '1 thay đổi được áp dụng mà không có xung đột',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get gitMergePrevious => 'Xung đột trước đó';

  @override
  String get gitMergeNext => 'Xung đột tiếp theo';

  @override
  String get gitMergeApply => 'Áp dụng';

  @override
  String get gitMergeAppend => 'Nối thêm';

  @override
  String get gitMergeIgnore => 'Phớt lờ';

  @override
  String get gitMergeAi => 'Hợp nhất với AI';

  @override
  String get gitMergeAiAll => 'Hợp nhất xung đột với AI';

  @override
  String gitMergeAiFailed(String error) {
    return 'AI không thể hợp nhất xung đột: $error';
  }

  @override
  String get gitMergeAiNoAnswer =>
      'câu trả lời không có dòng nào được hợp nhất';

  @override
  String get gitMergeAcceptOurs => 'Chấp nhận hiện tại';

  @override
  String get gitMergeAcceptTheirs => 'Chấp nhận đến';

  @override
  String gitMergeUnresolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Xung đột $count không được giải quyết.',
      one: '1 mâu thuẫn chưa được giải quyết.',
    );
    return '$_temp0';
  }

  @override
  String get gitMergeUnresolvedDetail =>
      'Lưu kết quả như hiện tại và đánh dấu tệp đã được giải quyết?';

  @override
  String get gitMergeSaveAnyway => 'Lưu và đánh dấu đã giải quyết';

  @override
  String get gitMergeDiscard => 'Hủy kết quả hợp nhất?';

  @override
  String get gitMergeDiscardButton => 'Loại bỏ';

  @override
  String get gitDiffExcludeChange => 'Để thay đổi này ra khỏi commit';

  @override
  String get gitDiffIncludeChange => 'Bao gồm Thay đổi này trong commit';

  @override
  String get gitDiffExcludeLine => 'Bỏ dòng này ra khỏi commit';

  @override
  String get gitDiffIncludeLine => 'Bao gồm dòng này trong commit';

  @override
  String get gitChangelistActive => 'tích cực';

  @override
  String get gitChangelistMoveTo => 'Chuyển sang danh sách thay đổi khác';

  @override
  String get gitChangelistNew => 'Danh sách thay đổi mới…';

  @override
  String get gitChangelistCreate => 'Tạo nên';

  @override
  String get gitChangelistName => 'Tên danh sách thay đổi';

  @override
  String get gitChangelistCommitOnly => 'Chỉ commit danh sách thay đổi này';

  @override
  String get gitChangelistSetActive => 'Đặt danh sách thay đổi đang hoạt động';

  @override
  String get gitChangelistRename => 'Đổi tên danh sách thay đổi…';

  @override
  String get gitChangelistRenameButton => 'Đổi tên';

  @override
  String get gitChangelistDelete => 'Xóa danh sách thay đổi';

  @override
  String get gitStashChangesTitle => 'Lưu trữ các thay đổi';

  @override
  String gitStashFilesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lưu trữ các tệp $count',
      one: 'Chứa 1 tệp',
    );
    return '$_temp0';
  }

  @override
  String get gitStashButton => 'cất giữ';

  @override
  String get gitStashMessage => 'Tin nhắn (tùy chọn)';

  @override
  String get gitStashUntracked => 'Bao gồm các tệp không bị theo dõi';

  @override
  String get gitStashBase => 'Căn cứ';

  @override
  String get gitStashApply => 'Áp dụng';

  @override
  String get gitStashPop => 'Nhạc pop';

  @override
  String get gitStashAsBranch => 'Hủy lưu trữ dưới dạng Chi nhánh…';

  @override
  String get gitStashCopyMessage => 'Sao chép tin nhắn';

  @override
  String get gitStashDrop => 'Làm rơi…';

  @override
  String gitStashDropConfirm(String ref) {
    return 'Thả $ref?';
  }

  @override
  String get gitStashDropButton => 'Làm rơi';

  @override
  String get gitStashClear => 'Xóa các ngăn chứa…';

  @override
  String get gitStashClearConfirm => 'Bỏ mọi thứ?';

  @override
  String get gitStashClearButton => 'Xóa';

  @override
  String get gitStashNone => 'Không có kho lưu trữ';

  @override
  String get gitStashTab => 'cất giữ';

  @override
  String get gitCommitTab => 'Commit';

  @override
  String get gitCommitPanelFold => 'Nếp gấp';

  @override
  String get gitCommitPanelUnfold => 'Mở ra';

  @override
  String get gitStashSelected => 'Chứa các tệp đã chọn…';

  @override
  String get gitCommitIgnored => 'Tệp bị bỏ qua';

  @override
  String get gitCommitShowIgnored => 'Hiển thị các tệp bị bỏ qua';

  @override
  String gitCommitLongSubject(int limit) {
    return 'Chủ đề dài hơn ký tự $limit';
  }

  @override
  String get gitCommitNoBlankLine =>
      'Tách chủ thể khỏi nội dung bằng một dòng trống';

  @override
  String get gitCommitMessageHistory => 'Lịch sử tin nhắn commit (Ctrl+M)';

  @override
  String get gitCommitNoMessageHistory => 'Chưa có tin nhắn nào';

  @override
  String get gitCommitOptions => 'Tùy chọn commit';

  @override
  String get gitCommitAuthor => 'Tác giả…';

  @override
  String gitCommitAuthorIs(String author) {
    return 'Tác giả: $author';
  }

  @override
  String get gitCommitAuthorReset => 'Sử dụng tác giả được cấu hình';

  @override
  String get gitCommitAuthorPlaceholder => 'Tên <email>';

  @override
  String get gitCommitSignOff => 'commit đăng xuất';

  @override
  String get gitCommitRunHooks => 'Chạy Git Hook';

  @override
  String get gitCommitSignedOff => 'Đã đăng xuất';

  @override
  String get gitCommitNoHooks => 'Móc bị bỏ qua';

  @override
  String get gitLogInteractiveRebase => 'Rebase tương tác từ đây…';

  @override
  String gitRebaseTitle(int count, String base) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'commit $count',
      one: '1 commit',
    );
    return 'Khởi động lại $_temp0 từ $base';
  }

  @override
  String get gitRebasePick => 'Nhặt';

  @override
  String get gitRebaseReword => 'Viết lại';

  @override
  String get gitRebaseEdit => 'Biên tập';

  @override
  String get gitRebaseSquash => 'bí';

  @override
  String get gitRebaseFixup => 'Sửa chữa';

  @override
  String get gitRebaseDrop => 'Làm rơi';

  @override
  String get gitRebaseMoveUp => 'Di chuyển lên (Alt+Up)';

  @override
  String get gitRebaseMoveDown => 'Di chuyển xuống (Alt+Dưới)';

  @override
  String get gitRebaseMessage => 'Thông báo commit';

  @override
  String get gitRebaseStart => 'Bắt đầu khởi động lại';

  @override
  String get gitRebaseNothingBelow =>
      'commit cũ nhất được giữ không thể bị đè bẹp hoặc sửa chữa: không có gì bên dưới nó.';

  @override
  String get gitRebaseStopped =>
      'Quá trình rebase đã dừng: sửa đổi commit hoặc giải quyết xung đột, sau đó Tiếp tục.';

  @override
  String get gitRebaseCleanUpWithAi => 'Dọn dẹp bằng AI';

  @override
  String get gitRebaseCleanUpWithAiDetail =>
      'Hãy để mô hình đề xuất những gì cần sửa chữa, sắp xếp lại và điều chỉnh lại; bạn xem qua trước khi rebase bắt đầu';

  @override
  String get gitRebaseAiPlanning => 'Lập kế hoạch… (bấm để dừng)';

  @override
  String get gitRebaseAiNoPlan =>
      'Câu trả lời của mô hình không phải là danh sách rebase của những commit này.';

  @override
  String gitRebaseAiFailed(String error) {
    return 'Không thể dọn dẹp bằng AI: $error';
  }

  @override
  String gitTagPushTo(String remote) {
    return 'Đẩy thẻ vào $remote';
  }

  @override
  String gitTagDeleteOn(String remote) {
    return 'Xóa thẻ trên $remote';
  }

  @override
  String gitTagDeleteOnConfirm(String name, String remote) {
    return 'Xóa thẻ $name trên $remote?';
  }

  @override
  String get gitRemotesManage => 'Quản lý điều khiển từ xa…';

  @override
  String get gitRemotesTitle => 'Điều khiển từ xa Git';

  @override
  String get gitRemotesNone => 'Không có điều khiển từ xa';

  @override
  String get gitRemoteAdd => 'Thêm điều khiển từ xa';

  @override
  String get gitRemoteEdit => 'Chỉnh sửa từ xa';

  @override
  String get gitRemoteRemove => 'Di dời';

  @override
  String get gitRemoteName => 'Tên';

  @override
  String get gitRemoteUrl => 'URL';

  @override
  String gitRemoteRemoveConfirm(String name) {
    return 'Xóa $name từ xa?';
  }

  @override
  String get gitRemoteRemoveDetail =>
      'Các nhánh xa của nó đi theo nó; không có gì trên máy chủ thay đổi.';

  @override
  String get gitCloneTitle => 'Nhận từ Kiểm soát phiên bản';

  @override
  String get gitCloneUrl => 'URL';

  @override
  String get gitCloneDirectory => 'Thư mục';

  @override
  String get gitCloneBrowse => 'Duyệt…';

  @override
  String get gitCloneButton => 'Dòng vô tính';

  @override
  String get gitCloning => 'Nhân bản…';

  @override
  String get gitCloneCommand => 'Sao chép kho lưu trữ…';

  @override
  String get gitReviewWithAi => 'Xem lại các thay đổi với AI';

  @override
  String get gitReviewStop => 'Dừng đánh giá';

  @override
  String get gitReviewBeforeCommit => 'Đánh giá với AI trước khi cam kết';

  @override
  String get gitReviewRunning => 'Xem xét những thay đổi…';

  @override
  String get gitReviewClean => 'Không tìm thấy vấn đề nào';

  @override
  String gitReviewFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tìm thấy $count vấn đề',
      one: 'Tìm thấy 1 vấn đề',
    );
    return '$_temp0';
  }

  @override
  String get gitReviewCommitAnyway => 'Dù sao cũng commit';

  @override
  String get gitReviewCommitAndPushAnyway => 'commit và đẩy dù sao';

  @override
  String gitReviewFailed(String error) {
    return 'Không thể xem lại các thay đổi: $error';
  }

  @override
  String get gitAskAiCommit => 'Hỏi AI về commit này';

  @override
  String gitAskAiCommitPrompt(String id, String subject) {
    return 'Giải thích commit $id (“$subject”): nó thay đổi những gì và tại sao cũng như bất kỳ điều gì trong đó có vẻ rủi ro. Đọc nó với `git show $id`.';
  }

  @override
  String gitAskAiCommits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hỏi AI về những commit $count này',
      one: 'Hỏi AI về commit này',
    );
    return '$_temp0';
  }

  @override
  String gitAskAiCommitsPrompt(String ids) {
    return 'Giải thích các commit $ids: những gì chúng thay đổi cùng nhau và bất kỳ điều gì trong đó có vẻ rủi ro. Đọc chúng với `git show`.';
  }

  @override
  String get gitAskAiHunk => 'Hỏi AI về sự thay đổi này';

  @override
  String gitAskAiHunkPrompt(String path, int line, String change) {
    return 'Về sự thay đổi này trong $path tại dòng $line: giải thích nó làm gì và liệu có điều gì sai trong đó không.\n\n```diff\n$change\n```';
  }

  @override
  String get gitAskAiChanges => 'Hỏi AI về những thay đổi này';

  @override
  String gitAskAiChangesPrompt(String paths) {
    return 'Xem lại những thay đổi chưa được cam kết của tôi trong $paths (`git diff HEAD -- $paths`): giải thích những gì họ làm và chỉ ra bất kỳ điều gì sai.';
  }

  @override
  String get gitAskAiConflicts => 'Yêu cầu AI giải quyết xung đột';

  @override
  String gitAskAiConflictsPrompt(String paths) {
    return 'Giải quyết xung đột hợp nhất trong $paths: giữ nguyên ý nghĩa của cả hai bên, sau đó cho tôi biết bạn đã chọn gì. Đừng giai đoạn hoặc commit.';
  }

  @override
  String get gitLogFixup => 'Khắc phục các thay đổi đã kiểm tra';

  @override
  String get compareWith => 'So sánh với';

  @override
  String get compareWithClipboard => 'Bảng nhớ tạm';

  @override
  String compareWithClipboardLabel(String name) {
    return '$name (Bảng nhớ tạm ↔ Tệp)';
  }

  @override
  String get gitCompareWithBranch => 'Chi nhánh hoặc Thẻ…';

  @override
  String get gitCompareWithRevision => 'Ôn tập…';

  @override
  String get gitCompareWithBranchPlaceholder =>
      'Chọn một nhánh hoặc thẻ để so sánh tệp với';

  @override
  String get gitCompareWithRevisionPlaceholder =>
      'Chọn một phiên bản của tệp để so sánh với';

  @override
  String gitCompareLabel(String name, String other) {
    return '$name ($other ↔ Cây làm việc)';
  }

  @override
  String get explorerSelectForCompare => 'Chọn để so sánh';

  @override
  String explorerCompareWithSelected(String name) {
    return 'So sánh với \'$name\'';
  }

  @override
  String compareFoldersSame(String original, String modified) {
    return '“$original” và “$modified” có cùng một tệp.';
  }

  @override
  String compareFoldersPick(String original, String modified) {
    return 'Các tệp “$original” và “$modified” khác nhau ở';
  }

  @override
  String compareFoldersOnlyIn(String name) {
    return 'Chỉ có trong “$name”';
  }

  @override
  String get compareFoldersModified => 'Đã thay đổi';

  @override
  String get compareWithLocalHistory => 'Lịch sử địa phương…';

  @override
  String get localHistoryShow => 'Hiển thị lịch sử địa phương';

  @override
  String localHistoryNone(String name) {
    return 'Chưa có lịch sử cục bộ nào của “$name”: nó được lưu giữ khi tệp được lưu.';
  }

  @override
  String localHistoryPick(String name) {
    return 'Một phiên bản của “$name” để so sánh với';
  }

  @override
  String localHistoryLabel(String name, String time) {
    return '$name (Lịch sử địa phương, $time)';
  }

  @override
  String get explorerCompareSelected => 'So sánh đã chọn';

  @override
  String compareFilesLabel(String original, String modified) {
    return '$original ↔ $modified';
  }

  @override
  String get settingsSectionUsage => 'Mức sử dụng';

  @override
  String get sidePanelUsage => 'Cách sử dụng';

  @override
  String get ustatKeywords =>
      'số liệu thống kê sử dụng mã thông báo bộ đệm cuộc gọi bảng thông tin chi phí mô hình ngược dòng';

  @override
  String get ustatAll => 'Tất cả';

  @override
  String get ustatAgent => 'Agent';

  @override
  String get ustatKind => 'Loại';

  @override
  String get ustatModel => 'Người mẫu';

  @override
  String get ustatUpstream => 'Thượng nguồn';

  @override
  String get ustatConversation => 'Cuộc hội thoại';

  @override
  String get ustatFailedOnly => 'Chỉ thất bại';

  @override
  String get ustatResetFilters => 'Đặt lại bộ lọc';

  @override
  String get ustatRefresh => 'Làm cho khỏe lại';

  @override
  String get ustatUnpin => 'Quay lại toàn bộ phạm vi';

  @override
  String get ustatRangeHour => 'Giờ trước';

  @override
  String get ustatRangeToday => 'Hôm nay';

  @override
  String get ustatRangeDay => '24 giờ qua';

  @override
  String get ustatRangeWeek => '7 ngày qua';

  @override
  String get ustatRangeMonth => '30 ngày qua';

  @override
  String get ustatRangeQuarter => '90 ngày qua';

  @override
  String get ustatRangeAll => 'Mọi lúc';

  @override
  String get ustatClassMain => 'Agent chính';

  @override
  String get ustatClassSubagent => 'chất phụ';

  @override
  String get ustatClassWorkflow => 'Quy trình làm việc';

  @override
  String get ustatClassCompaction => 'nén chặt';

  @override
  String get ustatClassAuxiliary => 'phụ trợ';

  @override
  String get ustatClassSideReply => 'Trả lời bên lề';

  @override
  String get ustatMainAgent => 'Agent chính';

  @override
  String get ustatPartSystem => 'Lời nhắc hệ thống';

  @override
  String get ustatPartTools => 'Định nghĩa công cụ';

  @override
  String get ustatPartUser => 'Tin nhắn của người dùng';

  @override
  String get ustatPartAssistant => 'Trả lời';

  @override
  String get ustatPartThinking => 'suy nghĩ';

  @override
  String get ustatPartToolUse => 'Cuộc gọi công cụ';

  @override
  String get ustatPartToolResult => 'Kết quả công cụ';

  @override
  String get ustatPartMedia => 'Hình ảnh và tệp';

  @override
  String get ustatTokenInput => 'đầu vào';

  @override
  String get ustatTokenOutput => 'đầu ra';

  @override
  String get ustatTokenCacheRead => 'Đọc bộ nhớ đệm';

  @override
  String get ustatTokenCacheWrite => 'Ghi bộ nhớ đệm';

  @override
  String get ustatTokenReasoning => 'Lý luận';

  @override
  String get ustatTotalTokens => 'Mã thông báo';

  @override
  String ustatTokensDetail(String input, String output) {
    return '$input vào · $output ra';
  }

  @override
  String get ustatCalls => 'Cuộc gọi';

  @override
  String ustatCallsDetail(String count) {
    return 'Đã yêu cầu cuộc gọi công cụ $count';
  }

  @override
  String get ustatCallsOk => 'thành công';

  @override
  String ustatCallsShort(int count) {
    return 'Cuộc gọi $count';
  }

  @override
  String get ustatCacheHit => 'Tỷ lệ truy cập bộ đệm';

  @override
  String ustatCacheDetail(String read, String written) {
    return '$read đã đọc · $written đã viết';
  }

  @override
  String get ustatFirstToken => 'Thời gian nhận được mã thông báo đầu tiên';

  @override
  String ustatDurationDetail(String duration) {
    return 'Trung bình $duration mỗi cuộc gọi';
  }

  @override
  String get ustatSpeed => 'Tốc độ đầu ra';

  @override
  String ustatOutputDetail(String tokens) {
    return 'Tất cả đầu ra $tokens';
  }

  @override
  String ustatReasoningDetail(String tokens) {
    return '$tokens của nó lý luận';
  }

  @override
  String get ustatErrors => 'Thất bại';

  @override
  String ustatErrorRate(String rate) {
    return '$rate số cuộc gọi';
  }

  @override
  String get ustatOverTime => 'Theo thời gian';

  @override
  String get ustatMetricTokens => 'Mã thông báo';

  @override
  String get ustatMetricCalls => 'Cuộc gọi';

  @override
  String get ustatMetricLatency => 'Độ trễ';

  @override
  String get ustatMetricSpeed => 'Tốc độ';

  @override
  String get ustatByUpstream => 'Bằng thượng nguồn';

  @override
  String get ustatByModel => 'Theo mô hình';

  @override
  String get ustatByConversation => 'Bằng cuộc trò chuyện';

  @override
  String get ustatByTurn => 'Lần lượt';

  @override
  String get ustatByTurnDetail =>
      'Mỗi tin nhắn của bạn và tất cả các yêu cầu đã trả lời nó';

  @override
  String ustatTurnDetail(String duration, String peak) {
    return '$duration · ngữ cảnh lên tới $peak';
  }

  @override
  String get ustatNoConversations =>
      'Không có cuộc trò chuyện nào được đặt tên cho phiên của nó';

  @override
  String get ustatTools => 'Công cụ';

  @override
  String get ustatToolsDetail =>
      'Kết quả của họ mang lại điều gì cho bối cảnh (ước tính), tần suất họ được gọi, họ chạy trong bao lâu';

  @override
  String get ustatToolSortTokens => 'Bối cảnh';

  @override
  String get ustatToolSortCalls => 'Cuộc gọi';

  @override
  String get ustatToolSortTime => 'Thời gian';

  @override
  String get ustatNoTools => 'Không có công cụ nào được sử dụng';

  @override
  String get ustatToolCalled => 'Gọi điện';

  @override
  String get ustatToolResult => 'kết quả';

  @override
  String ustatShowAll(int count) {
    return 'Hiển thị tất cả $count';
  }

  @override
  String get ustatShowLess => 'Hiển thị ít hơn';

  @override
  String get ustatContextGrowth => 'Tăng trưởng bối cảnh';

  @override
  String ustatContextNow(String tokens) {
    return '$tokens bây giờ';
  }

  @override
  String ustatContextPeak(String tokens) {
    return 'đỉnh $tokens';
  }

  @override
  String ustatCompactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nén $count',
      one: '1 lần nén',
    );
    return '$_temp0';
  }

  @override
  String ustatCompactedFrom(String tokens) {
    return 'Được nén ở $tokens';
  }

  @override
  String get ustatContextMakeup => 'Những gì lấp đầy bối cảnh';

  @override
  String get ustatRecentCalls => 'Cuộc gọi gần đây';

  @override
  String get ustatCallsTitle => 'Cuộc gọi';

  @override
  String ustatRecentCallsDetail(int count) {
    return 'Nói chung là $count, mới nhất trước tiên';
  }

  @override
  String ustatShowMoreCalls(int count) {
    return 'Hiển thị thêm ($count còn lại)';
  }

  @override
  String get ustatNoCalls => 'Không có cuộc gọi';

  @override
  String get ustatCopyJson => 'Sao chép cuộc gọi dưới dạng JSON';

  @override
  String get ustatFieldTime => 'Thời gian';

  @override
  String get ustatFieldStatus => 'Trạng thái';

  @override
  String get ustatFieldUpstream => 'Thượng nguồn';

  @override
  String get ustatFieldModel => 'Người mẫu';

  @override
  String get ustatFieldEffort => 'Cố gắng';

  @override
  String get ustatFieldClass => 'Loại';

  @override
  String get ustatFieldSession => 'Phiên họp';

  @override
  String get ustatFieldAgent => 'Agent';

  @override
  String get ustatFieldTask => 'Nhiệm vụ';

  @override
  String get ustatFieldAccount => 'Tài khoản';

  @override
  String get ustatFieldUpstreamLatency => 'Thượng nguồn đã trả lời';

  @override
  String get ustatCallAsking => 'Yêu cầu';

  @override
  String get ustatCallAnswering => 'Trả lời';

  @override
  String get ustatCallCancelled => 'Đã hủy';

  @override
  String get ustatFieldFirstToken => 'Mã thông báo đầu tiên';

  @override
  String get ustatFieldDuration => 'Khoảng thời gian';

  @override
  String get ustatFieldSpeed => 'Tốc độ';

  @override
  String get ustatFieldMessages => 'Tin nhắn';

  @override
  String get ustatFieldTools => 'công cụ';

  @override
  String get ustatFieldBytes => 'Kích cỡ';

  @override
  String get ustatFieldCompacted => 'Sau khi nén';

  @override
  String get ustatFieldError => 'Lỗi';

  @override
  String get ustatEmptyTitle => 'Chưa có cuộc gọi nào';

  @override
  String get ustatEmptyDetail =>
      'Cuộc gọi sẽ hiển thị ở đây sau khi cuộc trò chuyện diễn ra.';

  @override
  String get ustatEmptyFiltered => 'Không có gì phù hợp với các bộ lọc này';

  @override
  String get ustatConversationNew =>
      'Cách sử dụng hiển thị khi cuộc trò chuyện bắt đầu';

  @override
  String get ustatConversationEmpty =>
      'Không có cuộc gọi nào được lưu giữ cho cuộc trò chuyện này';

  @override
  String get ustatConversationEmptyDetail =>
      'Chỉ các cuộc hội thoại trên thượng nguồn tùy chỉnh mới được tính: Dịch vụ chính thức của Claude không thông qua proxy của BaoCode.';

  @override
  String get ustatRecordOff => 'Việc sử dụng không được ghi lại';

  @override
  String get ustatTurnOn => 'Bật';

  @override
  String get ustatDataTitle => 'dữ liệu';

  @override
  String get ustatDataDescription =>
      'Các hồ sơ chi tiết sẽ có chỗ trống: giữ chúng bao lâu tùy thích và xóa những gì bạn không cần nữa.';

  @override
  String get ustatRecord => 'Ghi lại việc sử dụng';

  @override
  String get ustatRecordDescription =>
      'Các cuộc gọi riêng của Claude Code được đọc từ những gì nó in ra; các phiên trên luồng ngược tùy chỉnh sẽ đi qua proxy cục bộ của BaoCode, nơi lưu giữ từng cuộc gọi. Áp dụng cho agent bắt đầu từ bây giờ.';

  @override
  String get ustatRecordOffDescription =>
      'Hãy bật tính năng này để duy trì từng cuộc gọi đến một mô hình: mã thông báo, bộ nhớ đệm, thời gian, theo cuộc hội thoại, tác nhân phụ và công cụ.';

  @override
  String get ustatDetailed => 'Hồ sơ chi tiết';

  @override
  String get ustatDetailedDescription =>
      'Đồng thời giữ lại những gì được lấp đầy trong bối cảnh của từng yêu cầu và phần chia sẻ của các công cụ. Cần nhiều chỗ hơn.';

  @override
  String get ustatRetention => 'Lưu giữ hồ sơ cho';

  @override
  String get ustatRetentionDescription =>
      'Những ngày cũ sẽ bị xóa khi chúng trôi qua.';

  @override
  String ustatKeepDays(int days) {
    return '$days ngày';
  }

  @override
  String get ustatKeepForever => 'Mãi mãi';

  @override
  String ustatSpace(String size) {
    return 'Sử dụng $size';
  }

  @override
  String ustatSpaceDetail(int days, String oldest) {
    return 'Số ngày $days được giữ lại, kể từ $oldest';
  }

  @override
  String get ustatSpaceEmpty => 'Chưa có gì được giữ lại';

  @override
  String get ustatLoading => 'Đọc cuộc gọi…';

  @override
  String get ustatClearEllipsis => 'Thông thoáng…';

  @override
  String get ustatClear => 'Xóa';

  @override
  String ustatClearOlderThan(int days) {
    return 'Xóa tất cả trừ những ngày $days cuối cùng';
  }

  @override
  String get ustatClearShown => 'Xóa thời gian hiển thị';

  @override
  String get ustatClearShownFiltered => 'Xóa những gì bộ lọc hiển thị';

  @override
  String get ustatClearAll => 'Xóa mọi thứ';

  @override
  String ustatClearConfirm(String what) {
    return '$what?';
  }

  @override
  String get ustatClearDetail =>
      'Các cuộc gọi sẽ bị xóa khỏi máy tính này. Điều này không thể hoàn tác được.';

  @override
  String get autoResetCreditsToggle => 'Tín dụng đặt lại tự động sử dụng';

  @override
  String modelsResetCredits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count đặt lại còn lại',
      one: 'còn 1 lần đặt lại',
    );
    return '$_temp0';
  }

  @override
  String modelsResetCreditsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tín dụng đặt lại $count',
      one: '1 tín dụng đặt lại',
    );
    return '$_temp0';
  }

  @override
  String get modelsResetCreditsDetail =>
      'Việc sử dụng một tài khoản sẽ bắt đầu hết hạn ngạch của tài khoản này cùng một lúc.';

  @override
  String modelsResetCreditExpires(String time) {
    return 'Hết hạn $time';
  }

  @override
  String get modelsResetCreditUse => 'Đặt lại ngay';

  @override
  String modelsResetCreditConfirm(String account) {
    return 'Sử dụng tín dụng đặt lại của $account?';
  }

  @override
  String get modelsResetCreditConfirmDetail =>
      'Hạn ngạch của nó bắt đầu lại cùng một lúc. Tín dụng không thể được trả lại và bất kỳ hạn ngạch nào còn lại bây giờ sẽ bị mất.';

  @override
  String claudeResets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đặt lại $count',
      one: '1 lần đặt lại',
    );
    return '$_temp0';
  }

  @override
  String get claudeResetsTitle => 'Đặt lại giới hạn Claude';

  @override
  String get claudeResetsDetail =>
      'Được cấp bởi Anthropic. Việc sử dụng một sẽ đặt ra các giới hạn mà nó liệt kê lại thành không được sử dụng. Với nhiều hơn một, chúng được sử dụng cùng một lúc, theo thứ tự các bộ Anthropic.';

  @override
  String claudeResetClears(String windows) {
    return 'Xóa $windows';
  }

  @override
  String claudeResetWindowUsed(String window, int percent) {
    return '$window ($percent% đã sử dụng)';
  }

  @override
  String claudeResetWeeklyOf(String model) {
    return '$model hàng tuần';
  }

  @override
  String get claudeResetNext => 'Có thể sử dụng ngay bây giờ';

  @override
  String get claudeResetQueued =>
      'Chờ đến lượt: có thể sử dụng được khi sử dụng cái trên';

  @override
  String get claudeResetUse => 'Sử dụng cái này…';

  @override
  String get claudeResetConfirm => 'Sử dụng thiết lập lại giới hạn Claude?';

  @override
  String claudeResetConfirmDetail(String label, String windows) {
    return '“$label” đặt $windows trở về trạng thái không sử dụng cùng một lúc. Việc thiết lập lại không thể được trả lại và những gì còn lại trong các giới hạn này hiện sẽ bị mất.';
  }

  @override
  String get claudeResetPaused => 'Đã tạm dừng';

  @override
  String claudeResetCooldown(String time) {
    return 'Có thể sử dụng lại $time';
  }

  @override
  String claudeResetUnavailable(String reason) {
    return 'Hiện không thể sử dụng được ($reason)';
  }

  @override
  String get claudeResetSignedOut =>
      'Đăng nhập Claude.ai đã hết hạn; Claude Code đổi mới nó trong lần chạy tiếp theo.';

  @override
  String claudeResetDone(String windows) {
    return 'Đặt lại: $windows';
  }

  @override
  String claudeResetNotDone(String reason) {
    return 'Chưa đặt lại: $reason';
  }

  @override
  String get claudeResetNotNext =>
      'Một thiết lập lại khác hiện có thể sử dụng được; không có gì được sử dụng. Hãy làm mới và thử lại.';

  @override
  String get claudeResetNotLimited =>
      'Việc đặt lại này chỉ có thể được sử dụng khi đạt đến giới hạn; không có gì được sử dụng.';

  @override
  String get claudeResetAlreadyUsed =>
      'Thiết lập lại này đã được sử dụng; bây giờ không có gì được sử dụng.';

  @override
  String get claudeResetCoolingDown =>
      'Một thiết lập lại vừa được sử dụng; đợi một chút trước khi tiếp theo. Không có gì được sử dụng.';

  @override
  String get claudeResetsRefresh => 'Làm cho khỏe lại';

  @override
  String resetCreditsHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tín dụng đặt lại $count hết hạn',
      one: 'Tín dụng đặt lại hết hạn',
    );
    return '$_temp0 trong vòng một tuần. Để nhận được giá trị của chúng, hãy sử dụng các mô hình Codex trong gói này, đặt lại sau khi hết hạn ngạch:';
  }

  @override
  String resetCreditsHintDay(String day, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lần',
      one: 'một lần',
    );
    return '$day: đặt lại $_temp0';
  }

  @override
  String resetCreditsHintBy(String time) {
    return 'bởi $time';
  }

  @override
  String get resetCreditsHintToday => 'Hôm nay';

  @override
  String get resetCreditsHintTomorrow => 'Ngày mai';

  @override
  String get resetCreditsHintAuto => 'Tự động đặt lại';

  @override
  String get resetCreditsHintLater => 'Hiểu rồi';

  @override
  String get ustatPartMemory => 'CLAUDE.md & quy tắc';

  @override
  String get ustatPartSkills => 'Kỹ năng';

  @override
  String get ustatPartMcp => 'MCP';

  @override
  String get ustatPartMessages => 'Cuộc hội thoại';

  @override
  String ustatCacheHitShort(String rate) {
    return '$rate được lưu trong bộ nhớ đệm';
  }

  @override
  String get ustatCompactedAfter => 'Đầu tiên sau khi nén';

  @override
  String get ustatContextPickHint => 'Nhấn vào đây để xem những gì lấp đầy nó';

  @override
  String ustatRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yêu cầu',
      one: '1 yêu cầu',
    );
    return '$_temp0';
  }

  @override
  String ustatRequestOf(int index, int count) {
    return '#$index của $count';
  }

  @override
  String get ustatPreviousRequest => 'Yêu cầu trước đó';

  @override
  String get ustatNextRequest => 'Yêu cầu tiếp theo';

  @override
  String get ustatNoMakeup =>
      'Nội dung trong ngữ cảnh của yêu cầu này không được ghi lại (bật Ghi chi tiết).';

  @override
  String get ustatMakeupNoDetail =>
      'Ghi nhận trước khi phân tích theo tool, server MCP và kỹ năng: các yêu cầu từ nay đã có.';

  @override
  String get ustatMakeupShapeMissing =>
      'Không tìm thấy thông tin chi tiết về các công cụ và kỹ năng của yêu cầu này.';

  @override
  String ustatMcpTools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Công cụ $count',
      one: '1 công cụ',
      zero: 'chỉ hướng dẫn',
    );
    return '$_temp0';
  }

  @override
  String get ustatMcpInstructions => 'Hướng dẫn';

  @override
  String get ustatSkillPlugin => 'phần bổ trợ';

  @override
  String ustatToolInputs(String tokens) {
    return 'đầu vào $tokens';
  }

  @override
  String get ustatSwitchedHint =>
      'Đã lưu vào Cài đặt → Tùy chỉnh. Các yêu cầu tiếp theo của agent sẽ không được tắt.';

  @override
  String get ustatShowAuxiliary => 'Hiển thị các yêu cầu phụ trợ';

  @override
  String get ustatShowAuxiliaryDescription =>
      'Đếm các yêu cầu của Claude Code bên cạnh cuộc trò chuyện (gợi ý lời nhắc tiếp theo, đặt tên cho cuộc trò chuyện, tóm tắt một trang web) trong biểu đồ và tổng số. Chúng được giữ theo một trong hai cách.';

  @override
  String get ustatTrace => 'Chụp gỡ lỗi';

  @override
  String get ustatTraceDescription =>
      'Ngoài ra, hãy giữ mọi yêu cầu đối với toàn bộ thượng nguồn tùy chỉnh: khi Claude Code gửi nó, khi nó đi lên thượng nguồn, câu trả lời thô của thượng nguồn và những gì quay lại; mô hình riêng của Claude Code, chỉ có câu trả lời của họ. Chìa khóa được che dấu. Tốn nhiều dung lượng: tắt nó khi hoàn tất.';

  @override
  String get ustatTraceTitle => 'Trao đổi thô';

  @override
  String get ustatTraceLoading => 'Đọc…';

  @override
  String get ustatTraceGone => 'Việc trao đổi thô đã bị xóa.';

  @override
  String get ustatTraceNone =>
      'Không có gì diễn ra theo cách này (nó đã được trả lời trước đó).';

  @override
  String get ustatTraceRequestBody => 'Nội dung yêu cầu';

  @override
  String get ustatTraceRawResponse => 'Phản hồi thô';

  @override
  String get ustatTraceToUpstream => 'Đã gửi ngược dòng';

  @override
  String ustatTraceResponseHeaders(int count) {
    return 'Tiêu đề phản hồi · $count';
  }

  @override
  String get ustatTraceAnswerOnly =>
      'Như Claude Code đã in nó; yêu cầu tới Anthropic không được nhìn thấy';

  @override
  String ustatTraceTry(int n) {
    return 'Hãy thử $n';
  }

  @override
  String get ustatTraceCopyAll => 'Sao chép tất cả';

  @override
  String get ustatTraceCopyBody => 'Sao chép';

  @override
  String ustatTraceHeaders(int count) {
    return 'Tiêu đề yêu cầu · $count';
  }

  @override
  String get ustatTraceRaw => 'Như đã gửi';

  @override
  String get ustatTraceFormatted => 'Đã định dạng';

  @override
  String get ustatTraceEmpty => 'Trống';

  @override
  String ustatTraceMore(String size) {
    return 'Hiển thị thêm ($size còn lại)';
  }

  @override
  String get ustatTraceTruncated => 'cắt ở 24M ký tự';

  @override
  String ustatSpaceTraces(String size, int count) {
    return '; trao đổi thô $size ($count)';
  }

  @override
  String get ustatClearTraces => 'Chỉ xóa các trao đổi thô';

  @override
  String get ustatClearTracesDetail =>
      'Các cuộc gọi ở lại; các yêu cầu và câu trả lời thô của họ sẽ bị xóa khỏi máy tính này.';

  @override
  String get ustatColumnTotal => 'Tổng cộng';

  @override
  String get ustatColumnMix => 'Sự cố';

  @override
  String ustatDeferred(String size) {
    return 'hoãn lại, $size';
  }

  @override
  String get ustatSwitchedOff => 'tắt';

  @override
  String usageUntilCompaction(String tokens) {
    return '$tokens để tự động nén';
  }

  @override
  String get usageAgentDefinition => 'agent';

  @override
  String get usageAttachments => 'Lời nhắc và tệp đính kèm';

  @override
  String get ustatCost => 'Trị giá';

  @override
  String get ustatCostEstimated => 'Với mức giá như hiện nay';

  @override
  String ustatCostUnpriced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cuộc gọi $count không được định giá',
      one: '1 cuộc gọi không tính phí',
    );
    return '$_temp0';
  }

  @override
  String get ustatCostNoPrices => 'Không có giá nào được đặt';

  @override
  String get ustatPrices => 'Giá mẫu';

  @override
  String get ustatPricesDetail =>
      'Một triệu token mỗi cái. Chi phí được tính toán theo mức giá hiện tại, bao gồm cả các cuộc gọi trước khi thay đổi, trừ khi giá được ấn định từ một ngày trở đi.';

  @override
  String get ustatPricesAgentHint =>
      'BaoCode có thể giữ những thứ này cho bạn: yêu cầu nó trong phần trò chuyện để tra cứu giá hiện tại của các mẫu này và cập nhật chúng. Nó kiểm tra trang định giá của chính thượng nguồn và ghi chúng vào đây.';

  @override
  String get ustatPriceCurrency => 'Tiền tệ';

  @override
  String get ustatPriceAnyUpstream => 'bất kỳ thượng nguồn nào';

  @override
  String get ustatPriceSource => 'Giá được đọc ở đâu';

  @override
  String ustatPriceUpdated(String when) {
    return 'đã cập nhật $when';
  }

  @override
  String get ustatPriceClear => 'Xóa giá';

  @override
  String get ustatPriceIncomplete => 'Điền cả giá đầu vào và giá đầu ra';

  @override
  String get ustatPriceSpent => 'trong thời gian này';

  @override
  String get modelsAutoResetCreditsOff => 'Tắt';

  @override
  String get modelsAutoResetCreditsLong => 'Khi hết tuần hoặc tháng';

  @override
  String get modelsAutoResetCreditsAny => 'Khi bất kỳ cửa sổ nào hết';

  @override
  String get modelsAutoResetCreditsOffDescription =>
      'Một tài khoản hết hạn ngạch sẽ chờ tài khoản bắt đầu lại.';

  @override
  String get modelsAutoResetCreditsLongDescription =>
      'Tài khoản hết tuần (hoặc tháng) sẽ sử dụng tín dụng đặt lại và tiếp tục. Chờ đợi năm giờ sắp hết: họ sẽ sớm bắt đầu lại.';

  @override
  String get modelsAutoResetCreditsAnyDescription =>
      'Một tài khoản ngoài bất kỳ cửa sổ nào, cũng trong năm giờ, sử dụng tín dụng đặt lại ngay lập tức và tiếp tục. Tín dụng đi nhanh hơn.';

  @override
  String get ustatQuota => 'Kế hoạch Claude';

  @override
  String get ustatQuotaDetail =>
      'Các mô hình của chính Claude Code đã đạt được bao nhiêu giới hạn của kế hoạch trong thời gian này, từ các giới hạn mà chúng tồn tại sau mỗi cuộc gọi.';

  @override
  String get ustatQuotaFiveHour => 'giới hạn 5 giờ';

  @override
  String get ustatQuotaWeek => 'Giới hạn hàng tuần';

  @override
  String ustatQuotaWeekOf(String model) {
    return 'Giới hạn $model hàng tuần';
  }

  @override
  String ustatQuotaUsed(String percent) {
    return '$percent được sử dụng trong thời gian này';
  }

  @override
  String ustatQuotaPeak(String percent, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lần',
      one: 'một lần',
    );
    return 'Đỉnh $percent trong thời gian này · đặt lại $_temp0';
  }

  @override
  String ustatQuotaPerPercent(String tokens) {
    return '1% giới hạn hàng tuần ≈ mã thông báo $tokens';
  }

  @override
  String ustatQuotaPerPercentCost(String cost) {
    return '≈ $cost theo giá API';
  }

  @override
  String ustatCacheSaved(String amount) {
    return 'Đã lưu $amount';
  }

  @override
  String ustatCostIn(String currency) {
    return 'Chỉ trong $currency; các loại tiền tệ khác nằm trong tổng số';
  }

  @override
  String get ustatPriceClaudeDefault =>
      'Các mẫu riêng của Claude Code không có giá của bạn được định giá theo giá API của Anthropic: các số liệu màu xám.';

  @override
  String ustatPriceRuleTiers(int count) {
    return 'Các bậc $count theo độ dài dấu nhắc';
  }

  @override
  String get ustatPriceRuleSchedule => 'giờ cao điểm và thấp điểm';

  @override
  String ustatPriceRuleFast(String factor) {
    return 'chế độ nhanh ×$factor';
  }

  @override
  String get ustatPriceRuleServiceTiers => 'theo cấp độ dịch vụ';

  @override
  String get ustatPriceRuleGeo => 'theo khu vực';

  @override
  String ustatPriceRulePerCall(String amount) {
    return '$amount một cuộc gọi';
  }

  @override
  String get ustatPriceRuleTools => 'công cụ có giá sử dụng';

  @override
  String ustatPriceRuleVersions(int count) {
    return 'Giá $count theo ngày';
  }

  @override
  String ustatPriceRuleRate(String factor) {
    return 'tốc độ ngược dòng ×$factor';
  }

  @override
  String ustatPriceRuleTime(String factor) {
    return 'thời gian trong tuần ×$factor';
  }

  @override
  String ustatPriceRuleFees(String amount) {
    return 'phí $amount';
  }

  @override
  String get ustatFees => 'Phí';

  @override
  String get ustatPricedBy => 'Được định giá bởi';

  @override
  String get ustatUpstreamRates => 'Giá ngược dòng';

  @override
  String get ustatUpstreamRatesDetail =>
      'Các mô hình ở thượng nguồn này không có giá riêng: giá của cùng một mô hình ở nơi khác, nhân với tỷ giá.';

  @override
  String get ustatUpstreamRateClear => 'Xóa tỷ lệ';

  @override
  String get ustatContextUnpickHint =>
      'Bấm lần nữa để bỏ chọn: quay lại bối cảnh như hiện tại';

  @override
  String get localRunTitle => 'Chạy trên máy tính này';

  @override
  String localRunReason(String host, String system) {
    return 'Tác nhân trên $host muốn chạy lệnh này trên máy tính của bạn ($system), không phải trên $host.';
  }

  @override
  String localRunAlways(String host) {
    return 'Luôn cho phép $host';
  }

  @override
  String get remoteLocalAccess =>
      'Cho phép tác nhân từ xa hành động trên máy tính này';

  @override
  String get remoteLocalAccessDetail =>
      'Các tác nhân trên các máy chủ này có thể chạy các lệnh trên máy tính này (sẽ hỏi bạn mỗi lần), sao chép tệp theo cả hai cách và chuyển tiếp cổng.';

  @override
  String get remoteLocalAccessNoAsking => 'Chạy lệnh mà không cần hỏi';

  @override
  String get remoteLocalAccessAskAgain => 'Hỏi mỗi lần';

  @override
  String get sidePanelPorts => 'Cổng';

  @override
  String portsEmpty(String host) {
    return 'Không có cổng nào được chuyển tiếp. Một máy chủ trên $host in địa chỉ http://localhost của nó sẽ được chuyển tiếp tới đây.';
  }

  @override
  String get portsAdd => 'Chuyển tiếp một cổng';

  @override
  String get portsCopy => 'Sao chép địa chỉ';

  @override
  String get portsOpen => 'Mở trong trình duyệt';

  @override
  String get portsStop => 'Dừng chuyển tiếp';

  @override
  String portsHostToHere(String host) {
    return '$host → máy tính này';
  }

  @override
  String portsHereToHost(String host) {
    return 'Máy tính này → $host';
  }

  @override
  String get portsAuto => 'Tự động';

  @override
  String get portsPort => 'Cảng';

  @override
  String get portsListen => 'Nghe tiếp (tùy chọn)';

  @override
  String get portsForward => 'Phía trước';

  @override
  String portsCopied(String address) {
    return 'Đã sao chép $address';
  }

  @override
  String branchBarFolder(String path) {
    return '$path\nBấm để sao chép đường dẫn của nó';
  }

  @override
  String get branchBarPathCopied => 'Đã sao chép đường dẫn';

  @override
  String get rewindFilesTitle =>
      'Hoàn tác các thay đổi tệp được thực hiện sau thông báo này?';

  @override
  String rewindFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tệp',
      one: '1 tệp',
    );
    return 'Agent đã thay đổi $_temp0 sau tin nhắn này:';
  }

  @override
  String rewindFilesMore(int count) {
    return '…và $count thêm';
  }

  @override
  String rewindFilesMerged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trong số đó là',
      one: '1 trong số đó là',
    );
    return '$_temp0 cũng thay đổi ở nơi khác vì: những thay đổi đó được giữ lại.';
  }

  @override
  String rewindFilesConflicts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các tệp $count không thể',
      one: '1 tệp không thể',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'họ là',
      one: 'nó là',
    );
    return '$_temp0 được hoàn tác một cách sạch sẽ và sẽ giữ nguyên như cũ $_temp1:';
  }

  @override
  String get rewindFilesCommands =>
      'Những lệnh đã thay đổi (Bash) không được theo dõi và giữ nguyên.';

  @override
  String get rewindFilesRevert => 'Hoàn tác và gửi';

  @override
  String get rewindFilesKeep => 'Giữ và gửi';

  @override
  String get rewindFilesRemember => 'Hãy nhớ sự lựa chọn của tôi';

  @override
  String get generalSettingsRewindFiles => 'Chỉnh sửa tin nhắn trước';

  @override
  String get generalSettingsRewindFilesDescription =>
      'Chọn cách xử lý các tệp đã bị agent thay đổi sau tin nhắn cũ khi bạn sửa và gửi lại tin nhắn đó. Thay đổi do lệnh Bash không được theo dõi. Chỉ hỗ trợ Claude Code và agent BaoCode.';

  @override
  String get generalSettingsRewindAsk => 'Hỏi mỗi lần';

  @override
  String get generalSettingsRewindRevert => 'Hoàn tác thay đổi';

  @override
  String get generalSettingsRewindKeep => 'Giữ thay đổi';

  @override
  String get settingsTransferTitle => 'Di chuyển sang máy tính khác';

  @override
  String get settingsTransferDescription =>
      'Cài đặt, tổ hợp phím và ngược dòng của bạn cùng với mô hình của chúng, trong một tệp để nhập trên máy tính khác.';

  @override
  String get settingsTransferLabel => 'Tệp cài đặt';

  @override
  String get settingsTransferExport => 'Xuất khẩu…';

  @override
  String get settingsTransferImport => 'Nhập khẩu…';

  @override
  String get settingsTransferExportQuestion => 'Xuất cài đặt của bạn?';

  @override
  String get settingsTransferExportDetail =>
      'Cài đặt, tổ hợp phím và ngược dòng đi vào tệp. Khóa API của thượng nguồn chỉ khi bạn đánh dấu vào ô bên dưới: khi đó chúng ở trong tệp dưới dạng văn bản thuần túy, vì vậy hãy giữ nó cho riêng bạn và xóa nó sau khi được nhập.';

  @override
  String get settingsTransferWithKeys =>
      'Bao gồm các khóa API của thượng nguồn';

  @override
  String settingsTransferExported(String path) {
    return 'Đã xuất sang $path';
  }

  @override
  String settingsTransferImportQuestion(String file) {
    return 'Nhập cài đặt trong $file?';
  }

  @override
  String get settingsTransferImportDetail =>
      'Cài đặt, tổ hợp phím và ngược dòng của nó thay thế cài đặt của bạn; cài đặt nó không giữ nguyên như hiện tại.';

  @override
  String get settingsTransferImported =>
      'Đã nhập khẩu. Một số cài đặt có hiệu lực sau khi BaoCode khởi động lại.';

  @override
  String get settingsTransferNotAFile =>
      'Đây không phải là file cài đặt BaoCode được xuất.';

  @override
  String settingsTransferFailed(String error) {
    return 'Chưa xong: $error';
  }

  @override
  String get generalSettingsSessionTools =>
      'Cho phép agent phối hợp các cuộc trò chuyện khác';

  @override
  String get generalSettingsSessionToolsDescription =>
      'Agent có thể liệt kê các cuộc trò chuyện khác, đọc trạng thái mà không đánh thức chúng, mở cuộc trò chuyện mới hoặc giao việc cho agent khác (dùng worktree riêng nếu cần). Agent tự nhận kết quả khi công việc hoàn tất, thất bại hoặc cần bạn phản hồi; cũng có thể dừng tác vụ và xem tệp đã thay đổi. Dùng khi muốn một cuộc trò chuyện điều phối các cuộc trò chuyện khác. Khi tắt, agent không thể xem hoặc thao tác với các cuộc trò chuyện khác và không nhận được phản hồi từ công việc đã giao.';

  @override
  String get generalSettingsCommandLine => 'Dòng lệnh';

  @override
  String get baoBashRecommended => 'BaoCode Bash (được khuyến nghị)';

  @override
  String get baoBashDescription =>
      'Một bash hoàn chỉnh dành cho các tác nhân trên Windows: rg, grep, sed, awk, find, jq, tar và khoảng 80 lệnh phổ biến khác được tích hợp sẵn, không cần Git cho Windows và các đường dẫn C:\\ và /c/ giống nhau. Cả lõi tích hợp và Claude Code đều chạy các lệnh của đặc vụ của họ bằng nó.';

  @override
  String get baoBashNotInstalled => 'Chưa được cài đặt.';

  @override
  String baoBashInstalled(String version) {
    return 'Đã cài đặt phiên bản $version.';
  }

  @override
  String baoBashUpdateAvailable(String version) {
    return 'Phiên bản $version đã hết.';
  }

  @override
  String baoBashDownloading(int percent) {
    return 'Đang tải xuống… $percent%';
  }

  @override
  String get baoBashInstall => 'Cài đặt';

  @override
  String baoBashInstallSize(String size) {
    return 'Cài đặt ($size)';
  }

  @override
  String get baoBashUpdate => 'Cập nhật';

  @override
  String get baoBashUninstall => 'Gỡ cài đặt';

  @override
  String baoBashFailed(String error) {
    return 'Không thể cài đặt nó: $error';
  }

  @override
  String get baoBashNoticeTitle => 'Trên Windows nên sử dụng BaoCode Bash';

  @override
  String get baoBashNoticeBody =>
      'Các agent chạy lệnh đáng tin cậy hơn với nó. Nó mang đến bash với rg, grep, sed, awk, find, jq, tar và khoảng 80 lệnh phổ biến khác, không cần Git cho Windows; nó có các đường dẫn C:\\ và /c/ giống nhau, do đó các lệnh không còn bị lỗi do sự khác biệt giữa cmd và PowerShell.';

  @override
  String get baoBashNoticeLater => 'Không phải bây giờ';

  @override
  String get baoBashSource => 'Nguồn mở:';

  @override
  String get baoBashHintInstall => 'Cài đặt và sử dụng';

  @override
  String get commandLineShell => 'Vỏ bọc';

  @override
  String get commandLineShellDescription =>
      'Tác nhân nào chạy lệnh của họ trên Windows. Lõi CLI của Claude Code chỉ sử dụng bash: với cmd hoặc PowerShell được chọn, nó chạy Git Bash.';

  @override
  String get commandLineShellCustom => 'Phong tục…';

  @override
  String commandLineShellInUse(String path) {
    return 'Đang sử dụng: $path';
  }

  @override
  String commandLineShellFallback(String shell, String path) {
    return '$shell chưa sẵn sàng: trong khi đó các lệnh chạy trong $path.';
  }

  @override
  String get commandLineCustomPath => 'Vỏ tùy chỉnh';

  @override
  String get commandLineCustomPathDescription =>
      'Chương trình chạy lệnh với: bash.exe, cmd.exe, powershell.exe hoặc pwsh.exe.';

  @override
  String remoteBrowserFolderTitle(String host) {
    return 'Mở một thư mục trên $host';
  }

  @override
  String remoteBrowserFileTitle(String host) {
    return 'Mở tệp trên $host';
  }

  @override
  String get remoteBrowserPlaces => 'Địa điểm';

  @override
  String get remoteBrowserRecent => 'Vị trí gần đây';

  @override
  String get remoteBrowserHome => 'Trang chủ';

  @override
  String get remoteBrowserThisPc => 'Máy tính này';

  @override
  String get remoteBrowserRoot => 'Gốc';

  @override
  String remoteBrowserLocalDisk(String drive) {
    return 'Đĩa cục bộ ($drive)';
  }

  @override
  String get remoteBrowserBack => 'Mặt sau';

  @override
  String get remoteBrowserForward => 'Phía trước';

  @override
  String get remoteBrowserRefresh => 'Làm cho khỏe lại';

  @override
  String get remoteBrowserFilter => 'Lọc';

  @override
  String get remoteBrowserView => 'Xem tùy chọn';

  @override
  String get remoteBrowserShowHidden => 'Mục ẩn';

  @override
  String get remoteBrowserShowSystem => 'Tệp hệ điều hành được bảo vệ';

  @override
  String get remoteBrowserNewFolder => 'Thư mục mới';

  @override
  String get remoteBrowserOpen => 'Mở';

  @override
  String get remoteBrowserEmpty => 'Thư mục này trống.';

  @override
  String get remoteBrowserNoFolders => 'Không có thư mục nào ở đây.';

  @override
  String remoteBrowserNoMatch(String filter) {
    return 'Không có gì ở đây khớp với “$filter”.';
  }

  @override
  String remoteBrowserHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Các mục ẩn của $count',
      one: '1 mục ẩn',
    );
    return '$_temp0';
  }

  @override
  String get remoteBrowserShowHiddenNow => 'Trình diễn';

  @override
  String get remoteBrowserEditPath => 'Đi đến một con đường';

  @override
  String get remoteBrowserPathPlaceholder =>
      'Đường dẫn: ~/code, /srv/app, D:\\work';

  @override
  String remoteBrowserNotFound(String path) {
    return '$path không tồn tại.';
  }

  @override
  String remoteBrowserNotFolder(String path) {
    return '$path là một tệp, không phải thư mục.';
  }

  @override
  String remoteBrowserMakeFailed(String error) {
    return 'Không thể tạo thư mục: $error';
  }

  @override
  String get remoteBrowserFolderAction => 'Mở thư mục';

  @override
  String get remoteBrowserFileAction => 'Mở tệp';

  @override
  String remoteBrowserSaveTitle(String host) {
    return 'Lưu vào $host';
  }

  @override
  String get remoteBrowserSaveAction => 'Lưu dưới dạng';

  @override
  String get remoteBrowserSaveName => 'Lưu dưới dạng:';

  @override
  String get remoteBrowserSave => 'Cứu';

  @override
  String remoteBrowserReplace(String name) {
    return '“$name” đã tồn tại. Thay thế nó?';
  }
}
