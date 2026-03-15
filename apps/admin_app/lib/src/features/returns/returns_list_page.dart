import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'return_strings.dart';

class ReturnsListPage extends StatelessWidget {
  const ReturnsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: ReturnStrings.returnsListTitle,
      body: Center(
        child: Text(ReturnStrings.returnsListComingSoon),
      ),
    );
  }
}
