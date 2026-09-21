import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// How a hosting provider sets `Cache-Control` for a Flutter web build.
enum HeaderPolicy {
  /// No `Cache-Control` at all, but `Last-Modified`/`ETag` present, so the
  /// browser applies heuristic freshness (10% of the resource's age). This is
  /// what a bare nginx/Apache/`python -m http.server` deploy looks like.
  heuristic,

  /// Firebase Hosting with no `headers` rules: everything `max-age=3600`.
  firebaseDefaults,

  /// Firebase Hosting with the rules `flutter_web_cache_check fb-config`
  /// writes: hashed entrypoints immutable, bootloaders/manifests no-cache,
  /// everything else the Firebase default `max-age=3600`.
  firebaseRules,

  /// The fully correct policy for a content-hashed build: hashed files
  /// immutable, *every* unhashed file `no-cache`.
  strict,

  /// Misconfiguration: everything `max-age=31536000, immutable`.
  cacheEverything,

  /// Misconfiguration: `index.html` revalidates but `flutter_bootstrap.js`
  /// (and everything else) is cached for a year.
  bootstrapCached,

  /// Misconfiguration: `**/*.{js,wasm,mjs,png}` set to immutable with unguarded
  /// SPA rewrite (`**` -> `/index.html`).
  naiveImmutableGlobs,

  /// Misconfiguration: valid file headers, but 404 responses for hashed paths
  /// are cached with `public, max-age=31536000, immutable` (F-06).
  immutable404Trap;

  static const HeaderPolicy naiveLongCache = HeaderPolicy.cacheEverything;
  static const HeaderPolicy firebaseDefault = HeaderPolicy.firebaseDefaults;
  static const HeaderPolicy spaFallbackTrap = HeaderPolicy.naiveImmutableGlobs;

  static List<Map<String, Object>> get firebaseRulesTable =>
      FirebaseConfig.defaultHeaders;
}

final RegExp _hashedEntrypoint = RegExp(
  r'^main\.dart(_module\d+)?\.[a-f0-9]{8}\.(js|wasm|mjs)$',
);
final RegExp _hashedAsset = RegExp(r'\.[a-f0-9]{8}(\.[A-Za-z0-9]+)?$');

const String _immutableDirective = 'public, max-age=31536000, immutable';
const String _noCacheDirective = 'max-age=0, must-revalidate, no-cache';

/// `Cache-Control` for [relPath] under [policy]; null means omit the header.
String? cacheControlFor(HeaderPolicy policy, String relPath) {
  final base = p.posix.basename(relPath);
  final isHashedEntry = _hashedEntrypoint.hasMatch(base);
  final isHashedAsset =
      relPath.startsWith('assets/') && _hashedAsset.hasMatch(base);
  switch (policy) {
    case HeaderPolicy.heuristic:
      return null;
    case HeaderPolicy.firebaseDefaults:
      return 'max-age=3600';
    case HeaderPolicy.firebaseRules:
    case HeaderPolicy.immutable404Trap:
      return _firebaseRulesCacheControl(relPath);
    case HeaderPolicy.strict:
      return (isHashedEntry || isHashedAsset)
          ? _immutableDirective
          : _noCacheDirective;
    case HeaderPolicy.cacheEverything:
      return _immutableDirective;
    case HeaderPolicy.bootstrapCached:
      return base == 'index.html' ? _noCacheDirective : _immutableDirective;
    case HeaderPolicy.naiveImmutableGlobs:
      return _isNaiveImmutableAsset(relPath)
          ? _immutableDirective
          : 'max-age=3600';
  }
}

String _firebaseRulesCacheControl(String relPath) {
  String result = 'max-age=3600';
  for (final Map<String, Object> rule in HostingServer.firebaseRules) {
    final String source = rule['source']! as String;
    if (_matchesFirebaseRuleSource(source, relPath)) {
      final List<Map<String, String>> headers =
          rule['headers']! as List<Map<String, String>>;
      for (final Map<String, String> header in headers) {
        if (header['key']?.toLowerCase() == 'cache-control') {
          result = header['value']!;
        }
      }
    }
  }
  return result;
}

