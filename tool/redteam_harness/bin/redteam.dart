import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:redteam_harness/redteam_harness.dart';

ArgParser _buildParser(List<String> defaultSdk) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addFlag('list', negatable: false, help: 'List scenarios and exit.')
  ..addMultiOption('sdk', defaultsTo: defaultSdk, help: 'master and/or phase3.')
  ..addMultiOption(
    'scenario',
    abbr: 's',
    help: 'Scenario ids (prefix match). Default: all.',
  )
  ..addMultiOption('only', help: 'Scenario ids to run (alias for --scenario).')
  ..addOption(
    'out',
    abbr: 'o',
    help: 'Results directory (default: results/<timestamp>).',
  )
  ..addOption(
    'work',
    help: 'Scratch directory for builds/profiles (default: /tmp).',
  )
  ..addOption(
    'backend',
    allowed: <String>['sim', 'firebase-emulator', 'firebase-live'],
    defaultsTo: 'sim',
    help: 'Hosting backend (sim, firebase-emulator, or firebase-live).',
  )
  ..addOption(
    'firebase-project',
    defaultsTo: Platform.environment['REDTEAM_FIREBASE_PROJECT'],
    help: 'Firebase project ID (required for --backend=firebase-live).',
  )
  ..addOption(
    'firebase-site',
    defaultsTo: Platform.environment['REDTEAM_FIREBASE_SITE'],
    help: 'Firebase Hosting site ID (required for --backend=firebase-live).',
  )
  ..addFlag('headed', negatable: false, help: 'Run Chromium with a window.');

List<Scenario> _selectScenarios(List<Scenario> scenarios, List<String> wanted) {
  if (wanted.isEmpty) return scenarios;
  return scenarios
      .where((s) => wanted.any((w) => s.id == w || s.id.startsWith('$w.')))
      .toList();
}

void _printScenarioOutcome(ScenarioResult result, Duration elapsed) {
  stdout.writeln(
    '${result.verdict.name.toUpperCase()} (${elapsed.inSeconds}s)',
  );
  for (final step in result.steps) {
    for (final c in step.checks.where((c) => !c.passed)) {
      final suffix = c.detail.isEmpty ? '' : ' — ${c.detail}';
      stdout.writeln('     ✗ ${step.title}: ${c.name}$suffix');
    }
  }
  if (result.error != null) {
    stdout.writeln('     ! ${result.error!.split('\n').first}');
  }
}

Future<void> main(List<String> argv) async {
  final defaultSdk = Platform.environment.containsKey('REDTEAM_FLUTTER_PHASE3')
      ? <String>['phase3']
      : <String>['master'];
  final parser = _buildParser(defaultSdk);
  final args = parser.parse(argv);
  if (args['help'] as bool) {
    stdout.writeln(
      'Usage: dart run bin/redteam.dart [options]\n${parser.usage}',
    );
    return;
  }

  final scenarios = allScenarios();
  if (args['list'] as bool) {
    for (final s in scenarios) {
      stdout.writeln(
        '${s.id.padRight(24)} ${s.title}\n${' ' * 25}${s.description}',
      );
    }
    return;
  }

  final String backend = args['backend'] as String;
  final String? firebaseProject = args['firebase-project'] as String?;
  final String? firebaseSite = args['firebase-site'] as String?;
  if (backend == 'firebase-live' &&
      (firebaseProject == null ||
          firebaseProject.isEmpty ||
          firebaseSite == null ||
          firebaseSite.isEmpty)) {
    stderr.writeln(
      'Error: --backend=firebase-live requires both --firebase-project and '
      '--firebase-site.',
    );
    exit(64);
  }

  final wanted = <String>[
    ...(args['scenario'] as List<String>),
    ...(args['only'] as List<String>),
  ];
  final selected = _selectScenarios(scenarios, wanted);
  if (selected.isEmpty) {
    stderr.writeln('No scenario matches $wanted. Use --list.');
    exit(64);
  }

  final toolRoot = _findToolRoot();
  final workDir = Directory(
    args['work'] as String? ??
        p.join(Directory.systemTemp.path, 'redteam_work'),
  );
  final outDir = Directory(
    args['out'] as String? ??
        p.join(
          toolRoot.path,
          'results',
          DateTime.now()
              .toUtc()
              .toIso8601String()
              .replaceAll(':', '-')
              .split('.')
              .first,
        ),
  );
  final builder = Builder(
    sampleAppDir: Directory(p.join(toolRoot.path, 'sample_app')),
    workDir: workDir,
  );

  final results = <ScenarioResult>[];
  final sdkVersions = <String, String>{};
  for (final label in args['sdk'] as List<String>) {
    await _runSdkScenarios(
      label: label,
      selected: selected,
      builder: builder,
      workDir: workDir,
      outDir: outDir,
      headless: !(args['headed'] as bool),
      useFirebaseEmulator: backend == 'firebase-emulator',
      useFirebaseLive: backend == 'firebase-live',
      firebaseProject: firebaseProject,
      firebaseSite: firebaseSite,
      results: results,
      sdkVersions: sdkVersions,
    );
  }
  stdout.writeln('\nResults: ${outDir.path}/summary.md');
  if (results.any((r) => r.verdict != Verdict.pass)) {
    exitCode = 1;
  }
}

Future<void> _runSdkScenarios({
  required String label,
  required List<Scenario> selected,
  required Builder builder,
  required Directory workDir,
  required Directory outDir,
  required bool headless,
  required bool useFirebaseEmulator,
  required bool useFirebaseLive,
  required String? firebaseProject,
  required String? firebaseSite,
  required List<ScenarioResult> results,
  required Map<String, String> sdkVersions,
}) async {
  final sdk = FlutterSdk.byLabel(label);
  if (!File(sdk.flutterBin).existsSync()) {
    stderr.writeln('SDK $label not found at ${sdk.root.path}');
    exit(1);
  }
  sdkVersions[label] = await sdk.version();
  stdout.writeln('== SDK $label: ${sdkVersions[label]}');
  final ctx = ScenarioContext(
    sdk: sdk,
    builder: builder,
    workDir: workDir,
    headless: headless,
    useFirebaseEmulator: useFirebaseEmulator,
    useFirebaseLive: useFirebaseLive,
    firebaseProject: firebaseProject,
    firebaseSite: firebaseSite,
  );
  for (final scenario in selected) {
    stdout.write('-- ${scenario.id} ${scenario.title} ... ');
    final started = DateTime.now();
    final result = await scenario.execute(ctx);
    results.add(result);
    _printScenarioOutcome(result, DateTime.now().difference(started));
    await ReportWriter(outDir).write(results, sdkVersions: sdkVersions);
  }
}

Directory _findToolRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory(p.join(dir.path, 'sample_app')).existsSync()) {
      return dir;
    }
    if (Directory(p.join(dir.path, 'tool', 'sample_app')).existsSync()) {
      return Directory(p.join(dir.path, 'tool'));
    }
    if (dir.parent.path == dir.path) {
      throw StateError('Run from inside the flutter_web_cache_check repo.');
    }
    dir = dir.parent;
  }
}
