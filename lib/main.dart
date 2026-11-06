import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/app_log.dart';
import 'services/audio_handler.dart';

/// Platforms the audio stack (just_audio + audio_service) really supports.
bool get isSupportedPlatform {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing may fail silently: every uncaught error lands in the Playback Log
  // (Settings → Playback Log) instead of vanishing or killing the app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    nlog('[N] flutter error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    nlog('[N] uncaught error: $error');
    return true; // handled: do not crash the app
  };

  // Browsers block calls to YouTube (CORS) and desktop has no audio backend
  // here, so say so clearly instead of failing every search.
  if (!isSupportedPlatform) {
    runApp(const _UnsupportedPlatformApp());
    return;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  unawaited(_removeLegacyApiKey());
  runApp(const _Bootstrap());
}

/// Earlier versions stored a YouTube Data API key on the device. It is no
/// longer used, so do not leave a credential lying around.
Future<void> _removeLegacyApiKey() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove('nebula_api_key');
  } catch (_) {}
}

Future<NebulaAudioHandler> _initAudio() => AudioService.init<NebulaAudioHandler>(
      builder: () => NebulaAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nebula.nebula_music_player.audio',
        androidNotificationChannelName: 'Nebula Music',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );

/// Starts the audio service and shows a retryable error screen if that fails
/// (for example a device with a broken media stack) instead of a blank crash.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<NebulaAudioHandler> _future = _initAudio();

  void _retry() => setState(() => _future = _initAudio());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NebulaAudioHandler>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return ProviderScope(
            overrides: [audioHandlerProvider.overrideWithValue(snap.data!)],
            child: const NebulaApp(),
          );
        }
        if (snap.hasError) {
          nlog('[N] audio init failed: ${snap.error}');
          return _MessageApp(
            icon: Icons.error_outline_rounded,
            title: 'Audio could not start',
            message: 'Nebula could not start the audio service on this device.',
            action: FilledButton(onPressed: _retry, child: const Text('Try again')),
          );
        }
        return const _MessageApp(
          icon: Icons.graphic_eq_rounded,
          title: 'Nebula',
          message: 'Starting…',
        );
      },
    );
  }
}

class _UnsupportedPlatformApp extends StatelessWidget {
  const _UnsupportedPlatformApp();
  @override
  Widget build(BuildContext context) => const _MessageApp(
        icon: Icons.phone_android_rounded,
        title: 'Run Nebula on Android or iOS',
        message: 'Browsers block requests to YouTube and this platform has no '
            'audio backend, so Nebula only works as a phone app.',
      );
}

class _MessageApp extends StatelessWidget {
  const _MessageApp(
      {required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 56),
                    const SizedBox(height: 20),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    if (action != null) ...[const SizedBox(height: 24), action!],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
