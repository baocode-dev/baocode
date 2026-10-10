// Which Open VSX extensions to recommend for a file, when no installed
// extension provides its language: a data table of languages (VS Code's
// language ids), the file names and extensions that are theirs, and the
// extensions for them, best first. It replaces the language server packs'
// recommendations.
//
// Every id was checked to exist on Open VSX (2026-10-09).

import 'package:path/path.dart' as p;

/// A language and the extensions recommended for it.
class LanguageRecommendation {
  const LanguageRecommendation({
    required this.languageId,
    required this.label,
    required this.extensions,
    this.fileExtensions = const [],
    this.fileNames = const [],
  });

  /// VS Code's id: `python`, `cpp`.
  final String languageId;
  final String label;

  /// Open VSX ids, best first.
  final List<String> extensions;

  /// With the dot, lower-case: `.py`.
  final List<String> fileExtensions;

  /// Whole names, lower-case: `dockerfile`, `cargo.toml`.
  final List<String> fileNames;
}

const languageRecommendations = <LanguageRecommendation>[
  LanguageRecommendation(
    languageId: 'python',
    label: 'Python',
    extensions: [
      'ms-python.python',
      'detachhead.basedpyright',
      'ms-python.debugpy',
    ],
    fileExtensions: ['.py', '.pyi', '.pyw'],
  ),
  LanguageRecommendation(
    languageId: 'go',
    label: 'Go',
    extensions: ['golang.go'],
    fileExtensions: ['.go'],
    fileNames: ['go.mod', 'go.sum', 'go.work'],
  ),
  LanguageRecommendation(
    languageId: 'rust',
    label: 'Rust',
    extensions: ['rust-lang.rust-analyzer', 'vadimcn.vscode-lldb'],
    fileExtensions: ['.rs'],
  ),
  LanguageRecommendation(
    languageId: 'cpp',
    label: 'C/C++',
    extensions: [
      'llvm-vs-code-extensions.vscode-clangd',
      'vadimcn.vscode-lldb',
    ],
    fileExtensions: [
      '.c',
      '.h',
      '.cc',
      '.cpp',
      '.cxx',
      '.c++',
      '.hh',
      '.hpp',
      '.hxx',
      '.ipp',
      '.m',
      '.mm',
    ],
    fileNames: ['compile_commands.json', '.clangd', '.clang-format'],
  ),
  LanguageRecommendation(
    languageId: 'java',
    label: 'Java',
    extensions: ['redhat.java', 'vscjava.vscode-java-debug'],
    fileExtensions: ['.java'],
    fileNames: ['pom.xml'],
  ),
  LanguageRecommendation(
    languageId: 'csharp',
    label: 'C#',
    extensions: ['muhammad-sammy.csharp'],
    fileExtensions: ['.cs', '.csx', '.csproj', '.sln'],
  ),
  LanguageRecommendation(
    languageId: 'php',
    label: 'PHP',
    extensions: ['bmewburn.vscode-intelephense-client'],
    fileExtensions: ['.php', '.phtml'],
  ),
  LanguageRecommendation(
    languageId: 'ruby',
    label: 'Ruby',
    extensions: ['Shopify.ruby-lsp'],
    fileExtensions: ['.rb', '.rake', '.gemspec', '.erb'],
    fileNames: ['gemfile', 'rakefile'],
  ),
  LanguageRecommendation(
    languageId: 'kotlin',
    label: 'Kotlin',
    extensions: ['fwcd.kotlin'],
    fileExtensions: ['.kt', '.kts'],
  ),
  LanguageRecommendation(
    languageId: 'swift',
    label: 'Swift',
    extensions: ['swiftlang.swift-vscode'],
    fileExtensions: ['.swift'],
    fileNames: ['package.swift'],
  ),
  LanguageRecommendation(
    languageId: 'dart',
    label: 'Dart / Flutter',
    extensions: ['Dart-Code.dart-code', 'Dart-Code.flutter'],
    fileExtensions: ['.dart'],
    fileNames: ['pubspec.yaml', 'analysis_options.yaml'],
  ),
  LanguageRecommendation(
    languageId: 'lua',
    label: 'Lua',
    extensions: ['sumneko.lua'],
    fileExtensions: ['.lua'],
  ),
  LanguageRecommendation(
    languageId: 'zig',
    label: 'Zig',
    extensions: ['ziglang.vscode-zig'],
    fileExtensions: ['.zig', '.zon'],
  ),
  LanguageRecommendation(
    languageId: 'haskell',
    label: 'Haskell',
    extensions: ['haskell.haskell'],
    fileExtensions: ['.hs', '.lhs', '.cabal'],
  ),
  LanguageRecommendation(
    languageId: 'elixir',
    label: 'Elixir',
    extensions: ['elixir-lsp.elixir-ls'],
    fileExtensions: ['.ex', '.exs', '.heex'],
  ),
  LanguageRecommendation(
    languageId: 'erlang',
    label: 'Erlang',
    extensions: ['erlang-ls.erlang-ls'],
    fileExtensions: ['.erl', '.hrl'],
  ),
  LanguageRecommendation(
    languageId: 'gleam',
    label: 'Gleam',
    extensions: ['gleam.gleam'],
    fileExtensions: ['.gleam'],
  ),
  LanguageRecommendation(
    languageId: 'scala',
    label: 'Scala',
    extensions: ['scalameta.metals'],
    fileExtensions: ['.scala', '.sc', '.sbt'],
  ),
  LanguageRecommendation(
    languageId: 'clojure',
    label: 'Clojure',
    extensions: ['betterthantomorrow.calva'],
    fileExtensions: ['.clj', '.cljs', '.cljc', '.edn'],
  ),
  LanguageRecommendation(
    languageId: 'julia',
    label: 'Julia',
    extensions: ['julialang.language-julia'],
    fileExtensions: ['.jl'],
  ),
  LanguageRecommendation(
    languageId: 'r',
    label: 'R',
    extensions: ['REditorSupport.r'],
    fileExtensions: ['.r', '.rmd'],
  ),
  LanguageRecommendation(
    languageId: 'ocaml',
    label: 'OCaml',
    extensions: ['ocamllabs.ocaml-platform'],
    fileExtensions: ['.ml', '.mli'],
    fileNames: ['dune', 'dune-project'],
  ),
  LanguageRecommendation(
    languageId: 'nix',
    label: 'Nix',
    extensions: ['jnoortheen.nix-ide'],
    fileExtensions: ['.nix'],
  ),
  LanguageRecommendation(
    languageId: 'terraform',
    label: 'Terraform',
    extensions: ['hashicorp.terraform'],
    fileExtensions: ['.tf', '.tfvars', '.hcl'],
  ),
  LanguageRecommendation(
    languageId: 'yaml',
    label: 'YAML',
    extensions: ['redhat.vscode-yaml'],
    fileExtensions: ['.yaml', '.yml'],
  ),
  LanguageRecommendation(
    languageId: 'toml',
    label: 'TOML',
    extensions: ['tamasfe.even-better-toml'],
    fileExtensions: ['.toml'],
  ),
  LanguageRecommendation(
    languageId: 'dockerfile',
    label: 'Docker',
    extensions: ['docker.docker', 'ms-azuretools.vscode-docker'],
    fileExtensions: ['.dockerfile', '.containerfile'],
    fileNames: [
      'dockerfile',
      'containerfile',
      'docker-compose.yml',
      'docker-compose.yaml',
      'compose.yml',
      'compose.yaml',
    ],
  ),
  LanguageRecommendation(
    languageId: 'markdown',
    label: 'Markdown',
    extensions: ['DavidAnson.vscode-markdownlint'],
    fileExtensions: ['.md', '.markdown'],
  ),
  LanguageRecommendation(
    languageId: 'shellscript',
    label: 'Shell',
    extensions: ['timonwong.shellcheck'],
    fileExtensions: ['.sh', '.bash', '.zsh'],
  ),
  LanguageRecommendation(
    languageId: 'proto3',
    label: 'Protocol Buffers',
    extensions: ['zxh404.vscode-proto3'],
    fileExtensions: ['.proto'],
  ),
  LanguageRecommendation(
    languageId: 'graphql',
    label: 'GraphQL',
    extensions: ['GraphQL.vscode-graphql'],
    fileExtensions: ['.graphql', '.gql'],
  ),
  LanguageRecommendation(
    languageId: 'vue',
    label: 'Vue',
    extensions: ['Vue.volar'],
    fileExtensions: ['.vue'],
  ),
  LanguageRecommendation(
    languageId: 'svelte',
    label: 'Svelte',
    extensions: ['svelte.svelte-vscode'],
    fileExtensions: ['.svelte'],
  ),
  LanguageRecommendation(
    languageId: 'astro',
    label: 'Astro',
    extensions: ['astro-build.astro-vscode'],
    fileExtensions: ['.astro'],
  ),
  LanguageRecommendation(
    languageId: 'javascript',
    label: 'JavaScript / TypeScript',
    extensions: ['dbaeumer.vscode-eslint', 'esbenp.prettier-vscode'],
    fileExtensions: [
      '.js',
      '.jsx',
      '.mjs',
      '.cjs',
      '.ts',
      '.tsx',
      '.mts',
      '.cts',
    ],
    fileNames: [
      '.eslintrc',
      '.eslintrc.json',
      'eslint.config.js',
      '.prettierrc',
    ],
  ),
];

