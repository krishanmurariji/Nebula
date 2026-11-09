import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';

import 'home_screen.dart';
import 'search_screen.dart'; 
import 'library_screen.dart';
import 'settings_screen.dart';

final shellTabProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
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
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    // Only update provider if it was a manual swipe
    if (ref.read(shellTabProvider) != i) {
      ref.read(shellTabProvider.notifier).state = i;
    }
  }

  void goTo(int i) {
    HapticFeedback.selectionClick();
    ref.read(shellTabProvider.notifier).state = i;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes from the provider (e.g., when a child screen calls goTo)
    // and animate the PageView automatically.
    ref.listen<int>(shellTabProvider, (previous, next) {
      if (_pageCtrl.hasClients && _pageCtrl.page?.round() != next) {
        _pageCtrl.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF1C1814) : const Color(0xFFDCD8CD);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      // Just a pure PageView now, no bottom navigation bar
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: [
          HomeScreen(onNavigate: goTo),
          SearchScreen(onNavigate: goTo),
          const LibraryScreen(), // No onNavigate needed
          SettingsScreen(onNavigate: goTo),
        ],
      ),
    );
  }
}