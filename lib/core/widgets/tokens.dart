import 'package:material_ui/material_ui.dart';

/// Design tokens (docs/blueprint/04-ui-ux-spec.md §1). Feature code styles
/// itself only through these; literal colours, sizes and paddings in feature
/// files are rejected by test/architecture.
@immutable
class FbColors extends ThemeExtension<FbColors> {
  const FbColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.success,
    required this.warning,
    required this.error,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.scrim,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color success;
  final Color warning;
  final Color error;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color scrim;

  static const light = FbColors(
    primary: Color(0xFF0F766E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD5F0EC),
    onPrimaryContainer: Color(0xFF0B4F49),
    secondary: Color(0xFF48688C),
    success: Color(0xFF2E7D4F),
    warning: Color(0xFFB26A00),
    error: Color(0xFFBA1A1A),
    background: Color(0xFFF6F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEDF0EE),
    outline: Color(0xFFD5DAD7),
    textPrimary: Color(0xFF141A19),
    textSecondary: Color(0xFF55605E),
    textDisabled: Color(0xFF8A9491),
    scrim: Color(0x80141A19),
  );

  static const dark = FbColors(
    primary: Color(0xFF5EC9BD),
    onPrimary: Color(0xFF00201C),
    primaryContainer: Color(0xFF0B4F49),
    onPrimaryContainer: Color(0xFFD5F0EC),
    secondary: Color(0xFFA9C4E4),
    success: Color(0xFF7FD3A0),
    warning: Color(0xFFF2B866),
    error: Color(0xFFFFB4AB),
    background: Color(0xFF0F1514),
    surface: Color(0xFF171E1D),
    surfaceVariant: Color(0xFF222B2A),
    outline: Color(0xFF34403E),
    textPrimary: Color(0xFFE7EDEB),
    textSecondary: Color(0xFFA3AFAC),
    textDisabled: Color(0xFF66716F),
    scrim: Color(0x99000000),
  );

  @override
  FbColors copyWith() => this;

  @override
  FbColors lerp(ThemeExtension<FbColors>? other, double t) {
    if (other is! FbColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return FbColors(
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryContainer: mix(primaryContainer, other.primaryContainer),
      onPrimaryContainer: mix(onPrimaryContainer, other.onPrimaryContainer),
      secondary: mix(secondary, other.secondary),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceVariant: mix(surfaceVariant, other.surfaceVariant),
      outline: mix(outline, other.outline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textDisabled: mix(textDisabled, other.textDisabled),
      scrim: mix(scrim, other.scrim),
    );
  }
}

/// Spacing scale, in logical pixels.
abstract final class FbSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
}

abstract final class FbRadius {
  static const double input = 8;
  static const double chip = 12;
  static const double card = 16;
  static const double hero = 24;
}

abstract final class FbSize {
  /// Minimum touch target.
  static const double touch = 48;
  static const double primaryButton = 56;
  static const double field = 52;
  static const double icon = 24;
}

abstract final class FbFont {
  static const text = 'Inter';
  static const heading = 'PlusJakartaSans';
}

/// Text styles, coloured for the current theme.
@immutable
class FbTextStyles {
  const FbTextStyles(this._c);
  final FbColors _c;

  static const _tabular = [FontFeature.tabularFigures()];

  TextStyle get displayMetric => TextStyle(
    fontFamily: FbFont.text,
    fontSize: 40,
    height: 44 / 40,
    fontWeight: FontWeight.w700,
    color: _c.textPrimary,
    fontFeatures: _tabular,
  );
  TextStyle get headline => TextStyle(
    fontFamily: FbFont.heading,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
    color: _c.textPrimary,
  );
  TextStyle get title => TextStyle(
    fontFamily: FbFont.heading,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: _c.textPrimary,
  );
  TextStyle get metric => TextStyle(
    fontFamily: FbFont.text,
    fontSize: 22,
    height: 26 / 22,
    fontWeight: FontWeight.w600,
    color: _c.textPrimary,
    fontFeatures: _tabular,
  );
  TextStyle get body => TextStyle(
    fontFamily: FbFont.text,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: _c.textPrimary,
  );
  TextStyle get bodyStrong => body.copyWith(fontWeight: FontWeight.w600);
  TextStyle get bodySmall => TextStyle(
    fontFamily: FbFont.text,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: _c.textSecondary,
  );
  TextStyle get label => TextStyle(
    fontFamily: FbFont.text,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    color: _c.textSecondary,
  );
  TextStyle get caption => label.copyWith(fontWeight: FontWeight.w400);
}

extension FbThemeContext on BuildContext {
  FbColors get colors => Theme.of(this).extension<FbColors>()!;
  FbTextStyles get text => FbTextStyles(colors);
}
