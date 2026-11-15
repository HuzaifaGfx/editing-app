import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'storage/local_project_store.dart';
import 'ui/studio_screen.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await LocalProjectStore.instance.database;
  runApp(const QalamStudioApp());
}

class QalamStudioApp extends StatelessWidget {
  const QalamStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Qalam Studio',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F5F7),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF59E0B),
              surface: Color(0xFFFFFFFF),
              onSurface: Color(0xFF0F172A),
            ),
            cardColor: Colors.white,
            fontFamily: 'PlusJakartaSans',
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF111317),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF59E0B),
              surface: Color(0xFF191C22),
              onSurface: Color(0xFFF8FAFC),
            ),
            fontFamily: 'PlusJakartaSans',
            useMaterial3: true,
          ),
          home: const StudioScreen(),
        );
      },
    );
  }
}
