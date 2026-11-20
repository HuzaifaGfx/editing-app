import 'package:flutter/material.dart';
import 'ui/studio_screen.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QalamixApp());
}

class QalamixApp extends StatelessWidget {
  const QalamixApp({super.key});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    const amberDark = Color(0xFFD97706);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF3F5F8),
      fontFamily: 'PlusJakartaSans',
      colorScheme: const ColorScheme.light(
        primary: amberDark,
        onPrimary: Colors.white,
        secondary: amber,
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF0F172A),
        onSurfaceVariant: Color(0xFF475569),
        outline: Color(0xFFCBD5E1),
        outlineVariant: Color(0xFFE2E8F0),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: amber.withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? amberDark : const Color(0xFF64748B),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? amberDark : const Color(0xFF64748B),
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: amberDark, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0F12),
      fontFamily: 'PlusJakartaSans',
      colorScheme: const ColorScheme.dark(
        primary: amber,
        onPrimary: Colors.black,
        secondary: Color(0xFFFBBF24),
        surface: Color(0xFF16191E),
        onSurface: Color(0xFFF8FAFC),
        onSurfaceVariant: Color(0xFF94A3B8),
        outline: Color(0xFF334155),
        outlineVariant: Color(0xFF262B35),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: const Color(0xFF16191E),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF262B35)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Color(0xFF16191E),
        foregroundColor: Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: const Color(0xFF16191E),
        surfaceTintColor: Colors.transparent,
        indicatorColor: amber.withOpacity(0.20),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? amber : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? amber : const Color(0xFF94A3B8),
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111317),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2D3340)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF262B35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: amber, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F242D),
        contentTextStyle: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Qalamix',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: lightTheme,
          darkTheme: darkTheme,
          home: const StudioScreen(),
        );
      },
    );
  }
}
