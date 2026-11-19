import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_suggestions_provider.dart';
import '../theme/noor_palette.dart';

/// The list that drops under the search box while it is being typed in,
/// like YouTube's: your recent searches (clock icon; swipe one away to
/// forget it), then YouTube's suggestions. Tap a line to search it; tap the
/// arrow to put it in the box and keep typing.
///
/// Shows only while [focus] has focus and there is something to suggest, so
/// the results underneath are visible otherwise.
class SearchSuggestions extends ConsumerStatefulWidget {
  const SearchSuggestions({
    super.key,
    required this.controller,
    required this.focus,
    required this.onPick,
  });

  final TextEditingController controller;
  final FocusNode focus;

  /// Runs a search for the chosen text.
  final ValueChanged<String> onPick;

  @override
  ConsumerState<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends ConsumerState<SearchSuggestions> {
  /// YouTube's last answer, kept on screen while the next one loads so the
  /// list does not flicker at every letter.
  List<String> _lastYoutube = const [];
  String _lastFor = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SearchSuggestions old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focus != widget.focus) {
      old.focus.removeListener(_changed);
      widget.focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focus.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _fill(String text) {
    HapticFeedback.selectionClick();
    final value = '$text ';
    widget.controller.value = TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length));
    widget.focus.requestFocus();
  }

  void _pick(String text) {
    HapticFeedback.selectionClick();
    widget.onPick(text);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.focus.hasFocus) return const SizedBox.shrink();
    final t = NoorTheme.of(context);
    final typed = widget.controller.text;
    final recent = ref.watch(searchHistoryProvider);

    final yt = ref.watch(youtubeSuggestionsProvider(typed.trim()));
    if (yt.hasValue && !yt.isLoading) {
      _lastYoutube = yt.value!;
      _lastFor = typed.trim();
    }
    // Keep the previous answer only while it still fits what is typed.
    final youtube = typed.trim().isEmpty
        ? const <String>[]
        : (yt.hasValue && !yt.isLoading)
            ? yt.value!
            : (typed.trim().toLowerCase().startsWith(_lastFor.toLowerCase())
                ? _lastYoutube
                : const <String>[]);

    final items = mergeSuggestions(typed, recent, youtube);
    if (items.isEmpty) return const SizedBox.shrink();

    final q = typed.trim().toLowerCase();
    return Material(
      color: t.bg,
      child: ListView.builder(
        padding: EdgeInsets.only(
            top: 2, bottom: 120 + MediaQuery.viewInsetsOf(context).bottom),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final s = items[i];
          final line = _Line(
            suggestion: s,
            typed: q,
            onTap: () => _pick(s.text),
            onFill: () => _fill(s.text),
          );
          if (!s.recent) return line;
          return Dismissible(
            key: ValueKey('recent_${s.text}'),
            onDismissed: (_) {
              HapticFeedback.lightImpact();
              ref.read(searchHistoryProvider.notifier).remove(s.text);
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Remove',
                  style: TextStyle(
                      color: t.mute,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Remove',
                  style: TextStyle(
                      color: t.mute,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            child: line,
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.suggestion,
    required this.typed,
    required this.onTap,
    required this.onFill,
  });

  final SearchSuggestion suggestion;
  final String typed;
  final VoidCallback onTap;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final text = suggestion.text;
    // What was typed stays plain; the rest of the suggestion is bold, as on
    // YouTube, so the new words stand out.
    final at = typed.isEmpty ? -1 : text.toLowerCase().indexOf(typed);
    final base = TextStyle(color: t.ac, fontSize: 15, height: 1.25);
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final span = at < 0
        ? TextSpan(text: text, style: typed.isEmpty ? base : bold)
        : TextSpan(children: [
            TextSpan(text: text.substring(0, at), style: bold),
            TextSpan(text: text.substring(at, at + typed.length), style: base),
            TextSpan(text: text.substring(at + typed.length), style: bold),
          ]);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 2, 8, 2),
        child: Row(
          children: [
            Icon(
                suggestion.recent
                    ? Icons.history_rounded
                    : Icons.search_rounded,
                size: 20,
                color: suggestion.recent ? t.ac : t.mute),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text.rich(span,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
            Semantics(
              button: true,
              label: 'Put "$text" in the search box',
              excludeSemantics: true,
              child: IconButton(
                onPressed: onFill,
                icon: Icon(Icons.north_west_rounded, size: 20, color: t.mute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
