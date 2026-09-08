import 'package:flutter/material.dart';

/// Botanical Vitality — colour tokens.
///
/// Straight translation of tokens/colors.css. Deep Forest carries authority,
/// Sage is the botanical fill and the success state, Soft Lavender is used
/// sparingly for category coding, and Cream/Sand provide tonal layering
/// instead of heavy shadow.
class Bv {
  // Primary — Deep Forest
  static const forest900 = Color(0xFF0C2018);
  static const forest800 = Color(0xFF1F3A2E);
  static const forest700 = Color(0xFF2C4A3C);
  static const forest600 = Color(0xFF3A5B4A);
  static const forest400 = Color(0xFF88A695);
  static const forest300 = Color(0xFFB1CEBE);
  static const forest200 = Color(0xFFCFE7D8);

  // Secondary — Sage
  static const sage700 = Color(0xFF3F5C3A);
  static const sage600 = Color(0xFF5E7D57);
  static const sage500 = Color(0xFF6F8E69);
  static const sage400 = Color(0xFFA7C5A1);
  static const sage300 = Color(0xFFC2D8BD);
  static const sage200 = Color(0xFFDCEBD8);

  // Tertiary — Soft Lavender
  static const lavender700 = Color(0xFF3A2B52);
  static const lavender600 = Color(0xFF5B4A76);
  static const lavender500 = Color(0xFF6E5D89);
  static const lavender400 = Color(0xFFCBB6E2);
  static const lavender200 = Color(0xFFECE2F6);

  // Surfaces — Cream & Sand
  static const cream0 = Color(0xFFFFFFFF);
  static const cream50 = Color(0xFFF5F2EA);
  static const cream100 = Color(0xFFF1EDE2);
  static const cream200 = Color(0xFFECE7D9);
  static const cream300 = Color(0xFFE8DFCF);
  static const cream400 = Color(0xFFE1D7C4);
  static const sand400 = Color(0xFFD6CBB5);
  static const sand500 = Color(0xFFC0B8A4);
  static const blush200 = Color(0xFFF6E4D6);
  static const blush300 = Color(0xFFEFD7C4);

  // Ink
  static const ink900 = Color(0xFF1C1C17);
  static const ink700 = Color(0xFF424844);
  static const ink600 = Color(0xFF727974);

  static const error = Color(0xFFBA1A1A);
  static const borderCard = Color(0xFFDDD2BD);

  // Semantic aliases
  static const background = cream50;
  static const surfaceCard = cream300;
  static const surfaceRaised = cream0;
  static const actionPrimary = forest800;
  static const accentSage = sage600;
  static const accentLavender = lavender600;
  static const border = sand500;
  static const textPrimary = ink900;
  static const textSecondary = ink700;
  static const textMuted = ink600;

  // Spacing — 8px linear scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;

  // Radius — soft, organic
  static const rSm = 4.0;
  static const rMd = 8.0;
  static const rLg = 12.0;
  static const rXl = 16.0;
  static const r2Xl = 24.0;

  // Elevation — extremely diffused, tinted with the primary green
  static const shadowMd = BoxShadow(
    color: Color(0x0D1F3A2E),
    blurRadius: 20,
    offset: Offset(0, 4),
  );
}

/// Typefaces.
///
/// The brand names Playfair Display and Inter. Both are free from Google
/// Fonts, but an offline Android app has to bundle the files rather than
/// fetch them, and they are not included here. Until the .ttf files are
/// added, these stay null and the app falls back to the system typeface —
/// everything else in the brand still applies. See FONTS.md.
const String? kDisplayFont = null; // 'PlayfairDisplay'
const String? kBodyFont = null; // 'Inter'

/// Type roles.
///
/// Playfair carries display and headlines. Inter carries body, labels and
/// — importantly — all data. Numerals use tabular figures so a weight
/// column lines up across sets.
class BvType {
  static const _tabular = [FontFeature.tabularFigures()];

