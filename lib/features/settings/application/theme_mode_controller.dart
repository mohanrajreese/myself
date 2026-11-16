import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

enum AppThemeMode { system, light, dark }

const _key = 'theme_mode';

/// Loaded at start-up so the first frame already uses the right theme.
final initialThemeModeProvider = Provider<AppThemeMode>((ref) => AppThemeMode.system);

final themeModeProvider =
    NotifierProvider<ThemeModeController, AppThemeMode>(ThemeModeController.new);

AppThemeMode themeModeFromSetting(Object? stored) =>
    AppThemeMode.values.where((m) => m.name == stored).firstOrNull ?? AppThemeMode.system;

const themeModeSettingKey = _key;

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).write(_key, mode.name);
  }
}
