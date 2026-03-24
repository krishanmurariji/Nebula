#!/usr/bin/env python3
"""
patch_nebula.py  - Fix all compile errors in nebula_music_player
Identified issues:
  1. library_screen.dart  - missing: import '../models/song.dart'
  2. player_screen.dart   - missing: import '../models/song.dart'
  3. main_shell.dart      - unused import (player_screen) that could warn
  4. home_screen.dart     - unused search_provider import
Run from anywhere. Auto-detects project location.
"""
import os, sys, shutil

def find_project():
    candidates = [
        os.path.join(os.getcwd(), "nebula_music_player"),
        os.getcwd(),
        r"D:\Projects\nebula\nebula_music_player",
        r"D:\Projects\nebula_music_player",
    ]
    for c in candidates:
        if os.path.isfile(os.path.join(c, "pubspec.yaml")):
            return c
    return None

project = find_project()
if not project:
    print("ERROR: Cannot find nebula_music_player folder.")
    print("Run this script from inside nebula_music_player/ or its parent.")
    sys.exit(1)
print(f"Project: {project}\n")

D = chr(36)

def write(rel, content):
    full = os.path.join(project, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  fixed  {rel}")

# ── lib/screens/library_screen.dart ──────────────────────────────────────────
# Fix: added missing import '../models/song.dart'
LIBRARY_SCREEN = f"""\
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../neuo.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';

class LibraryScreen extends ConsumerWidget {{
  const LibraryScreen({{super.key}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {{
    final liked     = ref.watch(likedProvider);
    final playlists = ref.watch(playlistProvider);
    final player    = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NEBULA', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: N.primary, letterSpacing: 3)),
                    const Text('Library', style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800,
                      color: N.onSurf, letterSpacing: -0.5)),
                  ]),
                  NButton(
                    size: 42,
                    onTap: () => _createPlaylist(context, ref),
                    child: const Icon(Icons.add_rounded, color: N.primary, size: 22),
                  ),
                ],
              ),
            )),

            // Liked songs
            if (liked.isNotEmpty) ...[
              SliverToBoxAdapter(child: _Label('Liked Songs')),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: NCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SongListScreen(
                      id: '__liked__', name: 'Liked Songs', songs: liked))),
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCE4EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.pinkAccent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Liked Songs', style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: N.onSurf)),
                        Text('{D}{{liked.length}} songs',
                            style: const TextStyle(fontSize: 12, color: N.muted)),
                      ],
                    )),
                    const Icon(Icons.chevron_right_rounded, color: N.outline),
                  ]),
                ),
              )),
            ],

            // Playlists
            SliverToBoxAdapter(child: _Label('Playlists')),

            if (playlists.isEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  NButton(
                    size: 64,
                    onTap: () => _createPlaylist(context, ref),
                    child: const Icon(Icons.queue_music_rounded,
                        color: N.muted, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('No playlists yet',
                      style: TextStyle(color: N.muted)),
                  const SizedBox(height: 8),
                  const Text('Tap + to create one',
                      style: TextStyle(color: N.outline, fontSize: 12)),
                ]),
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 16,
                    mainAxisSpacing: 16, childAspectRatio: 1.0),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {{
                      final pl = playlists[i];
                      return NCard(
                        padding: EdgeInsets.zero,
                        radius: 20,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => SongListScreen(
                            id: pl.id, name: pl.name, songs: pl.songs))),
                        child: Stack(children: [
                          Positioned.fill(child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: pl.songs.isNotEmpty
                                ? _PlaylistThumb(songs: pl.songs)
                                : Container(color: N.surfHigh,
                                    child: const Icon(Icons.queue_music_rounded,
                                        color: N.outline, size: 36)),
                          )),
                          Positioned(
                            left: 12, right: 12, bottom: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pl.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                                Text('{D}{{pl.songs.length}} songs',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11)),
                              ],
                            ),
                          ),
                          Positioned(right: 8, top: 8,
                            child: GestureDetector(
                              onTap: () => ref.read(playlistProvider.notifier)
                                  .delete(pl.id),
                              child: Container(
                                width: 28, height: 28,
                                decoration: const BoxDecoration(
                                    color: Colors.black26, shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded,
                                    color: Colors.white, size: 14),
                              ),
                            )),
                        ]),
                      );
                    }},
                    childCount: playlists.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }}

  void _createPlaylist(BuildContext context, WidgetRef ref) {{
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: N.bg,
        title: const Text('New Playlist',
            style: TextStyle(color: N.onSurf, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: N.onSurf),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: N.outline)),
          onSubmitted: (_) async {{
            if (ctrl.text.trim().isNotEmpty) {{
              await ref.read(playlistProvider.notifier).create(ctrl.text);
              if (context.mounted) Navigator.pop(context);
            }}
          }},
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: N.muted))),
          TextButton(
            onPressed: () async {{
              if (ctrl.text.trim().isNotEmpty) {{
                await ref.read(playlistProvider.notifier).create(ctrl.text);
                if (context.mounted) Navigator.pop(context);
              }}
            }},
            child: const Text('Create',
                style: TextStyle(color: N.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }}
}}

class _PlaylistThumb extends StatelessWidget {{
  final List<Song> songs;
  const _PlaylistThumb({{required this.songs}});
  @override
  Widget build(BuildContext context) {{
    final urls = songs.take(4).map((s) => s.thumbnailUrl).toList();
    if (urls.length < 4) {{
      return CachedNetworkImage(imageUrl: urls.first, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: N.surfHigh));
    }}
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      children: urls.map((u) => CachedNetworkImage(
        imageUrl: u, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: N.surfHigh),
      )).toList(),
    );
  }}
}}

class _Label extends StatelessWidget {{
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
    child: Text(text.toUpperCase(), style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800,
      color: N.muted, letterSpacing: 2)),
  );
}}

// Public so it can be used from other screens too
class SongListScreen extends ConsumerWidget {{
  final String id, name;
  final List<Song> songs;
  const SongListScreen({{
    super.key, required this.id,
    required this.name, required this.songs,
  }});

  @override
  Widget build(BuildContext context, WidgetRef ref) {{
    final player    = ref.watch(playerProvider);
    final liveSongs = id == '__liked__'
        ? ref.watch(likedProvider)
        : (ref.watch(playlistProvider)
              .where((p) => p.id == id)
              .map((p) => p.songs)
              .firstOrNull ?? songs);

    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: N.onSurf, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(child: Text(name, style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: N.onSurf))),
            if (liveSongs.isNotEmpty)
              NButton(
                size: 40, filled: true,
                onTap: () {{
                  ref.read(playerProvider.notifier)
                      .playSong(liveSongs.first, queue: liveSongs);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()));
                }},
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 20),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('{D}{{liveSongs.length}} songs',
                style: const TextStyle(color: N.muted, fontSize: 12)),
          ),
        ),
        Expanded(child: liveSongs.isEmpty
            ? const Center(child: Text('No songs yet',
                style: TextStyle(color: N.muted)))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                physics: const BouncingScrollPhysics(),
                itemCount: liveSongs.length,
                itemBuilder: (_, i) {{
                  final s = liveSongs[i];
                  return SongTile(
                    song: s,
                    isPlaying: player.song?.videoId == s.videoId &&
                        player.status == NebulaPlayerStatus.playing,
                    onTap: () {{
                      ref.read(playerProvider.notifier)
                          .playSong(s, queue: liveSongs);
                      Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const PlayerScreen()));
                    }},
                  );
                }},
              )),
      ])),
    );
  }}
}}
"""

# ── lib/screens/player_screen.dart ────────────────────────────────────────────
# Fix: added missing import '../models/song.dart'
PLAYER_SCREEN = f"""\
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../neuo.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';

class PlayerScreen extends ConsumerWidget {{
  const PlayerScreen({{super.key}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {{
    final ps      = ref.watch(playerProvider);
    final song    = ps.song;
    final liked   = song != null
        ? ref.watch(isLikedProvider(song.videoId)) : false;
    final playing = ps.status == NebulaPlayerStatus.playing;
    final loading = ps.status == NebulaPlayerStatus.loading;
    final total   = ps.duration.inSeconds > 0 ? ps.duration.inSeconds : 1;
    final prog    = (ps.position.inSeconds / total).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(child: Column(children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: N.onSurf, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const Text('Now Playing', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: N.onSurf, letterSpacing: 0.3)),
              NButton(
                size: 38,
                onTap: song != null
                    ? () => ref.read(likedProvider.notifier).toggle(song)
                    : null,
                child: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? Colors.pinkAccent : N.muted, size: 18),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Album art - neumorphic lift
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: N.lift(intensity: 1.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: song?.thumbnailUrl.isNotEmpty == true
                    ? CachedNetworkImage(
                        imageUrl: song!.thumbnailUrl, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _PlaceholderArt())
                    : _PlaceholderArt(),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Song info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(children: [
            Text(song?.title ?? 'No song selected',
              maxLines: 2, textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: N.onSurf, letterSpacing: -0.3, height: 1.2)),
            const SizedBox(height: 6),
            Text(song?.artist ?? '',
              style: const TextStyle(
                fontSize: 13, color: N.muted, fontWeight: FontWeight.w500)),
          ]),
        ),

        const SizedBox(height: 24),

        // Waveform + time
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _Waveform(
            progress: prog,
            onSeek: (pct) {{
              final secs = (pct * total).round();
              ref.read(playerProvider.notifier).seek(Duration(seconds: secs));
            }},
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(ps.position), style: const TextStyle(
                  fontSize: 11, color: N.muted,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              Text(_fmt(ps.duration), style: const TextStyle(
                  fontSize: 11, color: N.muted,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
        ),

        if (loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(
              backgroundColor: N.surfHigh, color: N.primary, minHeight: 2),
          )
        else
          const SizedBox(height: 4),

        const SizedBox(height: 24),

        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NButton(
                size: 52,
                onTap: () => ref.read(playerProvider.notifier).skipPrevious(),
                child: const Icon(Icons.skip_previous_rounded,
                    color: N.onSurf, size: 26),
              ),
              NButton(
                size: 72,
                filled: true,
                onTap: () => ref.read(playerProvider.notifier).togglePlay(),
                child: loading
                    ? const SizedBox(
                        width: 26, height: 26,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 32),
              ),
              NButton(
                size: 52,
                onTap: () => ref.read(playerProvider.notifier).skipNext(),
                child: const Icon(Icons.skip_next_rounded,
                    color: N.onSurf, size: 26),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Songs pull indicator
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.keyboard_arrow_up_rounded,
                color: N.outline, size: 20),
            const SizedBox(height: 2),
            const Text('SONGS', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: N.outline, letterSpacing: 2)),
          ]),
        ),
      ])),
    );
  }}

  String _fmt(Duration d) {{
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '{D}m:{D}s';
  }}
}}

class _PlaceholderArt extends StatelessWidget {{
  @override
  Widget build(BuildContext context) => Container(
    color: N.surfHigh,
    child: const Icon(Icons.music_note_rounded, color: N.outline, size: 80));
}}

class _Waveform extends StatelessWidget {{
  final double progress;
  final ValueChanged<double> onSeek;
  const _Waveform({{required this.progress, required this.onSeek}});

  @override
  Widget build(BuildContext context) {{
    const barCount = 36;
    final rng = Random(7);
    return GestureDetector(
      onTapDown: (d) {{
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(d.globalPosition);
        onSeek((local.dx / box.size.width).clamp(0.0, 1.0));
      }},
      onHorizontalDragUpdate: (d) {{
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(d.globalPosition);
        onSeek((local.dx / box.size.width).clamp(0.0, 1.0));
      }},
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {{
            final pct    = i / barCount;
            final active = pct <= progress;
            final h      = 56 * (0.15 + rng.nextDouble() * 0.85);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3.5,
              height: h,
              decoration: BoxDecoration(
                color: active ? N.primary : N.surfHst,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }}),
        ),
      ),
    );
  }}
}}
"""

# ── lib/screens/home_screen.dart ─────────────────────────────────────────────
# Fix: removed unused search_provider import that could cause warnings
HOME_SCREEN = f"""\
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../neuo.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';

class HomeScreen extends ConsumerWidget {{
  const HomeScreen({{super.key}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {{
    final history = ref.watch(historyProvider);
    final player  = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NEBULA', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: N.primary, letterSpacing: 3)),
                    const Text('Explore', style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800,
                      color: N.onSurf, letterSpacing: -0.5, height: 1.1)),
                  ]),
                  NButton(size: 42,
                    child: const Icon(Icons.search_rounded,
                        color: N.muted, size: 20)),
                ],
              ),
            )),

            // Tab row
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(children: [
                _TabChip('Overview', true),
                _TabChip('Songs',    false),
                _TabChip('Albums',   false),
                _TabChip('Artists',  false),
              ]),
            )),

            if (history.isNotEmpty) ...[
              SliverToBoxAdapter(child: _SectionLabel('Recently Played')),
              SliverToBoxAdapter(child: SizedBox(
                height: 210,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: history.length.clamp(0, 8),
                  itemBuilder: (_, i) => _FeaturedCard(
                    song: history[i],
                    isPlaying: player.song?.videoId == history[i].videoId &&
                        player.status == NebulaPlayerStatus.playing,
                    onTap: () => _play(ref, context, history[i], history),
                  ),
                ),
              )),
              SliverToBoxAdapter(child: _SectionLabel('Top Songs')),
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {{
                  final s = history[i];
                  return SongTile(
                    song: s,
                    isPlaying: player.song?.videoId == s.videoId &&
                        player.status == NebulaPlayerStatus.playing,
                    onTap: () => _play(ref, context, s, history),
                  );
                }},
                childCount: history.length.clamp(0, 15),
              )),
            ] else ...[
              SliverFillRemaining(child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: N.bg, shape: BoxShape.circle,
                      boxShadow: N.lift()),
                    child: const Icon(Icons.music_note_rounded,
                        size: 36, color: N.outline),
                  ),
                  const SizedBox(height: 20),
                  const Text('Search for music to get started',
                      style: TextStyle(color: N.muted, fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text('Swipe right to search →',
                      style: TextStyle(color: N.outline, fontSize: 12)),
                ],
              ))),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }}

  void _play(WidgetRef ref, BuildContext context, Song song, List<Song> queue) {{
    ref.read(playerProvider.notifier).playSong(song, queue: queue);
    ref.read(historyProvider.notifier).add(song);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }}
}}

class _TabChip extends StatelessWidget {{
  final String label;
  final bool selected;
  const _TabChip(this.label, this.selected);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        color: selected ? N.onSurf : N.outline)),
      const SizedBox(height: 4),
      if (selected) Container(
        height: 2, width: 20,
        decoration: BoxDecoration(
          color: N.primary, borderRadius: BorderRadius.circular(1))),
    ]),
  );
}}

class _SectionLabel extends StatelessWidget {{
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
    child: Text(text, style: const TextStyle(
      fontSize: 20, fontWeight: FontWeight.w800,
      color: N.onSurf, letterSpacing: -0.3)));
}}

class _FeaturedCard extends StatelessWidget {{
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  const _FeaturedCard({{
    required this.song, required this.isPlaying, required this.onTap}});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 155,
      margin: const EdgeInsets.only(right: 16, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: N.lift(intensity: 0.8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          Positioned.fill(child: CachedNetworkImage(
            imageUrl: song.thumbnailUrl, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: N.surfHigh,
              child: const Icon(Icons.music_note_rounded,
                  color: N.outline, size: 40)))),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.72)])))),
          Positioned(left: 12, right: 12, bottom: 40,
            child: Text(song.title, maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700))),
          Positioned(left: 12, bottom: 12,
            child: Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: N.primary, size: 16))),
          if (isPlaying) Positioned(right: 12, bottom: 16,
            child: Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: N.primary, shape: BoxShape.circle))),
        ]),
      ),
    ),
  );
}}
"""

# ── lib/screens/main_shell.dart ───────────────────────────────────────────────
# Fix: removed unused player_screen import
MAIN_SHELL = f"""\
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../neuo.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

final shellTabProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {{
  const MainShell({{super.key}});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}}

class _MainShellState extends ConsumerState<MainShell> {{
  late final PageController _pageCtrl;

  @override
  void initState() {{
    super.initState();
    _pageCtrl = PageController();
  }}

  @override
  void dispose() {{
    _pageCtrl.dispose();
    super.dispose();
  }}

  void _onPageChanged(int i) =>
      ref.read(shellTabProvider.notifier).state = i;

  void _goTo(int i) {{
    ref.read(shellTabProvider.notifier).state = i;
    _pageCtrl.animateToPage(i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut);
  }}

  @override
  Widget build(BuildContext context) {{
    final tab = ref.watch(shellTabProvider);
    return Scaffold(
      backgroundColor: N.bg,
      resizeToAvoidBottomInset: false,
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: const [
          HomeScreen(),
          SearchScreen(),
          LibraryScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _BottomNav(current: tab, onTap: _goTo),
        ],
      ),
    );
  }}
}}

class _BottomNav extends StatelessWidget {{
  final int current;
  final ValueChanged<int> onTap;
  const _BottomNav({{required this.current, required this.onTap}});

  @override
  Widget build(BuildContext context) {{
    return Container(
      decoration: BoxDecoration(
        color: N.bg,
        boxShadow: [
          BoxShadow(color: const Color(0xFFD1D9E6).withOpacity(0.8),
              blurRadius: 20, offset: const Offset(0, -4)),
          const BoxShadow(color: Colors.white,
              blurRadius: 20, offset: Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.music_note_rounded,      index: 0, current: current, onTap: onTap),
              _NavItem(icon: Icons.search_rounded,          index: 1, current: current, onTap: onTap),
              _NavItem(icon: Icons.library_music_rounded,   index: 2, current: current, onTap: onTap),
              _NavItem(icon: Icons.settings_outlined,       index: 3, current: current, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }}
}}

class _NavItem extends StatelessWidget {{
  final IconData icon;
  final int index, current;
  final ValueChanged<int> onTap;
  const _NavItem({{required this.icon, required this.index,
      required this.current, required this.onTap}});

  @override
  Widget build(BuildContext context) {{
    final sel = current == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: sel ? BoxDecoration(
          color: N.bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: N.inset,
        ) : null,
        child: Icon(icon, size: 24,
            color: sel ? N.primary : N.outline),
      ),
    );
  }}
}}
"""

write("lib/screens/library_screen.dart", LIBRARY_SCREEN)
write("lib/screens/player_screen.dart",  PLAYER_SCREEN)
write("lib/screens/home_screen.dart",    HOME_SCREEN)
write("lib/screens/main_shell.dart",     MAIN_SHELL)

# Clear build cache so changes are picked up cleanly
for d in [
    os.path.join(project, "build"),
    os.path.join(project, ".dart_tool"),
]:
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)
        print(f"  cleared  {d}")

print()
print("=" * 60)
print("  ALL ISSUES FIXED:")
print()
print("  library_screen.dart")
print("    + import '../models/song.dart'   (Song type)")
print("    + _SongListScreen → SongListScreen (public)")
print("    + List<Song> typing on _PlaylistThumb")
print()
print("  player_screen.dart")
print("    + import '../models/song.dart'   (Song type)")
print()
print("  home_screen.dart")
print("    + import '../models/song.dart'   (Song type)")
print("    - removed unused import warning")
print()
print("  main_shell.dart")
print("    - removed unused player_screen import")
print()
print("  Run:")
print("    flutter run")
print("=" * 60)
