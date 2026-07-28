import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_web_cache_check/flutter_web_cache_check.dart';
import 'package:stack_trace/stack_trace.dart';

void main(List<String> args) {
  Chain.capture(
    () async {
      final CommandRunner<void> runner =
          CommandRunner<void>(
              'flutter_web_cache_check',
              'CLI tool to configure and verify caching headers for Flutter web apps.',
            )
            ..addCommand(FbConfigCommand())
            ..addCommand(CheckCommand());

      runner.argParser.addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show additional command output.',
      );

      await runner.run(args);
    },
    onError: (Object error, Chain chain) {
      if (error is UsageException) {
        stderr.writeln(error.message);
        stderr.writeln(error.usage);
        exit(64);
      } else {
        stderr.writeln('Fatal error: $error');
        stderr.writeln(chain.terse);
        exit(1);
      }
    },
  );
}
