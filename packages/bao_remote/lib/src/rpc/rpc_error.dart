import 'package:bao_exthost/bao_exthost.dart'
    show ExtHostRuntimeErrorKind, ExtHostRuntimeException;

import '../claude/claude_unavailable.dart';
import '../files/ide_file.dart';
import '../git/git_types.dart';
import '../lsp/lsp_server_definition.dart';
import '../review/review_store.dart';
import 'rpc_peer.dart';

/// Something the remote host failed at that has no type of its own here:
/// what it said, and what it was there ([type]).
class RemoteException implements Exception {
  const RemoteException(this.message, {this.type});

  final String message;

  /// The failure's type on the remote host (`FileSystemException`, …).
  final String? type;

  @override
  String toString() => message;
}

/// A JSON-RPC error: [code], [message] and the failure as [data], so that
/// the asking side throws what the answering side did (see [from] and
/// [toException]).
class RpcError {
  const RpcError(this.code, this.message, {this.data});

  factory RpcError.fromJson(Map<String, Object?> json) => RpcError(
    json['code'] as int? ?? internalError,
    json['message'] as String? ?? '',
    data: switch (json['data']) {
      final Map data => data.cast<String, Object?>(),
      _ => null,
    },
  );

  /// [error] as the asking side should get it: the exceptions both sides
  /// know by type, anything else by what it says.
  factory RpcError.from(Object error, [StackTrace? stack]) => switch (error) {
    RpcCancelled() => const RpcError(requestCancelled, 'Cancelled'),
    IdeFileConflictException(:final path) => _typed(error, 'conflict', {
      'path': path,
    }),
    IdeFileNotFoundException(:final path) => _typed(error, 'notFound', {
      'path': path,
    }),
    IdeBinaryFileException(:final path) => _typed(error, 'binary', {
      'path': path,
    }),
    IdeFileTooLargeException(:final path, :final size) => _typed(
      error,
      'tooLarge',
      {'path': path, 'size': size},
    ),
    IdeFileExistsException(:final path) => _typed(error, 'exists', {
      'path': path,
    }),
    IdeGitException(:final message) => _typed(error, 'git', {
      'message': message,
    }),
    ClaudeNotInstalled(:final message, :final detail) => _typed(
      error,
      'claudeNotInstalled',
      {'message': message, 'detail': ?detail},
    ),
    ClaudeDownloadFailed(:final message, :final detail) => _typed(
      error,
      'claudeDownloadFailed',
      {'message': message, 'detail': ?detail},
    ),
    ClaudeUnavailable(:final message, :final detail) => _typed(
      error,
      'claudeUnavailable',
      {'message': message, 'detail': ?detail},
    ),
    LspInstallException(:final message, :final detail) => _typed(
      error,
      'lspInstall',
      {'message': message, 'detail': ?detail},
    ),
    ReviewUnavailable(:final message) => _typed(error, 'reviewUnavailable', {
      'message': message,
    }),
    ExtHostRuntimeException(:final kind, :final message, :final statusCode) =>
      _typed(error, 'exthostRuntime', {
        'kind': kind.name,
        'message': message,
        'statusCode': ?statusCode,
      }),
    FormatException(:final message) => _typed(error, 'format', {
      'message': message,
    }),
    RemoteException(:final message, :final type) => RpcError(
      internalError,
      message,
      data: {'type': 'remote', 'remoteType': ?type},
    ),
    _ => RpcError(
      internalError,
      _describe(error),
      data: {'type': 'remote', 'remoteType': error.runtimeType.toString()},
    ),
  };

  static RpcError _typed(
    Object error,
    String type,
    Map<String, Object?> fields,
  ) => RpcError(applicationError, '$error', data: {'type': type, ...fields});

  /// What [error] says, without the name of its type where it leads with
  /// one (`FileSystemException: …`).
  static String _describe(Object error) {
    final text = '$error';
    return text.replaceFirst(RegExp(r'^[A-Z][A-Za-z]*(Exception|Error): '), '');
  }

  static const parseError = -32700;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// A failure of the method itself, typed by [data]'s `type`.
  static const applicationError = -32000;

  /// LSP's code for a request the asker cancelled.
  static const requestCancelled = -32800;

  final int code;
  final String message;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'data': ?data,
  };

  /// What to throw on the asking side.
  Object toException() {
    if (code == requestCancelled) return const RpcCancelled();
    final data = this.data ?? const {};
    String path() => data['path'] as String? ?? '';
    String text() => data['message'] as String? ?? message;
    return switch (data['type']) {
      'conflict' => IdeFileConflictException(path()),
      'notFound' => IdeFileNotFoundException(path()),
      'binary' => IdeBinaryFileException(path()),
      'tooLarge' => IdeFileTooLargeException(path(), data['size'] as int? ?? 0),
      'exists' => IdeFileExistsException(path()),
      'git' => IdeGitException(text()),
      'claudeNotInstalled' => ClaudeNotInstalled(
        text(),
        detail: data['detail'] as String?,
      ),
      'claudeDownloadFailed' => ClaudeDownloadFailed(
        text(),
        detail: data['detail'] as String?,
      ),
      'claudeUnavailable' => ClaudeUnavailable(
        text(),
        detail: data['detail'] as String?,
      ),
      'lspInstall' => LspInstallException(
        text(),
        detail: data['detail'] as String?,
      ),
      'reviewUnavailable' => ReviewUnavailable(text()),
      'exthostRuntime' => ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.values.firstWhere(
          (kind) => kind.name == data['kind'],
          orElse: () => ExtHostRuntimeErrorKind.install,
        ),
        text(),
        statusCode: data['statusCode'] as int?,
      ),
      'format' => FormatException(text()),
      _ => RemoteException(message, type: data['remoteType'] as String?),
    };
  }
}
