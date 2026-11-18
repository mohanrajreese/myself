import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/private_database.dart';
import '../core/platform/document_saver.dart';
import '../features/data_export/data/export_builder.dart';
import 'private_providers.dart';
import 'providers.dart';
import 'tracking_providers.dart';

final documentSaverProvider = Provider<DocumentSaver>((ref) => DeviceDocumentSaver());

final exportBuilderProvider = Provider<ExportBuilder>((ref) {
  PrivateDatabase? privateDb;
  try {
    privateDb = ref.watch(privateDatabaseProvider);
  } on StateError {
    privateDb = null;
  }
  return ExportBuilder(
    db: ref.watch(appDatabaseProvider),
    privateDb: privateDb,
    mealPhotos: ref.watch(mealPhotoStoreProvider),
    readProgressPhoto: privateDb == null
        ? null
        : (id) => ref.read(privateRepositoryProvider).readPhoto(id),
    clock: ref.watch(clockProvider),
  );
});
