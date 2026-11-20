import 'package:material_ui/material_ui.dart';

import '../../core/widgets/fb_format.dart';
import '../routine_labels.dart';
import '../../core/scheduling/schedule_rule.dart';
import '../../core/utils/local_date.dart';
import '../../core/widgets/fb_choice.dart';
import '../../core/widgets/fb_fields.dart';
import '../../core/widgets/fb_scaffolds.dart';
import '../../core/widgets/l10n.dart';
import '../../core/widgets/tokens.dart';

enum RepeatKind { once, daily, weekdays, interval, weekly, everyNDays, monthly }

/// Picks a [ScheduleRule]; shared by the activity builder and the reminder
/// editor. Reports the current rule (or null when incomplete) on change.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({required this.initial, required this.today, required this.onChanged, this.label, super.key});
  final ScheduleRule initial;
  final LocalDate today;
  final ValueChanged<ScheduleRule?> onChanged;
  final String? label;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late RepeatKind _kind;
  late List<int> _times;
  late Set<int> _days;
  late LocalDate _date;
  String _every = '';
  int _start = 8 * 60;
  int _end = 20 * 60;
  String _monthDay = '1';

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _date = widget.today;
    _days = {1, 2, 3, 4, 5};
    _times = [8 * 60];
    switch (r) {
      case OneTime(:final date, :final time):
        _kind = RepeatKind.once;
        _date = date;
        _times = [time];
      case Daily(:final times):
        _kind = RepeatKind.daily;
        _times = [...times];
      case Weekdays(:final weekdays, :final times):
        _kind = RepeatKind.weekdays;
        _days = {...weekdays};
        _times = [...times];
      case Weekly(:final everyWeeks, :final weekdays, :final times):
        _kind = RepeatKind.weekly;
        _every = '$everyWeeks';
        _days = {...weekdays};
        _times = [...times];
      case EveryNDays(:final days, :final times):
        _kind = RepeatKind.everyNDays;
        _every = '$days';
        _times = [...times];
      case Monthly(:final day, :final times):
        _kind = RepeatKind.monthly;
        _monthDay = '${day ?? 1}';
        _times = [...times];
      case IntervalRule(:final everyMinutes, :final start, :final end, :final weekdays):
        _kind = RepeatKind.interval;
        _every = '$everyMinutes';
        _start = start;
        _end = end;
        if (weekdays != null) _days = {...weekdays};
    }
    if (_every.isEmpty) _every = _kind == RepeatKind.interval ? '90' : '2';
  }

  ScheduleRule? _rule() {
    final every = int.tryParse(_every.trim());
    return switch (_kind) {
      RepeatKind.once => _times.isEmpty ? null : OneTime(date: _date, time: _times.first),
      RepeatKind.daily => Daily(times: _times),
      RepeatKind.weekdays => Weekdays(weekdays: _days, times: _times),
      RepeatKind.weekly =>
        every == null ? null : Weekly(everyWeeks: every, anchor: widget.today, weekdays: _days, times: _times),
      RepeatKind.everyNDays => every == null ? null : EveryNDays(days: every, anchor: widget.today, times: _times),
      RepeatKind.monthly =>
        int.tryParse(_monthDay.trim()) == null ? null : Monthly.dayOfMonth(int.parse(_monthDay.trim()), times: _times),
      RepeatKind.interval =>
        every == null
            ? null
            : IntervalRule(everyMinutes: every, start: _start, end: _end, weekdays: _days.length == 7 ? null : _days),
    };
  }

  void _set(VoidCallback change) {
    setState(change);
    widget.onChanged(_rule());
  }

  Future<int?> _pickTime(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final names = {
      RepeatKind.daily: l10n.repeatDaily,
      RepeatKind.weekdays: l10n.repeatSelectedDays,
      RepeatKind.interval: l10n.repeatInterval,
      RepeatKind.weekly: l10n.repeatWeekly,
      RepeatKind.everyNDays: l10n.repeatEveryNDays,
      RepeatKind.monthly: l10n.repeatMonthly,
      RepeatKind.once: l10n.repeatOnce,
    };
    final usesDays = _kind == RepeatKind.weekdays || _kind == RepeatKind.weekly || _kind == RepeatKind.interval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label ?? l10n.scheduleLabel, style: context.text.label),
        const SizedBox(height: FbSpace.sm),
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final e in names.entries)
              FbToggleChip(label: e.value, selected: _kind == e.key, onTap: () => _set(() => _kind = e.key)),
          ],
        ),
        if (usesDays) ...[
          const SizedBox(height: FbSpace.md),
          Semantics(
            label: l10n.repeatDaysLabel,
            child: Wrap(
              spacing: FbSpace.xs,
              runSpacing: FbSpace.xs,
              children: [
                for (var d = 1; d <= 7; d++)
                  FbToggleChip(
                    label: weekdayShort(context, d),
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(DateTime(2026, 11, 15 + d)).split(',').first,
                    circular: true,
                    selected: _days.contains(d),
                    onTap: () => _set(() => _days.contains(d) && _days.length > 1 ? _days.remove(d) : _days.add(d)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: FbSpace.md),
        if (_kind == RepeatKind.once)
          FbPickerField(
            label: l10n.dateLabel,
            valueText: context.shortDate(_date),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(_date.year, _date.month, _date.day),
                firstDate: DateTime(widget.today.year, widget.today.month, widget.today.day),
                lastDate: DateTime(widget.today.year + 5),
              );
              if (d != null) _set(() => _date = LocalDate.fromDateTime(d));
            },
          ),
        if (_kind == RepeatKind.weekly || _kind == RepeatKind.everyNDays || _kind == RepeatKind.interval) ...[
          const SizedBox(height: FbSpace.sm),
          FbTextField(
            label: l10n.everyLabel,
            value: _every,
            onChanged: (v) => _set(() => _every = v),
            suffix: switch (_kind) {
              RepeatKind.weekly => l10n.unitWeeks,
              RepeatKind.everyNDays => l10n.unitDays,
              _ => l10n.unitMin,
            },
            keyboardType: TextInputType.number,
          ),
        ],
        if (_kind == RepeatKind.monthly)
          FbTextField(
            label: l10n.dayOfMonth,
            value: _monthDay,
            onChanged: (v) => _set(() => _monthDay = v),
            keyboardType: TextInputType.number,
          ),
        const SizedBox(height: FbSpace.sm),
        if (_kind == RepeatKind.interval)
          FbFieldPair(
            first: FbPickerField(
              label: l10n.fromLabel,
              valueText: minuteLabel(context, _start),
              onTap: () async {
                final m = await _pickTime(_start);
                if (m != null) _set(() => _start = m);
              },
            ),
            second: FbPickerField(
              label: l10n.untilLabel,
              valueText: minuteLabel(context, _end),
              onTap: () async {
                final m = await _pickTime(_end);
                if (m != null) _set(() => _end = m);
              },
            ),
          )
        else ...[
          Text(l10n.timesLabel, style: context.text.label),
          const SizedBox(height: FbSpace.xs),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              for (final (i, t) in _times.indexed)
                InputChip(
                  label: Text(minuteLabel(context, t)),
                  onPressed: () async {
                    final m = await _pickTime(t);
                    if (m != null) _set(() => _times[i] = m);
                  },
                  onDeleted: _times.length > 1 ? () => _set(() => _times.removeAt(i)) : null,
                  deleteButtonTooltipMessage: l10n.removeTime(minuteLabel(context, t)),
                ),
              if (_kind != RepeatKind.once)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded),
                  label: Text(l10n.addTime),
                  onPressed: () async {
                    final m = await _pickTime(_times.isEmpty ? 8 * 60 : (_times.last + 60) % 1440);
                    if (m != null && !_times.contains(m)) _set(() => _times.add(m));
                  },
                ),
            ],
          ),
          if (_times.length > 1) ...[
            const SizedBox(height: FbSpace.xs),
            Text(l10n.severalTimesNote, style: context.text.caption),
          ],
        ],
      ],
    );
  }
}
