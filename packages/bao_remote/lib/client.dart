/// The app's side of a remote project: connecting over SSH, and the typed
/// calls to the server there.
library;

export 'protocol.dart';
export 'src/acp/agy_release.dart' show AgyBuild, AgyRelease;
export 'src/acp/agy_runtime.dart' show AgyModel, AgyUnavailable;
export 'src/acp/swarm_model.dart'
    show
        SwarmAttention,
        SwarmChannel,
        SwarmEdge,
        SwarmMember,
        SwarmMemberRole,
        SwarmMemberStatus,
        SwarmMessage,
        SwarmOverviewData,
        SwarmPlan,
        SwarmPlanThread,
        SwarmSnapshot,
        SwarmWorkerStep,
        SwarmWorkstream;
export 'src/claude/claude_release.dart' show ClaudeBuild, ClaudeRelease;
export 'src/client/remote_client.dart';
export 'src/client/remote_process.dart';
export 'src/client/remote_review_store.dart';
export 'src/client/ssh_config.dart';
export 'src/client/ssh_launcher.dart';
export 'src/client/ssh_servers.dart';
export 'src/client/wsl.dart';
export 'src/files/browse.dart' show BrowseEntry, BrowseRoot, BrowseRootKind;
export 'src/files/recursive_watch.dart' show WatchChange, WatchEvent;