final RegExp _firebaseMainBundleRule = RegExp(
  r'^main\.dart(_module\d+)?\..+\.(js|wasm|mjs)$',
);

bool _matchesFirebaseRuleSource(String source, String relPath) {
  if (source == '**') return true;
  if (source == '**/main.dart.*.{js,wasm,mjs}') {
    return _firebaseMainBundleRule.hasMatch(p.posix.basename(relPath));
  }
  if (source == 'assets/**') {
    return relPath.startsWith('assets/');
  }
  if (source.startsWith('assets/@(') && source.endsWith(')')) {
    final String inner = source.substring(
      'assets/@('.length,
      source.length - 1,
    );
    final Set<String> names = inner.split('|').toSet();
    return relPath.startsWith('assets/') &&
        names.contains(relPath.substring('assets/'.length));
  }
  return relPath == source;
}

bool _isNaiveImmutableAsset(String relPath) =>
    relPath.endsWith('.js') ||
    relPath.endsWith('.wasm') ||
    relPath.endsWith('.mjs') ||
    relPath.endsWith('.png');

/// One request the simulated host answered.
class ServedRequest {
  ServedRequest(
    this.path,
    this.status,
    this.cacheControl, {
    required this.conditional,
  });

  final String path;
  final int status;
  final String? cacheControl;
  final bool conditional;

  Map<String, Object?> toJson() => {
    'path': path,
    'status': status,
    'cacheControl': cacheControl,
    'conditional': conditional,
  };
}

/// A local stand-in for a static host / CDN with controllable headers,
/// deploy atomicity, and edge-cached `index.html`.
class HostingServer {
  HostingServer({
    required this.policy,
    this.cdnIndexTtl = Duration.zero,
    this.spaRewrite = false,
    this.spaRewriteAll = false,
    this.basePath = '/',
    this.negativeCacheTtl = Duration.zero,
    this.useFirebaseEmulator = false,
    this.useFirebaseLive = false,
    this.firebaseProject,
    this.firebaseSite,
  }) {
    if (useFirebaseLive &&
        (firebaseProject == null ||
            firebaseProject!.isEmpty ||
            firebaseSite == null ||
            firebaseSite!.isEmpty)) {
      throw ArgumentError(
        'useFirebaseLive requires non-empty firebaseProject and firebaseSite',
      );
    }
  }

  static int _liveChannelCounter = 0;

  static List<Map<String, Object>> get firebaseRules =>
      FirebaseConfig.defaultHeaders;

  HeaderPolicy policy;

  /// Whether to proxy `firebaseRules` requests through a live
  /// `firebase emulators:start --only hosting` subprocess.
  final bool useFirebaseEmulator;

  /// Whether to deploy `firebaseRules` builds to an ephemeral Firebase Hosting
  /// preview channel (`firebase hosting:channel:deploy`).
  final bool useFirebaseLive;
  final String? firebaseProject;
  final String? firebaseSite;

  /// `Cache-Control` applied to 404 responses. Zero = `no-cache`
  /// (Firebase Hosting, S3). Some CDNs apply the path's header rules to 404s
  /// too, which caches a missing hashed file for a year.
  final Duration negativeCacheTtl;

  /// URL prefix the site is mounted under (matches `--base-href`).
  final String basePath;

  /// Emulates a CDN edge that keeps serving the previous `index.html` for this
  /// long after a deploy, regardless of origin headers.
  final Duration cdnIndexTtl;

  /// Rewrite unknown paths without dots to `index.html` (guarded SPA mode).
  final bool spaRewrite;

  /// Rewrite ALL unknown paths (including missing `.js`/`.png`) to `index.html`
  /// (`"source": "**", "destination": "/index.html"`).
  bool spaRewriteAll;

