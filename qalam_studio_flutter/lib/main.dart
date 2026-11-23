import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ui/studio_screen.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

Future<void> saveAppThemeMode(ThemeMode mode) async {
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'qalamix_theme_mode.txt'));
    final value = mode == ThemeMode.dark
        ? 'dark'
        : (mode == ThemeMode.system ? 'system' : 'light');
    await file.writeAsString(value);
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'qalamix_theme_mode.txt'));
    if (file.existsSync()) {
      final raw = file.readAsStringSync().trim();
      if (raw == 'dark') {
        appThemeMode.value = ThemeMode.dark;
      } else if (raw == 'system') {
        appThemeMode.value = ThemeMode.system;
      } else {
        appThemeMode.value = ThemeMode.light;
      }
    }
  } catch (_) {}

  final isDarkStart = appThemeMode.value == ThemeMode.dark;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDarkStart ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: isDarkStart ? const Color(0xFF16191E) : Colors.white,
    systemNavigationBarIconBrightness: isDarkStart ? Brightness.light : Brightness.dark,
  ));
  runApp(const QalamixApp());
}

class QalamixApp extends StatelessWidget {
  const QalamixApp({super.key});

  @override
  Widget build(BuildContext context) {
    const inkBlack = Color(0xFF111317);
    const inkSlate = Color(0xFF334155);
    const inkWhite = Color(0xFFF8FAFC);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF3F5F8),
      fontFamily: 'PlusJakartaSans',
      colorScheme: const ColorScheme.light(
        primary: inkBlack,
        onPrimary: Colors.white,
        secondary: inkSlate,
        surface: Colors.white,
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
        indicatorColor: const Color(0xFFF59E0B).withOpacity(0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? inkBlack : const Color(0xFF64748B),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? const Color(0xFFD97706) : const Color(0xFF64748B),
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
          borderSide: const BorderSide(color: inkBlack, width: 1.5),
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
        primary: inkWhite,
        onPrimary: inkBlack,
        secondary: Color(0xFF94A3B8),
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
        indicatorColor: const Color(0xFFF59E0B).withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? inkWhite : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
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
          borderSide: const BorderSide(color: inkWhite, width: 1.5),
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
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark ? const Color(0xFF16191E) : Colors.white,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ));
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
