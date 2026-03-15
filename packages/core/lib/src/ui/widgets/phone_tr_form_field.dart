import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Standart TR GSM giriş alanı.
///
/// Solda sabit, düzenlenemez `+90` prefix'i gösterir; kullanıcı
/// yalnızca sağ tarafta 10 haneli yerel GSM numarasını (örn. `5441234567`)
/// girer. Sadece rakamlara izin verir ve ilk hanenin `0` olmasını engeller.
class PhoneTrFormField extends StatelessWidget {
  const PhoneTrFormField({
    super.key,
    required this.controller,
    required this.decoration,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveDecoration = decoration.copyWith(
      prefixText: decoration.prefixText ?? '+90 ',
      hintText: decoration.hintText ?? '5441234567',
      hintStyle: decoration.hintStyle ?? const TextStyle(color: Colors.black54),
      counterText: '',
    );

    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.black),
      cursorColor: Colors.black,
      decoration: effectiveDecoration,
      keyboardType: TextInputType.phone,
      maxLength: 10,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        const _NoLeadingZeroFormatter(),
      ],
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }
}

class _NoLeadingZeroFormatter extends TextInputFormatter {
  const _NoLeadingZeroFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    // İlk hanenin 0 olmasına izin verme.
    if (text.length == 1 && text.startsWith('0')) {
      return oldValue;
    }

    if (text.length > 10) {
      final truncated = text.substring(0, 10);
      return TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
    }

    return newValue;
  }
}
