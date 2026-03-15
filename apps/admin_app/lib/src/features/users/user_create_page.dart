import 'package:core/core.dart';
import 'package:flutter/material.dart';

class UserCreatePage extends StatelessWidget {
  const UserCreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Yeni Kullanıcı',
      body: Center(
        child: Text('Yeni kullanıcı oluşturma - Yakında'),
      ),
    );
  }
}
