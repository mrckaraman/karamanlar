import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/material.dart';

import '../../utils/uuid_utils.dart';
import 'return_strings.dart';

class ReturnDetailPage extends StatelessWidget {
  const ReturnDetailPage({super.key, required this.returnId});

  final String returnId;

  @override
  Widget build(BuildContext context) {
    if (!isValidUuid(returnId)) {
      return const AppScaffold(
        title: ReturnStrings.returnsDetailTitle,
        body: Center(
          child: Text(ReturnStrings.returnsDetailInvalidId),
        ),
      );
    }

    return const AppScaffold(
      title: ReturnStrings.returnsDetailTitle,
      body: Center(
        child: Text(ReturnStrings.returnsDetailComingSoon),
      ),
    );
  }
}
