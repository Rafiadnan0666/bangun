import 'package:flutter/material.dart';

import 'palette.dart';

/// White rounded card, standard Bangun surface.
class BgCard extends StatelessWidget {
  const BgCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 26,
    this.color = Bg.card,
    this.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Chunky primary button, the reference app's black pill.
class InkPill extends StatelessWidget {
  const InkPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = '⚡',
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final String icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: Bg.ink,
            borderRadius: BorderRadius.circular(999),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient (orange→pink) pill button.
class CtaPill extends StatelessWidget {
  const CtaPill({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 58,
    this.icon = '⚡',
  });

  final String label;
  final VoidCallback? onTap;
  final double height;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: Bg.cta,
            borderRadius: BorderRadius.circular(999),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastel icon tile, like the reference quick-action grid.
class PastelTile extends StatelessWidget {
  const PastelTile({
    super.key,
    required this.emoji,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 64,
  });

  final String emoji;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: TextStyle(fontSize: size * 0.45)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Bg.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label / value row, styled after the reference "Status / Recipient" card.
class StatusRow extends StatelessWidget {
  const StatusRow({super.key, required this.leading, required this.value});

  final String leading;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(leading, style: const TextStyle(color: Bg.sub, fontSize: 13.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: Bg.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selection chip with emoji; used for tones, targets, modes.
class EmojiChip extends StatelessWidget {
  const EmojiChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
    this.color,
    this.idleBorder = Bg.hairline,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? emoji;
  final Color? color;
  final Color idleBorder;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // Slight overshoot for a playful pop.
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      decoration: BoxDecoration(
        color: selected ? (color ?? Bg.lemon) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? Colors.transparent : idleBorder,
          width: 1.4,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Bg.ink : Bg.sub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Weekday letter pills (Mon..Sun), like the reference calendar row.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.days, this.h = 34});

  final List<int> days; // 1..7 ISO weekday
  final double h;

  @override
  Widget build(BuildContext context) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (var i = 1; i <= 7; i++)
          Expanded(
            child: Center(
              child: Container(
                width: h,
                height: h,
                decoration: BoxDecoration(
                  color: days.contains(i) ? Bg.ink : Bg.cardSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  letters[i - 1],
                  style: TextStyle(
                    fontSize: h * 0.36,
                    fontWeight: FontWeight.w700,
                    color: days.contains(i) ? Colors.white : Bg.subFaint,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Section heading for editor blocks.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});

  final String text;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Text(icon!, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: Bg.ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shaky feedback widget for wrong answers.
class ShakeFx extends StatefulWidget {
  const ShakeFx({super.key, required this.child, required this.trigger});

  final Widget child;
  final int trigger;

  @override
  State<ShakeFx> createState() => _ShakeFxState();
}

class _ShakeFxState extends State<ShakeFx> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _a = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic));

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(ShakeFx oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) {
        final t = _a.value;
        final off = t < 0.5 ? t : (1 - t);
        return Transform.translate(
          offset: Offset((t < 0.25 || t > 0.75 ? -1 : 1) * off * 14, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
