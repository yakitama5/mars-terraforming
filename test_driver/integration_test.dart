import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    // PNGはonScreenshotで保存する。画素の全byteを巨大なJSONへ再保存しない。
    responseDataCallback: (data) async {
      final summary = <String, dynamic>{...?data};
      final screenshots = summary['screenshots'];
      if (screenshots is List) {
        summary['screenshots'] = [
          for (final item in screenshots)
            if (item is Map)
              {
                ...item,
                'bytes': item['bytes'] is List
                    ? {'length': (item['bytes'] as List).length}
                    : null,
              },
        ];
      }
      await writeResponseData(summary);
    },
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory(
        Platform.environment['MARS_SCREENSHOT_DIR'] ?? 'docs/screenshots',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
