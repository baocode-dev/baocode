import 'conversation_search.dart';

/// No kept conversations on the web.
class ClaudeConversationSearch extends NoConversationSearch {
  ClaudeConversationSearch({this.configDir, this.indexDir});

  final String? configDir;
  final String? indexDir;
}
