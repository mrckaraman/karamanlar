import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/material.dart';

import '../../utils/uuid_utils.dart';

class UserDetailPage extends StatelessWidget {
  const UserDetailPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    if (!isValidUuid(userId)) {
      return const AppScaffold(
        title: 'Kullanıcı Detayı',
        body: Center(
          child: Text('Geçersiz kullanıcı ID bilgisi.'),
        ),
      );
    }

    return const AppScaffold(
      title: 'Kullanıcı Detayı',
      body: Center(
        child: Text('Kullanıcı detayı - Yakında'),
      ),
    );
  }
}
