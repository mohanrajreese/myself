import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// Takes or picks a photo with the phone's own camera or photo picker
/// (no storage permission is needed).
abstract interface class PhotoPicker {
  /// The image bytes, or null when the user cancels.
  Future<List<int>?> pick(PhotoSource source);
}

final class SystemPhotoPicker implements PhotoPicker {
  const SystemPhotoPicker();

  @override
  Future<List<int>?> pick(PhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    return file?.readAsBytes();
  }
}
