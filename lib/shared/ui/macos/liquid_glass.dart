import 'dart:ui';
import 'package:flutter/material.dart';

/// Implements Apple's Liquid Glass material guidelines (WWDC 2025 / macOS Design Language).
///
/// Intended strictly for the Navigation Layer (Toolbars, Sidebars, Floating Player HUDs, Sheets)
/// that floats above content. Avoids placing over raw list views to prevent visual noise.
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final bool enableLensing;
  final Color? tintColor;
  final Border? border;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.enableLensing = true,
    this.tintColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(14);

    final defaultTint = isDark
        ? const Color(0xFF16181D).withValues(alpha: 0.72)
        : const Color(0xFFF7F8FA).withValues(alpha: 0.78);

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tintColor ?? defaultTint,
              borderRadius: radius,
              border: border ??
                  Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: enableLensing ? 0.14 : 0.08)
                        : Colors.white.withValues(alpha: 0.55),
                    width: 1,
                  ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
