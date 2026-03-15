import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/customer_account_page.dart';
import '../features/auth/customer_login_page.dart';
import '../features/cari/customer_cari_page.dart';
import '../features/customer/home/customer_dashboard_page.dart';
import '../features/home/customer_shell_page.dart';
import '../features/orders/customer_new_order_page.dart';
import '../features/orders/customer_order_detail_page.dart';
import '../features/orders/customer_orders_page.dart';
import '../features/invoices/customer_invoice_detail_page.dart';
import '../features/invoices/customer_invoices_page.dart';
import '../features/products/customer_products_page.dart';

final customerRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.read(authRepositoryProvider);
  final refresh = GoRouterRefreshStream(authRepo.authStateChanges);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = authRepo.currentUser;
      final loggingIn = state.matchedLocation == '/login';
      final atRoot = state.matchedLocation == '/';
      final customerId = ref.read(customerIdProvider);
      final hasCustomer = customerId != null && customerId.isNotEmpty;

      // Login olmayan kullanıcı sadece /login'e gidebilir
      if (user == null) {
        return loggingIn ? null : '/login';
      }

      // Oturum var ama customerId henüz eşleşmemişse
      // kullanıcı sadece /login ekranında kalabilsin.
      if (!hasCustomer) {
        return loggingIn ? null : '/login';
      }

      // Root path ('/') kullanılmışsa ve kullanıcı + customerId hazırsa
      // bunu ana sayfa (dashboard) ekranına yönlendir.
      if (atRoot && hasCustomer) {
        return '/home/dashboard';
      }

      // Eski /products path'leri için backward compatible redirect
      if (state.matchedLocation == '/products') {
        return '/home/products';
      }

      // Eski /dashboard path'ini yeni dashboard adresine yönlendir.
      // (Core'da bazı ortak bileşenler /dashboard'ı varsayılan alabiliyor.)
      if (state.matchedLocation == '/dashboard') {
        return '/home/dashboard';
      }

      // Eski /home path'ini ana sayfa (dashboard) ekranına yönlendir.
      if (state.matchedLocation == '/home' && hasCustomer) {
        return '/home/dashboard';
      }

      // Customer login ekranındaysa veya root path'teyse
      // ve customerId set ise ana sayfaya (dashboard) at
      if ((loggingIn || atRoot) && hasCustomer) {
        return '/home/dashboard';
      }

      return null;
    },
    routes: [
      // Backward compatible: /dashboard -> /home/dashboard
      GoRoute(
        path: '/dashboard',
        redirect: (context, state) => '/home/dashboard',
      ),
      GoRoute(
        path: '/invoices',
        name: 'customer-invoices',
        builder: (context, state) => const CustomerInvoicesPage(),
      ),
      GoRoute(
        path: '/invoices/:id',
        name: 'customer-invoice-detail',
        builder: (context, state) {
          final invoiceId = state.pathParameters['id']!;
          return CustomerInvoiceDetailPage(invoiceId: invoiceId);
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const CustomerLoginPage(),
      ),
      // Eski /home adresini ana sayfa (dashboard) ekranına yönlendir.
      GoRoute(
        path: '/home',
        redirect: (context, state) => '/home/dashboard',
        builder: (context, state) => const CustomerLoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            CustomerShellPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/dashboard',
                name: 'dashboard',
                builder: (context, state) => const CustomerDashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/products',
                name: 'products',
                builder: (context, state) => const CustomerProductsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                name: 'orders',
                builder: (context, state) => const CustomerOrdersPage(),
              ),
              GoRoute(
                path: '/orders/new',
                name: 'order-new',
                builder: (context, state) => const CustomerNewOrderPage(),
              ),
              GoRoute(
                path: '/orders/:id',
                name: 'order-detail',
                builder: (context, state) {
                  final orderId = state.pathParameters['id']!;
                  return CustomerOrderDetailPage(orderId: orderId);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cari',
                name: 'cari',
                builder: (context, state) => const CustomerCariPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                name: 'account',
                builder: (context, state) => const CustomerAccountPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
