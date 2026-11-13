import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Client _buildBootstrapClient({
  required String bootstrapBody,
  String wasmCacheControl = 'public, max-age=31536000, immutable',
  String wasmContentType = 'application/wasm',
  String mjsCacheControl = 'public, max-age=31536000, immutable',
  String mjsContentType = 'text/javascript',
}) => MockClient(
  (http.Request request) async => _handleBootstrapRequest(
    request,
    bootstrapBody: bootstrapBody,
    wasmCacheControl: wasmCacheControl,
    wasmContentType: wasmContentType,
    mjsCacheControl: mjsCacheControl,
    mjsContentType: mjsContentType,
  ),
);

http.Response _handleBootstrapRequest(
  http.Request request, {
  required String bootstrapBody,
  required String wasmCacheControl,
  required String wasmContentType,
  required String mjsCacheControl,
  required String mjsContentType,
}) {
  final path = request.url.path;
  if (path == '/index.html' || path == '/') {
    return http.Response(
      '<html></html>',
      request.headers['if-none-match'] == '"v1"' ? 304 : 200,
      headers: <String, String>{
        'cache-control': 'max-age=0, must-revalidate',
        'etag': '"v1"',
      },
    );
  }
  if (path == '/flutter_bootstrap.js') {
    return http.Response(
      bootstrapBody,
      200,
      headers: <String, String>{
        'cache-control': 'max-age=0, must-revalidate',
        'content-type': 'text/javascript',
      },
    );
  }
  if (path == '/main.dart.5f77f974.wasm') {
    return http.Response(
      '\x00asm\x01\x00\x00\x00',
      200,
      headers: <String, String>{
        'cache-control': wasmCacheControl,
        'content-type': wasmContentType,
      },
    );
  }
  if (path == '/main.dart.db41cfdb.mjs') {
    return http.Response(
      'export const instantiate = () => {};',
      200,
      headers: <String, String>{
        'cache-control': mjsCacheControl,
        'content-type': mjsContentType,
      },
    );
  }
  if (path == '/main.dart.785ea741.js') {
    return http.Response(
      'console.log("app");',
      200,
      headers: <String, String>{
        'cache-control': 'public, max-age=31536000, immutable',
        'content-type': 'application/javascript',
      },
    );
  }
  if (path == '/assets/AssetManifest.bin.10579154.json' ||
      path == '/assets/FontManifest.e5f60718.json') {
    return http.Response(
      '{}',
      200,
      headers: <String, String>{
        'cache-control': 'public, max-age=31536000, immutable',
        'content-type': 'application/json',
      },
    );
  }
  return http.Response(
    'Not Found',
    404,
    headers: <String, String>{'cache-control': 'max-age=0, must-revalidate'},
  );
}

http.Client _buildWasmProbeClient({
  required int wasmStatus,
  required String wasmContentType,
  required String wasmCacheControl,
  String wasmBody = 'Not Found',
}) => MockClient((http.Request request) async {
  if (request.url.path == '/main.dart.00000000.wasm') {
    return http.Response(
      wasmBody,
      wasmStatus,
      headers: <String, String>{
        'cache-control': wasmCacheControl,
        'content-type': wasmContentType,
      },
    );
  }
  return _handleBootstrapRequest(
    request,
    bootstrapBody:
        '_flutter.buildConfig = {"builds": [ '
        '{"compileTarget": "dart2wasm", '
        '"mainWasmPath": "main.dart.5f77f974.wasm", '
        '"jsSupportRuntimePath": "main.dart.db41cfdb.mjs"}, '
        '{"compileTarget": "dart2js", '
        '"mainJsPath": "main.dart.785ea741.js"}]};',
    wasmCacheControl: 'public, max-age=31536000, immutable',
    wasmContentType: 'application/wasm',
    mjsCacheControl: 'public, max-age=31536000, immutable',
    mjsContentType: 'text/javascript',
  );
});

MockClient _buildSuperstaticClient() => MockClient(_handleSuperstaticRequest);

