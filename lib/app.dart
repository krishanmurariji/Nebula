import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/player_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/main_shell.dart';

final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

class NebulaApp extends ConsumerWidget {
  const NebulaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    ref.listen<String?>(playerProvider.select((s) => s.notice), (_, n) {
      if (n == null) return;
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(n), duration: const Duration(seconds: 3)));
    });
    return MaterialApp(
      title: 'Nebula',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _light(),
      darkTheme: _dark(),
      home: const MainShell(),
    );
  }

  ThemeData _light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFEDF2F7),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4993FC),
      surface: Color(0xFFEDF2F7),
      onSurface: Color(0xFF1A1A2E),
    ),
  );

  ThemeData _dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4993FC),
      surface: Color(0xFF161B22),
      onSurface: Colors.white,
    ),
  );
}
