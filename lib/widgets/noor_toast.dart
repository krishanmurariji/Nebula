import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/noor_palette.dart';
import '../theme/noor_search_button.dart';

/// Noor's messages: a dark capsule that grows out of a dot in the header,
/// between the logo and the search button (like a phone's island), says
/// its piece and shrinks away on its own. Tap it or swipe it up to dismiss
/// sooner. One at a time: a new message replaces the one showing.
class NoorToast {
  NoorToast._();

  static OverlayEntry? _entry;

  /// Shows [message] above the page [context] belongs to. With [action], a
  /// button such as "Undo" sits at the end and the message stays longer.
  static void show(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    showIn(overlay, message,
        action: action, onAction: onAction, duration: duration);
  }

  /// Same, for code without a page context (the app's own notices).
  static void showIn(
    OverlayState overlay,
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Island(
        message: message,
        action: action,
        onAction: onAction,
        showFor: duration ??
            (action != null
                ? const Duration(milliseconds: 4500)
                : const Duration(milliseconds: 2600)),
        onGone: () {
          if (identical(_entry, entry)) {
            entry.remove();
            _entry = null;
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _Island extends StatefulWidget {
  const _Island({
    required this.message,
    required this.showFor,
    required this.onGone,
    this.action,
    this.onAction,
  });

  final String message;
  final String? action;
  final VoidCallback? onAction;
  final Duration showFor;
  final VoidCallback onGone;

  @override
  State<_Island> createState() => _IslandState();
}

class _IslandState extends State<_Island> with TickerProviderStateMixin {
  /// 0: a dot; 1: the full capsule with its text.
  late final AnimationController _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 280));

  /// How long it stays (a ticker, so nothing is left pending if the page
  /// goes away).
  late final AnimationController _life =
      AnimationController(vsync: this, duration: widget.showFor);

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _open.forward();
    _life.forward().whenComplete(_close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _life.stop();
    await _open.reverse();
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _open.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final top = MediaQuery.paddingOf(context).top + 14;
    // The island's colours: deep espresso with the ivory and gold of the
    // palette, the same in light and dark mode.
    const island = Color(0xFF1F1914);
    const ink = Color(0xFFF6EFE8);
    const gold = Color(0xFFD8B06A);

    return Positioned(
      top: top,
      // Between the logo (left) and the search and settings buttons.
      left: 20 + kNoorHeaderSize + 8,
      right: 14 + 2 * kNoorHeaderSize + 16,
      height: kNoorHeaderSize,
      // A Material ancestor so the text gets the app's font and style.
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(builder: (context, box) {
          return AnimatedBuilder(
            animation: _open,
            builder: (context, _) {
              final v =
                  Curves.easeOutBack.transform(_open.value.clamp(0.0, 1.0));
              final w = kNoorHeaderSize +
                  (box.maxWidth - kNoorHeaderSize) * v.clamp(0.0, 1.05);
              final textIn = ((_open.value - 0.45) / 0.55).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.center,
                child: Opacity(
                  opacity: _open.value.clamp(0.0, 1.0),
                  child: GestureDetector(
                    onTap: _close,
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -100) _close();
                    },
                    child: Semantics(
                      liveRegion: true,
                      label: widget.message,
                      child: Container(
                        width: w.clamp(kNoorHeaderSize, box.maxWidth + 4),
                        height: kNoorHeaderSize,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: island,
                          borderRadius:
                              BorderRadius.circular(kNoorHeaderSize / 2),
                          boxShadow: [
                            BoxShadow(
                                color: t.ac.withOpacity(0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Opacity(
                          opacity: textIn,
                          child: Row(children: [
                            Expanded(
                              child: Text(widget.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: ink,
                                      fontSize: 12.5,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (widget.action != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onAction?.call();
                                  _close();
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(widget.action!,
                                      style: const TextStyle(
                                          color: gold,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
