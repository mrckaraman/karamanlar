import 'dart:async';

import 'package:flutter/material.dart';

import '../spacing.dart';

/// Debounce'lu arama alani.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.hintText,
    this.initialValue = '',
    this.onChanged,
    this.onSubmitted,
    this.padded = false,
  });

  final String? hintText;
  final String initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool padded;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged?.call(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.black),
      cursorColor: Colors.black,
      decoration: InputDecoration(
        hintText: widget.hintText ?? 'Ara',
        hintStyle: const TextStyle(color: Colors.black54),
        prefixIcon: const Icon(Icons.search),
      ),
      onChanged: _onChanged,
      onSubmitted: widget.onSubmitted,
    );

    if (!widget.padded) return field;

    return Padding(
      padding: AppSpacing.horizontal16,
      child: field,
    );
  }
}
