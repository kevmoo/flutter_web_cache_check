import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

void main() {
  test(
    'fb-config creates firebase.json with caching rules and predeploy script',
    () async {
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
        contains('flutter build web --web-content-hash'),
      );

      final List<Object?> headers = hosting['headers']! as List<Object?>;
      expect(headers.length, 4);

      // Verify immutable header Rule
      final Map<String, Object?> rule1 = headers[0] as Map<String, Object?>;
      expect(rule1['source'], '**/main.dart.*.{js,wasm,mjs}');
      final List<Object?> h1 = rule1['headers']! as List<Object?>;
      expect(
        (h1[0] as Map<String, Object?>)['value'],
        'public, max-age=31536000, immutable',
      );

      // Verify bootloader Rule
      final Map<String, Object?> rule2 = headers[1] as Map<String, Object?>;
      expect(
        rule2['source'],
        '**/{index.html,flutter_bootstrap.js,flutter.js,flutter_service_worker.js,manifest.json,version.json}',
      );
      final List<Object?> h2 = rule2['headers']! as List<Object?>;
      expect(
        (h2[0] as Map<String, Object?>)['value'],
        'no-cache, no-store, must-revalidate',
      );

      // Verify deferred part Rule
      final Map<String, Object?> rule3 = headers[2] as Map<String, Object?>;
      expect(rule3['source'], '**/*.part.{js,wasm}');

      // Verify deferred wasm Rule
      final Map<String, Object?> rule4 = headers[3] as Map<String, Object?>;
      expect(rule4['source'], '**/_module*.wasm');
    },
  );

  test('fb-config appends --web-content-hash to existing build command without overwriting other config', () async {
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
    expect(hosting['rewrites'], isNotEmpty); // Preserved

    final List<Object?> predeploy = hosting['predeploy']! as List<Object?>;
    expect(predeploy[0], 'npm run build');
    expect(predeploy[1], 'flutter build web --release --web-content-hash');
  });
}
