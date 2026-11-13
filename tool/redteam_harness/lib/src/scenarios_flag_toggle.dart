// Copyright (c) 2026, Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:path/path.dart' as p;

import 'builder.dart';
import 'hosting.dart';
import 'scenario.dart';

/// S16: stateful in-place transitions between `--web-content-hash` and plain
/// `flutter build web` (both JS and `--wasm`), back-to-back rebuilds, and
/// incremental template/asset edits.
class ContentHashFlagToggleScenario extends Scenario {
  @override
  String get id => 'S16';

  @override
  String get title =>
      'stateful --web-content-hash <-> plain (JS + Wasm) rebuild transitions';

  @override
  String get description =>
      'Toggles --web-content-hash on/off in-place across JS and --wasm builds, '
      'verifying index.html/flutter_bootstrap.js survival, zero stale artifacts, '
      'back-to-back compiler skipping, and template-edit re-injection.';

  static final RegExp _hashedSegment = RegExp(r'\.[0-9a-f]{8}(\.|$)');

  static const Set<String> _volatileBuildFiles = <String>{
    '.last_build_id',
    'flutter_bootstrap.js',
    'flutter_service_worker.js',
  };

  static const List<String> _jsVerboseArgs = <String>[
    '-v',
    '--no-wasm-dry-run',
  ];

