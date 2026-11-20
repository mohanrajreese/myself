import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routine_providers.dart';
import '../../../core/platform/sound_library.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

/// What the sheet returns: a sound URI, or [SoundPick.defaultSound].
final class SoundPick {
  const SoundPick(this.uri);
  final String? uri;
  static const defaultSound = SoundPick(null);
}

/// A readable name for a stored sound key.
String soundTitle(AppLocalizations l10n, String? uri, List<({String title, String uri})> system) {
  if (uri == null) return l10n.soundDefault;
  final match = system.where((s) => s.uri == uri).firstOrNull;
  if (match != null) return match.title;
  final file = Uri.tryParse(uri)?.pathSegments.lastOrNull ?? '';
  return file.isEmpty
      ? l10n.soundCustom
      : file.replaceAll('_', ' ').replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
}

/// Default, the phone's notification sounds, or a sound file (§5.15F).
class SoundPickerSheet extends ConsumerStatefulWidget {
  const SoundPickerSheet({required this.current, super.key});
  final String? current;

  @override
  ConsumerState<SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends ConsumerState<SoundPickerSheet> {
  late String? _selected = widget.current;
  late final SoundLibrary _library = ref.read(soundLibraryProvider);
  String? _imported;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_library.stop());
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final uri = await _library.pickSound();
    if (!mounted) return;
    setState(() => _busy = false);
    if (uri == null) {
      showFbSnackBar(context, l10n.soundImportFailed);
      return;
    }
    setState(() {
      _imported = uri;
      _selected = uri;
    });
    unawaited(ref.read(soundLibraryProvider).play(uri));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sounds = ref.watch(systemSoundsProvider);
    final library = _library;
    final system = sounds.value ?? const [];
    final custom = {
      ?_imported,
      if (widget.current != null && !system.any((s) => s.uri == widget.current)) widget.current!,
    };
    Widget option(String? uri, String title) => RadioListTile<String?>(
      value: uri,
      title: Text(title),
      secondary: uri == null
          ? null
          : IconButton(
              tooltip: l10n.playSound(title),
              onPressed: () => library.play(uri),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
    );
    return RadioGroup<String?>(
      groupValue: _selected,
      onChanged: (v) {
        setState(() => _selected = v);
        if (v != null) unawaited(library.play(v));
      },
      child: FbSheetBody(
        title: l10n.soundLabel,
        children: [
          option(null, l10n.soundDefault),
          for (final uri in custom) option(uri, soundTitle(l10n, uri, system)),
          if (sounds.isLoading) const FbLoading(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: [for (final s in system) option(s.uri, s.title)],
            ),
          ),
          const SizedBox(height: FbSpace.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseFile,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(l10n.chooseSoundFile),
          ),
          const SizedBox(height: FbSpace.sm),
          Text(l10n.soundPickerNote, style: context.text.caption),
          const SizedBox(height: FbSpace.md),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(SoundPick(_selected)),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }
}
