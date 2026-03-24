import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../screens/player_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    if (ps.song == null) return const SizedBox.shrink();
    final song    = ps.song!;
    final playing = ps.status == NebulaPlayerStatus.playing;
    final durMs   = ps.duration.inMilliseconds;
    final posMs   = ps.position.inMilliseconds;
    final prog    = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlayerScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1A2E).withOpacity(0.25),
              blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    width: 40, height: 40, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 40, height: 40,
                      color: Colors.white12,
                      child: const Icon(Icons.music_note,
                          color: Colors.white38, size: 18))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(song.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: Colors.white)),
                    Text(song.artist, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11, color: Colors.white54)),
                  ],
                )),
                GestureDetector(
                  onTap: () =>
                      ref.read(playerProvider.notifier).togglePlay(),
                  child: Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: const Color(0xFF1A1A2E), size: 18)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => ref.read(playerProvider.notifier).skipNext(),
                  child: const Icon(Icons.skip_next_rounded,
                      color: Colors.white54, size: 22)),
              ]),
            ),
            // Progress line
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: prog,
                backgroundColor: Colors.white12,
                color: Colors.white,
                minHeight: 2)),
          ]),
        ),
      ),
    );
  }
}
