import 'package:core/core.dart';
import 'package:flutter/material.dart';

class UsersListPage extends StatelessWidget {
  const UsersListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Kullanıcı & Yetki Yönetimi',
      body: Center(
        child: Text('Kullanıcı & yetki listesi - Yakında'),
      ),
    );
  }
}