/// The recommendation for [path]'s language, if there is one: its whole
/// name first (`Dockerfile`, `go.mod`), then its extension.
LanguageRecommendation? recommendationForPath(String path) {
  final name = p.basename(path).toLowerCase();
  for (final recommendation in languageRecommendations) {
    if (recommendation.fileNames.contains(name)) return recommendation;
  }
  // `Dockerfile.dev`.
  if (name.startsWith('dockerfile.') || name.startsWith('containerfile.')) {
    return recommendationForLanguage('dockerfile');
  }
  final extension = p.extension(name);
  if (extension.isEmpty) return null;
  for (final recommendation in languageRecommendations) {
    if (recommendation.fileExtensions.contains(extension)) {
      return recommendation;
    }
  }
  return null;
}

/// The recommendation for VS Code's language [languageId].
LanguageRecommendation? recommendationForLanguage(String languageId) {
  final id = switch (languageId) {
    'c' || 'objective-c' || 'objective-cpp' || 'cuda-cpp' => 'cpp',
    'typescript' || 'typescriptreact' || 'javascriptreact' => 'javascript',
    'docker' || 'dockercompose' => 'dockerfile',
    'flutter' => 'dart',
    _ => languageId,
  };
  for (final recommendation in languageRecommendations) {
    if (recommendation.languageId == id) return recommendation;
  }
  return null;
}

/// The Open VSX ids to recommend for [path], best first, without those
/// [installed] (lower-cased ids) has. Empty when an installed one provides
/// its language already ([providesLanguage]).
List<String> recommendationsFor(
  String path, {
  Set<String> installed = const {},
  bool Function(String languageId)? providesLanguage,
}) {
  final recommendation = recommendationForPath(path);
  if (recommendation == null) return const [];
  if (providesLanguage?.call(recommendation.languageId) ?? false) {
    return const [];
  }
  return [
    for (final id in recommendation.extensions)
      if (!installed.contains(id.toLowerCase())) id,
  ];
}
