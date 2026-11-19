import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../theme/noor_palette.dart';

import 'home_screen.dart';

/// The app has one main page, Home. Search lives inside Home (the Search
/// button), playlists are cards in Home's slider, and Settings opens from
/// the gear next to the search filters.
const kHomePage = 0;

final shellTabProvider = StateProvider<int>((ref) => kHomePage);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _askNotificationPermission());
  }

  /// Android 13+ hides the media notification and lock-screen controls unless
  /// the user allows notifications. Ask once, politely, and never block on it.
  Future<void> _askNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('asked_notification_permission') ?? false) return;
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
      await prefs.setBool('asked_notification_permission', true);
    } catch (_) {/* playback works without it */}
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final bg = NoorTheme.byMode(isDark).bg;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: const HomeScreen(),
    );
  }
}
