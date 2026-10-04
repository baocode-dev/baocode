/// The app's side of a remote project: connecting over SSH, and the typed
/// calls to the server there.
library;

export 'protocol.dart';
export 'src/claude/claude_release.dart' show ClaudeBuild, ClaudeRelease;
export 'src/client/remote_client.dart';
export 'src/client/remote_process.dart';
export 'src/client/remote_review_store.dart';
export 'src/client/ssh_config.dart';
export 'src/client/ssh_launcher.dart';
export 'src/files/recursive_watch.dart' show WatchChange, WatchEvent;
