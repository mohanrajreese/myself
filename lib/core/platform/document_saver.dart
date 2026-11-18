import 'dart:typed_data';

import 'generated/export.pigeon.dart';

/// The system "save as" picker. Returns false when cancelled or unwritable.
abstract interface class DocumentSaver {
  Future<bool> save(String fileName, Uint8List bytes);
}

final class DeviceDocumentSaver implements DocumentSaver {
  DeviceDocumentSaver([ExportApi? api]) : _api = api ?? ExportApi();
  final ExportApi _api;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    try {
      return await _api.saveDocument(fileName, bytes);
    } on Object {
      return false;
    }
  }
}
