import 'package:material_ui/material_ui.dart';

import '../core/widgets/tokens.dart';

/// Builds the Material theme from FitBuddy's tokens.
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? FbColors.dark : FbColors.light;
  final t = FbTextStyles(c);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onPrimary,
    error: c.error,
    onError: c.surface,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    outline: c.outline,
    outlineVariant: c.outline,
    surfaceContainerHighest: c.surfaceVariant,
    scrim: c.scrim,
  );

  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(FbRadius.input),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    fontFamily: FbFont.text,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      headlineSmall: t.headline,
      titleMedium: t.title,
      bodyLarge: t.body,
      bodyMedium: t.bodySmall,
      labelMedium: t.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: t.headline,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: c.surfaceVariant, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: t.body.copyWith(color: c.textDisabled),
      suffixStyle: t.bodySmall,
      errorStyle: t.caption.copyWith(color: c.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.md),
      border: border(c.outline),
      enabledBorder: border(c.outline),
      focusedBorder: border(c.primary, 2),
      errorBorder: border(c.error),
      focusedErrorBorder: border(c.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, FbSize.primaryButton),
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        disabledBackgroundColor: c.surfaceVariant,
        disabledForegroundColor: c.textDisabled,
        textStyle: t.bodyStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FbRadius.card)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, FbSize.touch),
        foregroundColor: c.textPrimary,
        backgroundColor: c.surface,
        side: BorderSide(color: c.outline),
        textStyle: t.bodySmall.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FbRadius.chip)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(FbSize.touch, FbSize.touch),
        foregroundColor: c.primary,
        textStyle: t.bodySmall.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.surface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.primary : c.textDisabled,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: FbFont.text,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? c.primary : c.textSecondary,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: FbSize.icon,
          color: states.contains(WidgetState.selected) ? c.primary : c.textSecondary,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FbRadius.hero)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: t.title,
      contentTextStyle: t.bodySmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FbRadius.hero)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.textPrimary,
      contentTextStyle: t.bodySmall.copyWith(color: c.background),
      actionTextColor: c.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FbRadius.chip)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
  );
}