Future<http.Response> _handleSuperstaticRequest(http.Request request) async {
  final path = request.url.path;
  if (path == '/index.html' || path == '/flutter_bootstrap.js') {
    final body = path == '/flutter_bootstrap.js'
        ? '_flutter.buildConfig = {"builds": [ '
              '{"compileTarget": "dart2wasm", '
              '"mainWasmPath": "main.dart.5f77f974.wasm", '
              '"jsSupportRuntimePath": "main.dart.db41cfdb.mjs"}]};'
        : '<html></html>';
    return http.Response(
      body,
      200,
      request: request,
      headers: <String, String>{
        'cache-control': 'max-age=0, must-revalidate',
        'etag': '319936f5c0f8203a7759ef58ec667249',
        'content-type': path.endsWith('.js')
            ? 'application/javascript'
            : 'text/html; charset=utf-8',
      },
    );
  }
  if (path == '/main.dart.5f77f974.wasm' || path == '/main.dart.db41cfdb.mjs') {
    return http.Response(
      'x' * 2048,
      200,
      request: request,
      headers: <String, String>{
        'cache-control': 'public, max-age=31536000, immutable',
        'etag': '319936f5c0f8203a7759ef58ec667249',
        'content-type': path.endsWith('.wasm')
            ? 'application/wasm'
            : 'application/javascript',
      },
    );
  }
  if (path == '/assets/AssetManifest.bin.json') {
    return http.Response(
      '{}',
      200,
      request: request,
      headers: <String, String>{
        'cache-control': 'max-age=0, must-revalidate',
        'etag': '319936f5c0f8203a7759ef58ec667249',
        'content-type': 'application/json',
      },
    );
  }
  return http.Response(
    'Cannot GET $path',
    404,
    request: request,
    headers: <String, String>{
      'cache-control': 'public, max-age=31536000, immutable',
      'content-security-policy': "default-src 'none'",
      'content-type': 'text/html; charset=utf-8',
    },
  );
}

void main() {
  _registerW01Tests();
  _registerW02Tests();
  _registerE02Tests();
  _registerF08Tests();
  _registerMissingBootloaderTests();
}

