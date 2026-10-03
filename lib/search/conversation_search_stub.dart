import 'conversation_search.dart';

/// No kept conversations on the web.
class ClaudeConversationSearch extends NoConversationSearch {
  ClaudeConversationSearch({this.configDir});

  final String? configDir;
}
