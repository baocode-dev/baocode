#!/usr/bin/env python3
"""How BaoCode's own core (packages/bao_agent) stands against the Claude
Code CLI installed on this machine: what each sends the API for the same
first message.

Both are run against a fake API on 127.0.0.1 that keeps their requests and
answers "ok". The report compares the request parameters, the tool sets and
their parameters, and how much of our text (tool descriptions, parameter
descriptions, system prompt) is the same as the CLI's, word for word: the
share of ours in runs of 40 or more characters found in theirs. We write
our own text, so that share should stay near zero.

Nothing of the CLI's is kept: its requests go to a temporary folder that is
removed afterwards (unless --keep names one outside the repository).

    python3 tool/core_parity.py [--model claude-sonnet-5-5] [--matches]
"""

import argparse
import difflib
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_RUN = 40


class Capture:
    def __init__(self):
        self.requests = []
        self.lock = threading.Lock()


def serve(capture):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def _body(self):
            if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
                data = b''
                while True:
                    size = int(self.rfile.readline().strip().split(b';')[0], 16)
                    if size == 0:
                        self.rfile.readline()
                        return data
                    data += self.rfile.read(size)
                    self.rfile.readline()
            return self.rfile.read(int(self.headers.get('Content-Length') or 0))

        def _send(self, code, kind, payload):
            self.send_response(code)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            self._send(404, 'application/json', b'{}')

        def do_POST(self):
            raw = self._body()
            try:
                body = json.loads(raw or b'{}')
            except ValueError:
                body = {}
            with capture.lock:
                capture.requests.append({
                    'path': self.path,
                    'headers': {k.lower(): v for k, v in self.headers.items()},
                    'body': body,
                })
            if 'count_tokens' in self.path:
                self._send(200, 'application/json', b'{"input_tokens": 10}')
                return
            if not self.path.startswith('/v1/messages'):
                self._send(404, 'application/json', b'{}')
                return
            model = body.get('model', 'model')
            message = {
                'id': 'msg_parity', 'type': 'message', 'role': 'assistant',
                'model': model, 'content': [], 'stop_reason': None,
                'stop_sequence': None,
                'usage': {'input_tokens': 1, 'output_tokens': 1},
            }
            if not body.get('stream'):
                message['content'] = [{'type': 'text', 'text': 'ok'}]
                message['stop_reason'] = 'end_turn'
                self._send(200, 'application/json', json.dumps(message).encode())
                return
            events = [
                ('message_start', {'type': 'message_start', 'message': message}),
                ('content_block_start', {'type': 'content_block_start', 'index': 0,
                                         'content_block': {'type': 'text', 'text': ''}}),
                ('content_block_delta', {'type': 'content_block_delta', 'index': 0,
                                         'delta': {'type': 'text_delta', 'text': 'ok'}}),
                ('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
                ('message_delta', {'type': 'message_delta',
                                   'delta': {'stop_reason': 'end_turn', 'stop_sequence': None},
                                   'usage': {'output_tokens': 1}}),
                ('message_stop', {'type': 'message_stop'}),
            ]
            payload = ''.join(
                f'event: {name}\ndata: {json.dumps(data)}\n\n' for name, data in events
            ).encode()
            self._send(200, 'text/event-stream', payload)

    class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True

    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def run(command, home, extra_env=None, timeout=90):
    """Runs [command] with a home of its own, on the fake API, until it ends
    or [timeout]; the requests it made."""
    capture = Capture()
    server = serve(capture)
    os.makedirs(os.path.join(home, 'config'), exist_ok=True)
    env = {
        'HOME': home,
        'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
        'CLAUDE_CONFIG_DIR': os.path.join(home, 'config'),
        'ANTHROPIC_API_KEY': 'sk-parity',
        'ANTHROPIC_BASE_URL': f'http://127.0.0.1:{server.server_address[1]}',
        'CLAUDE_CODE_MAX_RETRIES': '0',
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
        **(extra_env or {}),
    }
    work = os.path.join(home, 'project')
    os.makedirs(work, exist_ok=True)
    message = json.dumps({
        'type': 'user',
        'message': {'role': 'user', 'content': 'hi'},
    }) + '\n'
    # To a file: a pipe left unread could fill and stop it.
    errors = open(os.path.join(home, 'stderr.txt'), 'w+b')
    process = subprocess.Popen(
        command, cwd=work, env=env, stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL, stderr=errors,
    )
    try:
        process.stdin.write(message.encode())
        process.stdin.flush()
        # Input kept open (ours stops at its end) until the turn is asked.
        deadline = time.time() + timeout
        while process.poll() is None and time.time() < deadline:
            with capture.lock:
                if any(r['body'].get('tools') for r in capture.requests):
                    break
            time.sleep(0.2)
        time.sleep(1)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        errors.seek(0)
        error = errors.read().decode(errors='replace')
        errors.close()
        server.shutdown()
    if not capture.requests:
        sys.exit(f'{command[0]} made no request:\n{error[-2000:]}')
    return capture.requests


def main_request(requests):
    """The agent's own turn: the request with the most tools."""
    return max(requests, key=lambda r: len(r['body'].get('tools') or []))


def text_of(system):
    if isinstance(system, str):
        return system
    return '\n\n'.join(b.get('text', '') for b in system or [] if isinstance(b, dict))


def described(schema):
    """Every description in a JSON schema, depth first."""
    out = []
    if isinstance(schema, dict):
        if isinstance(schema.get('description'), str):
            out.append(schema['description'])
        for value in schema.values():
            out.extend(described(value))
    elif isinstance(schema, list):
        for value in schema:
            out.extend(described(value))
    return out


def overlap(ours, theirs):
    """The share of [ours] in runs of MIN_RUN characters or more that are in
    [theirs] too, and those runs."""
    if not ours or not theirs:
        return 0.0, []
    matcher = difflib.SequenceMatcher(None, ours, theirs, autojunk=False)
    runs = [ours[b.a:b.a + b.size] for b in matcher.get_matching_blocks()
            if b.size >= MIN_RUN]
    return sum(map(len, runs)) / len(ours), runs


def shown(value, width=160):
    text = json.dumps(value)
    return text if len(text) <= width else text[:width - 1] + '…'


def compare(official, ours, show_matches, root):
    # The runs' own folders are not text of either.
    def plain(text):
        for prefix in ('/private' + root, root):
            text = text.replace(prefix, '<tmp>')
        return text

    a, b = official['body'], ours['body']
    print('# Request')
    for key in sorted((set(a) | set(b)) - {'messages', 'system', 'tools'}):
        left, right = a.get(key), b.get(key)
        if key == 'metadata':
            left = sorted((left or {}).keys())
            right = sorted((right or {}).keys())
        mark = ' ' if left == right else '≠'
        print(f'{mark} {key}: CLI {shown(left)} | ours {shown(right)}')
    betas_a = set(filter(None, official['headers'].get('anthropic-beta', '').split(',')))
    betas_b = set(filter(None, ours['headers'].get('anthropic-beta', '').split(',')))
    print(f'  betas, both: {", ".join(sorted(betas_a & betas_b)) or "-"}')
    print(f'≠ betas, CLI only: {", ".join(sorted(betas_a - betas_b)) or "-"}')
    print(f'≠ betas, ours only: {", ".join(sorted(betas_b - betas_a)) or "-"}')

    print('\n# Tools')
    tools_a = {t.get('name'): t for t in a.get('tools') or []}
    tools_b = {t.get('name'): t for t in b.get('tools') or []}
    print(f'CLI only: {", ".join(sorted(set(tools_a) - set(tools_b))) or "-"}')
    print(f'ours only: {", ".join(sorted(set(tools_b) - set(tools_a))) or "-"}')
    rows = []
    for name in sorted(set(tools_a) & set(tools_b)):
        ta, tb = tools_a[name], tools_b[name]
        pa = set((ta.get('input_schema') or {}).get('properties') or {})
        pb = set((tb.get('input_schema') or {}).get('properties') or {})
        theirs = '\n'.join([ta.get('description') or ''] + described(ta.get('input_schema')))
        mine = '\n'.join([tb.get('description') or ''] + described(tb.get('input_schema')))
        share, runs = overlap(mine, theirs)
        rows.append((name, share, sorted(pa - pb), sorted(pb - pa), runs))
    for name, share, only_a, only_b, runs in rows:
        params = ''
        if only_a:
            params += f'  params CLI only: {", ".join(only_a)}'
        if only_b:
            params += f'  params ours only: {", ".join(only_b)}'
        print(f'{name:<16} same text {share:6.1%}{params}')
        if show_matches:
            for run in runs:
                print(f'    “{run[:100]}”')

    print('\n# System prompt')
    share, runs = overlap(plain(text_of(b.get('system'))),
                          plain(text_of(a.get('system'))))
    print(f'same text {share:.1%} ({len(runs)} runs)')
    if show_matches:
        for run in runs:
            print(f'    “{run[:100]}”')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--model', default='claude-sonnet-5-5')
    parser.add_argument('--claude', default=shutil.which('claude') or 'claude',
                        help='the Claude Code CLI to compare with')
    parser.add_argument('--matches', action='store_true',
                        help='print the runs of text found in both')
    parser.add_argument('--keep', help='a folder (outside the repository) '
                        'to keep the requests in')
    args = parser.parse_args()
    dart = shutil.which('dart')
    if dart is None:
        sys.exit('dart is not on PATH')
    # As the app runs either.
    flags = ['-p', '--input-format', 'stream-json', '--output-format',
             'stream-json', '--verbose', '--thinking-display', 'summarized',
             '--model', args.model]
    root = tempfile.mkdtemp(prefix='core-parity-')
    try:
        official = run([args.claude, *flags], os.path.join(root, 'cli'))
        ours = run(
            [dart, 'run', os.path.join(REPO, 'packages/bao_agent/bin/bao_agent.dart'), *flags],
            os.path.join(root, 'ours'),
            extra_env={
                # The fake API stands for Anthropic's own: requests laid out
                # as for it, as the CLI lays out all of its.
                'BAOCODE_FIRST_PARTY_API': '1',
                'PUB_CACHE': os.environ.get('PUB_CACHE')
                or os.path.join(os.path.expanduser('~'), '.pub-cache'),
                'PATH': os.path.dirname(dart) + os.pathsep + os.environ.get('PATH', ''),
            },
            timeout=180,
        )
        if args.keep:
            keep = os.path.abspath(args.keep)
            if keep.startswith(REPO + os.sep):
                sys.exit('--keep must be outside the repository')
            os.makedirs(keep, exist_ok=True)
            for name, requests in (('cli', official), ('ours', ours)):
                with open(os.path.join(keep, f'{name}.json'), 'w') as out:
                    json.dump(requests, out, indent=1, ensure_ascii=False)
        print(f'CLI: {subprocess.run([args.claude, "--version"], capture_output=True, text=True).stdout.strip()}, '
              f'model {args.model}\n')
        compare(main_request(official), main_request(ours), args.matches,
                os.path.realpath(root).removeprefix('/private'))
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == '__main__':
    main()