void _registerW01Tests() {
  group('W-01: First-Class WebAssembly (dart2wasm) Target Detection', () {
    test(
      'emits W-01 Severity.warn when flutter_bootstrap.js only has mainJsPath '
      'and requireWasm is true',
      () async {
        final report = await UrlChecker(
          'https://example.com',
          client: _buildBootstrapClient(
            bootstrapBody:
                '_flutter.buildConfig = {"builds": [ '
                '{"compileTarget": "dart2js", '
                '"mainJsPath": "main.dart.785ea741.js"}]};',
          ),
          minCompressionBytes: 100000,
        ).analyze();

        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'W-01' &&
                f.severity == Severity.warn &&
                f.message.contains(
                  'flutter build web --wasm --web-content-hash',
                ),
          ),
          isTrue,
        );
      },
    );

    test('emits W-01 Severity.ok when flutter_bootstrap.js only has mainJsPath '
        'and requireWasm is false', () async {
      final report = await UrlChecker(
        'https://example.com',
        client: _buildBootstrapClient(
          bootstrapBody:
              '_flutter.buildConfig = {"builds": [ '
              '{"compileTarget": "dart2js", '
              '"mainJsPath": "main.dart.785ea741.js"}]};',
        ),
        requireWasm: false,
        minCompressionBytes: 100000,
      ).analyze();

      expect(report.hasWarnings, isFalse);
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'W-01' &&
              f.severity == Severity.ok &&
              f.message.contains('--no-wasm'),
        ),
        isTrue,
      );
    });

    test('emits W-01 Severity.ok and validates .wasm (F-03, M-01) and .mjs '
        '(F-03, M-02) when mainWasmPath is present', () async {
      final report = await UrlChecker(
        'https://example.com',
        client: _buildBootstrapClient(
          bootstrapBody:
              '_flutter.buildConfig = {"builds": [ '
              '{"compileTarget": "dart2wasm", '
              '"mainWasmPath": "main.dart.5f77f974.wasm", '
              '"jsSupportRuntimePath": "main.dart.db41cfdb.mjs"}, '
              '{"compileTarget": "dart2js", '
              '"mainJsPath": "main.dart.785ea741.js"}], '
              '"assetManifest": "AssetManifest.bin.10579154.json", '
              '"fontManifest": "FontManifest.e5f60718.json"};',
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(report.hasErrors, isFalse);
      expect(report.hasWarnings, isFalse);
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'W-01' &&
              f.severity == Severity.ok &&
              f.message.contains('main.dart.5f77f974.wasm'),
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'M-01' &&
              f.path == 'main.dart.5f77f974.wasm' &&
              f.severity == Severity.ok,
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'M-02' &&
              f.path == 'main.dart.db41cfdb.mjs' &&
              f.severity == Severity.ok,
        ),
        isTrue,
      );
    });

    test('emits W-01 Severity.warn when mainWasmPath is empty/whitespace or '
        'dart2wasm is only in JS comments', () async {
      final emptyPathReport = await UrlChecker(
        'https://example.com',
        client: _buildBootstrapClient(
          bootstrapBody:
              '_flutter.buildConfig = {"builds": [ '
              '{"compileTarget": "dart2wasm", "mainWasmPath": "   "}, '
              '{"compileTarget": "dart2js", '
              '"mainJsPath": "main.dart.785ea741.js"}]};',
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        emptyPathReport.findings.any(
          (CheckFinding f) => f.ruleId == 'W-01' && f.severity == Severity.warn,
        ),
        isTrue,
      );

      final commentedWasmReport = await UrlChecker(
        'https://example.com',
        client: _buildBootstrapClient(
          bootstrapBody:
              '// {"compileTarget": "dart2wasm", '
              '"mainWasmPath": "main.dart.5f77f974.wasm"}\n'
              '_flutter.buildConfig = {"builds": [ '
              '{"compileTarget": "dart2js", '
              '"mainJsPath": "main.dart.785ea741.js"}]};',
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        commentedWasmReport.findings.any(
          (CheckFinding f) => f.ruleId == 'W-01' && f.severity == Severity.warn,
        ),
        isTrue,
      );
    });
  });
}

void _registerW02Tests() {
  group(
    'W-02: Synthetic Missing .wasm SPA Fallback & 404 Negative-Cache Probe',
    () {
      test(
        'fails with F-05 Severity.error when /main.dart.00000000.wasm returns '
        '200 text/html even if .js returns 404',
        () async {
          final report = await UrlChecker(
            'https://example.com',
            client: _buildWasmProbeClient(
              wasmStatus: 200,
              wasmContentType: 'text/html; charset=utf-8',
              wasmCacheControl: 'public, max-age=31536000, immutable',
              wasmBody: '<!DOCTYPE html><html></html>',
            ),
            minCompressionBytes: 100000,
          ).analyze();

          expect(
            report.findings.any(
              (CheckFinding f) =>
                  f.ruleId == 'F-05' &&
                  f.path == 'main.dart.00000000.wasm' &&
                  f.severity == Severity.error &&
                  f.message.contains('0x3c21444f') &&
                  f.message.contains('WebAssembly.compileStreaming'),
            ),
            isTrue,
          );
        },
      );

      test(
        'fails with F-06 Severity.error when /main.dart.00000000.wasm returns '
        '404 with immutable',
        () async {
          final report = await UrlChecker(
            'https://example.com',
            client: _buildWasmProbeClient(
              wasmStatus: 404,
              wasmContentType: 'text/plain',
              wasmCacheControl: 'public, max-age=31536000, immutable',
            ),
            minCompressionBytes: 100000,
          ).analyze();

          expect(
            report.findings.any(
              (CheckFinding f) =>
                  f.ruleId == 'F-06' &&
                  f.path == 'main.dart.00000000.wasm' &&
                  f.severity == Severity.error,
            ),
            isTrue,
          );
        },
      );

      test('emits F-05 Severity.ok when /main.dart.00000000.wasm returns 404 '
          'with no-store', () async {
        final report = await UrlChecker(
          'https://example.com',
          client: _buildWasmProbeClient(
            wasmStatus: 404,
            wasmContentType: 'text/plain',
            wasmCacheControl: 'no-store',
          ),
          minCompressionBytes: 100000,
        ).analyze();

        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-05' &&
                f.path == 'main.dart.00000000.wasm' &&
                f.severity == Severity.ok,
          ),
          isTrue,
        );
      });
    },
  );
}

