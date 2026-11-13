import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'entrypoints.dart';
import 'legacy_sw.dart';

/// A Flutter SDK checkout to build with.
class FlutterSdk {
  FlutterSdk(this.label, this.root);

  final String label;
  final Directory root;

  String get flutterBin => p.join(root.path, 'bin', 'flutter');

  static String _home() => Platform.environment['HOME'] ?? '';

  static Directory _normalizeSdkRoot(String rawPath) {
    final String cleaned = p.normalize(rawPath);
    if (cleaned.endsWith(p.join('bin', 'flutter'))) {
      return Directory(cleaned).parent.parent;
    }
    return Directory(cleaned);
  }

  /// `master` = what ships today (Phase 1 only).
  static FlutterSdk master() => FlutterSdk(
    'master',
    _normalizeSdkRoot(
      Platform.environment['REDTEAM_FLUTTER_MASTER'] ??
          p.join(_home(), 'github', 'flutter'),
    ),
  );

  /// The `web-content-hash-phase-3` branch (Phases 1–3).
  static FlutterSdk phase3() => FlutterSdk(
    'phase3',
    _normalizeSdkRoot(
      Platform.environment['REDTEAM_FLUTTER_PHASE3'] ??
          p.join(_home(), 'github', '_flutter-web-content-hash-phase-3'),
    ),
  );

  static FlutterSdk byLabel(String label) => switch (label) {
    'master' => master(),
    'phase3' => phase3(),
    _ => throw ArgumentError.value(label, 'label', 'expected master|phase3'),
  };

  Future<String> version() async {
    final res = await Process.run(flutterBin, ['--version', '--machine']);
    if (res.exitCode != 0) return 'unknown';
    final out = res.stdout as String;
    final start = out.indexOf('{');
    if (start < 0) return 'unknown';
    final map = json.decode(out.substring(start)) as Map<String, Object?>;
    return '${map['frameworkVersion']} @ ${(map['frameworkRevision'] as String?)?.substring(0, 10)}';
  }
}

/// Everything that distinguishes one build of the sample app from another.
class BuildOptions {
  const BuildOptions({
    required this.version,
    this.contentHash = true,
    this.wasm = false,
    this.sourceMaps = false,
    this.baseHref,
    this.pwaStrategy = 'offline-first',
    this.flavor,
    this.legacyServiceWorker = false,
    this.customIndexHtml,
    this.customBootstrapJs,
    this.target,
    this.relativeOutput = false,
    this.symlinkOutput = false,
    this.expandWildcardAssets = false,
    this.extraArgs = const <String>[],
  });

  /// Shown by the app and reported via `window.__redteam.version`.
  final String version;
  final bool contentHash;
  final bool wasm;
  final bool sourceMaps;
  final String? baseHref;
  final String pwaStrategy;
  final String? flavor;

  /// Replace the generated service worker with the pre-#176834 offline-first
  /// worker (what every app deployed before Flutter 3.38 installed in users'
  /// browsers).
  final bool legacyServiceWorker;

  /// Contents to write to `web/index.html` before building (null = default).
  final String? customIndexHtml;

  /// Contents to write to `web/flutter_bootstrap.js` before building.
  final String? customBootstrapJs;

  /// Entrypoint passed as `--target` (default `lib/main.dart`).
  final String? target;

  /// Pass `-o` as a path relative to `srcDir` instead of an absolute path.
  final bool relativeOutput;

  /// Pass `-o` through a symlink pointing at `outDir`.
  final bool symlinkOutput;

  /// Expand directory-wildcard asset entries in `pubspec.yaml` to explicit
  /// files so `flutter_assets.d` does not force wildcard reruns.
  final bool expandWildcardAssets;
  final List<String> extraArgs;

  String get key => [
    version,
    if (contentHash) 'hash' else 'nohash',
    if (wasm) 'wasm',
    if (sourceMaps) 'sourcemaps',
    // No '=' anywhere: dart2js splits `--packages=<path>` on it.
    if (baseHref != null) 'base-$baseHref',
    'pwa-$pwaStrategy',
    if (flavor != null) 'flavor-$flavor',
    if (legacyServiceWorker) 'legacysw',
    if (customIndexHtml != null)
      'customindex-${sha256.convert(utf8.encode(customIndexHtml!)).toString().substring(0, 6)}',
    if (customBootstrapJs != null)
      'custombootstrap-${sha256.convert(utf8.encode(customBootstrapJs!)).toString().substring(0, 6)}',
    if (target != null) 'target-${p.basenameWithoutExtension(target!)}',
    if (relativeOutput) 'relout',
    if (symlinkOutput) 'symout',
    if (expandWildcardAssets) 'explicitassets',
    ...extraArgs,
  ].join('_').replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
}

