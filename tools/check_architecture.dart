import 'dart:io';

void main() {
  var failed = false;
  final rules = <String, List<String>>{
    'domain': [
      'package:flutter',
      'dart:io',
      '../application/',
      '../infrastructure/',
      '../presentation/',
      '../rendering/',
    ],
    'application': [
      '../infrastructure/',
      '../presentation/',
      '../rendering/',
      'flutter_scene',
    ],
    'infrastructure': ['../application/', '../presentation/', '../rendering/'],
    'rendering': ['../application/', '../infrastructure/', '../domain/'],
    'presentation': ['../infrastructure/', 'package:flutter_scene'],
  };
  for (final layer in rules.entries) {
    final directory = Directory('lib/${layer.key}');
    if (!directory.existsSync()) continue;
    for (final file
        in directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final line in file.readAsLinesSync().where(
        (line) => line.startsWith('import ') || line.startsWith('export '),
      )) {
        for (final forbidden in layer.value) {
          if (line.contains(forbidden)) {
            stderr.writeln('${file.path}: forbidden dependency $line');
            failed = true;
          }
        }
      }
    }
  }
  if (failed) exit(1);
  stdout.writeln('Layer dependencies OK');
}
