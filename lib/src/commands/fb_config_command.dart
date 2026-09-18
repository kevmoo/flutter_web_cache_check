import 'dart:io';

import 'package:args/command_runner.dart';

import '../firebase_config.dart';

class FbConfigCommand extends Command<void> {
  @override
  final String name = 'fb-config';
  @override
  final String description =
      'Inject or audit Firebase Hosting caching header rules and predeploy build scripts.';

  FbConfigCommand() {
    argParser.addOption(
      'file',
      abbr: 'f',
      defaultsTo: 'firebase.json',
      help: 'Path to firebase.json.',
    );
    argParser.addFlag(
      'add-predeploy',
      abbr: 'p',
      defaultsTo: true,
      help: 'Add or update "flutter build web --web-content-hash" in hosting.predeploy.',
    );
  }

  @override
  Future<void> run() async {
    final String filePath = argResults!['file']! as String;
    final bool addPredeploy = argResults!['add-predeploy']! as bool;

    try {
      FirebaseConfig.configure(filePath: filePath, addPredeploy: addPredeploy);
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      exit(1);
    } catch (e) {
      stderr.writeln('Fatal error during configuration: $e');
      exit(1);
    }
  }
}
