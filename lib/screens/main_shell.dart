import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);

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