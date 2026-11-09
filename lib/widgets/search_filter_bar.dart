import 'package:flutter/material.dart';
import '../theme/noor_palette.dart';

/// How search results are shown.
enum SearchFilter {
  /// Everything, best match first.
  bestMatch,

  /// Only uploads from a trusted source (Topic / VEVO / label / the artist).
  officialOnly,
}

/// The two filter chips shown under the search bar.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.totalCount,
    required this.officialCount,
    required this.isDark,
  });

  final SearchFilter filter;
  final ValueChanged<SearchFilter> onChanged;
  final int totalCount;
  final int officialCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _FilterChipButton(
            label: 'Best match',
            count: totalCount,
            icon: Icons.auto_awesome_rounded,
            selected: filter == SearchFilter.bestMatch,
            isDark: isDark,
            onTap: () => onChanged(SearchFilter.bestMatch),
          ),
          _FilterChipButton(
            label: 'Official only',
            count: officialCount,
            icon: Icons.verified_rounded,
            selected: filter == SearchFilter.officialOnly,
            isDark: isDark,
            onTap: () => onChanged(SearchFilter.officialOnly),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.byMode(isDark);
    final fg = selected ? t.onAc : t.mute;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count results',
      onTap: onTap,
      // Read the chip once ("Official only, 3 results"), not once per inner text.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // 40 px tall: comfortable to tap.
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.ac : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? t.ac : t.soft, width: 1),
          ),
          // Shrinks to fit instead of overflowing on very narrow screens or
          // with huge system text.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
