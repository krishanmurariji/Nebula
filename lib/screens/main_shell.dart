import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  void _onPageChanged(int i) =>
      ref.read(shellTabProvider.notifier).state = i;

  void goTo(int i) {
    ref.read(shellTabProvider.notifier).state = i;
    _pageCtrl.animateToPage(i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: [
          HomeScreen(onNavigate: goTo),
          SearchScreen(onNavigate: goTo),
          LibraryScreen(onNavigate: goTo),
          SettingsScreen(onNavigate: goTo),
        ],
      ),
    );
  }
}
