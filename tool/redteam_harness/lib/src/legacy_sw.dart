import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'entrypoints.dart';

/// The offline-first service worker every Flutter web app shipped before
/// flutter/flutter#176834 (Oct 2025). Users who visited such an app still
/// have it installed; a new deploy has to migrate them off it.
final String legacyServiceWorkerTemplate = File(_resolveTemplatePath())
    .readAsStringSync();

String _resolveTemplatePath() {
  final resolved = Isolate.resolvePackageUriSync(
    Uri.parse('package:redteam_harness/src/legacy_sw_template.js'),
  );
  if (resolved == null) {
    throw StateError(
      'Cannot resolve package:redteam_harness/src/legacy_sw_template.js',
    );
  }
  return p.fromUri(resolved);
}

/// Rewrites `flutter_service_worker.js` in [build] with the legacy worker,
/// populated exactly as the old `WebServiceWorker` target did: md5 of every
/// output file (minus source maps), `/` aliased to `index.html`, and the app
/// shell as `CORE`.
void injectLegacyServiceWorker(Directory build) {
  final resources = <String, String>{};
  for (final file in build.listSync(recursive: true).whereType<File>()) {
    final rel = p.posix.joinAll(
      p.split(p.relative(file.path, from: build.path)),
    );
    if (rel.endsWith('.map') || rel == 'flutter_service_worker.js') continue;
    final hash = md5.convert(file.readAsBytesSync()).toString();
    resources[rel] = hash;
    if (rel.contains('%')) resources[Uri.encodeFull(rel)] = hash;
    if (rel == 'index.html') resources['/'] = hash;
  }
  final entry = resources.keys.firstWhere(
    (k) => isMainEntrypoint(k, jsOnly: true),
    orElse: () => 'main.dart.js',
  );
  final core = <String>[
    entry,
    'index.html',
    'flutter_bootstrap.js',
    'assets/AssetManifest.bin.json',
    'assets/FontManifest.json',
  ];
  final js = legacyServiceWorkerTemplate
      .replaceFirst(
        r'$$RESOURCES_MAP',
        const JsonEncoder.withIndent('  ').convert(resources),
      )
      .replaceFirst(r'$$CORE_LIST', json.encode(core));
  File(p.join(build.path, 'flutter_service_worker.js')).writeAsStringSync(js);
}
