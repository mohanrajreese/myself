/// The only tables whose rows may enter the sync outbox (PRD §7.2).
///
/// A database trigger rebuilt from this list on every open rejects any other
/// table name, so local-only and private tables cannot be queued for upload
/// even by mistake. Parents come before children: this is also push order.
const syncedTableNames = <String>[
  'profiles',
  'user_goals',
  'nutrition_goals',
  'weight_logs',
  'body_measurements',
  'water_logs',
  'food_items',
  'meal_logs',
  'meal_food_items',
  'saved_meals',
  'sleep_logs',
  'daily_health_checkins',
  'activity_definitions',
  'activity_logs',
  'reminders',
  'step_logs',
  'exercises',
  'workout_sessions',
  'workout_exercises',
  'exercise_sets',
  'workout_templates',
];
