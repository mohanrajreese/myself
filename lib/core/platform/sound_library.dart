import 'generated/sound.pigeon.dart';

typedef SoundOption = ({String title, String uri});

/// System notification sounds, imported sound files and previews.
abstract interface class SoundLibrary {
  Future<List<SoundOption>> systemSounds();

  /// Lets the user pick an audio file and copies it into app storage;
  /// returns its URI, or null when cancelled or unreadable.
  Future<String?> pickSound();
  Future<void> play(String uri);
  Future<void> stop();
}

final class DeviceSoundLibrary implements SoundLibrary {
  DeviceSoundLibrary([SoundApi? api]) : _api = api ?? SoundApi();
  final SoundApi _api;

  @override
  Future<List<SoundOption>> systemSounds() async {
    try {
      return [for (final s in await _api.systemSounds()) (title: s.title, uri: s.uri)];
    } on Object {
      return const [];
    }
  }

  @override
  Future<String?> pickSound() async {
    try {
      return await _api.pickAndImportSound();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> play(String uri) async {
    try {
      await _api.play(uri);
    } on Object {
      // A sound that cannot play is simply silent; the picker still works.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _api.stop();
    } on Object {
      // Nothing to stop.
    }
  }
}
