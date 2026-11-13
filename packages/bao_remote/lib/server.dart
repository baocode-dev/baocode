/// The server of a remote project (see bin/baocode_server.dart).
library;

export 'protocol.dart';
export 'src/claude/claude_settings_file.dart';
export 'src/server/remote_server.dart';
export 'src/server/server_claude.dart' show ServerClaude;
export 'src/server/server_cli.dart' show ServerCli, runCodeCommand;
export 'src/server/server_session.dart';