  static const String _editedIndexHtml = r'''
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <title>sample_app edited</title>
  <link rel="manifest" href="manifest.json">
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

  @override
  Future<void> run(ScenarioContext ctx, ScenarioResult result) async {
    await _runJsToggleSequence(ctx, result);
    await _runWasmToggleSequence(ctx, result);
  }

  Future<void> _runJsToggleSequence(
    ScenarioContext ctx,
    ScenarioResult result,
  ) async {
    const BuildOptions v1HashedOpts = BuildOptions(
      version: 'v1',
      contentHash: true,
      relativeOutput: true,
      expandWildcardAssets: true,
      extraArgs: _jsVerboseArgs,
    );
    final BuildResult b1Hashed = await ctx.builder.build(
      ctx.sdk,
      v1HashedOpts,
      workspaceId: 's16_js',
    );
    result.builds.add(b1Hashed.toJson());
    final Step noOpHashedStep = result.step(
      'hashed JS -> hashed JS back-to-back rebuild (relative -o)',
    );
    _checkHashedOutputInvariants(noOpHashedStep, b1Hashed, expectWasm: false);

    final BuildResult b2HashedNoOp = await ctx.builder.build(
      ctx.sdk,
      v1HashedOpts,
      incrementalFrom: b1Hashed,
    );
    result.builds.add(b2HashedNoOp.toJson());
    final Set<String> v1HashedEntries = b2HashedNoOp.succeeded
        ? b2HashedNoOp.entrypoints().toSet()
        : const <String>{};
    _checkRepeatRebuild(noOpHashedStep, b2HashedNoOp, expectHashed: true);

    const BuildOptions v2EditedHashedOpts = BuildOptions(
      version: 'v2',
      contentHash: true,
      customIndexHtml: _editedIndexHtml,
      relativeOutput: true,
      expandWildcardAssets: true,
      extraArgs: _jsVerboseArgs,
    );
    final BuildResult b3EditedHashed = await ctx.builder.build(
      ctx.sdk,
      v2EditedHashedOpts,
      incrementalFrom: b2HashedNoOp,
    );
    result.builds.add(b3EditedHashed.toJson());
    final Step editStep = result.step(
      'hashed JS -> template & asset edit re-injects hashed buildConfig',
    );
    _checkTemplateEditRebuild(
      editStep,
      previousEntries: v1HashedEntries,
      current: b3EditedHashed,
    );

    const BuildOptions v2PlainOpts = BuildOptions(
      version: 'v2',
      contentHash: false,
      customIndexHtml: _editedIndexHtml,
      relativeOutput: true,
      expandWildcardAssets: true,
      extraArgs: _jsVerboseArgs,
    );
    final BuildResult b4Plain = await ctx.builder.build(
      ctx.sdk,
      v2PlainOpts,
      incrementalFrom: b3EditedHashed,
    );
    result.builds.add(b4Plain.toJson());
    final BuildResult freshPlain = await ctx.build(
      const BuildOptions(
        version: 'v2',
        contentHash: false,
        customIndexHtml: _editedIndexHtml,
        expandWildcardAssets: true,
        extraArgs: <String>['--no-wasm-dry-run'],
      ),
    );
    result.builds.add(freshPlain.toJson());

    final Step plainStep = result.step(
      'hashed JS -> plain JS rebuild preserves index.html & bootstrap (relative -o)',
    );
    _checkPlainOutputInvariants(
      plainStep,
      b4Plain,
      expectWasm: false,
      expectedTitle: 'sample_app edited',
    );
    _checkMatchesCleanBuild(plainStep, b4Plain, freshPlain);
    await _verifyLiveDeploy(
      ctx,
      plainStep,
      b4Plain,
      expectedVersion: 'v2',
      requireWasm: false,
    );

    final BuildResult b5PlainNoOp = await ctx.builder.build(
      ctx.sdk,
      v2PlainOpts,
      incrementalFrom: b4Plain,
    );
    result.builds.add(b5PlainNoOp.toJson());
    final Step noOpPlainStep = result.step(
      'plain JS -> plain JS back-to-back rebuild (relative -o)',
    );
    _checkRepeatRebuild(noOpPlainStep, b5PlainNoOp, expectHashed: false);

    final BuildResult b6Rehashed = await ctx.builder.build(
      ctx.sdk,
      const BuildOptions(
        version: 'v2',
        contentHash: true,
        customIndexHtml: _editedIndexHtml,
        relativeOutput: true,
        expandWildcardAssets: true,
        extraArgs: <String>['--no-wasm-dry-run'],
      ),
      incrementalFrom: b5PlainNoOp,
    );
    result.builds.add(b6Rehashed.toJson());
    final Step rehashedStep = result.step(
      'plain JS -> hashed JS rebuild restores hashed outputs cleanly (relative -o)',
    );
    _checkHashedOutputInvariants(
      rehashedStep,
      b6Rehashed,
      expectWasm: false,
      expectedTitle: 'sample_app edited',
    );
    await _verifyLiveDeploy(
      ctx,
      rehashedStep,
      b6Rehashed,
      expectedVersion: 'v2',
      requireWasm: false,
    );
  }

  Future<void> _runWasmToggleSequence(
    ScenarioContext ctx,
    ScenarioResult result,
  ) async {
    final BuildResult w1Hashed = await ctx.builder.build(
      ctx.sdk,
      const BuildOptions(
        version: 'v1',
        wasm: true,
        contentHash: true,
        sourceMaps: true,
        symlinkOutput: true,
      ),
      workspaceId: 's16_wasm',
    );
    result.builds.add(w1Hashed.toJson());

    final BuildResult w2Plain = await ctx.builder.build(
      ctx.sdk,
      const BuildOptions(
        version: 'v1',
        wasm: true,
        contentHash: false,
        sourceMaps: false,
        symlinkOutput: true,
      ),
      incrementalFrom: w1Hashed,
    );
    result.builds.add(w2Plain.toJson());

    final Step plainWasmStep = result.step(
      'hashed Wasm -> plain Wasm rebuild preserves index.html & bootstrap (symlink -o)',
    );
    _checkPlainOutputInvariants(plainWasmStep, w2Plain, expectWasm: true);
    await _verifyLiveDeploy(
      ctx,
      plainWasmStep,
      w2Plain,
      expectedVersion: 'v1',
      requireWasm: true,
    );

    final BuildResult w3Rehashed = await ctx.builder.build(
      ctx.sdk,
      const BuildOptions(
        version: 'v1',
        wasm: true,
        contentHash: true,
        symlinkOutput: true,
      ),
      incrementalFrom: w2Plain,
    );
    result.builds.add(w3Rehashed.toJson());
    final Step rehashedWasmStep = result.step(
      'plain Wasm -> hashed Wasm rebuild removes unhashed Wasm entrypoints (symlink -o)',
    );
    _checkHashedOutputInvariants(
      rehashedWasmStep,
      w3Rehashed,
      expectWasm: true,
    );

    final BuildResult w4PlainJs = await ctx.builder.build(
      ctx.sdk,
      const BuildOptions(
        version: 'v1',
        wasm: false,
        contentHash: false,
        symlinkOutput: true,
        extraArgs: <String>['--no-wasm-dry-run'],
      ),
      incrementalFrom: w3Rehashed,
    );
    result.builds.add(w4PlainJs.toJson());
    final Step plainJsAfterWasmStep = result.step(
      'hashed Wasm -> plain JS rebuild cleans Wasm/MJS & preserves shell (symlink -o)',
    );
    _checkPlainOutputInvariants(
      plainJsAfterWasmStep,
      w4PlainJs,
      expectWasm: false,
    );
  }

  static void _checkRepeatRebuild(
    Step step,
    BuildResult build, {
    required bool expectHashed,
  }) {
    final String logs = '${build.stdout}\n${build.stderr}';
    step.check(
      'dart2js, web_templated_files, web_release_bundle, and web_service_worker skipped on identical rebuild',
      logs.contains('Skipping target: dart2js') &&
          logs.contains('Skipping target: web_templated_files') &&
          logs.contains('Skipping target: web_release_bundle') &&
          logs.contains('Skipping target: web_service_worker'),
    );
    if (expectHashed) {
      _checkHashedOutputInvariants(step, build, expectWasm: false);
    } else {
      _checkPlainOutputInvariants(
        step,
        build,
        expectWasm: false,
        expectedTitle: 'sample_app edited',
      );
    }
  }

  static void _checkTemplateEditRebuild(
    Step step, {
    required Set<String> previousEntries,
    required BuildResult current,
  }) {
    final String logs = '${current.stdout}\n${current.stderr}';
    step.check(
      'both web_templated_files and web_release_bundle executed',
      logs.contains('web_templated_files: Starting due to') &&
          logs.contains('web_release_bundle: Starting due to'),
    );
    _checkHashedOutputInvariants(
      step,
      current,
      expectWasm: false,
      expectedTitle: 'sample_app edited',
    );
    if (!current.succeeded) return;
    final Set<String> currEntries = current.entrypoints().toSet();
    final Set<String> lingeringOld = previousEntries.intersection(currEntries);
    step.check(
      'previous v1 hashed entrypoint replaced by v2 hash',
      currEntries.isNotEmpty && lingeringOld.isEmpty,
      lingeringOld.join(', '),
    );
  }

  static String? _checkBootloaderShell(
    Step step,
    BuildResult build, {
    String? expectedTitle,
  }) {
    step.check('build succeeded', build.succeeded, build.stderr.trim());
    if (!build.succeeded) return null;

    final File indexFile = File(p.join(build.outDir.path, 'index.html'));
    final File bootstrapFile = File(
      p.join(build.outDir.path, 'flutter_bootstrap.js'),
    );
    final bool indexExists = indexFile.existsSync();
    final bool bootstrapExists = bootstrapFile.existsSync();
    step.check('index.html exists', indexExists);
    step.check('flutter_bootstrap.js exists', bootstrapExists);
    if (expectedTitle != null) {
      final String indexBody = indexExists ? indexFile.readAsStringSync() : '';
      step.check(
        'index.html retains edited title ($expectedTitle)',
        indexBody.contains('<title>$expectedTitle</title>'),
      );
    }
    return bootstrapExists ? bootstrapFile.readAsStringSync() : '';
  }

  static bool _isStaleHashedArtifact(String relPath) =>
      !relPath.startsWith('canvaskit/') &&
      (_hashedSegment.hasMatch(p.posix.basename(relPath)) ||
          (relPath.startsWith('main.dart.') && relPath.endsWith('.map')));

  static bool _hasExpectedWasmBootstrap(
    String bootstrapBody, {
    required bool expectWasm,
    required bool hashed,
  }) {
    if (!expectWasm) return true;
    final bool hasWasmPath = hashed
        ? RegExp(r'"mainWasmPath"\s*:\s*"main\.dart\.[0-9a-f]{8}\.wasm"')
              .hasMatch(bootstrapBody)
        : bootstrapBody.contains('"mainWasmPath":"main.dart.wasm"');
    return hasWasmPath && bootstrapBody.contains('_flutter.supportsDart2Wasm');
  }

  static void _checkPlainOutputInvariants(
    Step step,
    BuildResult build, {
    required bool expectWasm,
    String? expectedTitle,
  }) {
    final String? bootstrapBody = _checkBootloaderShell(
      step,
      build,
      expectedTitle: expectedTitle,
    );
    if (bootstrapBody == null) return;

    step.check(
      'flutter_bootstrap.js points to unhashed entrypoints without hashed manifests',
      bootstrapBody.contains('"mainJsPath":"main.dart.js"') &&
          _hasExpectedWasmBootstrap(
            bootstrapBody,
            expectWasm: expectWasm,
            hashed: false,
          ) &&
          !_hashedSegment.hasMatch(bootstrapBody),
    );

    final Set<String> files = build.fileHashes().keys.toSet();
    final List<String> expectedEntries = <String>[
      'main.dart.js',
      if (expectWasm) ...const <String>['main.dart.wasm', 'main.dart.mjs'],
    ];
    final bool hasUnexpectedWasmOrMjs =
        !expectWasm &&
        files.any(
          (String f) =>
              !f.startsWith('canvaskit/') &&
              (f.endsWith('.wasm') || f.endsWith('.mjs')),
        );
    step.check(
      'expected unhashed entrypoints exist',
      expectedEntries.every(files.contains) && !hasUnexpectedWasmOrMjs,
      build.entrypoints().join(', '),
    );

    final List<String> staleHashed = files
        .where(_isStaleHashedArtifact)
        .toList();
    step.check(
      'no stale hashed entrypoints, maps, or assets remain',
      staleHashed.isEmpty,
      staleHashed.take(6).join(', '),
    );
    step.check(
      'no stale precache_manifest.json remains on plain build',
      !files.contains('precache_manifest.json'),
    );
  }

  static void _checkHashedOutputInvariants(
    Step step,
    BuildResult build, {
    required bool expectWasm,
    String? expectedTitle,
  }) {
    final String? bootstrapBody = _checkBootloaderShell(
      step,
      build,
      expectedTitle: expectedTitle,
    );
    if (bootstrapBody == null) return;

    step.check(
      'flutter_bootstrap.js contains hashed entrypoint and assetManifest config',
      RegExp(r'"mainJsPath"\s*:\s*"main\.dart\.[0-9a-f]{8}\.js"')
              .hasMatch(bootstrapBody) &&
          _hasExpectedWasmBootstrap(
            bootstrapBody,
            expectWasm: expectWasm,
            hashed: true,
          ) &&
          bootstrapBody.contains('"assetManifest"'),
    );

    final Set<String> files = build.fileHashes().keys.toSet();
    final List<String> lingeringUnhashed = <String>[
      for (final String candidate in const <String>[
        'main.dart.js',
        'main.dart.wasm',
        'main.dart.mjs',
        'assets/AssetManifest.bin.json',
        'assets/FontManifest.json',
      ])
        if (files.contains(candidate)) candidate,
    ];
    step.check(
      'no lingering unhashed entrypoints or manifests remain',
      lingeringUnhashed.isEmpty,
      lingeringUnhashed.join(', '),
    );
    step.check(
      'precache_manifest.json exists on hashed build',
      files.contains('precache_manifest.json'),
    );
  }

  static void _checkMatchesCleanBuild(
    Step step,
    BuildResult incremental,
    BuildResult clean,
  ) {
    if (!incremental.succeeded || !clean.succeeded) return;
    final Set<String> incrFiles = incremental
        .fileHashes()
        .keys
        .where((String f) => !_volatileBuildFiles.contains(f))
        .toSet();
    final Set<String> cleanFiles = clean
        .fileHashes()
        .keys
        .where((String f) => !_volatileBuildFiles.contains(f))
        .toSet();
    final List<String> extra = incrFiles.difference(cleanFiles).toList()
      ..sort();
    final List<String> missing = cleanFiles.difference(incrFiles).toList()
      ..sort();
    step.check(
      'no extra files vs clean build',
      extra.isEmpty,
      extra.take(6).join(', '),
    );
    step.check(
      'no missing files vs clean build',
      missing.isEmpty,
      missing.take(6).join(', '),
    );
  }

  Future<void> _verifyLiveDeploy(
    ScenarioContext ctx,
    Step step,
    BuildResult build, {
    required String expectedVersion,
    required bool requireWasm,
  }) async {
    if (!build.succeeded) return;
    final HostingServer host = await ctx.host(
      HeaderPolicy.firebaseRules,
      useFirebaseEmulator: ctx.useFirebaseEmulator,
    );
    final profile = ctx.freshProfile('S16');
    try {
      await host.deployAtomic(build.outDir);
      final CheckReport checkReport = await UrlChecker(
        host.baseUri.toString(),
        requireWasm: requireWasm,
      ).analyze();
      step.check(
        'UrlChecker passes deployed output',
        !checkReport.hasFailures && !checkReport.hasWarnings,
        checkReport.findings
            .where((CheckFinding f) => f.severity != Severity.ok)
            .map((CheckFinding f) => f.toString())
            .join(' | '),
      );

      final bool hasIndex = File(p.join(build.outDir.path, 'index.html'))
          .existsSync();
      final chrome = await ctx.chrome(profile);
      try {
        final Map<String, Object?>? appReport = await loadAndCapture(
          step,
          chrome,
          host,
          host.baseUri,
          timeout: Duration(seconds: hasIndex ? 30 : 4),
        );
        checkHealthyLoad(
          step,
          chrome,
          appReport,
          expectedVersion: expectedVersion,
        );
      } finally {
        await chrome.close();
      }
    } finally {
      await host.stop();
    }
  }
}
