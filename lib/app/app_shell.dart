import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/widgets/l10n.dart';
import '../core/widgets/tokens.dart';

/// The six main destinations (PRD §3.2).
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (Icons.home_outlined, Icons.home_rounded, l10n.tabHome),
      (Icons.fitness_center_outlined, Icons.fitness_center_rounded, l10n.tabFitness),
      (Icons.restaurant_outlined, Icons.restaurant_rounded, l10n.tabNutrition),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, l10n.tabHealth),
      (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, l10n.tabHabits),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, l10n.tabMoney),
    ];
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.outline)),
        ),
        child: MediaQuery.withClampedTextScaling(
          // Six labels cannot grow without clipping; the label is also the
          // accessible name, so screen readers are unaffected.
          maxScaleFactor: 1.15,
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
            destinations: [
              for (final (icon, selected, label) in destinations)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      ),
    );
  }
}
