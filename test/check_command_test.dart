import 'dart:io';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  late HttpServer server;

  tearDown(() async {
    await server.close();
  });

  test('check passes when deployed server returns correct headers and hashed entrypoints', () async {
    server = await HttpServer.bind('localhost', 0);
    server.listen((HttpRequest request) {
      final String path = request.uri.path;
      if (path == '/index.html' || path == '/') {
        request.response.headers.set(
          'Cache-Control',
          'no-cache, must-revalidate',
        );
        request.response.write('<html></html>');
      } else if (path == '/flutter_bootstrap.js') {
        request.response.headers.set('Cache-Control', 'no-cache, no-store');
        request.response.write(
          '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
        );
      } else if (path == '/main.dart.10579154.js') {
        request.response.headers.set(
          'Cache-Control',
          'public, max-age=31536000, immutable',
        );
        request.response.headers.set('Content-Type', 'application/javascript');
        request.response.write('console.log("app");');
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });

    final TestProcess process = await TestProcess.start('dart', <String>[
      'run',
      'bin/flutter_web_cache_check.dart',
      'check',
      '--url',
      'http://localhost:${server.port}',
    ]);

    await expectLater(
      process.stdout,
      emitsThrough('✨ All caching header checks PASSED!'),
    );
    await process.shouldExit(0);
  });

  test(
    'check fails with exit code 1 when bootloader is cached aggressively',
    () async {
      server = await HttpServer.bind('localhost', 0);
      server.listen((HttpRequest request) {
        final String path = request.uri.path;
        if (path == '/index.html' || path == '/') {
          // Bad header: caching index.html for 1 year!
          request.response.headers.set('Cache-Control', 'max-age=31536000');
          request.response.write('<html></html>');
        } else if (path == '/flutter_bootstrap.js') {
          request.response.headers.set('Cache-Control', 'no-cache');
          request.response.write(
            '_flutter.buildConfig = {"mainJsPath":"main.dart.10579154.js"};',
          );
        } else if (path == '/main.dart.10579154.js') {
          request.response.headers.set(
            'Cache-Control',
            'public, max-age=31536000, immutable',
          );
          request.response.headers.set(
            'Content-Type',
            'application/javascript',
          );
          request.response.write('console.log("app");');
        } else {
          request.response.statusCode = 404;
        }
        request.response.close();
      });

      final TestProcess process = await TestProcess.start('dart', <String>[
        'run',
        'bin/flutter_web_cache_check.dart',
        'check',
        'http://localhost:${server.port}',
      ]);

      await expectLater(
        process.stdout,
        emitsThrough('❌ Some caching header checks FAILED. See report above.'),
      );
      await process.shouldExit(1);
    },
  );
}
