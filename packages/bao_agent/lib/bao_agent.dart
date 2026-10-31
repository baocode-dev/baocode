/// BaoCode's own coding agent: Claude Code's protocol, written in Dart.
///
/// A session is an [AgentEngine] (in the caller's isolate) or an
/// [AgentIsolate] (in one of its own), made with [EngineOptions]; it takes
/// and sends the messages of `claude -p --input-format stream-json
/// --output-format stream-json`.
library;

export 'src/api/anthropic_client.dart' show AnthropicClient, ApiConfig;
export 'src/api/model_catalog.dart' show ModelCatalog, ModelInfo;
export 'src/api/model_client.dart'
    show ApiError, ModelClient, ModelRequest, RetryInfo, requestHints;
export 'src/cli/agent_cli.dart' show AgentCommandLine, runAgentCommandLine;
export 'src/config/paths.dart' show AgentPaths;
export 'src/engine/engine.dart'
    show AgentEngine, BuiltInCommand, builtInCommands, engineVersion;
export 'src/engine/isolate.dart' show AgentIsolate;
export 'src/engine/session.dart' show EngineOptions, MissingCredentials;
export 'src/engine/session_store.dart' show agentVersion;
export 'src/util/cancel.dart' show CancelToken, Cancelled;