void _registerE02Tests() {
  group('E-02: Local Firebase superstatic emulator recognition', () {
    test(
      'recognizes superstatic on 127.0.0.1/localhost/[::1] for F-06 and C-01',
      () async {
        for (final url in <String>[
          'http://127.0.0.1:5000',
          'http://localhost:5000',
          'http://[::1]:5000',
        ]) {
          final report = await UrlChecker(
            url,
            client: _buildSuperstaticClient(),
          ).analyze();

          expect(report.hasErrors, isFalse, reason: 'Failed on $url');
          expect(report.hasWarnings, isFalse, reason: 'Warned on $url');
          expect(
            report.findings.any(
              (CheckFinding f) =>
                  f.ruleId == 'F-06' &&
                  f.severity == Severity.ok &&
                  f.message.contains('superstatic'),
            ),
            isTrue,
          );
          expect(
            report.findings.any(
              (CheckFinding f) =>
                  f.ruleId == 'C-01' &&
                  f.severity == Severity.ok &&
                  f.message.contains('superstatic'),
            ),
            isTrue,
          );
        }
      },
    );

    test(
      'still flags F-06 fail and C-01 warn on non-localhost domain',
      () async {
        final report = await UrlChecker(
          'https://example.web.app',
          client: _buildSuperstaticClient(),
        ).analyze();

        expect(report.hasErrors, isTrue);
        expect(report.hasWarnings, isTrue);
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-06' && f.severity == Severity.error,
          ),
          isTrue,
        );
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'C-01' && f.severity == Severity.warn,
          ),
          isTrue,
        );
      },
    );
  });
}

http.Client _buildPrecacheManifestClient({
  required String manifestBody,
  String manifestCacheControl = 'max-age=0, must-revalidate',
}) => MockClient((http.Request request) async {
  if (request.url.path == '/precache_manifest.json') {
    return http.Response(
      manifestBody,
      200,
      headers: <String, String>{
        'cache-control': manifestCacheControl,
        'content-type': 'application/json',
      },
    );
  }
  return _handleBootstrapRequest(
    request,
    bootstrapBody:
        '_flutter.buildConfig = {"builds": [ '
        '{"compileTarget": "dart2wasm", '
        '"mainWasmPath": "main.dart.5f77f974.wasm", '
        '"jsSupportRuntimePath": "main.dart.db41cfdb.mjs"}, '
        '{"compileTarget": "dart2js", '
        '"mainJsPath": "main.dart.785ea741.js"}]};',
    wasmCacheControl: 'public, max-age=31536000, immutable',
    wasmContentType: 'application/wasm',
    mjsCacheControl: 'public, max-age=31536000, immutable',
    mjsContentType: 'text/javascript',
  );
});

