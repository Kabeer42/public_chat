import 'package:flutter/material.dart';

class AppColors {
  // Brand Primary & Accents
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color accent = Color(0xFF10B981); // Emerald / Online
  static const Color accentRose = Color(0xFFF43F5E); // Hangup / Danger

  // Dark Theme Palette
  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B);    // Slate 800
  static const Color cardDark = Color(0xFF334155);       // Slate 700
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // Light Theme Palette
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFF1F5F9);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);

  // Chat Bubbles
  static const Color myMessageBubble = Color(0xFF6366F1);
  static const Color peerMessageBubble = Color(0xFF1E293B);
  static const Color peerMessageBubbleLight = Color(0xFFE2E8F0);

  // Call Status
  static const Color callActive = Color(0xFF10B981);
  static const Color callMuted = Color(0xFFEAB308);
  static const Color callEnded = Color(0xFFEF4444);

  // Dynamic Helpers for Context-Aware Theming
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) => isDark(context) ? backgroundDark : backgroundLight;
  static Color surface(BuildContext context) => isDark(context) ? surfaceDark : surfaceLight;
  static Color card(BuildContext context) => isDark(context) ? cardDark : cardLight;
  static Color textPrimary(BuildContext context) => isDark(context) ? textPrimaryDark : textPrimaryLight;
  static Color textSecondary(BuildContext context) => isDark(context) ? textSecondaryDark : textSecondaryLight;
  static Color peerBubble(BuildContext context) => isDark(context) ? peerMessageBubble : peerMessageBubbleLight;
}
