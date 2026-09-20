import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

void main() {
  test('fb-config generates 5-rule last-match-wins stack with max-age=0, must-revalidate', () async {
    final String targetFile = '${d.sandbox}/firebase.json';

    final TestProcess process = await TestProcess.start('dart', <String>[
      'run',
      'bin/flutter_web_cache_check.dart',
      'fb-config',
      '--file',
      targetFile,
    ]);

    await expectLater(
      process.stdout,
      emitsThrough('✅ Successfully updated $targetFile with caching rules.'),
    );
    await process.shouldExit(0);

    final File file = File(targetFile);
    expect(file.existsSync(), isTrue);

    final Map<String, Object?> config =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final Map<String, Object?> hosting =
        config['hosting']! as Map<String, Object?>;

    expect(hosting['public'], 'build/web');
    expect(
      hosting['predeploy'],
      contains('flutter build web --wasm --web-content-hash'),
    );

    final List<Object?> headers = hosting['headers']! as List<Object?>;
    expect(headers.length, 5);

    final List<(String, String)> expectedRules = <(String, String)>[
      ('**', 'max-age=0, must-revalidate'),
      ('**/main.dart.*.{js,wasm,mjs}', 'public, max-age=31536000, immutable'),
      ('assets/**', 'public, max-age=31536000, immutable'),
      (
        'assets/@(AssetManifest.json|AssetManifest.bin|AssetManifest.bin.json|FontManifest.json|NOTICES)',
        'max-age=0, must-revalidate',
      ),
      ('404.html', 'max-age=0, must-revalidate'),
    ];

    for (int i = 0; i < expectedRules.length; i++) {
      final Map<String, Object?> rule = headers[i] as Map<String, Object?>;
      expect(rule['source'], expectedRules[i].$1);
      final List<Object?> h = rule['headers']! as List<Object?>;
      expect((h[0] as Map<String, Object?>)['value'], expectedRules[i].$2);
    }
  });

  test('fb-config migrates legacy v0.1.0 no-cache rules in-place without duplication', () async {
    final String targetFile = '${d.sandbox}/firebase.json';
    await d
        .file(
          'firebase.json',
          jsonEncode(<String, Object?>{
            'hosting': <String, Object?>{
              'public': 'build/web',
              'headers': <Map<String, Object>>[
                <String, Object>{
                  'source': '**/main.dart.*.{js,wasm,mjs}',
                  'headers': <Map<String, String>>[
                    <String, String>{
                      'key': 'Cache-Control',
                      'value': 'public, max-age=31536000, immutable',
                    },
                  ],
                },
                <String, Object>{
                  'source': '**/{index.html,flutter_bootstrap.js,flutter.js,flutter_service_worker.js,manifest.json,version.json}',
                  'headers': <Map<String, String>>[
                    <String, String>{
                      'key': 'Cache-Control',
                      'value': 'no-cache, no-store, must-revalidate',
                    },
                  ],
                },
                <String, Object>{
                  'source': '**/*.part.{js,wasm}',
                  'headers': <Map<String, String>>[
                    <String, String>{
                      'key': 'Cache-Control',
                      'value': 'no-cache, no-store, must-revalidate',
                    },
                  ],
                },
                <String, Object>{
                  'source': '**/_module*.wasm',
                  'headers': <Map<String, String>>[
                    <String, String>{
                      'key': 'Cache-Control',
                      'value': 'no-cache, no-store, must-revalidate',
                    },
                  ],
                },
              ],
            },
          }),
        )
        .create();

    final TestProcess process = await TestProcess.start('dart', <String>[
      'run',
      'bin/flutter_web_cache_check.dart',
      'fb-config',
      '--file',
      targetFile,
    ]);

    await expectLater(
      process.stdout,
      emitsThrough('✅ Successfully updated $targetFile with caching rules.'),
    );
    await process.shouldExit(0);

    final String rawJson = File(targetFile).readAsStringSync();
    expect(rawJson, isNot(contains('no-store')));

    final Map<String, Object?> config =
        jsonDecode(rawJson) as Map<String, Object?>;
    final Map<String, Object?> hosting =
        config['hosting']! as Map<String, Object?>;
    final List<Object?> headers = hosting['headers']! as List<Object?>;
    expect(headers.length, 5);
  });

  test('fb-config appends --web-content-hash and tightens unguarded SPA rewrite "**" -> "/index.html" to exclude static assets (F-05)', () async {
    await d
        .file(
          'firebase.json',
          jsonEncode(<String, Object?>{
            'hosting': <String, Object?>{
              'public': 'custom/dir',
              'predeploy': <String>[
                'npm run build',
                'flutter build web --release',
              ],
              'rewrites': <Object>[
                <String, String>{'source': '**', 'destination': '/index.html'},
              ],
            },
          }),
        )
        .create();

    final String targetFile = '${d.sandbox}/firebase.json';
    final TestProcess process = await TestProcess.start('dart', <String>[
      'run',
      'bin/flutter_web_cache_check.dart',
      'fb-config',
      '--file',
      targetFile,
    ]);

    await expectLater(
      process.stdout,
      emitsThrough('✅ Successfully updated $targetFile with caching rules.'),
    );
    await process.shouldExit(0);

    final Map<String, Object?> config =
        jsonDecode(File(targetFile).readAsStringSync()) as Map<String, Object?>;
    final Map<String, Object?> hosting =
        config['hosting']! as Map<String, Object?>;

    expect(hosting['public'], 'custom/dir'); // Preserved
    final List<Object?> rewrites = hosting['rewrites']! as List<Object?>;
    expect(rewrites, isNotEmpty);
    expect(
      (rewrites[0] as Map<String, Object?>)['source'],
      '!/@(assets|canvaskit|icons|main.dart.*)/**',
    );

    final List<Object?> predeploy = hosting['predeploy']! as List<Object?>;
    expect(predeploy[0], 'npm run build');
    expect(
      predeploy[1],
      'flutter build web --release --wasm --web-content-hash',
    );
  });
}