void _registerF08Tests() {
  group('F-07 & F-08: precache_manifest.json validation', () {
    test('passes F-07 and F-08 when precache_manifest.json revalidates and all '
        'hashed entries match', () async {
      const validManifest = '''
{
  "version": 1,
  "entries": [
    {"url": "index.html", "hash": "11111111", "size": 13, "urlHashed": false},
    {"url": "flutter_bootstrap.js", "hash": "22222222", "size": 100, "urlHashed": false},
    {"url": "main.dart.5f77f974.wasm", "hash": "5f77f974", "size": 8, "urlHashed": true},
    {"url": "main.dart.db41cfdb.mjs", "hash": "db41cfdb", "size": 36, "urlHashed": true},
    {"url": "main.dart.785ea741.js", "hash": "785ea741", "size": 19, "urlHashed": true},
    {"url": "assets/images/logo.342887cc.png", "hash": "342887cc", "size": 42, "urlHashed": true}
  ]
}
''';
      final report = await UrlChecker(
        'https://example.com',
        client: _buildPrecacheManifestClient(manifestBody: validManifest),
        minCompressionBytes: 100000,
      ).analyze();

      expect(report.hasErrors, isFalse);
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-07' &&
              f.path == 'precache_manifest.json' &&
              f.severity == Severity.ok,
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-08' &&
              f.path == 'precache_manifest.json' &&
              f.severity == Severity.ok,
        ),
        isTrue,
      );
    });

    test('fails F-08 when --source-maps mutates JS after hashing '
        '(urlHashed: false on hashed filename)', () async {
      const brokenSourceMapManifest = '''
{
  "version": 1,
  "entries": [
    {"url": "main.dart.5f77f974.wasm", "hash": "5f77f974", "size": 8, "urlHashed": true},
    {"url": "main.dart.db41cfdb.mjs", "hash": "b8c4bc7f", "size": 36, "urlHashed": false},
    {"url": "main.dart.785ea741.js", "hash": "fca793b5", "size": 19, "urlHashed": false},
    {"url": "assets/images/logo.342887cc.png/", "hash": "00000000", "size": 42, "urlHashed": false}
  ]
}
''';
      final report = await UrlChecker(
        'https://example.com',
        client: _buildPrecacheManifestClient(
          manifestBody: brokenSourceMapManifest,
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-08' &&
              f.path == 'precache_manifest.json' &&
              f.severity == Severity.fail &&
              f.message.contains('main.dart.785ea741.js') &&
              f.message.contains('main.dart.db41cfdb.mjs') &&
              f.message.contains('assets/images/logo.342887cc.png/'),
        ),
        isTrue,
      );
    });

    test(
      'fails F-07 when precache_manifest.json is cached with max-age > 0 and '
      'F-08 when .map is included or entrypoint is missing',
      () async {
        const badManifest = '''
{
  "version": 1,
  "entries": [
    {"url": "main.dart.5f77f974.wasm", "hash": "5f77f974", "size": 8, "urlHashed": true},
    {"url": "main.dart.785ea741.js.map", "hash": "785ea741", "size": 10, "urlHashed": true}
  ]
}
''';
        final report = await UrlChecker(
          'https://example.com',
          client: _buildPrecacheManifestClient(
            manifestBody: badManifest,
            manifestCacheControl: 'public, max-age=3600',
          ),
          minCompressionBytes: 100000,
        ).analyze();

        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-07' &&
                f.path == 'precache_manifest.json' &&
                f.severity == Severity.fail,
          ),
          isTrue,
        );
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-08' &&
                f.path == 'precache_manifest.json' &&
                f.severity == Severity.fail &&
                f.message.contains('main.dart.785ea741.js.map') &&
                f.message.contains('main.dart.db41cfdb.mjs missing'),
          ),
          isTrue,
        );
      },
    );

    test('fails F-08 when stale precache_manifest.json lingers on an unhashed '
        'deployment', () async {
      final unhashedWithStaleManifest = MockClient((
        http.Request request,
      ) async {
        final path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            request.headers['if-none-match'] == '"v2"' ? 304 : 200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v2"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"builds": [ '
            '{"compileTarget": "dart2js", "mainJsPath": "main.dart.js"}]};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.js') {
          return http.Response(
            'console.log("unhashed");',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'application/javascript',
            },
          );
        }
        if (path == '/precache_manifest.json') {
          return http.Response(
            '{"version":1,"entries":['
            '{"url":"main.dart.785ea741.js","hash":"785ea741",'
            '"size":19,"urlHashed":true}]}',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'application/json',
            },
          );
        }
        return http.Response(
          'Not Found',
          404,
          headers: <String, String>{
            'cache-control': 'max-age=0, must-revalidate',
          },
        );
      });

      final report = await UrlChecker(
        'https://example.com',
        client: unhashedWithStaleManifest,
        requireWasm: false,
        minCompressionBytes: 100000,
      ).analyze();

      expect(report.hasFailures, isTrue);
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-08' &&
              f.path == 'precache_manifest.json' &&
              f.severity == Severity.fail &&
              f.message.contains('unhashed deployment') &&
              f.message.contains('main.dart.js missing') &&
              f.message.contains('main.dart.785ea741.js'),
        ),
        isTrue,
      );
    });

    test('fails F-08 when precache_manifest.json lists stale main.dart.* '
        'entrypoints not in flutter_bootstrap.js', () async {
      const manifestWithStaleEntrypoint = '''
{
  "version": 1,
  "entries": [
    {"url": "main.dart.5f77f974.wasm", "hash": "5f77f974", "size": 8, "urlHashed": true},
    {"url": "main.dart.db41cfdb.mjs", "hash": "db41cfdb", "size": 36, "urlHashed": true},
    {"url": "main.dart.785ea741.js", "hash": "785ea741", "size": 19, "urlHashed": true},
    {"url": "main.dart.deadbeef.js", "hash": "deadbeef", "size": 19, "urlHashed": true}
  ]
}
''';
      final report = await UrlChecker(
        'https://example.com',
        client: _buildPrecacheManifestClient(
          manifestBody: manifestWithStaleEntrypoint,
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-08' &&
              f.path == 'precache_manifest.json' &&
              f.severity == Severity.fail &&
              f.message.contains('main.dart.deadbeef.js (stale entrypoint'),
        ),
        isTrue,
      );
    });
  });
}

