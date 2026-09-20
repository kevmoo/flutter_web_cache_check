import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Client _mockSite({
  String indexCacheControl = 'max-age=0, must-revalidate',
  String? indexCdnCacheControl,
  String? indexSurrogateControl,
  String bootstrapCacheControl = 'max-age=0, must-revalidate',
  String mainJsCacheControl = 'public, max-age=31536000, immutable',
}) {
  return MockClient((http.Request request) async {
    final String path = request.url.path;
    if (path == '/index.html' || path == '/') {
      final int status = request.headers['if-none-match'] == '"v1"' ? 304 : 200;
      return http.Response(
        status == 304 ? '' : '<html></html>',
        status,
        headers: <String, String>{
          'cache-control': indexCacheControl,
          'cdn-cache-control': ?indexCdnCacheControl,
          'surrogate-control': ?indexSurrogateControl,
          'etag': '"v1"',
        },
      );
    }
    if (path == '/flutter_bootstrap.js') {
      return http.Response(
        '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
        200,
        headers: <String, String>{
          'cache-control': bootstrapCacheControl,
          'content-type': 'text/javascript',
        },
      );
    }
    if (path == '/main.dart.10579154.js') {
      return http.Response(
        'console.log("app");',
        200,
        headers: <String, String>{
          'cache-control': mainJsCacheControl,
          'content-type': 'application/javascript',
        },
      );
    }
    return http.Response(
      'Not Found',
      404,
      headers: <String, String>{'cache-control': 'max-age=0, must-revalidate'},
    );
  });
}

void main() {
  group('CacheDirectives.parse unit tests (G-01)', () {
    test('parses directives case-insensitively with numeric values', () {
      final CacheDirectives d = CacheDirectives.parse(
        'Public, Max-Age=31536000, s-maxage=86400, Immutable, Must-Revalidate',
      );
      expect(d.publicDirective, isTrue);
      expect(d.maxAge, 31536000);
      expect(d.sMaxAge, 86400);
      expect(d.immutable, isTrue);
      expect(d.mustRevalidate, isTrue);
      expect(d.noCache, isFalse);
      expect(d.noStore, isFalse);
      expect(d.privateDirective, isFalse);
    });

    test('parses quoted parameters containing commas without splitting inside quotes', () {
      final CacheDirectives d = CacheDirectives.parse(
        'private="Set-Cookie, no-store, max-age=0", max-age=31536000, immutable',
      );
      expect(d.privateDirective, isTrue);
      expect(d.raw['private'], 'Set-Cookie, no-store, max-age=0');
      expect(d.noStore, isFalse);
      expect(d.maxAge, 31536000);
      expect(d.immutable, isTrue);
    });

    test('contradictory max-age=3600, no-cache is NOT considered revalidatingOrZero', () {
      final CacheDirectives d = CacheDirectives.parse('max-age=3600, no-cache');
      expect(d.isRevalidatingOrZero, isFalse);
    });
  });

  group('Phase 1 (G-01 & G-02): False-Pass Regressions & CDN Precedence', () {
    test('max-age=3600 FAILS immutable check (regression for contains("max-age="))', () async {
      final UrlChecker checker = UrlChecker(
        'https://example.com',
        client: _mockSite(mainJsCacheControl: 'public, max-age=3600'),
        minCompressionBytes: 100000,
      );
      final CheckReport report = await checker.analyze();
      final CheckFinding finding = report.findings.firstWhere(
        (CheckFinding f) =>
            f.path == 'main.dart.10579154.js' && f.ruleId == 'F-03',
      );
      expect(finding.severity, Severity.fail);
    });

    test('max-age=3600, must-revalidate FAILS revalidating root check (regression for contains("must-revalidate"))', () async {
      final UrlChecker checker = UrlChecker(
        'https://example.com',
        client: _mockSite(
          indexCacheControl: 'public, max-age=3600, must-revalidate',
        ),
        minCompressionBytes: 100000,
      );
      final CheckReport report = await checker.analyze();
      final CheckFinding finding = report.findings.firstWhere(
        (CheckFinding f) => f.path == 'index.html' && f.ruleId == 'F-01',
      );
      expect(finding.severity, Severity.fail);
    });

    test('max-age=0, must-revalidate PASSES revalidating root check with zero warnings', () async {
      final UrlChecker checker = UrlChecker(
        'https://example.com',
        client: _mockSite(indexCacheControl: 'max-age=0, must-revalidate'),
        minCompressionBytes: 100000,
      );
      final CheckReport report = await checker.analyze();
      final CheckFinding finding = report.findings.firstWhere(
        (CheckFinding f) => f.path == 'index.html' && f.ruleId == 'F-01',
      );
      expect(finding.severity, Severity.ok);
      expect(
        report.findings.where(
          (CheckFinding f) =>
              f.path == 'index.html' && f.severity != Severity.ok,
        ),
        isEmpty,
      );
    });

    test('CDN-Cache-Control: max-age=3600 FAILS revalidating root even when Cache-Control is max-age=0', () async {
      final UrlChecker checker = UrlChecker(
        'https://example.com',
        client: _mockSite(
          indexCacheControl: 'max-age=0, must-revalidate',
          indexCdnCacheControl: 'public, max-age=3600',
        ),
        minCompressionBytes: 100000,
      );
      final CheckReport report = await checker.analyze();
      final CheckFinding finding = report.findings.firstWhere(
        (CheckFinding f) => f.path == 'index.html' && f.ruleId == 'F-01',
      );
      expect(finding.severity, Severity.fail);
    });

    test('max-age=31536000 without immutable WARNS on hashed bundle', () async {
      final UrlChecker checker = UrlChecker(
        'https://example.com',
        client: _mockSite(mainJsCacheControl: 'public, max-age=31536000'),
        minCompressionBytes: 100000,
      );
      final CheckReport report = await checker.analyze();
      final CheckFinding finding = report.findings.firstWhere(
        (CheckFinding f) =>
            f.path == 'main.dart.10579154.js' && f.ruleId == 'F-03',
      );
      expect(finding.severity, Severity.warn);
    });

    test(
      'max-age=31536000, immutable, private FAILS hashed bundle check (F-03)',
      () async {
        final UrlChecker checker = UrlChecker(
          'https://example.com',
          client: _mockSite(
            mainJsCacheControl: 'max-age=31536000, immutable, private',
          ),
          minCompressionBytes: 100000,
        );
        final CheckReport report = await checker.analyze();
        final CheckFinding finding = report.findings.firstWhere(
          (CheckFinding f) =>
              f.path == 'main.dart.10579154.js' && f.ruleId == 'F-03',
        );
        expect(finding.severity, Severity.fail);
      },
    );
  });
}
