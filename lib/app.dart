import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/player_provider.dart';
import 'theme/noor_palette.dart';
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
      title: 'Noor',
      scaffoldMessengerKey: _messengerKey,
      builder: (context, child) =>
          ResponsiveFrame(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _light(),
      darkTheme: _dark(),
      home: const MainShell(),
    );
  }

  ThemeData _light() => _themeFor(NoorTheme.light);
  ThemeData _dark() => _themeFor(NoorTheme.dark);

  ThemeData _themeFor(NoorTheme t) => ThemeData(
        useMaterial3: true,
        brightness: t.isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: t.bg,
        canvasColor: t.bg,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        textTheme: ThemeData(brightness: t.isDark ? Brightness.dark : Brightness.light)
            .textTheme
            .apply(bodyColor: t.ac, displayColor: t.ac),
        colorScheme: ColorScheme(
          brightness: t.isDark ? Brightness.dark : Brightness.light,
          primary: t.ac,
          onPrimary: t.bg,
          secondary: t.ac,
          onSecondary: t.bg,
          error: const Color(0xFFA83836),
          onError: Colors.white,
          surface: t.bg,
          onSurface: t.ac,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: t.ac,
          contentTextStyle: TextStyle(color: t.bg),
          behavior: SnackBarBehavior.floating,
        ),
      );
}


/// Widest the app content is allowed to get. The layouts are designed for a
/// phone; on tablets, unfolded foldables and large windows the content stays
/// phone-sized and centered instead of stretching into odd proportions.
const double kMaxContentWidth = 600;

/// Text-scale limits: below 0.85 text becomes unreadable, above 1.35 the fixed
/// phone layouts start to overflow. (The OS may still go higher or lower.)
const double kMinTextScale = 0.85;
const double kMaxTextScale = 1.35;

/// Makes the whole app behave on any screen:
///  * clamps the system font scale so layouts cannot overflow,
///  * caps and centers the content width on wide screens,
///  * lets tablets rotate while phones stay in portrait.
class ResponsiveFrame extends StatefulWidget {
  const ResponsiveFrame({super.key, required this.child});
  final Widget child;

  @override
  State<ResponsiveFrame> createState() => _ResponsiveFrameState();
}

class _ResponsiveFrameState extends State<ResponsiveFrame> {
  bool? _wasTablet;

  void _applyOrientation(bool isTablet) {
    if (_wasTablet == isTablet) return;
    _wasTablet = isTablet;
    SystemChrome.setPreferredOrientations(isTablet
        ? DeviceOrientation.values
        : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _applyOrientation(mq.size.shortestSide >= 600);

    final width = math.min(mq.size.width, kMaxContentWidth);
    final data = mq.copyWith(
      size: Size(width, mq.size.height),
      textScaler: mq.textScaler
          .clamp(minScaleFactor: kMinTextScale, maxScaleFactor: kMaxTextScale),
    );

    Widget content = MediaQuery(data: data, child: widget.child);
    if (mq.size.width > kMaxContentWidth) {
      content = ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: SizedBox(width: width, child: content)),
      );
    }
    return content;
  }
}
