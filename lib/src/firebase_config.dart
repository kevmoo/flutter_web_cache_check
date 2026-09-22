import 'dart:convert';
import 'dart:io';

class FirebaseConfig {
  static const List<Map<String, Object>> defaultHeaders = <Map<String, Object>>[
    <String, Object>{
      'source': '**',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'max-age=0, must-revalidate',
        },
      ],
    },
    <String, Object>{
      'source': '**/main.dart.*.{js,wasm,mjs}',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'public, max-age=31536000, immutable',
        },
      ],
    },
    <String, Object>{
      'source': 'assets/**',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'public, max-age=31536000, immutable',
        },
      ],
    },
    <String, Object>{
      'source': 'assets/@(AssetManifest.json|AssetManifest.bin|AssetManifest.bin.json|FontManifest.json|NOTICES)',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'max-age=0, must-revalidate',
        },
      ],
    },
    <String, Object>{
      'source': '404.html',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'max-age=0, must-revalidate',
        },
      ],
    },
  ];

  static const Set<String> _legacySources = <String>{
    '**/{index.html,flutter_bootstrap.js,flutter.js,flutter_service_worker.js,manifest.json,version.json}',
    '**/*.part.{js,wasm}',
    '**/_module*.wasm',
  };

  static const String guardedSpaRewriteSource =
      '!(/assets/**|/canvaskit/**|/icons/**|/main.dart.*)';

  static void configure({
    required String filePath,
    required bool addPredeploy,
    bool wasm = true,
  }) {
    final File file = File(filePath);
    final Map<String, Object?> config = _loadConfigFile(file, filePath);

    applyUpdates(
      config,
      filePath: filePath,
      addPredeploy: addPredeploy,
      wasm: wasm,
    );

    final String updatedJson = const JsonEncoder.withIndent('  ')
        .convert(config);
    file.writeAsStringSync('$updatedJson\n');
    print('✅ Successfully updated $filePath with caching rules.');
  }

  static void applyUpdates(
    Map<String, Object?> root, {
    String filePath = 'firebase.json',
    bool addPredeploy = true,
    bool wasm = true,
  }) {
    _applyHostingConfig(
      config: root,
      filePath: filePath,
      addPredeploy: addPredeploy,
      wasm: wasm,
    );
  }

  static Map<String, Object?> _loadConfigFile(File file, String filePath) {
    if (!file.existsSync()) {
      print('Creating new $filePath...');
      return <String, Object?>{};
    }
    final String content = file.readAsStringSync();
    if (content.trim().isEmpty) {
      return <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      throw FormatException('Expected a JSON object in $filePath.');
    } on FormatException catch (e) {
      throw FormatException('Failed to parse $filePath: ${e.message}');
    }
  }

  static void _applyHostingConfig({
    required Map<String, Object?> config,
    required String filePath,
    required bool addPredeploy,
    required bool wasm,
  }) {
    final Object hostingObj =
        config['hosting'] ??
        (config['hosting'] = <String, Object?>{'public': 'build/web'});

    if (hostingObj is Map<String, Object?>) {
      _configureHostingSection(hostingObj, addPredeploy, wasm: wasm);
      return;
    }
    if (hostingObj is List<Object?>) {
      for (final Map<String, Object?> item
          in hostingObj.whereType<Map<String, Object?>>()) {
        _configureHostingSection(item, addPredeploy, wasm: wasm);
      }
      return;
    }
    throw FormatException('Unexpected type for "hosting" in $filePath.');
  }

  static void _configureHostingSection(
    Map<String, Object?> hosting,
    bool addPredeploy, {
    required bool wasm,
  }) {
    _configureHeaders(hosting);
    _guardSpaRewrites(hosting);
    if (addPredeploy) {
      _configurePredeploy(hosting, wasm: wasm);
    }
  }

  static void _configureHeaders(Map<String, Object?> hosting) {
    final List<Object?> existingHeaders =
        (hosting['headers'] as List<Object?>?) ?? <Object?>[];
    final Set<String> managedSources = <String>{
      ..._legacySources,
      for (final Map<String, Object> rule in defaultHeaders)
        rule['source']! as String,
    };

    final List<Object?> customHeaders = <Object?>[
      for (final Object? item in existingHeaders)
        if (item is! Map<String, Object?> ||
            !managedSources.contains(item['source']))
          item,
    ];

    hosting['headers'] = <Object?>[...defaultHeaders, ...customHeaders];
  }

  static void _guardSpaRewrites(Map<String, Object?> hosting) {
    final Object? rewrites = hosting['rewrites'];
    if (rewrites is! List<Object?>) return;

    for (final Map<String, Object?> item
        in rewrites.whereType<Map<String, Object?>>()) {
      final Object? source = item['source'];
      final Object? destination = item['destination'];
      final bool isCatchAll =
          source == '**' ||
          source == '**/*' ||
          source == '!/@(assets|canvaskit|icons|main.dart.*)/**' ||
          source == '!/@(assets|canvaskit)/**';
      final bool isIndexDest =
          destination == '/index.html' || destination == 'index.html';
      if (isCatchAll && isIndexDest) {
        item['source'] = guardedSpaRewriteSource;
      }
    }
  }

  static void _configurePredeploy(
    Map<String, Object?> hosting, {
    required bool wasm,
  }) {
    final String targetCommand = wasm
        ? 'flutter build web --wasm --web-content-hash'
        : 'flutter build web --web-content-hash';
    final Object? predeploy = hosting['predeploy'];

    if (predeploy == null) {
      hosting['predeploy'] = <String>[targetCommand];
      print('Added "$targetCommand" to hosting.predeploy.');
    } else if (predeploy is String) {
      _configureStringPredeploy(hosting, predeploy, targetCommand, wasm: wasm);
    } else if (predeploy is List<Object?>) {
      _configureListPredeploy(predeploy, targetCommand, wasm: wasm);
    }
  }

  static String _upgradeFlutterBuildCmd(String cmd, {required bool wasm}) {
    final RegExp segmentReg = RegExp(r'flutter\s+build\s+web([^;&|]*)');
    return cmd.replaceFirstMapped(segmentReg, (Match m) {
      String segment = m.group(0)!;
      final bool hadTrailingSpace = segment.endsWith(' ');
      segment = segment.trimRight();
      if (wasm) {
        segment = segment.replaceAll(RegExp(r'\s+--no-wasm\b'), '');
      }
      segment = segment.replaceAll(RegExp(r'\s+--no-web-content-hash\b'), '');
      if (wasm && !RegExp(r'(^|\s)--wasm(\s|$)').hasMatch(segment)) {
        segment = '$segment --wasm';
      }
      if (!RegExp(r'(^|\s)--web-content-hash(\s|$)').hasMatch(segment)) {
        segment = '$segment --web-content-hash';
      }
      return hadTrailingSpace ? '$segment ' : segment;
    });
  }

  static void _configureStringPredeploy(
    Map<String, Object?> hosting,
    String predeploy,
    String targetCommand, {
    required bool wasm,
  }) {
    if (!predeploy.contains('flutter build web')) {
      hosting['predeploy'] = <String>[predeploy, targetCommand];
      print('Added "$targetCommand" to predeploy array.');
      return;
    }
    final String upgraded = _upgradeFlutterBuildCmd(predeploy, wasm: wasm);
    if (upgraded != predeploy) {
      hosting['predeploy'] = upgraded;
      print('Updated predeploy string to "$upgraded".');
    }
  }

  static void _configureListPredeploy(
    List<Object?> predeploy,
    String targetCommand, {
    required bool wasm,
  }) {
    bool foundFlutterBuild = false;
    for (int i = 0; i < predeploy.length; i++) {
      final Object? cmd = predeploy[i];
      if (cmd is String && cmd.contains('flutter build web')) {
        foundFlutterBuild = true;
        final String upgraded = _upgradeFlutterBuildCmd(cmd, wasm: wasm);
        if (upgraded != cmd) {
          predeploy[i] = upgraded;
          print('Updated predeploy command to "$upgraded".');
        }
      }
    }
    if (!foundFlutterBuild) {
      predeploy.add(targetCommand);
      print('Added "$targetCommand" to predeploy array.');
    }
  }
}
