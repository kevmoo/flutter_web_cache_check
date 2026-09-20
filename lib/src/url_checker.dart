import 'dart:io';

import 'package:http/http.dart' as http;

enum Severity {
  ok,
  warn,
  fail;

  static const Severity error = Severity.fail;
}

enum HostPlatform { auto, firebase, generic }

typedef Finding = CheckFinding;

class CheckFinding {
  const CheckFinding({
    required this.ruleId,
    required this.severity,
    String? path,
    String? url,
    required this.message,
  }) : path = path ?? url ?? '';

  final String ruleId;
  final Severity severity;
  final String path;
  final String message;

  String get url => path;

  @override
  String toString() =>
      '[${severity.name.toUpperCase()}] ($ruleId) $path: $message';
}

class CheckReport {
  const CheckReport({required this.detectedPlatform, required this.findings});

  final HostPlatform detectedPlatform;
  final List<CheckFinding> findings;

  bool get hasFailures =>
      findings.any((CheckFinding f) => f.severity == Severity.fail);

  bool get hasErrors => hasFailures;

  bool get hasWarnings =>
      findings.any((CheckFinding f) => f.severity == Severity.warn);
}

class CacheDirectives {
  const CacheDirectives({
    this.noCache = false,
    this.noStore = false,
    this.mustRevalidate = false,
    this.proxyRevalidate = false,
    this.publicDirective = false,
    this.privateDirective = false,
    this.immutable = false,
    this.maxAge,
    this.sMaxAge,
    this.raw = const <String, String?>{},
  });

  factory CacheDirectives.parse(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const CacheDirectives();
    }
    final Map<String, String?> raw = <String, String?>{};
    for (final String part in _splitCommaOutsideQuotes(header)) {
      final String token = part.trim();
      if (token.isEmpty) continue;
      final int eqIdx = token.indexOf('=');
      if (eqIdx == -1) {
        raw[token.toLowerCase()] = null;
      } else {
        final String key = token.substring(0, eqIdx).trim().toLowerCase();
        String val = token.substring(eqIdx + 1).trim();
        if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
          val = val.substring(1, val.length - 1).replaceAll(r'\"', '"');
        }
        raw[key] = val;
      }
    }
    return CacheDirectives(
      noCache: raw.containsKey('no-cache'),
      noStore: raw.containsKey('no-store'),
      mustRevalidate: raw.containsKey('must-revalidate'),
      proxyRevalidate: raw.containsKey('proxy-revalidate'),
      publicDirective: raw.containsKey('public'),
      privateDirective: raw.containsKey('private'),
      immutable: raw.containsKey('immutable'),
      maxAge: int.tryParse(raw['max-age'] ?? ''),
      sMaxAge: int.tryParse(raw['s-maxage'] ?? ''),
      raw: raw,
    );
  }

  static List<String> _splitCommaOutsideQuotes(String input) {
    final List<String> parts = <String>[];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;
    bool escaped = false;
    for (int i = 0; i < input.length; i++) {
      final String ch = input[i];
      if (escaped) {
        current.write(ch);
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        current.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inQuotes = !inQuotes;
        current.write(ch);
        continue;
      }
      if (ch == ',' && !inQuotes) {
        parts.add(current.toString());
        current.clear();
        continue;
      }
      current.write(ch);
    }
    parts.add(current.toString());
    return parts;
  }

  final bool noCache;
  final bool noStore;
  final bool mustRevalidate;
  final bool proxyRevalidate;
  final bool publicDirective;
  final bool privateDirective;
  final bool immutable;
  final int? maxAge;
  final int? sMaxAge;
  final Map<String, String?> raw;

  bool get isRevalidatingOrZero =>
      !immutable &&
      (maxAge == null || maxAge! <= 0) &&
      (sMaxAge == null || sMaxAge! <= 0) &&
      (noCache || noStore || (maxAge != null && maxAge! <= 0));

  bool get isSharedEdgeRevalidatingOrZero {
    final int? effectiveTtl = sMaxAge ?? maxAge;
    return !immutable &&
        (maxAge == null ||
            maxAge! <= 0 ||
            (sMaxAge != null && sMaxAge! <= 0)) &&
        (sMaxAge == null || sMaxAge! <= 0) &&
        (noCache || noStore || (effectiveTtl != null && effectiveTtl <= 0));
  }
}

