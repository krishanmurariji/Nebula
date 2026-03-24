import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
    (ref) => ThemeNotifier());

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = (p.getBool('dark_mode') ?? false)
        ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggle() async {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    final p = await SharedPreferences.getInstance();
    await p.setBool('dark_mode', state == ThemeMode.dark);
  }

  bool get isDark => state == ThemeMode.dark;
}
