import 'dart:io';

import 'package:args/command_runner.dart';

import '../url_checker.dart';

class CheckCommand extends Command<void> {
  @override
  final String name = 'check';
  @override
  final String description =
      'Live HTTP audit of a deployed Flutter web application.';

  CheckCommand() {
    argParser
      ..addOption(
        'url',
        abbr: 'u',
        help: 'Target URL of the published Flutter web app.',
      )
      ..addOption(
        'platform',
        allowed: const <String>['auto', 'firebase', 'generic'],
        defaultsTo: 'auto',
        help: 'Host platform adapter mode (auto, firebase, generic).',
      );
  }

  @override
  Future<void> run() async {
    String? targetUrl = argResults!['url'] as String?;
    if (targetUrl == null && argResults!.rest.isNotEmpty) {
      targetUrl = argResults!.rest.first;
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      stderr.writeln(
        'Error: Please specify a target URL via --url or positional argument.',
      );
      stderr.writeln(usage);
      exit(64);
    }

    final bool verbose = globalResults?['verbose'] as bool? ?? false;
    final String platformName = argResults!['platform'] as String? ?? 'auto';
    final HostPlatform platform = switch (platformName) {
      'firebase' => HostPlatform.firebase,
      'generic' => HostPlatform.generic,
      _ => HostPlatform.auto,
    };
    await UrlChecker.checkUrl(targetUrl, verbose: verbose, platform: platform);
  }
}
