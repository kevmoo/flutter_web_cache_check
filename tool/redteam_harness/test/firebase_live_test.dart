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
}

void main() {
  group('L-01 & L-02: Firebase Live Preview Channel Backend + UrlChecker', () {
    test(
      'throws ArgumentError when useFirebaseLive is missing project or site',
      () {
        expect(
          () => HostingServer(
            policy: HeaderPolicy.firebaseRules,
            useFirebaseLive: true,
          ),
          throwsArgumentError,
        );
        expect(
          () => HostingServer(
            policy: HeaderPolicy.firebaseRules,
            useFirebaseLive: true,
            firebaseProject: 'flutterweb-wasm',
          ),
          throwsArgumentError,
        );
        expect(
          () => HostingServer(
            policy: HeaderPolicy.firebaseRules,
            useFirebaseLive: true,
            firebaseSite: 'bouncing',
          ),
          throwsArgumentError,
        );
      },
    );

    final String? project = Platform.environment['REDTEAM_FIREBASE_PROJECT'];
    final String? site = Platform.environment['REDTEAM_FIREBASE_SITE'];
    final bool hasLiveCreds =
        project != null &&
        project.isNotEmpty &&
        site != null &&
        site.isNotEmpty;

    test(
      'deploys to ephemeral Firebase Hosting preview channel and passes UrlChecker with zero localhost exemptions',
      () async {
        final Directory tempDir = Directory.systemTemp.createTempSync(
          'firebase_live_test_',
        );
        try {
          final Directory buildDir = Directory(p.join(tempDir.path, 'build'))
            ..createSync(recursive: true);
          _populateSyntheticWasmDeploy(buildDir);

          final HostingServer host = HostingServer(
            policy: HeaderPolicy.firebaseRules,
            useFirebaseLive: true,
            firebaseProject: project,
            firebaseSite: site,
          );
          await host.start();
          try {
            await host.deployAtomic(buildDir);

            expect(host.baseUri.scheme, 'https');
            expect(host.baseUri.host, startsWith('$site--redteam-'));
            expect(host.baseUri.host, endsWith('.web.app'));

            // Verify production stages.go /404.html header precedence on missing .wasm
            final http.Response missingWasmResp = await http.get(
              host.baseUri.resolve('main.dart.00000000.wasm'),
            );
            expect(missingWasmResp.statusCode, 404);
            expect(
              missingWasmResp.headers['cache-control'],
              'max-age=0, must-revalidate',
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
              'F-01',
              'F-02',
              'F-03',
              'F-04',
              'F-05',
              'F-06',
              'W-01',
              'M-01',
              'M-02',
              'C-01',
              'R-02',
            ]) {
              expect(
                report.findings.any(
                  (CheckFinding f) =>
                      f.ruleId == ruleId && f.severity == Severity.ok,
                ),
                isTrue,
                reason:
                    'Expected $ruleId to be Severity.ok against live Firebase Hosting preview channel',
              );
            }
          } finally {
            await host.stop();
          }
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
      skip: hasLiveCreds ? false : 'Set REDTEAM_FIREBASE_PROJECT and REDTEAM_FIREBASE_SITE to run live Firebase preview channel tests.',
    );
  });
}
