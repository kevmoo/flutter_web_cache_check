import 'dart:convert';
import 'dart:io';

class FirebaseConfig {
  static const List<Map<String, Object>> defaultHeaders = <Map<String, Object>>[
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
      'source':
          '**/{index.html,flutter_bootstrap.js,flutter.js,flutter_service_worker.js,manifest.json,version.json}',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'no-cache, no-store, must-revalidate',
        },
      ],
    },
    <String, Object>{
      'source': '**/*.part.{js,wasm}',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'no-cache, no-store, must-revalidate',
        },
      ],
    },
    <String, Object>{
      'source': '**/_module*.wasm',
      'headers': <Map<String, String>>[
        <String, String>{
          'key': 'Cache-Control',
          'value': 'no-cache, no-store, must-revalidate',
        },
      ],
    },
  ];

  static void configure({
    required String filePath,
    required bool addPredeploy,
  }) {
    final File file = File(filePath);
    Map<String, Object?> config = <String, Object?>{};

    if (file.existsSync()) {
      final String content = file.readAsStringSync();
      if (content.trim().isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(content);
          if (decoded is Map<String, Object?>) {
            config = decoded;
          } else {
            throw FormatException('Expected a JSON object in $filePath.');
          }
        } on FormatException catch (e) {
          throw FormatException('Failed to parse $filePath: ${e.message}');
        }
      }
    } else {
      print('Creating new $filePath...');
    }

    // Handle hosting config (can be Map or List in firebase.json)
    Object? hostingObj = config['hosting'];
    if (hostingObj == null) {
      hostingObj = <String, Object?>{'public': 'build/web'};
      config['hosting'] = hostingObj;
    }

    if (hostingObj is Map<String, Object?>) {
      _configureHostingSection(hostingObj, addPredeploy);
    } else if (hostingObj is List<Object?>) {
      for (final Object? item in hostingObj) {
        if (item is Map<String, Object?>) {
          _configureHostingSection(item, addPredeploy);
        }
      }
    } else {
      throw FormatException('Unexpected type for "hosting" in $filePath.');
    }

    final String updatedJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(config);
    file.writeAsStringSync('$updatedJson\n');
    print('✅ Successfully updated $filePath with caching rules.');
  }

  static void _configureHostingSection(
    Map<String, Object?> hosting,
    bool addPredeploy,
  ) {
    // 1. Configure Headers
    final List<Object?> headers =
        (hosting['headers'] as List<Object?>?) ?? <Object?>[];

    for (final Map<String, Object> targetRule in defaultHeaders) {
      final String targetSource = targetRule['source']! as String;
      bool ruleExists = false;

      for (int i = 0; i < headers.length; i++) {
        final Object? existing = headers[i];
        if (existing is Map<String, Object?> &&
            existing['source'] == targetSource) {
          headers[i] = targetRule;
          ruleExists = true;
          break;
        }
      }

      if (!ruleExists) {
        headers.add(targetRule);
      }
    }
    hosting['headers'] = headers;

    // 2. Configure Predeploy
    if (addPredeploy) {
      const String targetCommand = 'flutter build web --web-content-hash';
      final Object? predeploy = hosting['predeploy'];

      if (predeploy == null) {
        hosting['predeploy'] = <String>[targetCommand];
        print('Added "$targetCommand" to hosting.predeploy.');
      } else if (predeploy is String) {
        if (predeploy.contains('flutter build web')) {
          if (!predeploy.contains('--web-content-hash')) {
            hosting['predeploy'] = '$predeploy --web-content-hash';
            print('Appended --web-content-hash to predeploy string.');
          }
        } else {
          hosting['predeploy'] = <String>[predeploy, targetCommand];
          print('Added "$targetCommand" to predeploy array.');
        }
      } else if (predeploy is List<Object?>) {
        bool foundFlutterBuild = false;
        for (int i = 0; i < predeploy.length; i++) {
          final Object? cmd = predeploy[i];
          if (cmd is String && cmd.contains('flutter build web')) {
            foundFlutterBuild = true;
            if (!cmd.contains('--web-content-hash')) {
              predeploy[i] = '$cmd --web-content-hash';
              print('Appended --web-content-hash to predeploy command.');
            }
          }
        }
        if (!foundFlutterBuild) {
          predeploy.add(targetCommand);
          print('Added "$targetCommand" to predeploy array.');
        }
      }
    }
  }
}
