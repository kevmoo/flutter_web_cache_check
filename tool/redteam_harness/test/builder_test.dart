// Copyright (c) 2026, Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:redteam_harness/redteam_harness.dart';
import 'package:test/test.dart';

List<String> _extractCoreList(Directory buildDir) {
  final swJs = File(p.join(buildDir.path, 'flutter_service_worker.js'))
      .readAsStringSync();
  final match = RegExp(
    r'^const CORE = (\[.*?\]);$',
    multiLine: true,
  ).firstMatch(swJs);
  expect(match, isNotNull, reason: 'Expected const CORE = [...] in worker JS');
  return (json.decode(match!.group(1)!) as List<Object?>).cast<String>();
}

void _writeFiles(Directory root, Iterable<String> relPaths) {
  for (final rel in relPaths) {
    final file = File(p.join(root.path, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('content:$rel');
  }
}

void main() {
  group('BuildOptions.key', () {
    test('preserves multi-dot target stems without key collision', () {
      const prod = BuildOptions(version: 'v1', target: 'lib/main.prod.dart');
      const dev = BuildOptions(version: 'v1', target: 'lib/main.dev.dart');
      const staging = BuildOptions(
        version: 'v1',
        target: 'lib/main.staging.dart',
      );

      expect(prod.key, isNot(equals(dev.key)));
      expect(prod.key, isNot(equals(staging.key)));
      expect(prod.key, contains('target-main.prod'));
      expect(dev.key, contains('target-main.dev'));
      expect(staging.key, contains('target-main.staging'));
    });

    test('strips nested directories and single .dart extension', () {
      final nested = BuildOptions(
        version: 'v1',
        target: p.join('lib', 'entrypoints', 'main.prod.dart'),
      );
      const root = BuildOptions(version: 'v1', target: 'lib/main.prod.dart');
      const standard = BuildOptions(version: 'v1', target: 'lib/main.dart');
      const deferred = BuildOptions(
        version: 'v1',
        target: 'lib/main_deferred.dart',
      );

      expect(nested.key, equals(root.key));
      expect(nested.key, contains('target-main.prod'));
      expect(standard.key, contains('target-main'));
      expect(deferred.key, contains('target-main_deferred'));
    });
  });

  group('isMainEntrypoint', () {
    test('accepts js/wasm/mjs by default and restricts to js when jsOnly', () {
      for (final ext in ['js', 'wasm', 'mjs']) {
        expect(isMainEntrypoint('main.dart.$ext'), isTrue);
        expect(isMainEntrypoint('main.dart.deadbeef.$ext'), isTrue);
        expect(isMainEntrypoint('main.dart.$ext', jsOnly: true), ext == 'js');
        expect(
          isMainEntrypoint('main.dart.deadbeef.$ext', jsOnly: true),
          ext == 'js',
        );
      }

      for (final invalid in [
        'main.dart.support.js',
        'main.dart.1.part.js',
        'main.dart.DEADBEEF.js',
        'main.dart.abc.js',
        'main.dart.deadbeef0.js',
        'main.dart.deadbeeg.js',
        'assets/main.dart.js',
      ]) {
        expect(isMainEntrypoint(invalid), isFalse, reason: invalid);
        expect(
          isMainEntrypoint(invalid, jsOnly: true),
          isFalse,
          reason: invalid,
        );
      }
    });
  });

  group('BuildResult.entrypoints', () {
    test('matches unhashed and 8-char lowercase hex entrypoints only', () {
      final tempDir = Directory.systemTemp.createTempSync('builder_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      _writeFiles(tempDir, [
        // Positive cases: unhashed + 8-char lowercase hex across js/wasm/mjs.
        'main.dart.js',
        'main.dart.wasm',
        'main.dart.mjs',
        'main.dart.deadbeef.js',
        'main.dart.deadbeef.wasm',
        'main.dart.deadbeef.mjs',
        'main.dart.01234567.js',
        // Negative cases.
        'main.dart.support.js',
        'main.dart.1.part.js',
        'main.dart.DEADBEEF.js',
        'main.dart.DEADBEEF.wasm',
        'main.dart.DEADBEEF.mjs',
        'main.dart.abc.js',
        'main.dart.deadbeef0.js',
        'main.dart.deadbeeg.js',
        'main.dart.js.map',
        'main.dart.deadbeef.js.map',
        'flutter_bootstrap.js',
        'index.html',
        'assets/main.dart.js',
      ]);

      final result = BuildResult(
        sdk: FlutterSdk('test', tempDir),
        options: const BuildOptions(version: 'v1'),
        srcDir: tempDir,
        outDir: tempDir,
        exitCode: 0,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
      );

      expect(result.entrypoints(), [
        'main.dart.01234567.js',
        'main.dart.deadbeef.js',
        'main.dart.deadbeef.mjs',
        'main.dart.deadbeef.wasm',
        'main.dart.js',
        'main.dart.mjs',
        'main.dart.wasm',
      ]);
    });
  });

  group('injectLegacyServiceWorker', () {
    test('selects hashed root main.dart.<hex8>.js over non-JS and decoys', () {
      final tempDir = Directory.systemTemp.createTempSync('legacy_sw_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      _writeFiles(tempDir, [
        'index.html',
        'flutter_bootstrap.js',
        'assets/main.dart.js',
        'main.dart.deadbeef.wasm',
        'main.dart.deadbeef.mjs',
        'main.dart.support.js',
        'main.dart.1.part.js',
        'main.dart.DEADBEEF.js',
        'main.dart.abc.js',
        'main.dart.deadbeef.js',
      ]);

      injectLegacyServiceWorker(tempDir);

      expect(_extractCoreList(tempDir).first, 'main.dart.deadbeef.js');
    });

    test('falls back to main.dart.js when only decoys or Wasm/MJS exist', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'legacy_sw_fallback_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      _writeFiles(tempDir, [
        'index.html',
        'assets/main.dart.deadbeef.js',
        'main.dart.deadbeef.wasm',
        'main.dart.deadbeef.mjs',
        'main.dart.support.js',
        'main.dart.1.part.js',
        'main.dart.DEADBEEF.js',
        'main.dart.abc.js',
      ]);

      injectLegacyServiceWorker(tempDir);

      expect(_extractCoreList(tempDir).first, 'main.dart.js');
    });
  });
}
