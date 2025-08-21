import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class DownloaderService {
  final _downloadsChannel = MethodChannel('com.justpixel.studio/downloads');

  Future<String?> _saveBase64ToDownloads({
    required String base64,
    required String
    filename, // 반드시 확장자 포함 (예: image.gif / archive.zip / data.json)
    required String
    mime, // 예: image/gif, image/png, application/zip, application/json
  }) async {
    final bytes = base64Decode(base64);
    final uri = await _downloadsChannel.invokeMethod<String>(
      'saveToDownloads',
      {'filename': filename, 'mime': mime, 'bytes': bytes},
    );
    return uri;
  }

  Future<void> _openDownloadsFolder() async {
    await _downloadsChannel.invokeMethod('openDownloads');
  }

  Future<void> saveBase64File({
    required String base64,
    required String
    filename, // 확장자 포함: image.gif / data.json / image.png / archive.zip
    required String
    mime, // 예: image/gif, application/json, image/png, application/zip
  }) async {
    try {
      final uri = await _saveBase64ToDownloads(
        base64: base64,
        filename: filename,
        mime: mime,
      );
      if (uri != null) {
        debugPrint('Saved to Downloads: $uri');
        // 원하면 바로 열기:
        _openDownloadsFolder();
      } else {
        debugPrint('save returned null');
      }
    } catch (e) {
      debugPrint('save error: $e');
    }
  }
}
