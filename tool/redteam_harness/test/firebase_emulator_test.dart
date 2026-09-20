import 'dart:io';

import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:redteam_harness/redteam_harness.dart';
import 'package:test/test.dart';

void _populateSyntheticWasmDeploy(Directory dir) {
  void writeFile(String rel, String content) {
    final File f = File(p.join(dir.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  writeFile('index.html', '<!DOCTYPE html><html><body>App v1</body></html>');
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
  writeFile('main.dart.5f77f974.wasm', '\x00asm\x01\x00\x00\x00${'w' * 2048}');
  writeFile(
    'main.dart.db41cfdb.mjs',
    'export const instantiate = () => {}; // ${'m' * 2048}',
  );
  writeFile('main.dart.785ea741.js', 'console.log("v1"); // ${'j' * 2048}');
  writeFile('assets/AssetManifest.bin.10579154.json', '{"assets":[]}');
  writeFile('assets/AssetManifest.bin.json', '{"assets":[]}');
  writeFile('assets/FontManifest.e5f60718.json', '[]');
  writeFile('assets/assets/sub%20dir/space%20image.342887cc.png', 'spaced-png');
}

void main() {
  group(
    'E-01 & E-02: Real Firebase Emulator (superstatic) Backend + UrlChecker',
    () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync(
          'firebase_emulator_test_',
        );
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('proxies requests through real firebase emulators:start --only hosting and passes UrlChecker', () async {
        final Directory buildDir = Directory(p.join(tempDir.path, 'build'))
          ..createSync(recursive: true);
        _populateSyntheticWasmDeploy(buildDir);

        final HostingServer host = HostingServer(
          policy: HeaderPolicy.firebaseRules,
          useFirebaseEmulator: true,
        );
        await host.start();
        try {
          await host.deployAtomic(buildDir);

          // Verify raw superstatic headers pass through HostingServer unchanged
          final http.Response indexResp = await http.get(
            host.baseUri.resolve('index.html'),
          );
          expect(indexResp.statusCode, 200);
          expect(
            indexResp.headers['cache-control'],
            'max-age=0, must-revalidate',
          );
          expect(indexResp.headers['etag'], isNotNull);
          expect(indexResp.headers['etag']!.startsWith('"'), isFalse);

          final http.Response missingWasmResp = await http.get(
            host.baseUri.resolve('main.dart.00000000.wasm'),
          );
          expect(missingWasmResp.statusCode, 404);
          expect(
            missingWasmResp.headers['content-security-policy'],
            contains("default-src 'none'"),
          );

          final CheckReport report = await UrlChecker(
            host.baseUri.toString(),
            requireWasm: true,
          ).analyze();

          expect(
            report.hasErrors,
            isFalse,
            reason: report.findings.map((f) => f.toString()).join('\n'),
          );
          expect(
            report.hasWarnings,
            isFalse,
            reason: report.findings.map((f) => f.toString()).join('\n'),
          );

          for (final String ruleId in <String>[
            'W-01',
            'M-01',
            'M-02',
            'F-03',
            'F-05',
            'F-06',
            'C-01',
          ]) {
            expect(
              report.findings.any(
                (CheckFinding f) =>
                    f.ruleId == ruleId && f.severity == Severity.ok,
              ),
              isTrue,
              reason: 'Expected $ruleId to be Severity.ok against superstatic',
            );
          }
        } finally {
          await host.stop();
        }
      });

      test(
        'supports non-root basePath (/app/) with real firebase emulator',
        () async {
          final Directory buildDir = Directory(p.join(tempDir.path, 'build'))
            ..createSync(recursive: true);
          _populateSyntheticWasmDeploy(buildDir);

          final HostingServer host = HostingServer(
            policy: HeaderPolicy.firebaseRules,
            basePath: '/app/',
            useFirebaseEmulator: true,
          );
          await host.start();
          try {
            await host.deployAtomic(buildDir);
            final http.Response spacedResp = await http.get(
              host.baseUri.resolve(
                'assets/assets/sub%2520dir/space%2520image.342887cc.png',
              ),
            );
            expect(spacedResp.statusCode, 200);
            expect(spacedResp.body, 'spaced-png');
            final CheckReport report = await UrlChecker(
              host.baseUri.toString(),
              requireWasm: true,
            ).analyze();
            expect(report.hasErrors, isFalse);
            expect(report.hasWarnings, isFalse);
          } finally {
            await host.stop();
          }
        },
      );
    },
  );
}
