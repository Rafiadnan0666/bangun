import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bangun design tokens — a strict blue-and-white system: white surfaces on
/// a pale blue canvas, blue family for every accent, chunky rounded type.
/// Red only marks destructive actions and green marks wins; everything else
/// is blue, so the brand reads instantly.
abstract final class Bg {
  // Canvas & surfaces.
  static const bg = Color(0xFFEDF4FE);
  static const card = Colors.white;
  static const cardSoft = Color(0xFFDCEBFF);
  static const hairline = Color(0xFFC9DEFA);

  // Ink.
  static const ink = Color(0xFF0B2A55);
  static const sub = Color(0xFF4F6E9E);
  static const subFaint = Color(0xFF8FA9CE);

  // Accent family — every hue a blue, from deep navy to airy sky.
  static const coral = Color(0xFF1D74E0);
  static const peach = Color(0xFF5B9DF4);
  static const lemon = Color(0xFFA9CFFA);
  static const mint = Color(0xFF3E97F5);
  static const sky = Color(0xFF6EB1FA);
  static const lilac = Color(0xFF0B57C2);
  static const rose = Color(0xFF2E6FD8);
  static const olive = Color(0xFF7FB4F2);
  static const plum = Color(0xFF084A9E);

  // CTA gradient (deep blue -> bright blue).
  static const ctaA = Color(0xFF0F5FC7);
  static const ctaB = Color(0xFF4FA5FF);
  static const cta = LinearGradient(
    colors: [ctaA, ctaB],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Ring screen gradient — a blue sunrise instead of the old peach-pink.
  static const ring = LinearGradient(
    colors: [Color(0xFF0B57C2), Color(0xFF3E97F5), Color(0xFF8CC9F8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Sound-card blue & white system (tone section only).
  static const toneBlue = Color(0xFF1D74E0);
  static const toneBlueDeep = Color(0xFF0B57C2);
  static const toneSky = Color(0xFF3E97F5);
  static const toneGradient = LinearGradient(
    colors: [toneBlueDeep, toneBlue, toneSky],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Signals (kept functional — they are the only non-blue accents).
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

/// Headline text rendered with the brand gradient via a shader mask.
class GradientText extends StatelessWidget {
  const GradientText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          Bg.cta.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(text, style: style),
    );
  }
}

ThemeData bangunTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Bg.ctaA,
        brightness: Brightness.light,
      ).copyWith(
        primary: Bg.ctaA,
        secondary: Bg.sky,
        surface: Bg.card,
        error: Bg.danger,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Bg.bg,
    // Material 3's fade-forward transition is smoother than the default
    // zoom/slide, especially when moving between the editor and the gates.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
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
    dividerTheme: const DividerThemeData(color: Bg.hairline),
  );
}
