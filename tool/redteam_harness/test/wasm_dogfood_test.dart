import 'dart:io';

import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:path/path.dart' as p;
import 'package:redteam_harness/redteam_harness.dart';
import 'package:test/test.dart';

void _populateSyntheticDeploy(Directory dir, {required bool includeWasm}) {
  void writeFile(String rel, String content) {
    final File f = File(p.join(dir.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  writeFile('index.html', '<!DOCTYPE html><html><body>App v1</body></html>');
  if (includeWasm) {
    writeFile('flutter_bootstrap.js', '''
_flutter.buildConfig = {
  "builds": [
    {
      "compileTarget": "dart2wasm",
      "renderer": "skwasm",
      "mainWasmPath": "main.dart.5f77f974.wasm",
      "jsSupportRuntimePath": "main.dart.db41cfdb.mjs"
    },
    {
      "compileTarget": "dart2js",
      "renderer": "canvaskit",
      "mainJsPath": "main.dart.785ea741.js"
    }
  ],
  "assetManifest": "AssetManifest.bin.10579154.json",
  "fontManifest": "FontManifest.e5f60718.json"
};
''');
    writeFile(
      'main.dart.5f77f974.wasm',
      '\x00asm\x01\x00\x00\x00${'w' * 2048}',
    );
    writeFile(
      'main.dart.db41cfdb.mjs',
      'export const instantiate = () => {}; // ${'m' * 2048}',
    );
  } else {
    writeFile('flutter_bootstrap.js', '''
_flutter.buildConfig = {
  "builds": [
    {
      "compileTarget": "dart2js",
      "renderer": "canvaskit",
      "mainJsPath": "main.dart.785ea741.js"
    }
  ],
  "assetManifest": "AssetManifest.bin.10579154.json",
  "fontManifest": "FontManifest.e5f60718.json"
};
''');
  }
  writeFile('main.dart.785ea741.js', 'console.log("v1"); // ${'j' * 2048}');
  writeFile('assets/AssetManifest.bin.10579154.json', '{"assets":[]}');
  writeFile('assets/FontManifest.e5f60718.json', '[]');
}

void main() {
  group('M-03: In-Process S15 Dual Dogfood (JS + WASM across all HeaderPolicy variants)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wasm_dogfood_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('JS-only deployment passes with requireWasm: false and warns W-01 with requireWasm: true', () async {
      final Directory jsDir = Directory(p.join(tempDir.path, 'js_only'))
        ..createSync(recursive: true);
      _populateSyntheticDeploy(jsDir, includeWasm: false);

      final HostingServer host = HostingServer(
        policy: HeaderPolicy.firebaseRules,
      );
      await host.start();
      try {
        await host.deployAtomic(jsDir);

        final CheckReport allowedJsReport = await UrlChecker(
          host.baseUri.toString(),
          requireWasm: false,
        ).analyze();
        expect(allowedJsReport.hasErrors, isFalse);
        expect(allowedJsReport.hasWarnings, isFalse);
        expect(
          allowedJsReport.findings.any(
            (CheckFinding f) => f.ruleId == 'W-01' && f.severity == Severity.ok,
          ),
          isTrue,
        );

        final CheckReport defaultWarnReport = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(defaultWarnReport.hasErrors, isFalse);
        expect(defaultWarnReport.hasWarnings, isTrue);
        expect(
          defaultWarnReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'W-01' && f.severity == Severity.warn,
          ),
          isTrue,
        );
      } finally {
        await host.stop();
      }
    });

    test('Wasm + JS deployment validates all HeaderPolicy variants accurately in-process', () async {
      final Directory wasmDir = Directory(p.join(tempDir.path, 'wasm_and_js'))
        ..createSync(recursive: true);
      _populateSyntheticDeploy(wasmDir, includeWasm: true);

      final HostingServer host = HostingServer(
        policy: HeaderPolicy.firebaseRules,
      );
      await host.start();
      try {
        await host.deployAtomic(wasmDir);

        // 1. HeaderPolicy.firebaseRules -> 0 errors, 0 warnings, W-01/M-01/M-02/F-03/F-05 ok
        host.policy = HeaderPolicy.firebaseRules;
        final CheckReport fbRulesReport = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(fbRulesReport.hasErrors, isFalse);
        expect(fbRulesReport.hasWarnings, isFalse);
        for (final String ruleId in <String>[
          'W-01',
          'M-01',
          'M-02',
          'F-03',
          'F-05',
        ]) {
          expect(
            fbRulesReport.findings.any(
              (CheckFinding f) =>
                  f.ruleId == ruleId && f.severity == Severity.ok,
            ),
            isTrue,
            reason: 'Expected $ruleId to be Severity.ok under firebaseRules',
          );
        }

        // 2. HeaderPolicy.naiveLongCache -> F-01 error
        host.policy = HeaderPolicy.naiveLongCache;
        final CheckReport naiveLongReport = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(naiveLongReport.hasErrors, isTrue);
        expect(
          naiveLongReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-01' && f.severity == Severity.error,
          ),
          isTrue,
        );

        // 3. HeaderPolicy.firebaseDefault -> F-03 error
        host.policy = HeaderPolicy.firebaseDefault;
        final CheckReport fbDefaultReport = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(fbDefaultReport.hasErrors, isTrue);
        expect(
          fbDefaultReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-03' && f.severity == Severity.error,
          ),
          isTrue,
        );

        // 4. HeaderPolicy.spaFallbackTrap -> F-05 error on both .js and .wasm
        host.policy = HeaderPolicy.spaFallbackTrap;
        final CheckReport spaTrapReport = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(spaTrapReport.hasErrors, isTrue);
        expect(
          spaTrapReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-05' &&
                f.path == 'main.dart.00000000.js' &&
                f.severity == Severity.error,
          ),
          isTrue,
        );
        expect(
          spaTrapReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-05' &&
                f.path == 'main.dart.00000000.wasm' &&
                f.severity == Severity.error,
          ),
          isTrue,
        );

        // 5. HeaderPolicy.immutable404Trap -> F-06 error on both .js and .wasm
        host.policy = HeaderPolicy.immutable404Trap;
        final CheckReport trap404Report = await UrlChecker(
          host.baseUri.toString(),
        ).analyze();
        expect(trap404Report.hasErrors, isTrue);
        expect(
          trap404Report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-06' &&
                f.path == 'main.dart.00000000.js' &&
                f.severity == Severity.error,
          ),
          isTrue,
        );
        expect(
          trap404Report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-06' &&
                f.path == 'main.dart.00000000.wasm' &&
                f.severity == Severity.error,
          ),
          isTrue,
        );
      } finally {
        await host.stop();
      }
    });
  });
}
