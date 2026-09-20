import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:test/test.dart';

void main() {
  group('W-03: Wasm-Ready fb-config Predeploy Command (FirebaseConfig.applyUpdates)', () {
    test('defaults predeploy to "flutter build web --wasm --web-content-hash" when wasm is true', () {
      final Map<String, Object?> root = <String, Object?>{};
      FirebaseConfig.applyUpdates(root);

      final Map<String, Object?> hosting =
          root['hosting']! as Map<String, Object?>;
      expect(
        hosting['predeploy'],
        equals(<String>['flutter build web --wasm --web-content-hash']),
      );
    });

    test('sets predeploy to "flutter build web --web-content-hash" when wasm is false', () {
      final Map<String, Object?> root = <String, Object?>{};
      FirebaseConfig.applyUpdates(root, wasm: false);

      final Map<String, Object?> hosting =
          root['hosting']! as Map<String, Object?>;
      expect(
        hosting['predeploy'],
        equals(<String>['flutter build web --web-content-hash']),
      );
    });

    test('preserves --wasm and adds --web-content-hash when upgrading existing "flutter build web --wasm"', () {
      final Map<String, Object?> root = <String, Object?>{
        'hosting': <String, Object?>{
          'public': 'build/web',
          'predeploy': <String>['flutter build web --wasm'],
        },
      };
      FirebaseConfig.applyUpdates(root, wasm: false);

      final Map<String, Object?> hosting =
          root['hosting']! as Map<String, Object?>;
      expect(
        hosting['predeploy'],
        equals(<String>['flutter build web --wasm --web-content-hash']),
      );
    });

    test('adds both --wasm and --web-content-hash to existing "flutter build web --release" when wasm is true', () {
      final Map<String, Object?> root = <String, Object?>{
        'hosting': <String, Object?>{
          'public': 'build/web',
          'predeploy': <String>['flutter build web --release'],
        },
      };
      FirebaseConfig.applyUpdates(root, wasm: true);

      final Map<String, Object?> hosting =
          root['hosting']! as Map<String, Object?>;
      expect(
        hosting['predeploy'],
        equals(<String>[
          'flutter build web --release --wasm --web-content-hash',
        ]),
      );
    });

    test('upgrades compound shell commands in-place and replaces --no-wasm / --no-web-content-hash when wasm is true', () {
      final Map<String, Object?> root = <String, Object?>{
        'hosting': <String, Object?>{
          'public': 'build/web',
          'predeploy': <String>[
            'flutter pub get && flutter build web --release --no-wasm --no-web-content-hash && echo done',
          ],
        },
      };
      FirebaseConfig.applyUpdates(root, wasm: true);

      final Map<String, Object?> hosting =
          root['hosting']! as Map<String, Object?>;
      expect(
        hosting['predeploy'],
        equals(<String>[
          'flutter pub get && flutter build web --release --wasm --web-content-hash && echo done',
        ]),
      );
    });
  });
}
