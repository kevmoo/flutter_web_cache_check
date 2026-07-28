import 'dart:io';

import 'package:http/http.dart' as http;

class UrlChecker {
  static Future<void> checkUrl(String targetUrl, {bool verbose = false}) async {
    final Uri baseUri = Uri.parse(targetUrl);
    print('🔍 Inspecting deployed Flutter web app at: $targetUrl');

    bool allPassed = true;

    // 1. Check Bootloader / Index
    final Uri indexUri = baseUri.resolve('index.html');
    final bool indexPassed = await _checkNoCacheHeader(
      indexUri,
      'index.html',
      verbose,
    );
    if (!indexPassed) allPassed = false;

    final Uri bootstrapUri = baseUri.resolve('flutter_bootstrap.js');
    final bool bootstrapPassed = await _checkNoCacheHeader(
      bootstrapUri,
      'flutter_bootstrap.js',
      verbose,
    );
    if (!bootstrapPassed) allPassed = false;

    // 2. Fetch and Parse flutter_bootstrap.js
    print('\n📦 Downloading and parsing flutter_bootstrap.js...');
    final http.Response bootstrapResp = await http.get(bootstrapUri);
    if (bootstrapResp.statusCode != 200) {
      print(
        '❌ [FAIL] Failed to fetch flutter_bootstrap.js (status ${bootstrapResp.statusCode}). Cannot verify entrypoints.',
      );
      exit(1);
    }

    final Map<String, String> entrypoints = _extractEntrypoints(
      bootstrapResp.body,
    );
    if (entrypoints.isEmpty) {
      print(
        '⚠️ [WARN] Could not find any active entrypoints (mainJsPath, mainWasmPath) in _flutter.buildConfig.',
      );
    } else {
      for (final MapEntry<String, String> entry in entrypoints.entries) {
        final String label = entry.key;
        final String filename = entry.value;
        final bool isHashed = RegExp(
          r'^main\.dart\.[a-f0-9]{8}\.(js|wasm|mjs)$',
        ).hasMatch(filename);

        if (isHashed) {
          print('✅ [PASS] Discovered content-hashed $label: $filename');
        } else {
          print(
            '⚠️ [WARN] Discovered un-hashed $label: $filename (--web-content-hash may not be enabled)',
          );
        }

        final Uri entryUri = baseUri.resolve(filename);
        final bool entryPassed = await _checkImmutableHeader(
          entryUri,
          filename,
          isHashed,
          verbose,
        );
        if (!entryPassed) allPassed = false;
      }
    }

    print('\n----------------------------------------');
    if (allPassed) {
      print('✨ All caching header checks PASSED!');
    } else {
      print('❌ Some caching header checks FAILED. See report above.');
      exit(1);
    }
  }

  static Future<bool> _checkNoCacheHeader(
    Uri uri,
    String label,
    bool verbose,
  ) async {
    try {
      final http.Response resp = await http.head(uri);
      if (resp.statusCode == 404 && label == 'index.html') {
        // Fallback to GET baseUri if index.html is rewritten
        return _checkNoCacheHeader(uri.resolve('./'), '/', verbose);
      }
      if (resp.statusCode >= 400) {
        print('❌ [FAIL] $label returned HTTP ${resp.statusCode}');
        return false;
      }

      final String? cacheControl = resp.headers['cache-control']?.toLowerCase();
      if (verbose) {
        print('[VERBOSE] $label ($uri) -> Cache-Control: $cacheControl');
      }

      if (cacheControl == null) {
        print(
          '❌ [FAIL] $label is missing Cache-Control header! (Should be no-cache/revalidating)',
        );
        return false;
      }

      final bool isNoCache =
          cacheControl.contains('no-cache') ||
          cacheControl.contains('no-store') ||
          cacheControl.contains('max-age=0') ||
          cacheControl.contains('must-revalidate');

      if (isNoCache) {
        print(
          '✅ [PASS] $label is correctly configured for revalidation ($cacheControl)',
        );
        return true;
      } else {
        print(
          '❌ [FAIL] $label has risky Cache-Control: "$cacheControl" (Must include no-cache, max-age=0, or must-revalidate)',
        );
        return false;
      }
    } catch (e) {
      print('❌ [FAIL] Error connecting to $uri: $e');
      return false;
    }
  }

  static Future<bool> _checkImmutableHeader(
    Uri uri,
    String filename,
    bool isHashed,
    bool verbose,
  ) async {
    try {
      final http.Response resp = await http.head(uri);
      if (resp.statusCode >= 400) {
        print('❌ [FAIL] Entrypoint $filename returned HTTP ${resp.statusCode}');
        return false;
      }

      final String? cacheControl = resp.headers['cache-control']?.toLowerCase();
      if (verbose) {
        print('[VERBOSE] $filename ($uri) -> Cache-Control: $cacheControl');
      }

      if (!isHashed) {
        // If un-hashed, it should NOT be immutable
        if (cacheControl != null &&
            (cacheControl.contains('immutable') ||
                cacheControl.contains('31536000'))) {
          print(
            '❌ [FAIL] Un-hashed entrypoint $filename is served with aggressive caching ("$cacheControl")! Users will get stuck on stale builds.',
          );
          return false;
        }
        return true;
      }

      if (cacheControl == null) {
        print(
          '❌ [FAIL] Hashed entrypoint $filename is missing Cache-Control header! Should be max-age=31536000, immutable.',
        );
        return false;
      }

      final bool isImmutable =
          cacheControl.contains('immutable') ||
          cacheControl.contains('31536000') ||
          cacheControl.contains('max-age=');

      if (isImmutable &&
          !cacheControl.contains('no-cache') &&
          !cacheControl.contains('max-age=0')) {
        print(
          '✅ [PASS] Hashed entrypoint $filename is aggressively cached ($cacheControl)',
        );
        return true;
      } else {
        print(
          '❌ [FAIL] Hashed entrypoint $filename is not cached aggressively enough: "$cacheControl" (Expected max-age=31536000, immutable)',
        );
        return false;
      }
    } catch (e) {
      print('❌ [FAIL] Error connecting to $uri: $e');
      return false;
    }
  }

  static Map<String, String> _extractEntrypoints(String bootstrapBody) {
    final Map<String, String> results = <String, String>{};
    // Match keys like "mainJsPath":"main.dart.10579154.js" or "mainWasmPath":"..."
    final RegExp reg = RegExp(
      r'"(mainJsPath|mainWasmPath|jsSupportRuntimePath)"\s*:\s*"([^"]+)"',
    );
    for (final Match match in reg.allMatches(bootstrapBody)) {
      if (match.groupCount == 2) {
        results[match.group(1)!] = match.group(2)!;
      }
    }
    return results;
  }
}
