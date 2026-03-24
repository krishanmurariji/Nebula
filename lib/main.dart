import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  final handler = await AudioService.init<NebulaAudioHandler>(
    builder: () => NebulaAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nebula.nebula_music_player.audio',
      androidNotificationChannelName: 'Nebula Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(ProviderScope(
    overrides: [audioHandlerProvider.overrideWithValue(handler)],
    child: const NebulaApp(),
  ));
}