  late final Directory root = Directory.systemTemp.createTempSync(
    'redteam_host_',
  );
  Directory get liveDir => Directory(p.join(root.path, 'live'));

  HttpServer? _server;
  Process? _emulatorProcess;
  int? _emulatorPort;
  http.Client? _proxyClient;
  late final String _liveChannelId =
      'redteam-$pid-${DateTime.now().millisecondsSinceEpoch}-${_liveChannelCounter++}';
  Uri? _liveChannelUri;
  bool _liveChannelDeployed = false;
  final List<ServedRequest> log = <ServedRequest>[];
  List<int>? _frozenIndex;
  DateTime? _frozenUntil;

  bool get _shouldUseFirebaseLive =>
      useFirebaseLive &&
      policy == HeaderPolicy.firebaseRules &&
      cdnIndexTtl == Duration.zero &&
      !spaRewriteAll;

  Uri get baseUri => (_shouldUseFirebaseLive && _liveChannelUri != null)
      ? _liveChannelUri!.resolve(
          basePath.startsWith('/') ? basePath.substring(1) : basePath,
        )
      : Uri.parse('http://127.0.0.1:${_server!.port}$basePath');

  Future<void> start() async {
    liveDir.createSync(recursive: true);
    _server = await shelf_io.serve(_handle, InternetAddress.loopbackIPv4, 0);
    if (useFirebaseEmulator) {
      try {
        await _startFirebaseEmulator();
      } catch (_) {
        await stop();
        rethrow;
      }
    }
  }

