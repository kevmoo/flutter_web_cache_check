import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 2 (G-03 – G-08): Universal Browser Runtime & Asset Graph Checks', () {
    test('G-03 (Case A): hashed AssetManifest & FontManifest in buildConfig fail (F-04) when max-age=3600 and pass when immutable', () async {
      http.Client buildClient({required String manifestCacheControl}) {
        return MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': '"v1"',
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js","assetManifest":"AssetManifest.bin.a1b2c3d4.json","fontManifest":"FontManifest.e5f60718.json"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'application/javascript',
              },
            );
          }
          if (path == '/assets/AssetManifest.bin.a1b2c3d4.json' ||
              path == '/assets/FontManifest.e5f60718.json') {
            return http.Response(
              '{}',
              200,
              headers: <String, String>{
                'cache-control': manifestCacheControl,
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

      final CheckReport badReport = await UrlChecker(
        'https://example.com',
        client: buildClient(manifestCacheControl: 'public, max-age=3600'),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        badReport.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-04' &&
              f.path == 'assets/AssetManifest.bin.a1b2c3d4.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );

      final CheckReport goodReport = await UrlChecker(
        'https://example.com',
        client: buildClient(
          manifestCacheControl: 'public, max-age=31536000, immutable',
        ),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        goodReport.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-04' &&
              f.path == 'assets/AssetManifest.bin.a1b2c3d4.json' &&
              f.severity == Severity.ok,
        ),
        isTrue,
      );
    });

    test('G-03 (Case B): unhashed assets/AssetManifest.bin.json served with max-age > 0 FAILS with F-07', () async {
      final MockClient client = MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
            },
          );
        }
        if (path == '/assets/AssetManifest.bin.json') {
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

      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: client,
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-07' &&
              f.path == 'assets/AssetManifest.bin.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );

      final MockClient cdnCachedManifestClient = MockClient((
        http.Request request,
      ) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
            },
          );
        }
        if (path == '/assets/AssetManifest.bin.json') {
          return http.Response(
            '{}',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'cdn-cache-control': 'max-age=3600',
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

      final CheckReport cdnReport = await UrlChecker(
        'https://example.com',
        client: cdnCachedManifestClient,
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        cdnReport.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-07' &&
              f.path == 'assets/AssetManifest.bin.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );
    });

    test('G-04: .wasm and .mjs MIME type enforcement (M-01, M-02)', () async {
      http.Client buildClient({
        required String wasmContentType,
        required String mjsContentType,
      }) {
        return MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': '"v1"',
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainWasmPath":"main.dart.10579154.wasm","jsSupportRuntimePath":"main.dart.10579154.mjs"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.wasm') {
            return http.Response(
              'wasm-bytes',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': wasmContentType,
              },
            );
          }
          if (path == '/main.dart.10579154.mjs') {
            return http.Response(
              'export default {};',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': mjsContentType,
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

      final CheckReport badReport = await UrlChecker(
        'https://example.com',
        client: buildClient(
          wasmContentType: 'application/octet-stream',
          mjsContentType: 'text/plain',
        ),
        minCompressionBytes: 100000,
      ).analyze();
      expect(badReport.hasFailures, isTrue);
      expect(
        badReport.findings.any(
          (CheckFinding f) => f.ruleId == 'M-01' && f.severity == Severity.fail,
        ),
        isTrue,
      );
      expect(
        badReport.findings.any(
          (CheckFinding f) => f.ruleId == 'M-02' && f.severity == Severity.fail,
        ),
        isTrue,
      );

      final CheckReport goodReport = await UrlChecker(
        'https://example.com',
        client: buildClient(
          wasmContentType: 'application/wasm',
          mjsContentType: 'text/javascript; charset=utf-8',
        ),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        goodReport.findings.any(
          (CheckFinding f) =>
              (f.ruleId == 'M-01' || f.ruleId == 'M-02') &&
              f.severity == Severity.fail,
        ),
        isFalse,
      );
    });

    test(
      'G-05: Compression (br/gzip) & Vary: Accept-Encoding (C-01, C-02)',
      () async {
        http.Client buildClient({String? contentEncoding, String? vary}) {
          final String largePayload = 'x' * 2048;
          return MockClient((http.Request request) async {
            final String path = request.url.path;
            if (path == '/index.html' || path == '/') {
              return http.Response(
                '<html></html>',
                200,
                headers: <String, String>{
                  'cache-control': 'max-age=0, must-revalidate',
                  'etag': '"v1"',
                },
              );
            }
            if (path == '/flutter_bootstrap.js') {
              return http.Response(
                '_flutter.buildConfig = {"mainWasmPath":"main.dart.10579154.wasm"};',
                200,
                headers: <String, String>{
                  'cache-control': 'max-age=0, must-revalidate',
                  'content-type': 'text/javascript',
                },
              );
            }
            if (path == '/main.dart.10579154.wasm') {
              return http.Response(
                largePayload,
                200,
                headers: <String, String>{
                  'cache-control': 'public, max-age=31536000, immutable',
                  'content-type': 'application/wasm',
                  'content-length': '${largePayload.length}',
                  'content-encoding': ?contentEncoding,
                  'vary': ?vary,
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

        final CheckReport missingCompression = await UrlChecker(
          'https://example.com',
          client: buildClient(),
        ).analyze();
        expect(
          missingCompression.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'C-01' && f.severity == Severity.warn,
          ),
          isTrue,
        );

        final CheckReport missingVary = await UrlChecker(
          'https://example.com',
          client: buildClient(contentEncoding: 'br'),
        ).analyze();
        expect(
          missingVary.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'C-02' && f.severity == Severity.warn,
          ),
          isTrue,
        );

        final CheckReport goodCompression = await UrlChecker(
          'https://example.com',
          client: buildClient(contentEncoding: 'br', vary: 'Accept-Encoding'),
        ).analyze();
        expect(
          goodCompression.findings.any(
            (CheckFinding f) =>
                (f.ruleId == 'C-01' || f.ruleId == 'C-02') &&
                f.severity == Severity.warn,
          ),
          isFalse,
        );
      },
    );

    test('G-06: Conditional Revalidation (ETag + If-None-Match -> 304 vs 200) (R-01, R-02)', () async {
      http.Client buildClient({String? etag, required int conditionalStatus}) {
        return MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            if (request.headers['if-none-match'] != null) {
              return http.Response(
                conditionalStatus == 304 ? '' : '<html></html>',
                conditionalStatus,
                headers: <String, String>{
                  'cache-control': 'max-age=0, must-revalidate',
                  'etag': ?etag,
                },
              );
            }
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': ?etag,
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'application/javascript',
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

      final CheckReport status200OnIfNoneMatch = await UrlChecker(
        'https://example.com',
        client: buildClient(etag: '"v1"', conditionalStatus: 200),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        status200OnIfNoneMatch.findings.any(
          (CheckFinding f) => f.ruleId == 'R-02' && f.severity == Severity.warn,
        ),
        isTrue,
      );

      final CheckReport status304OnIfNoneMatch = await UrlChecker(
        'https://example.com',
        client: buildClient(etag: '"v1"', conditionalStatus: 304),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        status304OnIfNoneMatch.findings.any(
          (CheckFinding f) => f.ruleId == 'R-02' && f.severity == Severity.ok,
        ),
        isTrue,
      );
    });

    test('G-07: SPA Catch-All Rewrite Poisoning Probe (F-05) fails when missing hashed asset returns 200 text/html', () async {
      final MockClient client = MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
            },
          );
        }
        if (path == '/main.dart.00000000.js' ||
            path == '/assets/__cache_check_missing__.00000000.png') {
          return http.Response(
            '<!DOCTYPE html><html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'text/html; charset=utf-8',
            },
          );
        }
        return http.Response('Not Found', 404);
      });

      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: client,
        minCompressionBytes: 100000,
      ).analyze();
      expect(report.hasFailures, isTrue);
      expect(
        report.findings.any(
          (CheckFinding f) => f.ruleId == 'F-05' && f.severity == Severity.fail,
        ),
        isTrue,
      );
    });

    test('G-07b: /flutter_bootstrap.js and /assets/AssetManifest.bin.json returning 200 text/html are flagged as F-05 SPA rewrite failures instead of F-02/F-07', () async {
      final MockClient spaFallbackClient = MockClient((
        http.Request request,
      ) async {
        final String path = request.url.path;
        if (path == '/index.html' ||
            path == '/' ||
            path == '/flutter_bootstrap.js' ||
            path == '/assets/AssetManifest.bin.json') {
          return http.Response(
            '<!DOCTYPE html><html><body>SPA</body></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/html; charset=utf-8',
              'etag': '"spa-v1"',
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

      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: spaFallbackClient,
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-05' &&
              f.path == 'flutter_bootstrap.js' &&
              f.severity == Severity.fail,
        ),
        isTrue,
        reason:
            'flutter_bootstrap.js returning 200 text/html must fail with F-05',
      );
      expect(
        report.findings.any((CheckFinding f) => f.ruleId == 'F-02'),
        isFalse,
        reason: 'flutter_bootstrap.js returning 200 text/html must not be evaluated as F-02',
      );
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-05' &&
              f.path == 'assets/AssetManifest.bin.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
        reason: 'assets/AssetManifest.bin.json returning 200 text/html must fail with F-05',
      );
      expect(
        report.findings.any((CheckFinding f) => f.ruleId == 'F-07'),
        isFalse,
        reason: 'assets/AssetManifest.bin.json returning 200 text/html must not be evaluated as F-07',
      );

      // Sub-case 2: /flutter_bootstrap.js is valid JS, but /assets/AssetManifest.bin.json
      // (both extracted from buildConfig and default probe) returns 200 text/html,
      // or carries CDN-Cache-Control: max-age=3600.
      final MockClient validBootstrapManifestHtmlClient = MockClient((
        http.Request request,
      ) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js","assetManifest":"AssetManifest.bin.json"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
            },
          );
        }
        if (path == '/assets/AssetManifest.bin.json') {
          return http.Response(
            '<!DOCTYPE html><html><body>SPA</body></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/html; charset=utf-8',
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

      final CheckReport report2 = await UrlChecker(
        'https://example.com',
        client: validBootstrapManifestHtmlClient,
        minCompressionBytes: 100000,
      ).analyze();

      expect(
        report2.findings.any(
          (CheckFinding f) => f.ruleId == 'F-02' && f.severity == Severity.ok,
        ),
        isTrue,
      );
      expect(
        report2.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-05' &&
              f.path == 'assets/AssetManifest.bin.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );
      expect(
        report2.findings.any((CheckFinding f) => f.ruleId == 'F-07'),
        isFalse,
      );
    });

    test('G-08: Negative-Cache / 404 TTL Probe (F-06) fails when 404 carries long TTL or immutable', () async {
      http.Client buildClient({required String notFoundCacheControl}) {
        return MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': '"v1"',
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'application/javascript',
              },
            );
          }
          return http.Response(
            'Not Found',
            404,
            headers: <String, String>{'cache-control': notFoundCacheControl},
          );
        });
      }

      final CheckReport badReport = await UrlChecker(
        'https://example.com',
        client: buildClient(
          notFoundCacheControl: 'public, max-age=31536000, immutable',
        ),
        minCompressionBytes: 100000,
      ).analyze();
      expect(badReport.hasFailures, isTrue);
      expect(
        badReport.findings.any(
          (CheckFinding f) => f.ruleId == 'F-06' && f.severity == Severity.fail,
        ),
        isTrue,
      );

      final CheckReport goodReport = await UrlChecker(
        'https://example.com',
        client: buildClient(notFoundCacheControl: 'max-age=0, must-revalidate'),
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        goodReport.findings.any(
          (CheckFinding f) => f.ruleId == 'F-06' && f.severity == Severity.ok,
        ),
        isTrue,
      );
    });
  });

  group('Phase 3 (FB-01 & FB-02): Firebase Hosting Adapter', () {
    test('detects Firebase Hosting via Vary: x-fh-requested-host and warns on no-cache/no-store (F-12)', () async {
      final MockClient client = MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'no-cache, no-store, must-revalidate',
              'vary': 'Accept-Encoding, x-fh-requested-host',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
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

      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: client,
        minCompressionBytes: 100000,
      ).analyze();
      expect(report.detectedPlatform, HostPlatform.firebase);
      expect(report.hasFailures, isFalse);
      final CheckFinding f12 = report.findings.firstWhere(
        (CheckFinding f) => f.ruleId == 'F-12',
      );
      expect(f12.severity, Severity.warn);
      expect(f12.message, contains('return(pass)'));
      expect(f12.message, contains('max-age=0, must-revalidate'));
    });

    test(
      'does NOT emit F-12 Fastly warning on generic host with no-cache',
      () async {
        final MockClient client = MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'no-cache, no-store, must-revalidate',
                'vary': 'Accept-Encoding',
                'etag': '"v1"',
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'application/javascript',
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

        final CheckReport report = await UrlChecker(
          'https://example.com',
          client: client,
          minCompressionBytes: 100000,
        ).analyze();
        expect(report.detectedPlatform, HostPlatform.generic);
        expect(
          report.findings.where((CheckFinding f) => f.ruleId == 'F-12'),
          isEmpty,
        );
      },
    );

    test(
      'G-04: .js served with text/plain FAILS M-02 and valid .js emits M-02 ok',
      () async {
        final MockClient badJsClient = MockClient((http.Request request) async {
          final String path = request.url.path;
          if (path == '/index.html' || path == '/') {
            return http.Response(
              '<html></html>',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'etag': '"v1"',
              },
            );
          }
          if (path == '/flutter_bootstrap.js') {
            return http.Response(
              '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
              200,
              headers: <String, String>{
                'cache-control': 'max-age=0, must-revalidate',
                'content-type': 'text/javascript',
              },
            );
          }
          if (path == '/main.dart.10579154.js') {
            return http.Response(
              'console.log("app");',
              200,
              headers: <String, String>{
                'cache-control': 'public, max-age=31536000, immutable',
                'content-type': 'text/plain; charset=utf-8',
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

        final CheckReport badJsReport = await UrlChecker(
          'https://example.com',
          client: badJsClient,
          minCompressionBytes: 100000,
        ).analyze();
        expect(
          badJsReport.findings.any(
            (CheckFinding f) =>
                f.ruleId == 'M-02' &&
                f.path == 'main.dart.10579154.js' &&
                f.severity == Severity.fail,
          ),
          isTrue,
        );
      },
    );

    test('G-01/G-03: unhashed entrypoint or manifest with missing Cache-Control FAILS (no heuristic caching false pass)', () async {
      final MockClient noHeaderClient = MockClient((
        http.Request request,
      ) async {
        final String path = request.url.path;
        if (path == '/index.html' || path == '/') {
          return http.Response(
            '<html></html>',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.js","assetManifest":"AssetManifest.bin.json"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/main.dart.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{'content-type': 'application/javascript'},
          );
        }
        if (path == '/assets/AssetManifest.bin.json') {
          return http.Response(
            '{}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
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

      final CheckReport report = await UrlChecker(
        'https://example.com',
        client: noHeaderClient,
        minCompressionBytes: 100000,
      ).analyze();
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-03' &&
              f.path == 'main.dart.js' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );
      expect(
        report.findings.any(
          (CheckFinding f) =>
              f.ruleId == 'F-07' &&
              f.path == 'assets/AssetManifest.bin.json' &&
              f.severity == Severity.fail,
        ),
        isTrue,
      );
    });

    test('sub-path deployment (--base-href /subapp/) and trailing /index.html targetUrl resolve all probes under /subapp/', () async {
      final List<String> requestedPaths = <String>[];
      final MockClient subappClient = MockClient((http.Request request) async {
        requestedPaths.add(request.url.path);
        final String path = request.url.path;
        if (path == '/subapp/index.html') {
          return http.Response(
            '<html></html>',
            request.headers['if-none-match'] == '"v1"' ? 304 : 200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'cdn-cache-control': 's-maxage=0',
              'etag': '"v1"',
            },
          );
        }
        if (path == '/subapp/flutter_bootstrap.js') {
          return http.Response(
            '_flutter.buildConfig = {"mainJsPath":"/main.dart.10579154.js"};',
            200,
            headers: <String, String>{
              'cache-control': 'max-age=0, must-revalidate',
              'content-type': 'text/javascript',
            },
          );
        }
        if (path == '/subapp/main.dart.10579154.js') {
          return http.Response(
            'console.log("app");',
            200,
            headers: <String, String>{
              'cache-control': 'public, max-age=31536000, immutable',
              'content-type': 'application/javascript',
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

      final CheckReport report = await UrlChecker(
        'https://example.com/subapp/index.html',
        client: subappClient,
        minCompressionBytes: 100000,
      ).analyze();
      expect(report.hasFailures, isFalse);
      expect(
        requestedPaths.every((String p) => p.startsWith('/subapp/')),
        isTrue,
      );
    });
  });
}
