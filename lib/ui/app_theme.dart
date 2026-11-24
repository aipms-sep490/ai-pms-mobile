import 'package:material_ui/material_ui.dart';

/// Shared FAMS-aligned color tokens synchronized with `ai-pms-frontend/src/index.css`.
abstract final class AppColors {
  static const background = Color(0xFFF8F9FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F5F9);
  static const warmTint = Color(0xFFFFF8F4);

  static const text = Color(0xFF222836);
  static const textSoft = Color(0xFF3C4757);
  static const textMuted = Color(0xFF647083);

  static const primary = Color(0xFFC2410C);
  static const primaryHover = Color(0xFF9A3412);
  static const primarySoft = Color(0xFFFFF3EB);
  static const attentionBg = Color(0xFFFFF4EA);
  static const attentionBorder = Color(0xFFF37021);

  static const navy = Color(0xFF222836);
  static const navyRaised = Color(0xFF303747);
  static const onNavy = Color(0xFFFFFFFF);
  static const onNavyMuted = Color(0xFFC4CBD6);

  static const border = Color(0xFFE4E7EC);
  static const borderStrong = Color(0xFFCED3DC);

  static const teal = Color(0xFF39C58F);
  static const tealSoft = Color(0xFFE8F9F1);
  static const amber = Color(0xFFF7AE70);
  static const violet = Color(0xFF7C3AED);

  static const success = Color(0xFF0B7B52);
  static const successBg = Color(0xFFE8F9F1);
  static const successBorder = Color(0xFFA7E7C7);

  static const warning = Color(0xFFA94808);
  static const warningBg = Color(0xFFFFF8F1);
  static const warningBorder = Color(0xFFFED7B4);

  static const danger = Color(0xFFBE2638);
  static const dangerSoft = Color(0xFFFFF1F2);
  static const dangerBorder = Color(0xFFF8B9C0);

  static const info = Color(0xFF1D4ED8);
  static const infoBg = Color(0xFFEFF6FF);
  static const infoBorder = Color(0xFFBFDBFE);

  static const cardShadow = Color(0x0D222836);
  static const primaryShadow = Color(0x33C2410C);
}

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: AppColors.surface,
        secondary: AppColors.navy,
        onSecondary: AppColors.onNavy,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
        outline: AppColors.border,
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarThemeData(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: AppColors.cardShadow,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: AppColors.text,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.textSoft,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primarySoft,
      secondarySelectedColor: AppColors.primarySoft,
      showCheckmark: true,
      checkmarkColor: AppColors.primary,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSoft,
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.navy,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: AppColors.navy,
      ),
      headlineSmall: TextStyle(
        fontSize: 21,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.text,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: AppColors.text),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: AppColors.textMuted,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      errorMaxLines: 3,
      fillColor: AppColors.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        elevation: 1,
        shadowColor: AppColors.primaryShadow,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.text,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.borderStrong),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      surfaceTintColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(color: AppColors.onNavy, fontSize: 14),
      actionTextColor: AppColors.amber,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
