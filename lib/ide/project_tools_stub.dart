import 'project_tools.dart';

class LocalIdeProjectTools implements IdeProjectTools {
  LocalIdeProjectTools(String root);

  static const _unsupported = IdeProjectToolsException(
    'Local project search and Git are unavailable in the browser. '
    'Open this project in the desktop app.',
  );

  @override
  Future<IdeSearchResult> search(
    String query, {
    bool caseSensitive = false,
    IdeSearchCancellation? cancellation,
    IdeSearchLimits limits = const IdeSearchLimits(),
  }) async => throw _unsupported;

  @override
  Future<IdeGitSnapshot> gitStatus({int maxEntries = 1000}) async =>
      throw _unsupported;
}
