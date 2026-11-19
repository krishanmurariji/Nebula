import 'package:flutter/material.dart';
import 'noor_palette.dart';

/// The thin-bordered "Search" button at the top right of Home and the
/// player. While search is open it reads "Cancel".
class NoorSearchButton extends StatelessWidget {
  const NoorSearchButton({super.key, required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final label = open ? 'Cancel' : 'Search';
    return Semantics(
      button: true,
      label: open ? 'Close search' : 'Search',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          width: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(label,
                key: ValueKey(label),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    color: t.ac,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
          ),
        ),
      ),
    );
  }
}
