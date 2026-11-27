import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/jdt_language_tools.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';

void main() {
  test('recognizes JDT LS by base/derived id, Mason package, or command', () {
    for (final server in const [
      LspServerDefinition(id: 'jdtls', command: 'java'),
      LspServerDefinition(id: 'jdtls#project', command: 'java'),
      LspServerDefinition(
        id: 'custom-java',
        command: 'java',
        masonPackage: 'jdtls',
      ),
      LspServerDefinition(id: 'custom-java', command: 'jdtls'),
      LspServerDefinition(id: 'custom-java', command: '/opt/bin/jdtls'),
      LspServerDefinition(id: 'custom-java', command: r'C:\bin\JDTLS.CMD'),
      LspServerDefinition(id: 'custom-java', command: r'C:\bin\jdtls.exe'),
      LspServerDefinition(id: 'custom-java', command: r'C:\bin\jdtls.bat'),
      LspServerDefinition(id: 'custom-java', command: '/opt/bin/jdtls.js'),
    ]) {
      expect(
        isJdtLanguageServer(server),
        isTrue,
        reason: '${server.id}: ${server.command}',
      );
    }
    for (final server in const [
      LspServerDefinition(id: 'java', command: 'java'),
      LspServerDefinition(id: 'jdtls-custom', command: 'custom-jdtls'),
      LspServerDefinition(id: 'java#jdtls', command: '/opt/jdtls/java'),
      LspServerDefinition(
        id: 'java',
        command: 'java',
        masonPackage: 'jdtls-custom',
      ),
    ]) {
      expect(
        isJdtLanguageServer(server),
        isFalse,
        reason: '${server.id}: ${server.command}',
      );
    }
  });

  test('adds class-file contents support when JDT LS has no options', () {
    expect(
      jdtInitializationOptions(
        const LspServerDefinition(id: 'jdtls', command: 'jdtls'),
      ),
      {
        'extendedClientCapabilities': {'classFileContentsSupport': true},
      },
    );
  });

  test('merges JDT capabilities without mutating other user options', () {
    const options = {
      'bundles': ['java-debug.jar'],
      'workspaceFolders': ['file:///workspace'],
      'extendedClientCapabilities': {
        'classFileContentsSupport': false,
        'progressReportProvider': true,
        'advancedExtractRefactoringSupport': true,
      },
    };
    const server = LspServerDefinition(
      id: 'jdtls#project',
      command: 'java',
      initializationOptions: options,
    );
    final merged = jdtInitializationOptions(server)!;
    expect(merged, {
      ...options,
      'extendedClientCapabilities': {
        'classFileContentsSupport': true,
        'progressReportProvider': true,
        'advancedExtractRefactoringSupport': true,
      },
    });
    expect(merged, isNot(same(options)));
    expect(
      (options['extendedClientCapabilities']!
          as Map)['classFileContentsSupport'],
      isFalse,
    );
    expect(server.initializationOptions, same(options));
  });

  test('leaves non-JDT initialization options, including null, unchanged', () {
    const options = {
      'extendedClientCapabilities': {'classFileContentsSupport': false},
      'hostInfo': 'custom',
    };
    expect(
      jdtInitializationOptions(
        const LspServerDefinition(
          id: 'other',
          command: 'other',
          initializationOptions: options,
        ),
      ),
      same(options),
    );
    expect(
      jdtInitializationOptions(
        const LspServerDefinition(id: 'other', command: 'other'),
      ),
      isNull,
    );
  });
}
