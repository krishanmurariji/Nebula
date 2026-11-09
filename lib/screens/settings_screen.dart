import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'playback_log_screen.dart';
import 'mini_player.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const SettingsScreen({super.key, required this.onNavigate});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with TickerProviderStateMixin {

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final t = NoorTheme.byMode(isDark);
    final textCol = t.ac;
    final mutedCol = t.mute;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: NoorBackdrop()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Settings',
                            style: noorSerif(textCol, size: 38, height: 1.0)),
                        const SizedBox(height: 28),

                        // ── THEME ORBIT SELECTOR ──────────────────────────
                        _SectionLabel('VISUAL EXPERIENCE', mutedCol),
                        const SizedBox(height: 16),
                        _CircularThemeSelector(isDark: isDark),

                        const SizedBox(height: 32),

                        _SectionLabel('DATA', mutedCol),
                        const SizedBox(height: 16),

                        // ── MEMORY & STORAGE ───────────────────────────────
                        _MemoryCard(
                          label: 'Clear History',
                          subtitle: 'Wipe all playback logs',
                          icon: Icons.history_rounded,
                          onTap: () {
                            ref.read(historyProvider.notifier).clear();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Playback history cleared'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ));
                          },
                        ),
                        const SizedBox(height: 16),
                        _MemoryCard(
                          label: 'Backup Sources',
                          subtitle: 'Used if YouTube blocks or breaks',
                          icon: Icons.shield_moon_rounded,
                          onTap: () => showBackupSourcesDialog(context),
                        ),
                        const SizedBox(height: 16),
                        _MemoryCard(
                          label: 'Playback Log',
                          subtitle: 'See what the player is doing',
                          icon: Icons.bug_report_rounded,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PlaybackLogScreen())),
                        ),

                        const SizedBox(height: 32),

                        // ── DEVELOPER SECTION ──────────────────────────────
                        _SectionLabel('DEVELOPER', mutedCol),
                        const SizedBox(height: 16),
                        NoorFrame(
                          radius: 26,
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: t.soft, width: 1.5),
                                  ),
                                  child: CircleAvatar(
                                    radius: 40,
                                    backgroundColor: t.tint(0.2),
                                    backgroundImage: const CachedNetworkImageProvider(
                                      'https://avatars.githubusercontent.com/Krishan-Vineforce?size=400',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text('Krishan Murari',
                                    style: noorSerif(textCol, size: 26, height: 1.0)),
                                const SizedBox(height: 4),
                                Text('Noor  •  v1.0.0',
                                    style: TextStyle(fontSize: 12, color: mutedCol)),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    NoorRoundButton(
                                        size: 50,
                                        semanticLabel: 'LinkedIn',
                                        onTap: () => _launchUrl(
                                            'https://www.linkedin.com/in/krishan-murari/'),
                                        child: const FaIcon(FontAwesomeIcons.linkedinIn)),
                                    const SizedBox(width: 20),
                                    NoorRoundButton(
                                        size: 50,
                                        semanticLabel: 'GitHub',
                                        onTap: () => _launchUrl(
                                            'https://github.com/krishanmurariji'),
                                        child: const FaIcon(FontAwesomeIcons.github)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const MiniPlayer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 2.2));
}

class _CircularThemeSelector extends ConsumerWidget {
  final bool isDark;
  const _CircularThemeSelector({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.byMode(isDark);
    return NoorFrame(
      radius: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SizedBox(
        height: 84,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ThemeOption(
                label: 'Light',
                icon: Icons.wb_sunny_rounded,
                active: !isDark,
                onTap: () =>
                    !isDark ? null : ref.read(themeProvider.notifier).toggle()),
            AnimatedRotation(
              duration: const Duration(milliseconds: 500),
              turns: isDark ? 0.5 : 0,
              child: Icon(Icons.sync_rounded, color: t.ac, size: 28),
            ),
            _ThemeOption(
                label: 'Dark',
                icon: Icons.nightlight_round,
                active: isDark,
                onTap: () =>
                    isDark ? null : ref.read(themeProvider.notifier).toggle()),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ThemeOption(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final fg = active ? t.onAc : t.mute;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: active ? t.ac : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: active ? t.ac : t.soft, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 24),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _MemoryCard(
      {required this.label,
      required this.subtitle,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return NoorFrame(
      radius: 22,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          NoorRoundButton(size: 46, child: Icon(icon)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15, color: t.ac)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: t.mute, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.mute),
        ],
      ),
    );
  }
}
