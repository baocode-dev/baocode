// Copyright (c) 2020 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/services/OscLinkService.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/attribute_data.dart';
import 'package:baocode/ide/terminal/xterm/common/services/buffer_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/options_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/osc_link_service.dart';
import 'package:baocode/ide/terminal/xterm/common/services/services.dart';
import 'package:baocode/ide/terminal/xterm/common/types.dart';

import '../test_utils.dart';

void main() {
  group('OscLinkService', () {
    group('constructor', () {
      late IBufferService bufferService;
      late IOptionsService optionsService;
      late IOscLinkService oscLinkService;
      setUp(() {
        optionsService = OptionsService(ITerminalOptions(rows: 3, cols: 10));
        bufferService = BufferService(optionsService, MockLogService());
        oscLinkService = OscLinkService(bufferService);
      });

      test('link IDs are created and fetched consistently', () {
        final linkId = oscLinkService.registerLink(
          IOscLinkData(id: 'foo', uri: 'bar'),
        );
        expect(linkId, isNonZero);
        expect(
          oscLinkService.registerLink(IOscLinkData(id: 'foo', uri: 'bar')),
          linkId,
        );
      });

      test('should dispose the link ID when the last marker is trimmed from the buffer', () {
        // Activate the alt buffer to get 0 scrollback
        bufferService.buffers.activateAltBuffer();
        final linkId = oscLinkService.registerLink(
          IOscLinkData(id: 'foo', uri: 'bar'),
        );
        expect(linkId, isNonZero);
        bufferService.scroll(AttributeData());
        expect(
          oscLinkService.registerLink(IOscLinkData(id: 'foo', uri: 'bar')),
          isNot(linkId),
        );
      });

      test('should fetch link data from link id', () {
        final linkId = oscLinkService.registerLink(
          IOscLinkData(id: 'foo', uri: 'bar'),
        );
        // Upstream deep-equals the data object; IOscLinkData has no `==`, so
        // the fields are compared.
        final data = oscLinkService.getLinkData(linkId);
        expect(data, isNotNull);
        expect(data!.id, 'foo');
        expect(data.uri, 'bar');
      });
    });
  });
}
