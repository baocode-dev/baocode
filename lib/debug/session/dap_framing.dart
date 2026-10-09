/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// DAP's base protocol on a byte stream: `Content-Length` headers, a blank
// line, then the JSON message.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/node/debugAdapter.ts (`StreamDebugAdapter`
// `sendMessage` and `handleData`).

import 'dart:convert';
import 'dart:typed_data';

import '../common/debug_types.dart';

/// [message] framed for the wire.
Uint8List encodeDapMessage(Json message) {
  final json = utf8.encode(jsonEncode(message));
  final header = ascii.encode('Content-Length: ${json.length}\r\n\r\n');
  return Uint8List(header.length + json.length)
    ..setRange(0, header.length, header)
    ..setRange(header.length, header.length + json.length, json);
}

/// Takes bytes as they come, and hands out each whole message.
final class DapMessageReader {
  DapMessageReader({required this.onMessage, required this.onError});

  final void Function(Json message) onMessage;
  final void Function(Object error) onError;

  final BytesBuilder _raw = BytesBuilder(copy: false);
  Uint8List _data = Uint8List(0);
  int _contentLength = -1;

  static const _twoCrlf = [13, 10, 13, 10];

  void add(List<int> chunk) {
    if (_data.isEmpty) {
      _data = Uint8List.fromList(chunk);
    } else {
      _raw
        ..add(_data)
        ..add(chunk);
      _data = _raw.takeBytes();
    }
    while (true) {
      if (_contentLength >= 0) {
        if (_data.length >= _contentLength) {
          final body = _data.sublist(0, _contentLength);
          _data = _data.sublist(_contentLength);
          _contentLength = -1;
          if (body.isNotEmpty) {
            final text = utf8.decode(body, allowMalformed: true);
            try {
              final decoded = jsonDecode(text);
              if (decoded is Map) {
                onMessage(decoded.cast<String, Object?>());
              }
            } on FormatException catch (e) {
              onError(FormatException('${e.message}\n$text'));
            }
          }
          continue;
        }
      } else {
        final index = _indexOfTwoCrlf();
        if (index != -1) {
          final header = latin1.decode(_data.sublist(0, index));
          for (final line in header.split(RegExp(r'\r?\n'))) {
            final pair = line.split(RegExp(r': *'));
            if (pair.first == 'Content-Length' && pair.length > 1) {
              _contentLength = int.tryParse(pair[1].trim()) ?? -1;
            }
          }
          _data = _data.sublist(index + 4);
          continue;
        }
      }
      break;
    }
  }

  int _indexOfTwoCrlf() {
    outer:
    for (var i = 0; i + 3 < _data.length; i++) {
      for (var j = 0; j < 4; j++) {
        if (_data[i + j] != _twoCrlf[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
