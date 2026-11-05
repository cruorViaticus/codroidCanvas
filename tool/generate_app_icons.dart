// Generátor launcher ikon pre všetky platformy.
//
// Kreslí sa reálnym Flutter Canvas-om (rovnaký kód ako logo v aplikácii),
// takže ikona je vyhladená a vždy konzistentná s UI.
//
// Spustenie (z koreňa projektu):
//   flutter test tool/generate_app_icons.dart
//
// Vygeneruje:
//   * Android  – mipmap-*/ic_launcher.png (48–192 px)
//   * Android  – mipmap-*/ic_launcher_foreground.png (108–432 px, adaptive)
//   * Windows  – windows/runner/resources/app_icon.ico (16–256 px)
//   * Web      – favicon.png + icons/Icon-*.png
//   * assets/icon/app_icon_1024.png (master pre obchod / README)
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:codroid_pen_plotter/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('vygeneruje ikony pre Android, Windows a web', (tester) async {
    await tester.runAsync(() async {
      await _generateAndroid();
      await _generateWindows();
      await _generateWeb();
      await _generateMaster();
    });
  });
}

/// Android – klasické (legacy) ikony.
const Map<String, int> _androidDensities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Android – adaptive icon foreground (108 dp grid).
const Map<String, int> _androidForegroundSizes = {
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};

Future<void> _generateAndroid() async {
  for (final entry in _androidDensities.entries) {
    await _writePng(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      entry.value,
      rounded: true,
      contentScale: 0.94,
    );
  }
  for (final entry in _androidForegroundSizes.entries) {
    await _writePng(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
      entry.value,
      background: false,
      rounded: false,
      contentScale: 0.62,
    );
  }
  _log('Android: ${_androidDensities.length} legacy + '
      '${_androidForegroundSizes.length} adaptive PNG');
}

Future<void> _generateWindows() async {
  await _writeIco(
    'windows/runner/resources/app_icon.ico',
    const [16, 24, 32, 48, 64, 128, 256],
  );
  _log('Windows: app_icon.ico');
}

Future<void> _generateWeb() async {
  await _writePng('web/favicon.png', 64, rounded: true, contentScale: 0.94);
  await _writePng('web/icons/Icon-192.png', 192,
      rounded: false, contentScale: 0.90);
  await _writePng('web/icons/Icon-512.png', 512,
      rounded: false, contentScale: 0.90);
  await _writePng('web/icons/Icon-maskable-192.png', 192,
      rounded: false, contentScale: 0.70);
  await _writePng('web/icons/Icon-maskable-512.png', 512,
      rounded: false, contentScale: 0.70);
  _log('Web: favicon + 4 PWA ikony');
}

Future<void> _generateMaster() async {
  await _writePng('assets/icon/app_icon_1024.png', 1024,
      rounded: true, contentScale: 0.94);
  _log('Master: assets/icon/app_icon_1024.png');
}

Future<ui.Image> _render(
  int size, {
  bool background = true,
  bool rounded = true,
  double contentScale = 0.94,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintCodroidIcon(
    canvas,
    Size(size.toDouble(), size.toDouble()),
    background: background,
    rounded: rounded,
    contentScale: contentScale,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

Future<void> _writePng(
  String path,
  int size, {
  bool background = true,
  bool rounded = true,
  double contentScale = 0.94,
}) async {
  final image = await _render(
    size,
    background: background,
    rounded: rounded,
    contentScale: contentScale,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data!.buffer.asUint8List());
}

/// Zapíše viac-veľkostný `.ico`. Malé rozmery ako 32-bit BMP (maximálna
/// kompatibilita), 128+ ako PNG (Windows Vista+).
Future<void> _writeIco(String path, List<int> sizes) async {
  final entries = <_IcoEntry>[];
  for (final size in sizes) {
    final image = await _render(size, rounded: false, contentScale: 0.90);
    if (size >= 128) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      entries.add(_IcoEntry(size, png!.buffer.asUint8List()));
    } else {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      entries.add(
        _IcoEntry(
          size,
          _toBmpDib(rgba!.buffer.asUint8List(), size),
        ),
      );
    }
    image.dispose();
  }

  final headerSize = 6 + entries.length * 16;
  final header = ByteData(headerSize);
  header.setUint16(0, 0, Endian.little); // reserved
  header.setUint16(2, 1, Endian.little); // type = icon
  header.setUint16(4, entries.length, Endian.little);

  var offset = headerSize;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final base = 6 + i * 16;
    header.setUint8(base, entry.size >= 256 ? 0 : entry.size); // width
    header.setUint8(base + 1, entry.size >= 256 ? 0 : entry.size); // height
    header.setUint8(base + 2, 0); // farby v palete
    header.setUint8(base + 3, 0); // reserved
    header.setUint16(base + 4, 1, Endian.little); // planes
    header.setUint16(base + 6, 32, Endian.little); // bpp
    header.setUint32(base + 8, entry.bytes.length, Endian.little);
    header.setUint32(base + 12, offset, Endian.little);
    offset += entry.bytes.length;
  }

  final builder = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final entry in entries) {
    builder.add(entry.bytes);
  }

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(builder.takeBytes());
}

/// BITMAPINFOHEADER + 32-bit BGRA pixely (bottom-up) + AND maska.
Uint8List _toBmpDib(Uint8List rgba, int size) {
  final header = ByteData(40);
  header.setUint32(0, 40, Endian.little); // biSize
  header.setInt32(4, size, Endian.little); // biWidth
  header.setInt32(8, size * 2, Endian.little); // biHeight (XOR + AND)
  header.setUint16(12, 1, Endian.little); // biPlanes
  header.setUint16(14, 32, Endian.little); // biBitCount
  header.setUint32(16, 0, Endian.little); // BI_RGB

  final maskRowBytes = ((size + 31) ~/ 32) * 4;
  final builder = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(Uint8List(size * size * 4))
    ..add(Uint8List(maskRowBytes * size));

  final out = builder.takeBytes();
  var pos = 40;
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out[pos++] = rgba[i + 2]; // B
      out[pos++] = rgba[i + 1]; // G
      out[pos++] = rgba[i]; // R
      out[pos++] = rgba[i + 3]; // A
    }
  }
  return out;
}

class _IcoEntry {
  const _IcoEntry(this.size, this.bytes);

  final int size;
  final Uint8List bytes;
}

void _log(String message) => debugPrint('[ICONS] $message');