class BuildResult {
  BuildResult({
    required this.sdk,
    required this.options,
    required this.srcDir,
    required this.outDir,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  final FlutterSdk sdk;
  final BuildOptions options;
  final Directory srcDir;
  final Directory outDir;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  bool get succeeded => exitCode == 0;

  /// Relative POSIX paths → sha256 of every file in the build output.
  Map<String, String> fileHashes() {
    final out = <String, String>{};
    for (final f in outDir.listSync(recursive: true).whereType<File>()) {
      final rel = p.posix.joinAll(
        p.split(p.relative(f.path, from: outDir.path)),
      );
      out[rel] = sha256.convert(f.readAsBytesSync()).toString();
    }
    return out;
  }

  /// The compiled JS/Wasm entrypoint basenames (hashed or not).
  List<String> entrypoints() =>
      outDir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where(isMainEntrypoint)
          .toList()
        ..sort();

  Map<String, Object?> toJson() => {
    'sdk': sdk.label,
    'options': options.key,
    'exitCode': exitCode,
    'durationMs': duration.inMilliseconds,
    'entrypoints': succeeded ? entrypoints() : null,
    'stderrTail': stderr
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList()
        .reversed
        .take(5)
        .toList()
        .reversed
        .toList(),
  };
}

/// Builds `sample_app` with a given SDK and options into a per-key output
/// directory. Builds are cached by `(sdk, options.key)` for the run.
class Builder {
  Builder({required this.sampleAppDir, required this.workDir});

  final Directory sampleAppDir;
  final Directory workDir;
  final Map<String, BuildResult> _cache = <String, BuildResult>{};

  /// [incrementalFrom] reuses that build's source directory (and its
  /// `build/` + `.dart_tool/` state) instead of a fresh copy, i.e. what a
  /// developer's repeated `flutter build web` does.
  ///
  /// [workspaceId] isolates the initial directory of a multi-step stateful
  /// build sequence from shared cached builds, and skips build caching so
  /// repeated invocations always execute `flutter build web`.
  Future<BuildResult> build(
    FlutterSdk sdk,
    BuildOptions options, {
    BuildResult? incrementalFrom,
    String? workspaceId,
  }) async {
    final bool stateful = incrementalFrom != null || workspaceId != null;
    final String key = workspaceId != null
        ? '${sdk.label}__ws_$workspaceId'
        : '${sdk.label}__${options.key}';
    if (!stateful) {
      final BuildResult? cached = _cache[key];
      if (cached != null) return cached;
    }

    final Directory srcDir =
        incrementalFrom?.srcDir ?? Directory(p.join(workDir.path, 'src', key));
    final Directory outDir =
        incrementalFrom?.outDir ?? Directory(p.join(workDir.path, 'out', key));
    if (incrementalFrom == null) {
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
      if (outDir.existsSync()) outDir.deleteSync(recursive: true);
      _copyApp(sampleAppDir, srcDir);
    }
    _prepareSourceVariant(srcDir, options);

    final String outArg = _resolveOutputArg(options, srcDir, outDir);
    final List<String> args = _buildFlutterArgs(options, outArg);
    final DateTime started = DateTime.now();
    final ProcessResult res = await Process.run(
      sdk.flutterBin,
      args,
      workingDirectory: srcDir.path,
      environment: const <String, String>{'FLUTTER_SUPPRESS_ANALYTICS': 'true'},
    );
    final Duration duration = DateTime.now().difference(started);

    if (res.exitCode == 0 && options.legacyServiceWorker) {
      injectLegacyServiceWorker(outDir);
    }

    final BuildResult result = BuildResult(
      sdk: sdk,
      options: options,
      srcDir: srcDir,
      outDir: outDir,
      exitCode: res.exitCode,
      stdout: res.stdout as String,
      stderr: res.stderr as String,
      duration: duration,
    );
    if (!stateful) {
      _cache[key] = result;
    }
    return result;
  }

  void _prepareSourceVariant(Directory srcDir, BuildOptions options) {
    for (final String rel in const <String>[
      'assets/data/deploy.txt',
      'assets/lazy/deploy.txt',
    ]) {
      _syncTextFile(File(p.join(srcDir.path, rel)), '${options.version}\n');
    }
    Directory variant = Directory(
      p.join(srcDir.path, 'variants', options.version),
    );
    if (!variant.existsSync()) {
      variant = Directory(p.join(srcDir.path, 'variants', 'v1'));
    }
    for (final String rel in const <String>[
      'logo.png',
      '2.0x/logo.png',
      '3.0x/logo.png',
    ]) {
      _copyFileIfChanged(
        File(p.join(variant.path, rel)),
        File(p.join(srcDir.path, 'assets', 'images', rel)),
      );
    }
    _syncTextFile(
      File(p.join(srcDir.path, 'web', 'index.html')),
      options.customIndexHtml,
      fallbackSource: File(p.join(sampleAppDir.path, 'web', 'index.html')),
    );
    _syncTextFile(
      File(p.join(srcDir.path, 'web', 'flutter_bootstrap.js')),
      options.customBootstrapJs,
      fallbackSource: File(
        p.join(sampleAppDir.path, 'web', 'flutter_bootstrap.js'),
      ),
    );
    final File templatePubspec = File(
      p.join(sampleAppDir.path, 'pubspec.yaml'),
    );
    _syncTextFile(
      File(p.join(srcDir.path, 'pubspec.yaml')),
      options.expandWildcardAssets
          ? _expandSampleAppWildcardAssets(templatePubspec.readAsStringSync())
          : null,
      fallbackSource: templatePubspec,
    );
  }

  static String _expandSampleAppWildcardAssets(String pubspecContent) =>
      pubspecContent
          .replaceFirst(
            '    - assets/dir/',
            '    - assets/dir/a.txt\n    - assets/dir/b.txt',
          )
          .replaceFirst(
            '    - assets/lazy/',
            '    - assets/lazy/deploy.txt\n'
                '    - assets/lazy/lazy.png\n'
                '    - assets/lazy/lazy.txt',
          );

  String _resolveOutputArg(
    BuildOptions options,
    Directory srcDir,
    Directory outDir,
  ) {
    String targetPath = outDir.path;
    if (options.symlinkOutput) {
      outDir.createSync(recursive: true);
      final Link link = Link(
        p.join(workDir.path, 'symlink_out', p.basename(outDir.path)),
      );
      if (!link.existsSync()) {
        link.parent.createSync(recursive: true);
        link.createSync(outDir.path);
      }
      targetPath = link.path;
    }
    return options.relativeOutput
        ? p.relative(targetPath, from: srcDir.path)
        : targetPath;
  }

  static void _syncTextFile(
    File dest,
    String? desiredContent, {
    File? fallbackSource,
  }) {
    if (desiredContent != null) {
      if (!dest.existsSync() || dest.readAsStringSync() != desiredContent) {
        dest.parent.createSync(recursive: true);
        dest.writeAsStringSync(desiredContent);
      }
      return;
    }
    if (fallbackSource != null && fallbackSource.existsSync()) {
      _copyFileIfChanged(fallbackSource, dest);
    } else if (dest.existsSync()) {
      dest.deleteSync();
    }
  }

  static void _copyFileIfChanged(File src, File dest) {
    final List<int> srcBytes = src.readAsBytesSync();
    if (dest.existsSync()) {
      final List<int> destBytes = dest.readAsBytesSync();
      if (_bytesEqual(srcBytes, destBytes)) return;
    }
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(srcBytes);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _buildFlutterArgs(BuildOptions options, String outArg) =>
      <String>[
        'build',
        'web',
        '--no-version-check',
        if (options.pwaStrategy != 'offline-first')
          '--pwa-strategy=${options.pwaStrategy}',
        '--dart-define=APP_VERSION=${options.version}',
        '-o',
        outArg,
        if (options.contentHash) '--web-content-hash',
        if (options.wasm) '--wasm',
        if (options.sourceMaps) '--source-maps',
        if (options.baseHref != null) '--base-href=${options.baseHref}',
        if (options.flavor != null) '--flavor=${options.flavor}',
        if (options.target != null) '--target=${options.target}',
        ...options.extraArgs,
      ];

  /// Copies `sample_app` and its sibling `sample_pkg` (path dependency) so
  /// the copy resolves without touching the checked-in tree.
  static void _copyApp(Directory from, Directory to) {
    _copyDir(from, to);
    _copyDir(
      Directory(p.join(from.parent.path, 'sample_pkg')),
      Directory(p.join(to.parent.path, 'sample_pkg')),
    );
  }

  static void _copyDir(Directory from, Directory to) {
    for (final entity in from.listSync(recursive: true)) {
      final rel = p.relative(entity.path, from: from.path);
      final top = p.split(rel).first;
      if (top == 'build' || top == '.dart_tool' || top == '.idea') continue;
      if (entity is File) {
        final dest = File(p.join(to.path, rel));
        dest.parent.createSync(recursive: true);
        entity.copySync(dest.path);
      }
    }
  }
}
