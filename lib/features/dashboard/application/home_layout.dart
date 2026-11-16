import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../app/providers.dart';

enum HomeSection { progress, quickAdd, essentials, timeline }

@immutable
final class HomeSectionSetting {
  const HomeSectionSetting(this.section, {this.visible = true});
  final HomeSection section;
  final bool visible;
}

const _key = 'home_layout';
const _default = [
  HomeSectionSetting(HomeSection.progress),
  HomeSectionSetting(HomeSection.quickAdd),
  HomeSectionSetting(HomeSection.essentials),
  HomeSectionSetting(HomeSection.timeline),
];

final homeLayoutProvider = AsyncNotifierProvider<HomeLayoutController, List<HomeSectionSetting>>(
  HomeLayoutController.new,
);

/// Order and visibility of the Home sections (PRD §4.2, dashboard
/// customisation). Stored on the device.
class HomeLayoutController extends AsyncNotifier<List<HomeSectionSetting>> {
  @override
  Future<List<HomeSectionSetting>> build() async {
    final stored = await ref.read(settingsRepositoryProvider).read(_key);
    if (stored is! List<Object?>) return _default;

    final result = <HomeSectionSetting>[];
    for (final item in stored.whereType<Map<String, Object?>>()) {
      final section = HomeSection.values.where((s) => s.name == item['id']).firstOrNull;
      if (section != null && result.every((r) => r.section != section)) {
        result.add(HomeSectionSetting(section, visible: item['visible'] != false));
      }
    }
    // Sections added in a later version appear at the end.
    for (final missing in _default) {
      if (result.every((r) => r.section != missing.section)) result.add(missing);
    }
    return result;
  }

  Future<void> setVisible(HomeSection section, bool visible) => _update([
    for (final item in state.value ?? _default)
      item.section == section ? HomeSectionSetting(section, visible: visible) : item,
  ]);

  /// Moves the item at [oldIndex] so that it ends up at [newIndex].
  Future<void> move(int oldIndex, int newIndex) {
    final items = [...state.value ?? _default];
    items.insert(newIndex.clamp(0, items.length - 1), items.removeAt(oldIndex));
    return _update(items);
  }

  Future<void> _update(List<HomeSectionSetting> items) async {
    state = AsyncData(items);
    await ref.read(settingsRepositoryProvider).write(_key, [
      for (final item in items) {'id': item.section.name, 'visible': item.visible},
    ]);
  }
}
