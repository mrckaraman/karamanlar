import 'package:core/core.dart';
import 'package:flutter/material.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Bildirimler',
      body: Center(
        child: Text('Bildirimler - Yakında'),
      ),
    );
  }
}
