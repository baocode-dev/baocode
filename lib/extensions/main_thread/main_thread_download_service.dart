/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDownloadService.ts with
// src/vs/platform/download/common/downloadService.ts (`DownloadService.
// download`: a `file:` source is copied; anything else is fetched, a
// response other than 200 is an error, the body is written to the target).
//
// Deviations: only `file:` targets (the app's own file system); the body
// goes through a temporary file renamed into place.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';

final class MainThreadDownloadService
    extends MainThreadDownloadServiceUnsupported {
  MainThreadDownloadService({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadDownloadServiceActor(MainThreadDownloadService());

  @override
  Future<void> $download(VsUri uri, VsUri to) async {
    if (to.scheme != 'file') {
      throw UnsupportedError('Cannot download to ${to.scheme}: URIs');
    }
    final target = File(to.fsPath(windows: Platform.isWindows));
    await target.parent.create(recursive: true);
    if (uri.scheme == 'file') {
      await File(uri.fsPath(windows: Platform.isWindows)).copy(target.path);
      return;
    }
    final client = _client();
    final temp = File('${target.path}.download');
    try {
      final request = await client.getUrl(Uri.parse(uri.toString()));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException(
          'Expected 200, got back ${response.statusCode} instead.\n\n'
          '${uri.toString()} --> ${to.toString()}',
        );
      }
      await response.pipe(temp.openWrite());
      await temp.rename(target.path);
    } finally {
      client.close();
      if (await temp.exists()) await temp.delete();
    }
  }
}
