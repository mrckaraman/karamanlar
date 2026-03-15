import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
      ),
      child: child,
    );

    if (!expand) return button;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Eğer yatayda bounded değilse (ör. Row/Wrap içi), genişliği zorlamadan
        // butonu kendi içeriği kadar bırak.
        if (!constraints.hasBoundedWidth) {
          return button;
        }

        // Bounded parent varsa full width.
        return SizedBox(
          width: double.infinity,
          child: button,
        );
      },
    );
  }
}
