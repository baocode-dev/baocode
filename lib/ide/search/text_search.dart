import 'package:bao_remote/search.dart';

import 'text_search_stub.dart'
    if (dart.library.io) 'text_search_io.dart'
    as platform;

export 'package:bao_remote/search.dart';

/// Searches with the platform's engine: Git's file list (respecting
/// `.gitignore`) or a walk of the folder, read and matched off the UI
/// isolate.
Stream<Object> ideSearchText(String root, IdeTextQuery query) =>
    platform.searchText(root, query);