class _AssetTarget {
  const _AssetTarget({
    required this.label,
    required this.path,
    required this.isHashed,
    required this.isManifest,
  });

  final String label;
  final String path;
  final bool isHashed;
  final bool isManifest;
}

class UrlChecker {
  UrlChecker(
    this.targetUrl, {
    http.Client? client,
    this.platform = HostPlatform.auto,
    this.minCompressionBytes = 1024,
    this.requireWasm = true,
    this.verbose = false,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String targetUrl;
  final http.Client _client;
  final bool _ownsClient;
  final HostPlatform platform;
  final int minCompressionBytes;
  final bool requireWasm;
  final bool verbose;

  static final RegExp _hashedPattern = RegExp(r'\.[0-9a-f]{8,64}\.');

  static Future<void> checkUrl(
    String targetUrl, {
    bool verbose = false,
    HostPlatform platform = HostPlatform.auto,
    bool requireWasm = true,
  }) async {
    final UrlChecker checker = UrlChecker(
      targetUrl,
      verbose: verbose,
      platform: platform,
      requireWasm: requireWasm,
    );
    final int code = await checker.run();
    if (code != 0) {
      exit(code);
    }
  }

  Future<int> run() async {
    print('🔍 Inspecting deployed Flutter web app at: $targetUrl');
    final CheckReport report = await analyze();
    print('🌐 Detected platform: ${report.detectedPlatform.name}');
    for (final CheckFinding finding in report.findings) {
      final String icon = switch (finding.severity) {
        Severity.ok => '✅ [PASS]',
        Severity.warn => '⚠️ [WARN]',
        Severity.fail => '❌ [FAIL]',
      };
      print('$icon (${finding.ruleId}) ${finding.path}: ${finding.message}');
    }
    print('\n----------------------------------------');
    if (!report.hasFailures) {
      print('✨ All caching header checks PASSED!');
      return 0;
    } else {
      print('❌ Some caching header checks FAILED. See report above.');
      return 1;
    }
  }

  Future<CheckReport> analyze() async {
    try {
      final Uri baseUri = _normalizeBaseUri(targetUrl);
      final List<CheckFinding> findings = <CheckFinding>[];
      HostPlatform detectedPlatform = platform == HostPlatform.auto
          ? HostPlatform.generic
          : platform;

      detectedPlatform = await _checkIndexAndConditional(
        baseUri: baseUri,
        currentPlatform: detectedPlatform,
        findings: findings,
      );

      detectedPlatform = await _checkBootstrapAndAssets(
        baseUri: baseUri,
        currentPlatform: detectedPlatform,
        findings: findings,
      );

      detectedPlatform = await _probeMissingHashedAssets(
        baseUri: baseUri,
        currentPlatform: detectedPlatform,
        findings: findings,
      );

      return CheckReport(
        detectedPlatform: detectedPlatform,
        findings: findings,
      );
    } finally {
      if (_ownsClient) {
        _client.close();
      }
    }
  }

  static Uri _normalizeBaseUri(String rawUrl) {
    String normalized = rawUrl.trim();
    if (normalized.endsWith('/index.html')) {
      normalized = normalized.substring(
        0,
        normalized.length - 'index.html'.length,
      );
    } else if (!normalized.endsWith('/')) {
      normalized = '$normalized/';
    }
    return Uri.parse(normalized);
  }

  HostPlatform _detectPlatform(
    HostPlatform current,
    Map<String, String> headers,
  ) {
    if (platform != HostPlatform.auto) return platform;
    final String vary = (headers['vary'] ?? '').toLowerCase();
    if (vary.contains('x-fh-requested-host')) {
      return HostPlatform.firebase;
    }
    return current;
  }

  static bool _isHtmlSpaFallback(http.Response resp) {
    if (resp.statusCode != 200) return false;
    final String contentType = (resp.headers['content-type'] ?? '')
        .toLowerCase();
    return contentType.contains('text/html') ||
        contentType.contains('application/xhtml+xml');
  }

  static void _recordSpaFallbackFinding({
    required String path,
    required http.Response resp,
    required List<CheckFinding> findings,
  }) {
    final String contentType = (resp.headers['content-type'] ?? '')
        .toLowerCase();
    final String wasmDetail = path.endsWith('.wasm')
        ? ' Missing .wasm requests rewritten to HTML (0x3c21444f / <!DO) break WebAssembly.compileStreaming().'
        : '';
    findings.add(
      CheckFinding(
        ruleId: 'F-05',
        severity: Severity.fail,
        path: path,
        message:
            'SPA catch-all rewrite poisoning: $path returned HTTP ${resp.statusCode} ($contentType) with Cache-Control "${resp.headers['cache-control']}".$wasmDetail Exclude static asset paths from SPA rewrites.',
      ),
    );
  }

  Future<HostPlatform> _checkIndexAndConditional({
    required Uri baseUri,
    required HostPlatform currentPlatform,
    required List<CheckFinding> findings,
  }) async {
    Uri indexUri = baseUri.resolve('index.html');
    String indexLabel = 'index.html';
    http.Response indexResp = await _client.get(indexUri);
    if (indexResp.statusCode == 404) {
      indexUri = baseUri.resolve('./');
      indexLabel = '/';
      indexResp = await _client.get(indexUri);
    }
    final HostPlatform detected = _detectPlatform(
      currentPlatform,
      indexResp.headers,
    );

    _evaluateRootResponse(
      resp: indexResp,
      label: indexLabel,
      ruleId: 'F-01',
      detectedPlatform: detected,
      findings: findings,
    );

    if (indexResp.statusCode < 400) {
      await _checkConditionalRevalidation(
        indexUri: indexUri,
        indexLabel: indexLabel,
        indexResp: indexResp,
        findings: findings,
      );
    }
    return detected;
  }

  Future<void> _checkConditionalRevalidation({
    required Uri indexUri,
    required String indexLabel,
    required http.Response indexResp,
    required List<CheckFinding> findings,
  }) async {
    final String? etag = indexResp.headers['etag'];
    final String? lastModified = indexResp.headers['last-modified'];
    if (etag == null && lastModified == null) {
      findings.add(
        CheckFinding(
          ruleId: 'R-01',
          severity: Severity.warn,
          path: indexLabel,
          message: 'Missing ETag and Last-Modified validators; browsers cannot perform 304 conditional revalidation.',
        ),
      );
      return;
    }
    if (etag == null) return;

    final http.Response condResp = await _client.get(
      indexUri,
      headers: <String, String>{'If-None-Match': etag},
    );
    if (condResp.statusCode == 304) {
      findings.add(
        CheckFinding(
          ruleId: 'R-02',
          severity: Severity.ok,
          path: indexLabel,
          message:
              'Conditional GET with If-None-Match returned 304 Not Modified.',
        ),
      );
    } else if (condResp.statusCode == 200) {
      findings.add(
        CheckFinding(
          ruleId: 'R-02',
          severity: Severity.warn,
          path: indexLabel,
          message:
              'Conditional GET with If-None-Match: $etag returned 200 OK instead of 304 Not Modified.',
        ),
      );
    }
  }

  Future<HostPlatform> _checkBootstrapAndAssets({
    required Uri baseUri,
    required HostPlatform currentPlatform,
    required List<CheckFinding> findings,
  }) async {
    final Uri bootstrapUri = baseUri.resolve('flutter_bootstrap.js');
    final http.Response bootstrapResp = await _client.get(bootstrapUri);
    HostPlatform detected = _detectPlatform(
      currentPlatform,
      bootstrapResp.headers,
    );

    if (_isHtmlSpaFallback(bootstrapResp)) {
      _recordSpaFallbackFinding(
        path: 'flutter_bootstrap.js',
        resp: bootstrapResp,
        findings: findings,
      );
      detected = await _probeDefaultUnhashedManifest(
        baseUri: baseUri,
        currentPlatform: detected,
        findings: findings,
      );
      return detected;
    }

    _evaluateRootResponse(
      resp: bootstrapResp,
      label: 'flutter_bootstrap.js',
      ruleId: 'F-02',
      detectedPlatform: detected,
      findings: findings,
    );

    if (bootstrapResp.statusCode != 200) {
      return detected;
    }

    _evaluateWasmBuildTarget(bootstrapResp.body, findings);

    final List<_AssetTarget> targets = _extractTargets(bootstrapResp.body);
    final bool sawManifest = targets.any((_AssetTarget t) => t.isManifest);

    for (final _AssetTarget target in targets) {
      detected = await _probeAssetTarget(
        baseUri: baseUri,
        target: target,
        currentPlatform: detected,
        findings: findings,
      );
    }

    if (!sawManifest) {
      detected = await _probeDefaultUnhashedManifest(
        baseUri: baseUri,
        currentPlatform: detected,
        findings: findings,
      );
    }

    return detected;
  }

  static String _stripJsComments(String source) => source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  void _evaluateWasmBuildTarget(
    String bootstrapBody,
    List<CheckFinding> findings,
  ) {
    final String stripped = _stripJsComments(bootstrapBody);
    final RegExp wasmPathReg = RegExp(r'"mainWasmPath"\s*:\s*"([^"]*)"');
    final Match? wasmMatch = wasmPathReg.firstMatch(stripped);
    final String? mainWasmPath = wasmMatch?.group(1)?.trim();
    final bool hasNonEmptyWasmPath =
        mainWasmPath != null && mainWasmPath.isNotEmpty;
    final bool hasExplicitEmptyWasmPath =
        wasmMatch != null && !hasNonEmptyWasmPath;
    final bool hasDart2Wasm =
        hasNonEmptyWasmPath ||
        (!hasExplicitEmptyWasmPath &&
            RegExp(r'"compileTarget"\s*:\s*"dart2wasm"').hasMatch(stripped));

    if (hasDart2Wasm) {
      final String label = hasNonEmptyWasmPath ? mainWasmPath : 'dart2wasm';
      findings.add(
        CheckFinding(
          ruleId: 'W-01',
          severity: Severity.ok,
          path: 'flutter_bootstrap.js',
          message:
              'WebAssembly (dart2wasm) build target detected in flutter_bootstrap.js ($label).',
        ),
      );
    } else if (requireWasm) {
      findings.add(
        const CheckFinding(
          ruleId: 'W-01',
          severity: Severity.warn,
          path: 'flutter_bootstrap.js',
          message: 'No WebAssembly (dart2wasm) build target detected in flutter_bootstrap.js. Build with "flutter build web --wasm --web-content-hash" (or pass --no-wasm if intentionally JS-only).',
        ),
      );
    } else {
      findings.add(
        const CheckFinding(
          ruleId: 'W-01',
          severity: Severity.ok,
          path: 'flutter_bootstrap.js',
          message: 'JS-only build target in flutter_bootstrap.js allowed via --no-wasm.',
        ),
      );
    }
  }

  Future<HostPlatform> _probeAssetTarget({
    required Uri baseUri,
    required _AssetTarget target,
    required HostPlatform currentPlatform,
    required List<CheckFinding> findings,
  }) async {
    final http.Response resp = await _client.get(baseUri.resolve(target.path));
    final HostPlatform detected = _detectPlatform(
      currentPlatform,
      resp.headers,
    );

    if (resp.statusCode >= 400) {
      findings.add(
        CheckFinding(
          ruleId: target.isManifest ? 'F-04' : 'F-03',
          severity: Severity.fail,
          path: target.path,
          message: 'Returned HTTP ${resp.statusCode}.',
        ),
      );
      return detected;
    }

    if (_isHtmlSpaFallback(resp)) {
      _recordSpaFallbackFinding(
        path: target.path,
        resp: resp,
        findings: findings,
      );
      return detected;
    }

    if (target.isHashed) {
      _evaluateHashedAssetResponse(
        resp: resp,
        path: target.path,
        ruleId: target.isManifest ? 'F-04' : 'F-03',
        findings: findings,
      );
    } else {
      _evaluateUnhashedAssetResponse(
        resp: resp,
        path: target.path,
        label: target.label,
        ruleId: target.isManifest ? 'F-07' : 'F-03',
        findings: findings,
      );
    }

    if (!target.isManifest) {
      _evaluateMimeType(resp: resp, path: target.path, findings: findings);
      _evaluateCompression(resp: resp, path: target.path, findings: findings);
    }

    return detected;
  }

  static void _evaluateUnhashedAssetResponse({
    required http.Response resp,
    required String path,
    required String label,
    required String ruleId,
    required List<CheckFinding> findings,
  }) {
    final CacheDirectives cc = CacheDirectives.parse(
      resp.headers['cache-control'],
    );
    if (!cc.isRevalidatingOrZero || !_isSharedEdgeRootCacheOk(resp, cc)) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: path,
          message:
              'Unhashed $label ($path) is cached with "${resp.headers['cache-control']}" (CDN-Cache-Control: "${resp.headers['cdn-cache-control']}"). Must revalidate (max-age=0, must-revalidate).',
        ),
      );
    } else {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.ok,
          path: path,
          message: 'Unhashed $label properly revalidates.',
        ),
      );
    }
  }

  Future<HostPlatform> _probeDefaultUnhashedManifest({
    required Uri baseUri,
    required HostPlatform currentPlatform,
    required List<CheckFinding> findings,
  }) async {
    const String defaultManifestPath = 'assets/AssetManifest.bin.json';
    final http.Response manifestResp = await _client.get(
      baseUri.resolve(defaultManifestPath),
    );
    final HostPlatform detected = _detectPlatform(
      currentPlatform,
      manifestResp.headers,
    );
    if (manifestResp.statusCode != 200) {
      return detected;
    }
    if (_isHtmlSpaFallback(manifestResp)) {
      _recordSpaFallbackFinding(
        path: defaultManifestPath,
        resp: manifestResp,
        findings: findings,
      );
      return detected;
    }
    _evaluateUnhashedAssetResponse(
      resp: manifestResp,
      path: defaultManifestPath,
      label: 'manifest',
      ruleId: 'F-07',
      findings: findings,
    );
    return detected;
  }

  Future<HostPlatform> _probeMissingHashedAssets({
    required Uri baseUri,
    required HostPlatform currentPlatform,
    required List<CheckFinding> findings,
  }) async {
    const List<String> missingProbes = <String>[
      'main.dart.00000000.js',
      'main.dart.00000000.wasm',
      'assets/__cache_check_missing__.00000000.png',
    ];
    HostPlatform detected = currentPlatform;
    for (final String probePath in missingProbes) {
      final http.Response probeResp = await _client.get(
        baseUri.resolve(probePath),
      );
      detected = _detectPlatform(detected, probeResp.headers);
      _evaluateMissingProbeResponse(
        probePath: probePath,
        probeResp: probeResp,
        detectedPlatform: detected,
        findings: findings,
      );
    }
    return detected;
  }

  void _evaluateMissingProbeResponse({
    required String probePath,
    required http.Response probeResp,
    required HostPlatform detectedPlatform,
    required List<CheckFinding> findings,
  }) {
    final String contentType = (probeResp.headers['content-type'] ?? '')
        .toLowerCase();
    if (probeResp.statusCode == 200 ||
        (probeResp.statusCode != 404 && contentType.contains('text/html'))) {
      _recordSpaFallbackFinding(
        path: probePath,
        resp: probeResp,
        findings: findings,
      );
    } else if (probeResp.statusCode == 404) {
      findings.add(
        CheckFinding(
          ruleId: 'F-05',
          severity: Severity.ok,
          path: probePath,
          message: 'Missing hashed asset returned 404 Not Found.',
        ),
      );
      _evaluateNegativeCache404(
        resp: probeResp,
        path: probePath,
        detectedPlatform: detectedPlatform,
        findings: findings,
      );
    }
  }

  void _evaluateRootResponse({
    required http.Response resp,
    required String label,
    required String ruleId,
    required HostPlatform detectedPlatform,
    required List<CheckFinding> findings,
  }) {
    if (resp.statusCode >= 400) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: label,
          message: 'Returned HTTP ${resp.statusCode}.',
        ),
      );
      return;
    }

    final String? rawCc = resp.headers['cache-control'];
    if (rawCc == null || rawCc.trim().isEmpty) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: label,
          message: 'Missing Cache-Control header! Must be max-age=0, must-revalidate (or no-cache).',
        ),
      );
      return;
    }

    final CacheDirectives cc = CacheDirectives.parse(rawCc);
    if (!cc.isRevalidatingOrZero || !_isSharedEdgeRootCacheOk(resp, cc)) {
      final String fbPrescription = detectedPlatform == HostPlatform.firebase
          ? ' On Firebase Hosting, add a {"source": "**"} rule with "max-age=0, must-revalidate" to override the 3600s default while keeping Fastly edge 304s.'
          : '';
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: label,
          message:
              'Risky caching headers on root $label (Cache-Control: "$rawCc", CDN-Cache-Control: "${resp.headers['cdn-cache-control']}"). Both browser and shared CDN TTL must be <= 0.$fbPrescription',
        ),
      );
      return;
    }

    findings.add(
      CheckFinding(
        ruleId: ruleId,
        severity: Severity.ok,
        path: label,
        message: 'Revalidating ($rawCc).',
      ),
    );

    if (detectedPlatform == HostPlatform.firebase &&
        (cc.noCache || cc.noStore || cc.privateDirective)) {
      findings.add(
        CheckFinding(
          ruleId: 'F-12',
          severity: Severity.warn,
          path: label,
          message: 'Firebase Hosting Fastly VCL executes return(pass) when Cache-Control contains no-cache, no-store, or private, disabling edge 304 caching. Prefer "max-age=0, must-revalidate".',
        ),
      );
    }
  }

  static bool _isSharedEdgeRootCacheOk(http.Response resp, CacheDirectives cc) {
    final String? rawCdn =
        resp.headers['cdn-cache-control'] ?? resp.headers['surrogate-control'];
    if (rawCdn != null) {
      return CacheDirectives.parse(rawCdn).isSharedEdgeRevalidatingOrZero;
    }
    return cc.sMaxAge == null || cc.sMaxAge! <= 0;
  }

  void _evaluateHashedAssetResponse({
    required http.Response resp,
    required String path,
    required String ruleId,
    required List<CheckFinding> findings,
  }) {
    final String? rawCc = resp.headers['cache-control'];
    if (rawCc == null || rawCc.trim().isEmpty) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: path,
          message: 'Missing Cache-Control header on hashed asset! Expected "public, max-age=31536000, immutable".',
        ),
      );
      return;
    }

    final CacheDirectives cc = CacheDirectives.parse(rawCc);
    if (cc.noCache ||
        cc.noStore ||
        cc.privateDirective ||
        cc.maxAge == null ||
        cc.maxAge! < 31536000 ||
        (cc.sMaxAge != null && cc.sMaxAge! < 31536000)) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.fail,
          path: path,
          message:
              'Hashed asset $path has insufficient or private caching ("$rawCc"). Expected "public, max-age=31536000, immutable".',
        ),
      );
      return;
    }

    if (!cc.immutable) {
      findings.add(
        CheckFinding(
          ruleId: ruleId,
          severity: Severity.warn,
          path: path,
          message:
              'Hashed asset $path has max-age=${cc.maxAge} but is missing "immutable" ("$rawCc"). Add "immutable" to skip reload revalidation.',
        ),
      );
      return;
    }

    findings.add(
      CheckFinding(
        ruleId: ruleId,
        severity: Severity.ok,
        path: path,
        message: 'Aggressively cached ($rawCc).',
      ),
    );
  }

  void _evaluateMimeType({
    required http.Response resp,
    required String path,
    required List<CheckFinding> findings,
  }) {
    final String? rawContentType = resp.headers['content-type'];
    if (rawContentType == null || rawContentType.trim().isEmpty) return;
    final String mediaType = rawContentType
        .split(';')
        .first
        .trim()
        .toLowerCase();

    if (path.endsWith('.wasm')) {
      if (mediaType != 'application/wasm') {
        findings.add(
          CheckFinding(
            ruleId: 'M-01',
            severity: Severity.fail,
            path: path,
            message:
                'Invalid .wasm MIME type "$rawContentType". WebAssembly.instantiateStreaming requires "application/wasm".',
          ),
        );
      } else {
        findings.add(
          CheckFinding(
            ruleId: 'M-01',
            severity: Severity.ok,
            path: path,
            message: 'Valid .wasm MIME type ($mediaType).',
          ),
        );
      }
    } else if (path.endsWith('.mjs') || path.endsWith('.js')) {
      if (mediaType != 'text/javascript' &&
          mediaType != 'application/javascript') {
        findings.add(
          CheckFinding(
            ruleId: 'M-02',
            severity: Severity.fail,
            path: path,
            message:
                'Invalid JavaScript MIME type "$rawContentType" for $path. Must be "text/javascript" or "application/javascript".',
          ),
        );
      } else {
        findings.add(
          CheckFinding(
            ruleId: 'M-02',
            severity: Severity.ok,
            path: path,
            message: 'Valid JavaScript MIME type ($mediaType).',
          ),
        );
      }
    }
  }

  void _evaluateCompression({
    required http.Response resp,
    required String path,
    required List<CheckFinding> findings,
  }) {
    final int contentLength =
        int.tryParse(resp.headers['content-length'] ?? '') ??
        resp.bodyBytes.length;
    if (contentLength <= minCompressionBytes) return;

    final String encoding = (resp.headers['content-encoding'] ?? '')
        .toLowerCase();
    final bool isCompressed =
        encoding.contains('br') ||
        encoding.contains('gzip') ||
        encoding.contains('zstd');

    if (!isCompressed) {
      findings.add(
        CheckFinding(
          ruleId: 'C-01',
          severity: Severity.warn,
          path: path,
          message:
              'Payload ($contentLength bytes) is served without Content-Encoding (br/gzip).',
        ),
      );
      return;
    }

    final String vary = (resp.headers['vary'] ?? '').toLowerCase();
    if (!vary.contains('accept-encoding') && !vary.contains('*')) {
      findings.add(
        CheckFinding(
          ruleId: 'C-02',
          severity: Severity.warn,
          path: path,
          message:
              'Compressed payload ($encoding) is missing "Vary: Accept-Encoding". Shared caches may serve mismatched encodings.',
        ),
      );
    } else {
      findings.add(
        CheckFinding(
          ruleId: 'C-01',
          severity: Severity.ok,
          path: path,
          message: 'Compressed ($encoding) with Vary: Accept-Encoding.',
        ),
      );
    }
  }

  void _evaluateNegativeCache404({
    required http.Response resp,
    required String path,
    required HostPlatform detectedPlatform,
    required List<CheckFinding> findings,
  }) {
    final String? rawCc = resp.headers['cache-control'];
    final CacheDirectives cc = CacheDirectives.parse(rawCc);
    final int effectiveMaxAge = cc.sMaxAge ?? cc.maxAge ?? 0;

    if (!cc.noCache && !cc.noStore && (cc.immutable || effectiveMaxAge > 60)) {
      final String fbPrescription = detectedPlatform == HostPlatform.firebase
          ? ' On Firebase Hosting, add a {"source": "404.html"} rule with "max-age=0, must-revalidate".'
          : '';
      findings.add(
        CheckFinding(
          ruleId: 'F-06',
          severity: Severity.fail,
          path: path,
          message:
              '404 response for hashed path carries aggressive Cache-Control: "$rawCc" (TTL=${effectiveMaxAge}s).$fbPrescription',
        ),
      );
    } else if (!cc.noCache &&
        !cc.noStore &&
        effectiveMaxAge > 0 &&
        effectiveMaxAge <= 60) {
      findings.add(
        CheckFinding(
          ruleId: 'F-06',
          severity: Severity.warn,
          path: path,
          message: '404 response caches for ${effectiveMaxAge}s ("$rawCc").',
        ),
      );
    } else {
      findings.add(
        CheckFinding(
          ruleId: 'F-06',
          severity: Severity.ok,
          path: path,
          message: '404 response does not cache stale missing assets.',
        ),
      );
    }
  }

  static String _normalizeRelativePath(String rawPath) =>
      rawPath.replaceFirst(RegExp(r'^(\./|/)+'), '');

  static List<_AssetTarget> _extractTargets(String bootstrapBody) {
    final String stripped = _stripJsComments(bootstrapBody);
    final List<_AssetTarget> targets = <_AssetTarget>[];
    final Set<String> seenPaths = <String>{};
    final RegExp entryReg = RegExp(
      r'"(mainJsPath|mainWasmPath|jsSupportRuntimePath)"\s*:\s*"([^"]+)"',
    );
    for (final Match match in entryReg.allMatches(stripped)) {
      final String label = match.group(1)!;
      final String cleanPath = _normalizeRelativePath(match.group(2)!.trim());
      if (cleanPath.isEmpty || !seenPaths.add(cleanPath)) continue;
      targets.add(
        _AssetTarget(
          label: label,
          path: cleanPath,
          isHashed: _hashedPattern.hasMatch(cleanPath),
          isManifest: false,
        ),
      );
    }

    final RegExp manifestReg = RegExp(
      r'"(assetManifest|fontManifest)"\s*:\s*"([^"]+)"',
    );
    for (final Match match in manifestReg.allMatches(stripped)) {
      final String label = match.group(1)!;
      final String cleanPath = _normalizeRelativePath(match.group(2)!.trim());
      if (cleanPath.isEmpty) continue;
      final String resolvedPath = cleanPath.startsWith('assets/')
          ? cleanPath
          : 'assets/$cleanPath';
      if (!seenPaths.add(resolvedPath)) continue;
      targets.add(
        _AssetTarget(
          label: label,
          path: resolvedPath,
          isHashed: _hashedPattern.hasMatch(resolvedPath),
          isManifest: true,
        ),
      );
    }

    return targets;
  }
}