void _registerMissingBootloaderTests() {
  group(
    'F-01 & F-02: Missing index.html and flutter_bootstrap.js deployments',
    () {
      test('fails F-01 and F-02 when both index.html (and /) and '
          'flutter_bootstrap.js return 404', () async {
        final missingBootloadersClient = MockClient(
          (http.Request request) async => http.Response(
            'Not Found',
            404,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
            },
          ),
        );

        final report = await UrlChecker(
          'https://example.com',
          client: missingBootloadersClient,
          minCompressionBytes: 100000,
        ).analyze();

        expect(report.hasFailures, isTrue);
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-01' &&
                f.path == '/' &&
                f.severity == Severity.fail &&
                f.message.contains('404'),
          ),
          isTrue,
        );
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-02' &&
                f.path == 'flutter_bootstrap.js' &&
                f.severity == Severity.fail &&
                f.message.contains('404'),
          ),
          isTrue,
        );
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'R-01' || f.ruleId == 'R-02' || f.ruleId == 'W-01',
          ),
          isFalse,
        );
      });

      test('falls back from 404 /index.html to 200 / while failing F-02 on 404 '
          'flutter_bootstrap.js', () async {
        final rootOnlyMissingBootstrapClient = MockClient((
          http.Request request,
        ) async {
          if (request.url.path == '/') {
            return http.Response(
              '<html></html>',
              request.headers['if-none-match'] == '"root-v1"' ? 304 : 200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': '"root-v1"',
              },
            );
          }
          return http.Response(
            'Not Found',
            404,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
            },
          );
        });

        final report = await UrlChecker(
          'https://example.com',
          client: rootOnlyMissingBootstrapClient,
          minCompressionBytes: 100000,
        ).analyze();

        expect(report.hasFailures, isTrue);
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-01' &&
                f.path == '/' &&
                f.severity == Severity.ok,
          ),
          isTrue,
        );
        expect(
          report.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'F-02' &&
                f.path == 'flutter_bootstrap.js' &&
                f.severity == Severity.fail &&
                f.message.contains('404'),
          ),
          isTrue,
        );
      });
    },
  );
}
