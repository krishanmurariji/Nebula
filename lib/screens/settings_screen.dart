import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/noor_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../providers/gesture_settings_provider.dart';
import '../providers/library_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_search_button.dart';
import '../theme/noor_song_card.dart';
import 'mini_player.dart';
import 'playback_log_screen.dart';

/// Settings, in Noor's own look: a script title, sections between thin
/// lines, and cards with a thin copper outline.
///
///  * Gestures (first): switch off any gesture that has another way in.
///  * Library: clear the history, backup sources.
///  * Help: the playback log.
///  * About: the logo, the real version of this build, the developer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    if (!await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        NoorToast.show(context, 'Could not open the link');
      }
    }
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final t = NoorTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: t.ac, width: 0.8)),
        title: Text('Clear your history?',
            style: noorSongTitleStyle(t.ac, size: 24)),
        content: Text(
            'Every song leaves My History. Favorites, playlists and saved songs stay.',
            style: TextStyle(color: t.mute)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep', style: TextStyle(color: t.mute))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Clear',
                  style: TextStyle(color: t.ac, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyProvider.notifier).clear();
    if (context.mounted) {
      NoorToast.show(context, 'History cleared');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final on = ref.watch(gestureSettingsProvider);
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 140),
            children: [
              // ── Header ───────────────────────────────────────────────────
              SizedBox(
                height: kNoorHeaderSize,
                child: Row(children: [
                  NoorCircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Text('Settings',
                          style: noorSongTitleStyle(t.ac, size: 32))),
                  const NoorLogo(),
                ]),
              ),
              const SizedBox(height: 26),

              // ── Gestures ─────────────────────────────────────────────────
              const _Section('Gestures'),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                child: Text(
                    'Turn off any swipe you keep doing by accident. Each one has a button or tap that does the same.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: t.mute, fontSize: 12.5, height: 1.35)),
              ),
              _Card(children: [
                for (final g in NoorGesture.values)
                  _Row(
                    icon: switch (g) {
                      NoorGesture.bottomCardSwipe => Icons.swap_horiz_rounded,
                      NoorGesture.bottomCardSwipeUp => Icons.north_rounded,
                      NoorGesture.homeSwipeDownSearch => Icons.south_rounded,
                      NoorGesture.playerRecordSwipe => Icons.album_outlined,
                      NoorGesture.songCardSwipe => Icons.west_rounded,
                    },
                    title: g.title,
                    subtitle: g.subtitle,
                    trailing: NoorToggle(
                      value: on.contains(g),
                      label: g.title,
                      onChanged: (v) =>
                          ref.read(gestureSettingsProvider.notifier).set(g, v),
                    ),
                    onTap: () => ref
                        .read(gestureSettingsProvider.notifier)
                        .set(g, !on.contains(g)),
                  ),
              ]),
              const SizedBox(height: 26),

              // ── Library ──────────────────────────────────────────────────
              const _Section('Library'),
              _Card(children: [
                _Row(
                  icon: Icons.history_rounded,
                  title: 'Clear history',
                  subtitle: 'Empty My History',
                  onTap: () => _clearHistory(context, ref),
                ),
                _Row(
                  icon: Icons.shield_outlined,
                  title: 'Backup sources',
                  subtitle: 'Your own servers, used if YouTube fails',
                  onTap: () => showBackupSourcesDialog(context),
                ),
              ]),
              const SizedBox(height: 26),

              // ── Help ─────────────────────────────────────────────────────
              const _Section('Help'),
              _Card(children: [
                _Row(
                  icon: Icons.receipt_long_outlined,
                  title: 'Playback log',
                  subtitle:
                      'What the player did, to share when something fails',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PlaybackLogScreen())),
                ),
              ]),
              const SizedBox(height: 26),

              // ── About ────────────────────────────────────────────────────
              const _Section('About'),
              _Card(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                children: [
                  Column(children: [
                    const NoorLogo(size: 84),
                    const SizedBox(height: 8),
                    Text('Noor', style: noorSongTitleStyle(t.ac, size: 34)),
                    const SizedBox(height: 2),
                    Text('Music in a warm light',
                        style: TextStyle(color: t.mute, fontSize: 12.5)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.soft, width: 0.8),
                      ),
                      child: Text(AppVersion.label,
                          key: const ValueKey('app-version'),
                          style: TextStyle(
                              color: t.ac,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: t.faint, height: 1),
                    const SizedBox(height: 18),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: t.ac, width: 0.8)),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: t.wash,
                          backgroundImage: const CachedNetworkImageProvider(
                              'https://avatars.githubusercontent.com/Krishan-Vineforce?size=200'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Krishan Murari',
                                style: noorSongTitleStyle(t.ac, size: 21)),
                            Text('Made Noor',
                                style: TextStyle(color: t.mute, fontSize: 12)),
                          ],
                        ),
                      ),
                      _LinkButton(
                          icon: FontAwesomeIcons.linkedinIn,
                          label: 'LinkedIn',
                          onTap: () => _open(context,
                              'https://www.linkedin.com/in/krishan-murari/')),
                      const SizedBox(width: 8),
                      _LinkButton(
                          icon: FontAwesomeIcons.github,
                          label: 'GitHub',
                          onTap: () => _open(
                              context, 'https://github.com/krishanmurariji')),
                    ]),
                  ]),
                ],
              ),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

/// A section title between two thin lines.
class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: NoorLinedLabel(text),
      );
}

/// A card with a thin copper outline holding rows, with faint lines
/// between them.
class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: t.ac, width: 0.8),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(color: t.faint, height: 1, indent: 64, endIndent: 18),
          children[i],
        ]
      ]),
    );
  }
}

/// One setting: an icon in a thin ring, a title and a line under it, and a
/// switch or an arrow.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.ac, width: 0.8)),
            child: Icon(icon, size: 18, color: t.ac),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: t.mute, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing ?? Icon(Icons.chevron_right_rounded, color: t.mute),
        ]),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(
      {required this.icon, required this.label, required this.onTap});
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.ac, width: 0.8)),
          child: FaIcon(icon, size: 16, color: t.ac),
        ),
      ),
    );
  }
}

/// Noor's on / off switch: a thin pill; when on it fills with the accent
/// and the dot slides to the right.
class NoorToggle extends StatelessWidget {
  const NoorToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Semantics(
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? t.ac : t.bg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.ac, width: 1),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: value ? t.bg : t.ac),
            ),
          ),
        ),
      ),
    );
  }
}
