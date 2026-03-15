import 'package:flutter/material.dart';

class AppStatusChip extends StatelessWidget {
  const AppStatusChip.active({super.key}) : _status = _Status.active;
  const AppStatusChip.inactive({super.key}) : _status = _Status.inactive;

  final _Status _status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isActive = _status == _Status.active;

    return Chip(
      label: Text(isActive ? 'Aktif' : 'Pasif'),
      avatar: Icon(
        isActive ? Icons.check_circle : Icons.remove_circle,
        size: 16,
        color: isActive ? colorScheme.primary : colorScheme.outline,
      ),
    );
  }
}

enum _Status { active, inactive }
