import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/api_key_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'onboarding_screen.dart';
import 'mini_player.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const SettingsScreen({super.key, required this.onNavigate});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with TickerProviderStateMixin {
  bool _showKey = false;

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
    final apiKey = ref.watch(apiKeyProvider);
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    
    // Theme Colors
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    final shadowD = isDark ? Colors.black54 : const Color(0xFFC8D3DF);
    final shadowL = isDark ? const Color(0xFF1E2530) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
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
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: textCol,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── THEME ORBIT SELECTOR ──────────────────────────────────
                    _SectionLabel('VISUAL EXPERIENCE', mutedCol),
                    const SizedBox(height: 16),
                    _CircularThemeSelector(
                      isDark: isDark,
                      cardBg: cardBg,
                      shadowD: shadowD,
                      shadowL: shadowL,
                    ),

                    const SizedBox(height: 32),

                    // ── API INTEGRATION ────────────────────────────────────────
                    _SectionLabel('API & DATA', mutedCol),
                    const SizedBox(height: 16),
                    _NeumorphicContainer(
                      cardBg: cardBg,
                      shadowD: shadowD,
                      shadowL: shadowL,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vpn_key_rounded,
                                  color: Color(0xFF4993FC), size: 20),
                              const SizedBox(width: 12),
                              Text('YouTube API Key',
                                  style: TextStyle(
                                      color: textCol, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              IconButton(
                                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility,
                                    color: mutedCol, size: 18),
                                onPressed: () => setState(() => _showKey = !_showKey),
                              )
                            ],
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: bg, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              _showKey
                                  ? (apiKey.isEmpty ? "Not configured" : apiKey)
                                  : "••••••••••••••••••••••••",
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: textCol),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: _ActionBtn(
                                      label: 'Update',
                                      icon: Icons.refresh,
                                      onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => const OnboardingScreen())))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _ActionBtn(
                                      label: 'Reset',
                                      icon: Icons.delete_sweep,
                                      isDanger: true,
                                      onTap: () =>
                                          ref.read(apiKeyProvider.notifier).clear())),
                            ],
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── MEMORY & STORAGE ───────────────────────────────────────
                    _MemoryCard(
                      label: 'Clear History',
                      subtitle: 'Wipe all playback logs',
                      icon: Icons.history_rounded,
                      iconColor: Colors.redAccent,
                      cardBg: cardBg,
                      shadowD: shadowD,
                      shadowL: shadowL,
                      onTap: () {
                        ref.read(historyProvider.notifier).clear();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text('Playback history shredded!'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: const Color(0xFF1A2540),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ));
                      },
                    ),

                    const SizedBox(height: 32),

                    // ── DEVELOPER SECTION ──────────────────────────────────────
                    _SectionLabel('DEVELOPER', mutedCol),
                    const SizedBox(height: 16),
                    _NeumorphicContainer(
                      cardBg: cardBg,
                      shadowD: shadowD,
                      shadowL: shadowL,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF4993FC).withOpacity(0.5),
                                  width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: const CachedNetworkImageProvider(
                                'https://avatars.githubusercontent.com/Krishan-Vineforce?size=400',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Krishan Murari',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: textCol)),
                          Text('v1.0.0 • The Sonic Nebula',
                              style: TextStyle(fontSize: 12, color: mutedCol)),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _SocialCircle(
                                  icon: FontAwesomeIcons.linkedinIn,
                                  color: const Color(0xFF0077B5),
                                  onTap: () => _launchUrl(
                                      'https://www.linkedin.com/in/krishan-murari/')),
                              const SizedBox(width: 20),
                              _SocialCircle(
                                  icon: FontAwesomeIcons.github,
                                  color: isDark ? Colors.white : const Color(0xFF181717),
                                  onTap: () => _launchUrl(
                                      'https://github.com/krishanmurariji')),
                            ],
                          )
                        ],
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
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 2));
}

class _CircularThemeSelector extends ConsumerWidget {
  final bool isDark;
  final Color cardBg, shadowD, shadowL;
  const _CircularThemeSelector(
      {required this.isDark,
      required this.cardBg,
      required this.shadowD,
      required this.shadowL});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(color: shadowD, blurRadius: 10, offset: const Offset(5, 5)),
          BoxShadow(color: shadowL, blurRadius: 10, offset: const Offset(-5, -5))
        ],
      ),
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
            child: const Icon(Icons.sync_rounded,
                color: Color(0xFF4993FC), size: 28),
          ),
          _ThemeOption(
              label: 'Dark',
              icon: Icons.nightlight_round,
              active: isDark,
              onTap: () =>
                  isDark ? null : ref.read(themeProvider.notifier).toggle()),
        ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4993FC) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : Colors.grey, size: 24),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: active ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _NeumorphicContainer extends StatelessWidget {
  final Widget child;
  final Color cardBg, shadowD, shadowL;
  const _NeumorphicContainer(
      {required this.child,
      required this.cardBg,
      required this.shadowD,
      required this.shadowL});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: shadowD, blurRadius: 10, offset: const Offset(5, 5)),
          BoxShadow(color: shadowL, blurRadius: 10, offset: const Offset(-5, -5))
        ],
      ),
      child: child,
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final Color iconColor, cardBg, shadowD, shadowL;
  final VoidCallback onTap;
  const _MemoryCard(
      {required this.label,
      required this.subtitle,
      required this.icon,
      required this.iconColor,
      required this.cardBg,
      required this.shadowD,
      required this.shadowL,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: shadowD, blurRadius: 10, offset: const Offset(5, 5)),
            BoxShadow(color: shadowL, blurRadius: 10, offset: const Offset(-5, -5))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _SocialCircle extends StatelessWidget {
  final dynamic icon; // Fixed: Use dynamic to accept both IconData and FaIconData
  final Color color;
  final VoidCallback onTap;
  const _SocialCircle(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.2))),
        child: Center(
          child: FaIcon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDanger;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label, required this.icon, this.isDanger = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
                color: isDanger
                    ? Colors.redAccent.withOpacity(0.5)
                    : const Color(0xFF4993FC).withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: isDanger ? Colors.redAccent : const Color(0xFF4993FC)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDanger ? Colors.redAccent : const Color(0xFF4993FC))),
            ],
          ),
        ),
      ),
    );
  }
}