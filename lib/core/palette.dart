import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bangun design tokens — pastel cards on a lavender canvas with a
/// chunky, rounded type look (mirrors the reference dashboard style).
abstract final class Bg {
  // Canvas & surfaces.
  static const bg = Color(0xFFF5F2FB);
  static const card = Colors.white;
  static const cardSoft = Color(0xFFEDE7FA);
  static const hairline = Color(0xFFE7E1F5);

  // Ink.
  static const ink = Color(0xFF241D33);
  static const sub = Color(0xFF8B85A4);
  static const subFaint = Color(0xFFB3ADCB);

  // Pastel tile palette.
  static const coral = Color(0xFFFF6E5A);
  static const peach = Color(0xFFFFB05E);
  static const lemon = Color(0xFFFDCE5A);
  static const mint = Color(0xFF7EDCA7);
  static const sky = Color(0xFF86C8FF);
  static const lilac = Color(0xFFB6A5FF);
  static const rose = Color(0xFFFFA9C7);
  static const olive = Color(0xFFA8C972);
  static const plum = Color(0xFF9C6ADE);

  // CTA gradient (orange -> pink, like the reference "Send again").
  static const ctaA = Color(0xFFFF8A3C);
  static const ctaB = Color(0xFFFF5E9C);
  static const cta = LinearGradient(
    colors: [ctaA, ctaB],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Ring screen gradient (peach -> pink -> lilac, "sunrise" energy).
  static const ring = LinearGradient(
    colors: [Color(0xFFFFB463), Color(0xFFFF7A9E), Color(0xFFB79DFC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Signals.
  static const success = Color(0xFF2FBE7B);
  static const danger = Color(0xFFFF5A6A);

  static const tileColors = [
    coral,
    mint,
    sky,
    lemon,
    lilac,
    peach,
    plum,
    olive,
  ];
}

ThemeData bangunTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Bg.ctaB,
        brightness: Brightness.light,
      ).copyWith(
        primary: Bg.ctaB,
        secondary: Bg.lilac,
        surface: Bg.card,
        error: Bg.danger,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Bg.bg,
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: GoogleFonts.poppins().fontFamily,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: Bg.ink,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Bg.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: Bg.subFaint, fontSize: 14.5),
      labelStyle: const TextStyle(color: Bg.sub, fontSize: 13.5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Bg.mint : Bg.hairline,
      ),
      thumbColor: WidgetStateProperty.resolveWith((states) => Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Bg.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 8,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 11),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
    ),
    dividerTheme: const DividerThemeData(
      color: Bg.hairline,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Gradient text for display headings (e.g. the alarm time).
class GradientText extends StatelessWidget {
  const GradientText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFFF8A3C), Color(0xFFFF5E9C)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(text, style: style),
    );
  }
}
