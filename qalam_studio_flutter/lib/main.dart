import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ui/studio_screen.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

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
    systemNavigationBarColor: isDarkStart ? const Color(0xFF1E222B) : Colors.white,
    systemNavigationBarIconBrightness: isDarkStart ? Brightness.light : Brightness.dark,
  ));
  runApp(const QalamixApp());
}

class QalamixApp extends StatelessWidget {
  const QalamixApp({super.key});

  @override
  Widget build(BuildContext context) {
    const amberNib = Color(0xFFF59E0B);
    const amberDark = Color(0xFFFBBF24);
    const inkOnAmber = Color(0xFF1C1917);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF6F4EF),
      fontFamily: 'PlusJakartaSans',
      colorScheme: const ColorScheme.light(
        primary: amberNib,
        onPrimary: inkOnAmber,
        secondary: Color(0xFFB45309),
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Color(0xFF1C1917),
        onSurfaceVariant: Color(0xFF57534E),
        outline: Color(0xFFD6D0C4),
        outlineVariant: Color(0xFFE7E2D8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amberNib,
          foregroundColor: inkOnAmber,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE7E2D8)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1C1917),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFFFF6E0),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? const Color(0xFFB45309) : const Color(0xFF64748B),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? const Color(0xFFB45309) : const Color(0xFF64748B),
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAF8F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE7E2D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE7E2D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: amberNib, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1C1917),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF12141A),
      fontFamily: 'PlusJakartaSans',
      colorScheme: const ColorScheme.dark(
        primary: amberNib,
        onPrimary: inkOnAmber,
        secondary: amberDark,
        onSecondary: inkOnAmber,
        surface: Color(0xFF1E222B),
        onSurface: Color(0xFFF8FAFC),
        onSurfaceVariant: Color(0xFF94A3B8),
        outline: Color(0xFF3A4150),
        outlineVariant: Color(0xFF2C313C),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amberNib,
          foregroundColor: inkOnAmber,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: const Color(0xFF1E222B),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF2C313C)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Color(0xFF1E222B),
        foregroundColor: Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: const Color(0xFF1E222B),
        surfaceTintColor: Colors.transparent,
        indicatorColor: amberNib.withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? amberDark : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: sel ? amberDark : const Color(0xFF94A3B8),
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF12141A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2C313C)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2C313C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: amberDark, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E222B),
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
          systemNavigationBarColor: isDark ? const Color(0xFF1E222B) : Colors.white,
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
