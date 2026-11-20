import 'package:material_ui/material_ui.dart';

import '../core/widgets/fb_sheet.dart';
import '../core/widgets/l10n.dart';
import '../features/money/domain/money.dart';

String paymentMethodLabel(AppLocalizations l10n, PaymentMethod m) => switch (m) {
  PaymentMethod.cash => l10n.moneyMethodCash,
  PaymentMethod.upi => l10n.moneyMethodUpi,
  PaymentMethod.debitCard => l10n.moneyMethodDebitCard,
  PaymentMethod.creditCard => l10n.moneyMethodCreditCard,
  PaymentMethod.netBanking => l10n.moneyMethodNetBanking,
  PaymentMethod.other => l10n.moneyMethodOther,
};

/// Names for the seeded categories, by system key (§5.21A).
Map<String, String> categoryNames(AppLocalizations l10n) => {
  'food': l10n.moneyCatFood,
  'groceries': l10n.moneyCatGroceries,
  'transport': l10n.moneyCatTransport,
  'fuel': l10n.moneyCatFuel,
  'bills': l10n.moneyCatBills,
  'rent': l10n.moneyCatRent,
  'shopping': l10n.moneyCatShopping,
  'health': l10n.moneyCatHealth,
  'entertainment': l10n.moneyCatEntertainment,
  'education': l10n.moneyCatEducation,
  'travel': l10n.moneyCatTravel,
  'gifts': l10n.moneyCatGifts,
  'emi': l10n.moneyCatEmi,
  'other': l10n.moneyCatOther,
};

/// Lets the user choose how they paid; null when dismissed.
Future<PaymentMethod?> pickPaymentMethod(BuildContext context, PaymentMethod current) {
  final l10n = context.l10n;
  return showFbSheet<PaymentMethod>(
    context,
    FbSheetBody(
      title: l10n.moneyPaidWith,
      children: [
        for (final m in PaymentMethod.values)
          FbListRow(
            title: paymentMethodLabel(l10n, m),
            trailing: m == current ? Icon(Icons.check_rounded, semanticLabel: l10n.selected) : null,
            onTap: () => Navigator.of(context).pop(m),
          ),
      ],
    ),
  );
}
