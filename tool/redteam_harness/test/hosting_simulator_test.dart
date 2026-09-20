import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:redteam_harness/redteam_harness.dart';
import 'package:test/test.dart';

void main() {
  group('M-02: 1:1 Policy Source-of-Truth Parity (HostingServer <-> FirebaseConfig)', () {
    test('HostingServer.firebaseRules derives directly from FirebaseConfig.defaultHeaders with 5 identical rules', () {
      expect(HostingServer.firebaseRules, same(FirebaseConfig.defaultHeaders));
      expect(HostingServer.firebaseRules.length, 5);

      for (int i = 0; i < FirebaseConfig.defaultHeaders.length; i++) {
        expect(
          HostingServer.firebaseRules[i]['source'],
          equals(FirebaseConfig.defaultHeaders[i]['source']),
        );
        expect(
          HostingServer.firebaseRules[i]['headers'],
          equals(FirebaseConfig.defaultHeaders[i]['headers']),
        );
      }
    });

    test('cacheControlFor(HeaderPolicy.firebaseRules, ...) matches every rule in FirebaseConfig.defaultHeaders', () {
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, 'index.html'),
        'max-age=0, must-revalidate',
      );
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, 'flutter_bootstrap.js'),
        'max-age=0, must-revalidate',
      );
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, 'main.dart.5f77f974.wasm'),
        'public, max-age=31536000, immutable',
      );
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, 'main.dart.db41cfdb.mjs'),
        'public, max-age=31536000, immutable',
      );
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, 'main.dart.785ea741.js'),
        'public, max-age=31536000, immutable',
      );
      expect(
        cacheControlFor(
          HeaderPolicy.firebaseRules,
          'assets/AssetManifest.bin.10579154.json',
        ),
        'public, max-age=31536000, immutable',
      );
      expect(
        cacheControlFor(
          HeaderPolicy.firebaseRules,
          'assets/AssetManifest.bin.json',
        ),
        'max-age=0, must-revalidate',
      );
      expect(
        cacheControlFor(HeaderPolicy.firebaseRules, '404.html'),
        'max-age=0, must-revalidate',
      );
      expect(
        cacheControlFor(
          HeaderPolicy.firebaseRules,
          'main.dart.785ea741.js_1.part.js',
        ),
        'public, max-age=31536000, immutable',
      );
      expect(
        cacheControlFor(
          HeaderPolicy.firebaseRules,
          'main.dart.5f77f974.wasm_1.part.wasm',
        ),
        'public, max-age=31536000, immutable',
      );
    });
  });
}