  static const headlineMd = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: Bv.textPrimary,
  );

  static const headlineSm = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: Bv.textPrimary,
  );

  static const bodyMd = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 15,
    height: 1.6,
    color: Bv.textSecondary,
  );

  static const bodySm = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 13,
    height: 1.5,
    color: Bv.textSecondary,
  );

  /// Small overline label. Rendered uppercase at the call site, per brand.
  static const label = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 12,
    height: 1.0,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w600,
    color: Bv.textMuted,
  );

  /// The session headline number.
  static const metricLg = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w600,
    color: Bv.textPrimary,
    fontFeatures: _tabular,
  );

  /// A logged value inside the set table.
  static const metric = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: Bv.textPrimary,
    fontFeatures: _tabular,
  );

  /// An empty slot waiting to be filled.
  static const metricEmpty = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w400,
    color: Bv.sand400,
    fontFeatures: _tabular,
  );

  /// RPE — subjective rather than measured, so it is category-coded lavender.
  static const metricRpe = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: Bv.lavender600,
    fontFeatures: _tabular,
  );

  /// Unit suffix — deliberately smaller so the number reads first.
  static const unit = TextStyle(
    fontFamily: kBodyFont,
    fontSize: 13,
    height: 1.2,
    color: Bv.textMuted,
  );
}

ThemeData botanicalVitalityTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: Bv.forest800,
    brightness: Brightness.light,
  );

  final scheme = base.copyWith(
    primary: Bv.forest800,
    onPrimary: Colors.white,
    primaryContainer: Bv.forest200,
    onPrimaryContainer: Bv.forest900,
    secondary: Bv.sage600,
    onSecondary: Colors.white,
    secondaryContainer: Bv.sage200,
    onSecondaryContainer: Bv.sage700,
    tertiary: Bv.lavender600,
    onTertiary: Colors.white,
    tertiaryContainer: Bv.lavender200,
    onTertiaryContainer: Bv.lavender700,
    surface: Bv.cream50,
    onSurface: Bv.ink900,
    onSurfaceVariant: Bv.ink700,
    outline: Bv.sand500,
    outlineVariant: Bv.cream400,
    error: Bv.error,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Bv.background,
    fontFamily: kBodyFont,
    textTheme: const TextTheme(
      titleLarge: BvType.headlineMd,
      titleMedium: BvType.headlineSm,
      titleSmall: BvType.bodyMd,
      bodyLarge: BvType.bodyMd,
      bodyMedium: BvType.bodyMd,
      bodySmall: BvType.bodySm,
      labelLarge: BvType.bodySm,
      labelMedium: BvType.label,
      labelSmall: BvType.label,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Bv.background,
      foregroundColor: Bv.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Bv.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s2),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Bv.r2Xl),
        side: const BorderSide(color: Bv.borderCard),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Bv.cream400,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Bv.forest600,
      contentPadding: EdgeInsets.symmetric(horizontal: Bv.s4, vertical: Bv.s1),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Bv.actionPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Bv.rMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Bv.s5, vertical: Bv.s3),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Bv.forest800,
        side: const BorderSide(color: Bv.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Bv.rMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Bv.s4, vertical: Bv.s3),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Bv.forest800),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Bv.forest800,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Bv.cream100,
      selectedColor: Bv.sage200,
      side: const BorderSide(color: Bv.border),
      labelStyle: BvType.bodySm,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Bv.cream0,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Bv.s3, vertical: Bv.s3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Bv.rMd),
        borderSide: const BorderSide(color: Bv.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Bv.rMd),
        borderSide: const BorderSide(color: Bv.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Bv.rMd),
        borderSide: const BorderSide(color: Bv.forest800, width: 1.5),
      ),
      labelStyle: BvType.bodySm,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Bv.cream100,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Bv.sage200,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.all(BvType.bodySm),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Bv.forest800,
      contentTextStyle: TextStyle(color: Colors.white, fontFamily: kBodyFont),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Bv.forest800,
    ),
  );
}
