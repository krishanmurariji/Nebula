import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../neuo.dart';
import '../providers/api_key_provider.dart';
import 'main_shell.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<OnboardingScreen> {
  final _ctrl   = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    final err = await ref.read(apiKeyProvider.notifier).validateAndSave(_ctrl.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
    } else {
      setState(() { _loading = false; _error = err; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(children: [
            // Logo
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: N.bg,
                shape: BoxShape.circle,
                boxShadow: N.lift(intensity: 1.2),
              ),
              child: const Center(child: Text('N', style: TextStyle(
                fontSize: 42, fontWeight: FontWeight.w900,
                color: N.primary, letterSpacing: -2))),
            ),
            const SizedBox(height: 28),
            const Text('Nebula', style: TextStyle(
              fontSize: 36, fontWeight: FontWeight.w900,
              color: N.onSurf, letterSpacing: -1)),
            const SizedBox(height: 8),
            const Text('The Sonic Nebula', style: TextStyle(
              fontSize: 13, color: N.muted, fontWeight: FontWeight.w500)),

            const SizedBox(height: 40),

            // Card
            NCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('YOUTUBE API KEY', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: N.muted, letterSpacing: 2)),
              const SizedBox(height: 16),
              const Text(
                'Nebula uses the free YouTube Data API to discover music. '
                'Get your free key in 2 minutes.',
                style: TextStyle(fontSize: 13, color: N.muted, height: 1.5)),
              const SizedBox(height: 16),
              _step(context, '1', 'Go to console.cloud.google.com'),
              _step(context, '2', 'Create project → Enable YouTube Data API v3'),
              _step(context, '3', 'Credentials → + Create → API key'),
            ])),

            const SizedBox(height: 20),

            // Input
            Container(
              decoration: BoxDecoration(
                color: N.bg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: N.inset,
              ),
              child: TextField(
                controller: _ctrl,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(color: N.onSurf,
                    fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'AIzaSy...',
                  hintStyle: const TextStyle(color: N.outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        size: 18, color: N.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(
                  color: N.error, fontSize: 13)),
            ],

            const SizedBox(height: 24),

            // Button
            GestureDetector(
              onTap: _loading ? null : _submit,
              child: Container(
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  color: N.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: N.primary.withOpacity(0.35),
                    blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Center(child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Get Started', style: TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700))),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Free. No account needed.',
                style: TextStyle(color: N.outline, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _step(BuildContext context, String n, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20, height: 20, margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: N.surfHigh, shape: BoxShape.circle),
            child: Center(child: Text(n, style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: N.primary))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(
            fontSize: 12, color: N.muted, height: 1.5))),
        ]),
      );
}
