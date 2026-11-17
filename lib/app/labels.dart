/// Display names for domain values used on several screens.
library;

import '../core/widgets/l10n.dart';
import '../features/nutrition/domain/nutrition_math.dart';

String mealName(AppLocalizations l10n, MealCategory c) => switch (c) {
  MealCategory.earlyMorning => l10n.mealEarlyMorning,
  MealCategory.breakfast => l10n.mealBreakfast,
  MealCategory.midMorning => l10n.mealMidMorning,
  MealCategory.lunch => l10n.mealLunch,
  MealCategory.eveningSnack => l10n.mealEveningSnack,
  MealCategory.dinner => l10n.mealDinner,
  MealCategory.lateNight => l10n.mealLateNight,
  MealCategory.other => l10n.mealOther,
};

String junkLabel(AppLocalizations l10n, JunkCategory? junk) => switch (junk) {
  null => l10n.junkNone,
  JunkCategory.fastFood => l10n.junkFastFood,
  JunkCategory.friedSnacks => l10n.junkFriedSnacks,
  JunkCategory.sweets => l10n.junkSweets,
  JunkCategory.sugaryDrinks => l10n.junkSugaryDrinks,
  JunkCategory.packagedSnacks => l10n.junkPackagedSnacks,
  JunkCategory.other => l10n.junkOther,
};
