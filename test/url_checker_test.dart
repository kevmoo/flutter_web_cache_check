import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('W-01: First-Class WebAssembly (dart2wasm) Target Detection', () {
    http.Client buildBootstrapClient({
      required String bootstrapBody,
      String wasmCacheControl = 'public, max-age=31536000, immutable',
      String wasmContentType = 'application/wasm',
      String mjsCacheControl = 'public, max-age=31536000, immutable',
      String mjsContentType = 'text/javascript',
    }) {
      return MockClient((http.Request request) async {
        final String path = request.url.path;
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
          headers: <String, String>{
            'cache-control': 'max-age=0, must-revalidate',
          },
        );
      });
    }

    test('emits W-01 Severity.warn when flutter_bootstrap.js only has mainJsPath and requireWasm is true', () async {
      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: buildBootstrapClient(
          bootstrapBody: '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}]};',
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'W-01' &&
              f.severity == Severity.warn &&
              f.message.contains('flutter build web --wasm --web-content-hash'),
        ),
        isTrue,
      );
    });

    test('emits W-01 Severity.ok when flutter_bootstrap.js only has mainJsPath and requireWasm is false', () async {
      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: buildBootstrapClient(
          bootstrapBody: '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}]};',
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

    test('emits W-01 Severity.ok and validates .wasm (F-03, M-01) and .mjs (F-03, M-02) when mainWasmPath is present', () async {
      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: buildBootstrapClient(
          bootstrapBody: '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm","mainWasmPath":"main.dart.5f77f974.wasm","jsSupportRuntimePath":"main.dart.db41cfdb.mjs"},{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}],"assetManifest":"AssetManifest.bin.10579154.json","fontManifest":"FontManifest.e5f60718.json"};',
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

    test('emits W-01 Severity.warn when mainWasmPath is empty/whitespace or dart2wasm is only in JS comments', () async {
      final CheckReport emptyPathReport = await UrlChecker(
        'https://example.com',
        client: buildBootstrapClient(
          bootstrapBody: '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm","mainWasmPath":"   "},{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}]};',
        ),
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        emptyPathReport.findings.any(
          (CheckFinding f) => f.ruleId == 'W-01' && f.severity == Severity.warn,
        ),
        isTrue,
      );

      final CheckReport commentedWasmReport = await UrlChecker(
        'https://example.com',
        client: buildBootstrapClient(
          bootstrapBody: '// {"compileTarget":"dart2wasm","mainWasmPath":"main.dart.5f77f974.wasm"}\n_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}]};',
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

  group(
    'W-02: Synthetic Missing .wasm SPA Fallback & 404 Negative-Cache Probe',
    () {
      http.Client buildWasmProbeClient({
        required int wasmStatus,
        required String wasmContentType,
        required String wasmCacheControl,
        String wasmBody = 'Not Found',
      }) {
        return MockClient((http.Request request) async {
          final String path = request.url.path;
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
              '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm","mainWasmPath":"main.dart.5f77f974.wasm","jsSupportRuntimePath":"main.dart.db41cfdb.mjs"},{"compileTarget":"dart2js","mainJsPath":"main.dart.785ea741.js"}]};',
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
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'application/wasm',
              },
            );
          }
          if (path == '/main.dart.db41cfdb.mjs' ||
              path == '/main.dart.785ea741.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.00000000.wasm') {
            return http.Response(
              wasmBody,
              wasmStatus,
              headers: <String, String>{
                'cache-control': wasmCacheControl,
                'content-type': wasmContentType,
              },
            );
          }
          return http.Response(
            'Not Found',
            404,
            headers: <String, String>{'cache-control': 'no-store'},
          );
        });
      }

      test('fails with F-05 Severity.error when /main.dart.00000000.wasm returns 200 text/html even if .js returns 404', () async {
        final CheckReport report = await UrlChecker(
          'https://example.com',
          client: buildWasmProbeClient(
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
      });

      test('fails with F-06 Severity.error when /main.dart.00000000.wasm returns 404 with immutable', () async {
        final CheckReport report = await UrlChecker(
          'https://example.com',
          client: buildWasmProbeClient(
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
      });

      test('emits F-05 Severity.ok when /main.dart.00000000.wasm returns 404 with no-store', () async {
        final CheckReport report = await UrlChecker(
          'https://example.com',
          client: buildWasmProbeClient(
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
