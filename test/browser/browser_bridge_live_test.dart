// The browser bridge end to end, in a real browser: a Chromium (Chrome for
// Testing; branded Chrome no longer loads extensions from the command
// line) with BaoCode's extension, its native messaging host (the debug
// app's), and the agents' tools. Run by hand:
//
//   BAO_BROWSER_LIVE="/path/to/Google Chrome for Testing" \
//     flutter test test/browser/browser_bridge_live_test.dart
//
// Its socket is its own: the user's browsers, with the extension too, never
// find it (their hosts look in the user's temporary folder).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/browser/browser_bridge.dart';
import 'package:baocode/browser/browser_tools.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final chrome = Platform.environment['BAO_BROWSER_LIVE'];
  final host = p.absolute(
    'build/macos/Build/Products/Debug/BaoCode.app/Contents/MacOS/'
    'baocode-browser-host',
  );

  test(
    'an agent opens, reads, clicks, types and shoots a page through the extension',
    () async {
      final profile = Directory.systemTemp.createTempSync('bao-browser-');
      final hosts = Directory(p.join(profile.path, 'NativeMessagingHosts'))
        ..createSync();
      File(p.join(hosts.path, '${BrowserBridge.hostName}.json'))
          .writeAsStringSync(
            jsonEncode({
              'name': BrowserBridge.hostName,
              'description': 'BaoCode',
              'path': host,
              'type': 'stdio',
              'allowed_origins': [
                for (final id in BrowserBridge.extensionIds)
                  'chrome-extension://$id/',
              ],
            }),
          );
      // Served: the extension may not reach file:// pages.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/api':
            final body = await utf8.decodeStream(request);
            response
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'echo': body}));
          case '/missing':
            response.statusCode = 404;
          case '/frames':
            // A frame of another site (its own process), and a link to a
            // new tab.
            response
              ..headers.contentType = ContentType.html
              ..write(
                '<title>Frames</title>'
                '<iframe src="http://localhost:${server.port}/inner"></iframe>'
                '<a href="/inner" target="_blank">Pop out</a>',
              );
          case '/inner':
            response
              ..headers.contentType = ContentType.html
              ..write('<title>Inner</title><p>Inside.</p>');
          case '/dot.png':
            response
              ..headers.contentType = ContentType('image', 'png')
              ..add(
                base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
                ),
              );
          default:
            response
              ..headers.contentType = ContentType.html
              ..write('''
<meta charset=utf-8><title>Live</title>
<input id=q placeholder="Search">
<button onclick="document.title = 'clicked ' + q.value">Go</button>
<p>Hello from the page.</p>
<img src="/dot.png">
<div class=c><b>alice</b> first! <button onclick="this.nextElementSibling.hidden = false">Reply</button><input hidden placeholder="Reply to alice" onkeydown="if (event.key === 'Enter') { const t = document.createElement('p'); t.textContent = 'Sent: ' + this.value; document.body.append(t); }"></div>
<div class=c><b>bob</b> second <button onclick="this.nextElementSibling.hidden = false">Reply</button><input hidden placeholder="Reply to bob"></div>
<div id=like style="cursor: pointer">Like</div>
<div contenteditable=true aria-placeholder="Write a note" style="border: 1px solid; min-height: 20px"></div>
<button onclick="document.body.insertAdjacentHTML('beforeend', '<div id=ov style=&quot;position: fixed; inset: 0; background: #0003&quot;>Download our app <button onclick=&quot;ov.remove()&quot;>关闭</button></div>')">Open modal</button>
<script>
  like.addEventListener('click', () => { like.textContent = 'Liked'; });
  console.log('hello', {n: 1});
  console.warn('careful');
  fetch('/api', {method: 'POST', body: JSON.stringify({q: 'baocode'})});
  fetch('/missing');
  setTimeout(() => { const end = performance.now() + 120; while (performance.now() < end); }, 0);
  setTimeout(() => { throw new Error('boom'); }, 10);
</script>
''');
        }
        await response.close();
      });
      final page = 'http://127.0.0.1:${server.port}/';

      // Short: a socket's path has a hundred bytes or so.
      final sockets = Directory('/tmp').createTempSync('bao-');
      addTearDown(() => sockets.deleteSync(recursive: true));
      BrowserBridge.socketFolder = sockets.path;
      final bridge = BrowserBridge.instance;
      await bridge.start();
      expect(bridge.otherApp, isFalse, reason: 'a BaoCode has the socket');
      BrowserTools.register();

      final browser = await Process.start(
        chrome!,
        [
          '--user-data-dir=${profile.path}',
          '--load-extension=${p.absolute('browser_extension')}',
          '--disable-features=DisableLoadExtensionCommandLineSwitch',
          '--no-first-run',
          '--no-default-browser-check',
          '--window-size=1000,700',
          // As on a Retina screen: screenshots made CSS pixels big here.
          '--force-device-scale-factor=2',
          'about:blank',
        ],
        environment: {'TMPDIR': sockets.path, 'XDG_RUNTIME_DIR': sockets.path},
      );
      addTearDown(() {
        browser.kill();
        unawaited(bridge.stop());
      });

      final end = DateTime.now().add(const Duration(seconds: 30));
      while (bridge.browsers.isEmpty && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(bridge.browsers, isNotEmpty, reason: 'the extension connects');
      // Chrome for Testing's brand: never one of the user's browsers.
      expect(bridge.browsers.single.browser, 'Chromium');
      // ignore: avoid_print
      print('connected: ${bridge.browsers.first.browser}');

      var id = 0;
      Future<List<Map>> call(
        String name,
        Map<String, Object?> input, {
        bool error = false,
      }) async {
        final answer = await ClaudeSdkTools.handle({
          'jsonrpc': '2.0',
          'id': ++id,
          'method': 'tools/call',
          'params': {'name': name, 'arguments': input},
        }, const ClaudeSdkCall(cwd: '/'));
        final result = answer['result'] as Map;
        final content = (result['content'] as List).cast<Map>();
        // ignore: avoid_print
        print(
          '$name → ${content.map((c) => c['type'] == 'text' ? c['text'] : '<${c['type']} ${(c['data'] as String).length}>').join()}',
        );
        expect(result['isError'] == true, error, reason: '$name: $content');
        return content;
      }

      // A local HTML file, by its path: the extension let reach files (an
      // unpacked one is; from the store, the user turns it on).
      expect(bridge.browsers.single.fileAccess, isTrue);
      final local = File(p.join(profile.path, 'local.html'))
        ..writeAsStringSync('<title>Local</title><p>From a file.</p>');
      final file = await call('browser_open', {'url': local.path});
      expect(file.first['text'], contains('From a file.'));
      await call('browser_close', {
        'tabId': int.parse(
          RegExp(r'\[(\d+)\]').firstMatch(file.first['text'] as String)![1]!,
        ),
      });

      final opened = await call('browser_open', {'url': page});
      final tabId = int.parse(
        RegExp(r'\[(\d+)\]').firstMatch(opened.first['text'] as String)![1]!,
      );
      await call('browser_tabs', {});
      final snapshot = await call('browser_snapshot', {'tabId': tabId});
      final text = snapshot.first['text'] as String;
      expect(text, contains('Hello from the page.'));
      final input = RegExp(r'\[(\d+)\] textbox').firstMatch(text)![1]!;
      final button = RegExp(r'\[(\d+)\] button').firstMatch(text)![1]!;
      final typed = await call('browser_type', {
        'tabId': tabId,
        'ref': int.parse(input),
        'text': '你好 abc',
      });
      expect(
        typed.first['text'],
        startsWith('Typed into textbox "Search" [$input].'),
      );
      // By its words; what it changed said.
      final clicked = await call('browser_click', {
        'tabId': tabId,
        'text': 'Go',
        'description': 'Click Go',
      });
      expect(
        clicked.first['text'],
        'Clicked button "Go" [$button].\nTitle: clicked 你好 abc',
      );
      // Alike: told apart by what is near, else listed.
      final alike = await call('browser_click', {
        'tabId': tabId,
        'text': 'Reply',
      }, error: true);
      expect(alike.first['text'], startsWith('2 elements match'));
      expect(alike.first['text'], contains('bob second'));
      final reply = await call('browser_click', {
        'tabId': tabId,
        'text': 'Reply',
        'near': 'bob',
      });
      expect(reply.first['text'], contains('textbox "Reply to bob"'));
      // What the page made to click with a hand cursor.
      final liked = await call('browser_click', {
        'tabId': tabId,
        'text': 'Like',
      });
      expect(
        liked.first['text'],
        contains(
          'Changed: [${RegExp(r'\[(\d+)\]').firstMatch(liked.first['text'] as String)![1]}] clickable "Liked" (was "Like")',
        ),
      );
      // Several at once, into a field that shows once asked, and into
      // rich text.
      final acted = await call('browser_act', {
        'tabId': tabId,
        'steps': [
          {'action': 'click', 'text': 'Reply', 'near': 'alice'},
          {
            'action': 'type',
            'into': 'Reply to alice',
            'text': 'yo',
            'submit': true,
          },
          {'action': 'wait', 'text': 'Sent: yo'},
          {'action': 'type', 'into': 'Write a note', 'text': 'note!'},
        ],
      });
      expect(
        acted.first['text'],
        contains('4. Typed into textbox "Write a note"'),
      );
      expect(acted.first['text'], contains('"Sent: yo"'));
      final note = await call('browser_evaluate', {
        'tabId': tabId,
        'expression': 'document.querySelector("[contenteditable]").innerText',
      });
      expect(note.first['text'], '"note!"');
      // Covered: said, with what closes it.
      await call('browser_click', {'tabId': tabId, 'text': 'Open modal'});
      final covered = await call('browser_click', {
        'tabId': tabId,
        'text': 'Go',
      }, error: true);
      expect(
        covered.first['text'],
        contains('is covered by "Download our app'),
      );
      expect(covered.first['text'], contains('button "关闭"'));
      await call('browser_click', {'tabId': tabId, 'text': '关闭'});
      final marked = await call('browser_screenshot', {
        'tabId': tabId,
        'marks': true,
      });
      expect(marked.first['type'], 'image');
      expect(marked.last['text'], contains('button "Go"'));
      await call('browser_press', {'tabId': tabId, 'key': 'Meta+A'});
      final shot = await call('browser_screenshot', {'tabId': tabId});
      expect(shot.first['type'], 'image');
      expect(shot.first['mimeType'], 'image/png');
      final picture = base64Decode(shot.first['data'] as String);
      // Its width, in its header: the page's, in CSS pixels.
      final pictureWidth = ByteData.sublistView(picture).getUint32(16);
      final cssWidth = await call('browser_evaluate', {
        'tabId': tabId,
        'expression': 'innerWidth',
      });
      expect('$pictureWidth', cssWidth.first['text']);
      final console = await call('browser_console', {'tabId': tabId});
      expect(console.first['text'], contains('log: hello'));
      expect(console.first['text'], contains('warning: careful'));
      expect(console.first['text'], contains('Error: boom'));
      final network = await call('browser_network', {'tabId': tabId});
      final api = RegExp(
        r'^(\S+) POST 200 Fetch',
        multiLine: true,
      ).firstMatch(network.first['text'] as String);
      expect(api, isNotNull, reason: 'the POST to /api is listed');
      final failed = await call('browser_network', {
        'tabId': tabId,
        'failed': true,
      });
      expect(failed.first['text'], contains('404'));
      final request = await call('browser_request', {
        'tabId': tabId,
        'id': api![1],
      });
      expect(request.first['text'], contains('{"q":"baocode"}'));
      expect(request.first['text'], contains('"echo"'));
      final document = RegExp(
        r'^(\S+) GET 200 Document',
        multiLine: true,
      ).firstMatch(network.first['text'] as String)![1]!;
      final both = await call('browser_request', {
        'tabId': tabId,
        'ids': [api[1], document],
      });
      expect(both.first['text'], contains('"echo"'));
      expect(both.first['text'], contains('Hello from the page.'));
      final har = p.join(profile.path, 'network.har');
      final saved = await call('browser_network', {
        'tabId': tabId,
        'save': har,
      });
      expect(saved.first['text'], contains('Saved'));
      final entries =
          (jsonDecode(File(har).readAsStringSync())['log']['entries'] as List)
              .cast<Map>();
      final post = entries.firstWhere((e) => e['request']['method'] == 'POST');
      expect(post['request']['postData']['text'], '{"q":"baocode"}');
      expect(post['response']['content']['text'], contains('"echo"'));
      final image = await call('browser_network', {
        'tabId': tabId,
        'type': 'Image',
      });
      final imageId = (image.first['text'] as String).split(' ').first;
      final png = await call('browser_request', {
        'tabId': tabId,
        'id': imageId,
      });
      expect(png.last['type'], 'image');
      final performance = await call('browser_performance', {'tabId': tabId});
      final report = performance.first['text'] as String;
      expect(report, contains('LCP'));
      expect(report, contains('Long tasks'));
      final trace = RegExp(r'Trace: (\S+)').firstMatch(report)![1]!;
      expect(File(trace).existsSync(), isTrue);
      await call('browser_emulate', {
        'tabId': tabId,
        'cpu': 4,
        'network': 'fast3g',
        'device': 'phone',
      });
      final width = await call('browser_evaluate', {
        'tabId': tabId,
        'expression': 'screen.width',
      });
      expect(width.first['text'], '390');
      await call('browser_emulate', {
        'tabId': tabId,
        'cpu': 1,
        'network': 'none',
        'device': 'none',
      });
      await call('browser_navigate', {'tabId': tabId, 'action': 'reload'});
      // Watching the user: their doings (trusted input, as the
      // DevTools protocol's is) recorded until they say they are done.
      final watched = call('browser_watch', {
        'tabId': tabId,
        'task': 'Search for abc',
      });
      while (BrowserWatching.current.value == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final user = bridge.browsers.single;
      Future<void> clickOn(String selector) async {
        final point =
            ((await user.cdp(tabId, 'Runtime.evaluate', {
                      'expression':
                          '(() => { const r = document.querySelector("$selector")'
                          '.getBoundingClientRect(); return [r.x + r.width / 2,'
                          ' r.y + r.height / 2]; })()',
                      'returnByValue': true,
                    }))['result']
                    as Map)['value']
                as List;
        for (final type in ['mousePressed', 'mouseReleased']) {
          await user.cdp(tabId, 'Input.dispatchMouseEvent', {
            'type': type,
            'x': point[0],
            'y': point[1],
            'button': 'left',
            'clickCount': 1,
          });
        }
      }

      await clickOn('#q');
      await user.cdp(tabId, 'Input.insertText', {'text': 'abc'});
      await clickOn('button');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(BrowserWatching.current.value!.steps, hasLength(3));
      BrowserWatching.current.value!.finish();
      final seen = await watched;
      final steps = seen.first['text'] as String;
      expect(steps, contains('The user is done'));
      expect(steps, contains('set input[text] "Search" (#q) to "abc"'));
      expect(steps, contains('clicked button "Go"'));
      expect(seen.where((b) => b['type'] == 'image'), isNotEmpty);
      expect(BrowserWatching.current.value, isNull);

      // What lets BaoCode grow without a new extension: the browser's APIs
      // within the tabs shared, frames' sessions, tabs the shared open.
      final connection = bridge.browsers.single;
      expect(
        connection.capabilities,
        containsAll(['cdp.session', 'call', 'subscribe', 'configure']),
      );
      final sharedTabs = await connection.call('tabs.query', [{}]) as List;
      // The window's first tab, about:blank, is not shared: left out.
      expect([for (final Map tab in sharedTabs) tab['id']], [tabId]);
      final windows = await connection.call('windows.getAll', [
        {'populate': true},
      ]) as List;
      expect(
        [
          for (final Map window in windows)
            for (final Map tab in window['tabs'] as List) tab['id'],
        ],
        [tabId],
      );
      await expectLater(
        connection.call('tabs.remove', [999999]),
        throwsA(isA<Object>()),
      );
      await expectLater(
        connection.call('runtime.reload'),
        throwsA(
          isA<BrowserError>().having(
            (e) => e.message,
            'message',
            contains('Not a method'),
          ),
        ),
      );
      expect(await connection.subscribe(['tabs.onActivated', 'bogus']), [
        'tabs.onActivated',
      ]);

      final attachedFrame = bridge.events
          .where(
            (e) =>
                e.event == 'cdp' &&
                e.message['method'] == 'Target.attachedToTarget' &&
                ((e.message['params'] as Map)['targetInfo'] as Map)['type'] ==
                    'iframe',
          )
          .first;
      await call('browser_navigate', {'tabId': tabId, 'url': '${page}frames'});
      // The page before's API answer, kept though the browser let it go.
      final before = await call('browser_request', {
        'tabId': tabId,
        'id': api[1],
      });
      expect(before.first['text'], contains('"echo"'));
      await connection.cdp(tabId, 'Target.setAutoAttach', {
        'autoAttach': true,
        'waitForDebuggerOnStart': false,
        'flatten': true,
      });
      final frame =
          (await attachedFrame.timeout(const Duration(seconds: 10)))
                  .message['params']
              as Map;
      // Asked through its session, the frame answers, not the page.
      final inner = await connection.cdp(
        tabId,
        'Runtime.evaluate',
        {'expression': 'window === window.top', 'returnByValue': true},
        const Duration(seconds: 10),
        frame['sessionId'] as String,
      );
      expect((inner['result'] as Map)['value'], isFalse);

      final popped = bridge.events
          .where(
            (e) =>
                e.event == 'tab' && (e.message['tab'] as Map)['tabId'] != tabId,
          )
          .first;
      await call('browser_click', {'tabId': tabId, 'text': 'Pop out'});
      final popTab =
          ((await popped.timeout(const Duration(seconds: 10))).message['tab']
                  as Map)['tabId']
              as int;
      final nowShared = await connection.call('tabs.query', [{}]) as List;
      expect([for (final Map tab in nowShared) tab['id']], contains(popTab));
      await connection.call('tabs.remove', [popTab]);
      await call('browser_close', {'tabId': tabId});
    },
    skip: chrome == null ? 'BAO_BROWSER_LIVE not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