  Future<void> _startFirebaseEmulator() async {
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int emulatorPort = socket.port;
    await socket.close();
    _emulatorPort = emulatorPort;
    _proxyClient = IOClient(HttpClient()..autoUncompress = false);

    final Map<String, Object?> config = <String, Object?>{
      'hosting': <String, Object?>{
        'public': 'live',
        if (spaRewrite)
          'rewrites': <Object?>[
            <String, Object?>{'source': '**', 'destination': '/index.html'},
          ],
      },
    };
    FirebaseConfig.applyUpdates(config, addPredeploy: false, wasm: true);
    config['emulators'] = <String, Object?>{
      'hosting': <String, Object?>{'host': '127.0.0.1', 'port': emulatorPort},
    };
    File(p.join(root.path, 'firebase.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );

    _emulatorProcess = await Process.start('firebase', <String>[
      'emulators:start',
      '--only',
      'hosting',
      '--project',
      'demo-redteam',
    ], workingDirectory: root.path);
    _emulatorProcess!.stdout.drain<void>().ignore();
    _emulatorProcess!.stderr.drain<void>().ignore();

    await _waitForEmulatorReady(emulatorPort);
  }

  Future<void> _waitForEmulatorReady(int emulatorPort) async {
    final Uri probeUri = Uri.parse('http://127.0.0.1:$emulatorPort/');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final http.Response resp = await _proxyClient!
            .get(probeUri)
            .timeout(const Duration(milliseconds: 500));
        if (resp.statusCode > 0) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'Timed out waiting for firebase emulators:start on port $emulatorPort',
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _proxyClient?.close();
    _proxyClient = null;
    await _stopFirebaseEmulator();
    await _deleteFirebaseLiveChannel();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<void> _stopFirebaseEmulator() async {
    final Process? proc = _emulatorProcess;
    _emulatorProcess = null;
    if (proc == null) return;
    proc.kill(ProcessSignal.sigterm);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  Future<void> _deployFirebaseLiveChannel(Directory build) async {
    if (basePath != '/') {
      final String sub = basePath.replaceAll(RegExp(r'^/+|/+$'), '');
      if (sub.isNotEmpty) {
        await _copyTree(build, Directory(p.join(liveDir.path, sub)));
      }
    }
    final Map<String, Object?> config = <String, Object?>{
      'hosting': <String, Object?>{
        'site': firebaseSite,
        'public': 'live',
        if (spaRewrite)
          'rewrites': <Object?>[
            <String, Object?>{'source': '**', 'destination': '/index.html'},
          ],
      },
    };
    FirebaseConfig.applyUpdates(config, addPredeploy: false, wasm: true);
    File(p.join(root.path, 'firebase.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );

    final ProcessResult res = await Process.run('firebase', <String>[
      'hosting:channel:deploy',
      _liveChannelId,
      '--project',
      firebaseProject!,
      '--expires',
      '1h',
      '--no-authorized-domains',
      '--json',
    ], workingDirectory: root.path);
    if (res.exitCode != 0) {
      throw StateError(
        'firebase hosting:channel:deploy failed (${res.exitCode}): '
        '${res.stdout}\n${res.stderr}',
      );
    }
    final Map<String, Object?> decoded =
        jsonDecode(res.stdout as String) as Map<String, Object?>;
    final Map<String, Object?> resultMap =
        decoded['result'] as Map<String, Object?>;
    final Map<String, Object?> siteInfo =
        (resultMap[firebaseSite!] ?? resultMap.values.first)
            as Map<String, Object?>;
    final String rawUrl = siteInfo['url'] as String;
    _liveChannelUri = Uri.parse(rawUrl.endsWith('/') ? rawUrl : '$rawUrl/');
    _liveChannelDeployed = true;
    await _waitForLiveIndex(build);
  }

  Future<void> _waitForLiveIndex(Directory build) async {
    final File indexFile = File(p.join(build.path, 'index.html'));
    if (!indexFile.existsSync()) return;
    final String expectedIndex = indexFile.readAsStringSync();
    final Uri indexUri = baseUri.resolve('index.html');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final http.Response r = await http
            .get(
              indexUri,
              headers: <String, String>{'Cache-Control': 'no-cache'},
            )
            .timeout(const Duration(seconds: 3));
        if (r.statusCode == 200 && r.body == expectedIndex) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _deleteFirebaseLiveChannel() async {
    if (!_liveChannelDeployed) return;
    _liveChannelDeployed = false;
    try {
      await Process.run('firebase', <String>[
        'hosting:channel:delete',
        _liveChannelId,
        '--project',
        firebaseProject!,
        '--site',
        firebaseSite!,
        '--force',
        '--json',
      ], workingDirectory: root.path);
    } catch (_) {}
  }

  // --- deploy strategies -------------------------------------------------

  void _freezeIndexIfCdn() {
    if (cdnIndexTtl == Duration.zero) return;
    final index = File(p.join(liveDir.path, 'index.html'));
    if (index.existsSync()) {
      _frozenIndex = index.readAsBytesSync();
      _frozenUntil = DateTime.now().add(cdnIndexTtl);
    }
  }

  /// Replace the whole site in one step (old files gone). What Firebase
  /// Hosting and most "upload then flip" hosts do.
  Future<void> deployAtomic(Directory build) async {
    _freezeIndexIfCdn();
    final staging = Directory(p.join(root.path, 'staging'));
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    await _copyTree(build, staging);
    final old = Directory(p.join(root.path, 'old'));
    if (old.existsSync()) old.deleteSync(recursive: true);
    if (liveDir.existsSync()) liveDir.renameSync(old.path);
    staging.renameSync(liveDir.path);
    if (old.existsSync()) old.deleteSync(recursive: true);
    if (_shouldUseFirebaseLive) {
      await _deployFirebaseLiveChannel(build);
    }
  }

  /// Copy the new build over the existing site without deleting anything
  /// (rsync without `--delete`, `gsutil cp`, S3 sync): old hashed files stay.
  Future<void> deployOverlay(Directory build) async {
    _freezeIndexIfCdn();
    await _copyTree(build, liveDir);
  }

  /// Copy only the files [include] accepts (in the order the source lists
  /// them): simulates a deploy caught mid-way, or a host that uploads
  /// `index.html` before the files it references.
  Future<void> deployPartial(
    Directory build,
    bool Function(String relPath) include,
  ) async {
    _freezeIndexIfCdn();
    await _copyTree(build, liveDir, include: include);
  }

  /// Delete live files matching [predicate] (e.g. purge old hashed files).
  void deleteWhere(bool Function(String relPath) predicate) {
    for (final entity
        in liveDir.listSync(recursive: true).whereType<File>().toList()) {
      final rel = p.relative(entity.path, from: liveDir.path);
      if (predicate(rel)) entity.deleteSync();
    }
  }

  static Future<void> _copyTree(
    Directory from,
    Directory to, {
    bool Function(String relPath)? include,
  }) async {
    for (final entity in from.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: from.path);
      if (include != null && !include(rel)) continue;
      final dest = File(p.join(to.path, rel));
      dest.parent.createSync(recursive: true);
      entity.copySync(dest.path);
    }
  }

  /// Relative paths of everything currently live.
  List<String> liveFiles() =>
      liveDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: liveDir.path))
          .toList()
        ..sort();

  // --- serving --------------------------------------------------------------

  bool get _shouldProxyToFirebaseEmulator =>
      useFirebaseEmulator &&
      _emulatorPort != null &&
      policy == HeaderPolicy.firebaseRules &&
      cdnIndexTtl == Duration.zero &&
      !spaRewriteAll;

  Future<Response> _handle(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405);
    }
    final rawRel = Uri.decodeComponent(request.url.path);
    final strippedRel = _stripBasePath(rawRel);
    if (strippedRel == null) {
      log.add(ServedRequest(rawRel, 404, null, conditional: false));
      return Response.notFound('outside base path: $rawRel');
    }
    if (_shouldProxyToFirebaseEmulator) {
      return _proxyToFirebaseEmulator(request, strippedRel);
    }
    final originalRel = strippedRel;
    final resolved = _resolvePayload(originalRel);
    final rel = resolved.resolvedRel;
    final bytes = resolved.bytes;

    // Header matching uses the pre-rewrite request path (originalRel).
    final cacheControl = cacheControlFor(policy, originalRel);
    if (bytes == null) {
      final notFoundCc = _notFoundCacheControl(cacheControl);
      log.add(ServedRequest(originalRel, 404, notFoundCc, conditional: false));
      return Response.notFound(
        'not found: $originalRel',
        headers: {'cache-control': notFoundCc},
      );
    }

    final etag = '"${md5.convert(bytes)}"';
    final ifNoneMatch = request.headers['if-none-match'];
    final acceptsGzip = (request.headers['accept-encoding'] ?? '')
        .toLowerCase()
        .contains('gzip');
    final responseBody = acceptsGzip ? gzip.encode(bytes) : bytes;
    final headers = <String, String>{
      'etag': etag,
      'last-modified': HttpDate.format(
        DateTime.now().toUtc().subtract(const Duration(days: 30)),
      ),
      'content-type': _contentType(rel),
      'vary': 'Accept-Encoding',
      if (acceptsGzip) 'content-encoding': 'gzip',
      'cache-control': ?cacheControl,
    };
    if (ifNoneMatch != null && ifNoneMatch == etag) {
      log.add(ServedRequest(rel, 304, cacheControl, conditional: true));
      return Response(304, headers: headers);
    }
    log.add(
      ServedRequest(rel, 200, cacheControl, conditional: ifNoneMatch != null),
    );
    return Response.ok(
      request.method == 'HEAD' ? null : responseBody,
      headers: headers,
    );
  }

  Future<Response> _proxyToFirebaseEmulator(Request request, String rel) async {
    final String encodedRel = _stripBasePath(request.url.path) ?? rel;
    final String subPath = basePath == '/' ? request.url.path : encodedRel;
    final Uri targetUri = Uri.parse('http://127.0.0.1:$_emulatorPort/$subPath');
    final http.Request emuReq = http.Request(request.method, targetUri);
    final String? ifNoneMatch = request.headers['if-none-match'];
    final String? acceptEncoding = request.headers['accept-encoding'];
    if (ifNoneMatch != null) emuReq.headers['if-none-match'] = ifNoneMatch;
    if (acceptEncoding != null) {
      emuReq.headers['accept-encoding'] = acceptEncoding;
    }
    final http.StreamedResponse streamed = await _proxyClient!.send(emuReq);
    final http.Response emuResp = await http.Response.fromStream(streamed);
    log.add(
      ServedRequest(
        rel,
        emuResp.statusCode,
        emuResp.headers['cache-control'],
        conditional: ifNoneMatch != null,
      ),
    );
    final Map<String, String> outHeaders =
        Map<String, String>.of(emuResp.headers)
          ..remove('transfer-encoding')
          ..remove('content-length');
    return Response(
      emuResp.statusCode,
      body: request.method == 'HEAD' || emuResp.statusCode == 304
          ? null
          : emuResp.bodyBytes,
      headers: outHeaders,
    );
  }

  String? _stripBasePath(String rawRel) {
    var rel = rawRel;
    final prefix = basePath.substring(1);
    if (prefix.isNotEmpty) {
      if (!rel.startsWith(prefix)) return null;
      rel = rel.substring(prefix.length);
    }
    if (rel.isEmpty || rel.endsWith('/')) {
      rel = '${rel}index.html';
    }
    return rel;
  }

  ({String resolvedRel, List<int>? bytes}) _resolvePayload(String rel) {
    if (rel == 'index.html' &&
        _frozenIndex != null &&
        DateTime.now().isBefore(_frozenUntil!)) {
      return (resolvedRel: rel, bytes: _frozenIndex);
    }
    final file = File(p.join(liveDir.path, rel));
    if (file.existsSync()) {
      return (resolvedRel: rel, bytes: file.readAsBytesSync());
    }
    final shouldSpaFallback =
        spaRewriteAll ||
        policy == HeaderPolicy.naiveImmutableGlobs ||
        (spaRewrite && !rel.contains('.'));
    if (shouldSpaFallback) {
      final index = File(p.join(liveDir.path, 'index.html'));
      return (
        resolvedRel: 'index.html',
        bytes: index.existsSync() ? index.readAsBytesSync() : null,
      );
    }
    return (resolvedRel: rel, bytes: null);
  }

  String _notFoundCacheControl(String? pathCacheControl) {
    if (negativeCacheTtl != Duration.zero) {
      return 'max-age=${negativeCacheTtl.inSeconds}';
    }
    return switch (policy) {
      HeaderPolicy.firebaseRules => cacheControlFor(policy, '404.html')!,
      HeaderPolicy.firebaseDefaults => pathCacheControl ?? 'max-age=3600',
      HeaderPolicy.immutable404Trap => _immutableDirective,
      _ => 'no-cache',
    };
  }

  static String _contentType(String rel) {
    switch (p.extension(rel)) {
      case '.html':
        return 'text/html; charset=utf-8';
      case '.js':
      case '.mjs':
        return 'text/javascript';
      case '.wasm':
        return 'application/wasm';
      case '.json':
        return 'application/json';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      case '.ttf':
        return 'font/ttf';
      case '.otf':
        return 'font/otf';
      case '.txt':
      case '.frag':
        return 'text/plain; charset=utf-8';
      default:
        return 'application/octet-stream';
    }
  }

  Map<String, Object?> snapshot() => {
    'policy': policy.name,
    'cdnIndexTtlSeconds': cdnIndexTtl.inSeconds,
    'served': log.map((r) => r.toJson()).toList(),
  };

  String describe() => json.encode(snapshot());
}
