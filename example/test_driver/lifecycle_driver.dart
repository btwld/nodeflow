import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test_driver_extended.dart';

/// Browser screenshots are captured at DPR 1. Compare a chosen minimap or edge
/// crop, with a static canvas region guarding against general frame noise.
void main() async {
  final captures = <String, image.Image>{};
  final artifacts = Directory('build/integration_artifacts');
  await artifacts.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${artifacts.path}/$name.png').writeAsBytes(bytes);
      final current = image.decodePng(Uint8List.fromList(bytes));
      if (current == null) {
        throw StateError('Chrome returned an invalid PNG: $name');
      }
      captures[name] = current;
      final previousName = args?['compareWith'] as String?;
      if (previousName == null) return true;
      final previous = captures[previousName];
      if (previous == null) {
        throw StateError('Missing comparison image: $previousName');
      }
      if (previous.width != current.width ||
          previous.height != current.height) {
        throw StateError('Screenshot dimensions changed for $name');
      }
      final region = _rect(args!['region'], current);
      final control = _rect(args['controlRegion'], current);
      final regionChanges = _changedPixels(previous, current, region);
      final controlChanges = _changedPixels(previous, current, control);
      final expectChange = args['expectChange'] == true;
      // Minimap and edge updates cover multiple pixels; the static region
      // should remain bitwise close even across Chrome antialiasing frames.
      final passed =
          controlChanges <= 10 &&
          (expectChange ? regionChanges >= 12 : regionChanges <= 10);
      stdout.writeln(
        '$previousName -> $name: region=$regionChanges, '
        'control=$controlChanges, pass=$passed',
      );
      return passed;
    },
  );
}

({int left, int top, int right, int bottom}) _rect(
  Object? value,
  image.Image screenshot,
) {
  final values = (value as List<Object?>).cast<num>();
  if (values.length != 4) throw StateError('Expected x/y/width/height');
  final left = values[0].round();
  final top = values[1].round();
  final right = (values[0] + values[2]).round();
  final bottom = (values[1] + values[3]).round();
  if (left < 0 ||
      top < 0 ||
      right > screenshot.width ||
      bottom > screenshot.height ||
      left >= right ||
      top >= bottom) {
    throw StateError(
      'Invalid screenshot crop ($left,$top,$right,$bottom) for '
      '${screenshot.width}x${screenshot.height}. Use DPR 1.',
    );
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

int _changedPixels(
  image.Image before,
  image.Image after,
  ({int left, int top, int right, int bottom}) rect,
) {
  var count = 0;
  for (var y = rect.top; y < rect.bottom; y++) {
    for (var x = rect.left; x < rect.right; x++) {
      final a = before.getPixel(x, y);
      final b = after.getPixel(x, y);
      final delta = (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      if (delta > 20) count++;
    }
  }
  return count;
}
