/// Per-table facts the sync engine needs beyond the Drift schema.
library;

/// Columns stored as JSON text locally and as `jsonb` in Supabase.
/// Checked against the migrations by a test.
const jsonColumns = <String, Set<String>>{
  'profiles': {'workout_days', 'custom_measurement_types'},
  'user_goals': {'fitness_goals'},
  'saved_meals': {'items'},
  'activity_definitions': {'schedule', 'schedule_history', 'checklist_items'},
  'activity_logs': {'checklist_state'},
  'reminders': {'schedule'},
  'workout_templates': {'exercises'},
  'recurring_expenses': {'schedule'},
};

/// Unique keys other than `id` used for upserts (03-database.md §5.4).
const conflictKeys = <String, String>{'step_logs': 'user_id,log_date'};

/// Local unique keys that a pulled row may collide with under another id.
const localNaturalKeys = <String, String>{'step_logs': 'log_date'};
