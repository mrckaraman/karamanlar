import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Admin yetkisi olmayan kullanıcıları engellemek için kullanılan gate widget.
///
/// - isAdminProvider loading ise: dairesel progress gösterir.
/// - isAdminProvider false dönerse: "Yetkiniz yok" ekranı gösterir.
/// - true ise: child render edilir.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (_, __) => const _NoPermissionView(),
      data: (isAdmin) {
        if (!isAdmin) {
          return const _NoPermissionView();
        }
        return child;
      },
    );
  }
}

class _NoPermissionView extends StatelessWidget {
  const _NoPermissionView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Yetkiniz yok',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bu alana erişmek için admin yetkisi gerekiyor.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
