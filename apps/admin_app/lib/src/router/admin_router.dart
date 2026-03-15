import 'package:core/core.dart' as core hide isValidUuid;
import 'package:core/core.dart' show Customer, GoRouterRefreshStream, authRepositoryProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/admin_gate.dart';
import '../features/auth/admin_login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/customers/customer_list_page.dart';
import '../features/customers/customer_form_page.dart';
import '../features/customers/customer_statement_page.dart';
import '../features/customers/customer_management_page.dart';
import '../features/customers/customer_detail_page.dart';
import '../features/customers/customer_payment_form_page.dart';
import '../features/customers/customer_ledger_page.dart';
import '../features/customers/customer_payments_page.dart';
import '../features/customers/customer_risk_page.dart';
import '../features/customers/customer_aging_page.dart';
import '../features/customers/customer_reports_page.dart';
import '../features/customers/customer_balance_report_page.dart';
import '../features/customers/customer_transfer_page.dart';
import '../features/customers/customer_phone_user_move_page.dart';
import '../features/stocks/stock_list_page.dart';
import '../features/stocks/stock_form_page.dart';
import '../features/stocks/stock_management_page.dart';
import '../features/stocks/stock_movements_page.dart';
import '../features/stocks/stock_import_export_page.dart';
import '../features/stocks/invalid_stocks_page.dart';
import '../features/categories/category_list_page.dart';
import '../features/categories/category_form_page.dart';
import '../features/orders/orders_list_page.dart';
import '../features/orders/order_create_page.dart';
import '../features/orders/order_detail_page.dart';
import '../features/orders/shipment_list_page.dart';
import '../features/invoices/invoices_list_page.dart';
import '../features/invoices/invoice_detail_page.dart';
import '../features/invoices/admin_invoice_edit_page.dart';
import '../features/returns/returns_list_page.dart';
import '../features/returns/return_create_page.dart';
import '../features/returns/return_detail_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/users/users_list_page.dart';
import '../features/users/user_create_page.dart';
import '../features/users/user_detail_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/settings_company_page.dart';
import '../features/settings/settings_numbering_page.dart';
import '../features/settings/settings_users_page.dart';
import '../features/settings/print_template_config.dart';
import '../features/settings/settings_print_templates_page.dart';
import '../features/settings/settings_print_template_editor_page.dart';
import '../features/settings/settings_notifications_page.dart';
import '../features/audit/audit_logs_page.dart';
import '../shell/admin_shell.dart';
import '../utils/uuid_utils.dart';

// core kütüphanesinden Customer ve GoRouterRefreshStream zaten export ediliyor.

final adminRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.read(authRepositoryProvider);
  final refresh = GoRouterRefreshStream(authRepo.authStateChanges);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = authRepo.currentUser;
      final loggingIn = state.matchedLocation == '/login';

      // Mevcut Supabase session bilgisini de logla.
      final session = core.supabaseClient.auth.currentSession;
      if (kDebugMode) {
        debugPrint('[ROUTER] location=${state.matchedLocation} '
            'uid=${user?.id} hasSession=${session != null}');
      }

      // Session / user yoksa sadece login sayfasına izin ver.
      if (session == null || user == null) {
        return loggingIn ? null : '/login';
      }

      // Kullanıcı giriş yapmışsa ve login sayfasına gitmeye çalışıyorsa dashboard'a yönlendir.
      if (loggingIn) {
        return '/dashboard';
      }

      // Diğer tüm durumlarda redirect yok.
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final section = _sectionForState(state);
          final isWide = MediaQuery.of(context).size.width >= 900;
          final shell = isWide
              ? AdminShell(
                  currentSection: section,
                  child: child,
                )
              : AdminMobileShell(
                  currentSection: section,
                  child: child,
                );

          return AdminGate(child: shell);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/admin/audit',
            name: 'auditLogs',
            builder: (context, state) => const AuditLogsPage(),
          ),
          GoRoute(
            path: '/admin/customers/:id',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/customers';
              }
              return '/customers/$id';
            },
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/admin/orders/:id',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/orders';
              }
              return '/orders/$id';
            },
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/admin/invoices/:id',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/invoices';
              }
              return '/invoices/$id';
            },
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomerListPage(),
          ),
          GoRoute(
            path: '/customers/new',
            name: 'customerNew',
            builder: (context, state) => const CustomerCreateTabsPage(),
          ),
          GoRoute(
            path: '/customers/reports',
            name: 'customerReports',
            builder: (context, state) => const CustomerReportsPage(),
          ),
          GoRoute(
            path: '/customers/reports/balances',
            name: 'customerBalanceReport',
            redirect: (context, state) => '/customers/reports?tab=balances',
            builder: (context, state) => const CustomerReportsPage(),
          ),
          GoRoute(
            path: '/customers/reports/balances/print',
            name: 'customerBalanceReportPrint',
            builder: (context, state) =>
                const CustomerBalanceReportPrintPage(),
          ),
          GoRoute(
            path: '/customers/transfer',
            name: 'customerTransfer',
            builder: (context, state) => const CustomerTransferPage(),
          ),
          GoRoute(
            path: '/customers/:id',
            name: 'customerDetail',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/customers';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final tabParam = state.uri.queryParameters['tab'];
              final initialTabIndex = int.tryParse(tabParam ?? '0') ?? 0;
              return CustomerDetailPage(
                customerId: id,
                initialTabIndex: initialTabIndex,
              );
            },
          ),
          GoRoute(
            path: '/customers/ledger/:customerId',
            name: 'customerLedger',
            builder: (context, state) {
              final id = state.pathParameters['customerId']!;
              return CustomerLedgerPage(customerId: id);
            },
          ),
          GoRoute(
            path: '/customers/risk/:customerId',
            name: 'customerRisk',
            builder: (context, state) {
              final id = state.pathParameters['customerId']!;
              return CustomerRiskPage(customerId: id);
            },
          ),
          GoRoute(
            path: '/customers/aging/:customerId',
            name: 'customerAging',
            builder: (context, state) {
              final id = state.pathParameters['customerId']!;
              return CustomerAgingPage(customerId: id);
            },
          ),
          GoRoute(
            path: '/customers/payments/:customerId',
            name: 'customerPayments',
            builder: (context, state) {
              final id = state.pathParameters['customerId']!;
              return CustomerPaymentsPage(customerId: id);
            },
          ),
          GoRoute(
            path: '/customer-management',
            name: 'customerManagement',
            builder: (context, state) => const CustomerManagementPage(),
          ),
          GoRoute(
            path: '/customers/auth-phone-move',
            name: 'customerPhoneUserMove',
            builder: (context, state) => const CustomerPhoneUserMovePage(),
          ),
          GoRoute(
            path: '/customers/:id/edit',
            name: 'customerEdit',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/customers';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return CustomerFormPage(
                customerId: id,
                initialCustomer: state.extra is Customer
                    ? state.extra as Customer
                    : null,
              );
            },
          ),
          GoRoute(
            path: '/customers/:id/statement',
            name: 'customerStatement',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/customers';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return CustomerStatementPage(customerId: id);
            },
          ),
          GoRoute(
            path: '/customers/:id/payments/new',
            name: 'customerPaymentNew',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/customers';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return CustomerPaymentFormPage(customerId: id);
            },
          ),
          // Sipariş Yönetimi
          GoRoute(
            path: '/orders',
            name: 'orders',
            builder: (context, state) {
              final status = state.uri.queryParameters['status'];
              final info = state.uri.queryParameters['info'];
              return OrdersListPage(
                initialStatus: status,
                info: info,
              );
            },
          ),
          GoRoute(
            path: '/orders/new',
            name: 'orderNew',
            builder: (context, state) => const OrderCreatePage(),
          ),
          GoRoute(
            path: '/orders/shipment',
            name: 'ordersShipment',
            builder: (context, state) {
              final idsParam = state.uri.queryParameters['ids'] ?? '';
              final idList = idsParam
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty && isValidUuid(e))
                  .toList();
              return ShipmentListPage(orderIds: idList);
            },
          ),
          GoRoute(
            path: '/orders/:id',
            name: 'orderDetail',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/orders';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return OrderDetailPage(orderId: id);
            },
          ),
          // Fatura
          GoRoute(
            path: '/invoices',
            name: 'invoices',
            builder: (context, state) => const InvoicesListPage(),
          ),
          GoRoute(
            path: '/invoices/new',
            name: 'invoiceNew',
            redirect: (context, state) {
              // Manuel fatura oluşturma devre dışı: sipariş tamamlanınca otomatik oluşur.
              final uri =
                  Uri(path: '/orders', queryParameters: <String, String>{
                'info': 'invoice-auto',
              });
              return uri.toString();
            },
            builder: (context, state) => const InvoicesListPage(),
          ),
          GoRoute(
            path: '/invoices/:id',
            name: 'invoiceDetail',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/invoices';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return InvoiceDetailPage(invoiceId: id);
            },
          ),
          GoRoute(
            path: '/invoices/:id/edit',
            name: 'invoiceEdit',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/invoices';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return AdminInvoiceEditPage(invoiceId: id);
            },
          ),
          // İade & Düzeltme
          GoRoute(
            path: '/returns',
            name: 'returns',
            builder: (context, state) => const ReturnsListPage(),
          ),
          GoRoute(
            path: '/returns/new',
            name: 'returnNew',
            builder: (context, state) => ReturnCreatePage(
              initialCustomerId: state.uri.queryParameters['customerId'],
              initialProductId: state.uri.queryParameters['productId'],
              initialBarcode: state.uri.queryParameters['barcode'],
            ),
          ),
          GoRoute(
            path: '/returns/:id',
            name: 'returnDetail',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/returns';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ReturnDetailPage(returnId: id);
            },
          ),
          // Bildirimler
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          // Kullanıcı & Yetki Yönetimi
          GoRoute(
            path: '/users',
            name: 'users',
            builder: (context, state) => const UsersListPage(),
          ),
          GoRoute(
            path: '/users/new',
            name: 'userNew',
            builder: (context, state) => const UserCreatePage(),
          ),
          GoRoute(
            path: '/users/:id',
            name: 'userDetail',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/users';
              }
              return null;
            },
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return UserDetailPage(userId: id);
            },
          ),
          // Ayarlar / Tanımlar
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/settings/company',
            name: 'settingsCompany',
            builder: (context, state) => const SettingsCompanyPage(),
          ),
          GoRoute(
            path: '/settings/numbering',
            name: 'settingsNumbering',
            builder: (context, state) => const SettingsNumberingPage(),
          ),
          GoRoute(
            path: '/settings/stock',
            redirect: (context, state) => '/stocks',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/settings/system',
            redirect: (context, state) => '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/settings/users',
            name: 'settingsUsers',
            builder: (context, state) => const SettingsUsersPage(),
          ),
          GoRoute(
            path: '/settings/print',
            name: 'settingsPrint',
            builder: (context, state) => const SettingsPrintTemplatesPage(),
          ),
          GoRoute(
            path: '/settings/print/edit/invoice-a5',
            name: 'settingsPrintEditInvoiceA5',
            builder: (context, state) => const SettingsPrintTemplateEditorPage(
              templateKey: PrintTemplateConfigRepository.invoiceKey,
              title: 'Fatura A5 Şablonu',
              isInvoice: true,
            ),
          ),
          GoRoute(
            path: '/settings/print/edit/order-a5',
            name: 'settingsPrintEditOrderA5',
            builder: (context, state) => const SettingsPrintTemplateEditorPage(
              templateKey: PrintTemplateConfigRepository.orderKey,
              title: 'Sipariş A5 Şablonu',
              isInvoice: false,
            ),
          ),
          GoRoute(
            path: '/settings/notifications',
            name: 'settingsNotifications',
            builder: (context, state) => const SettingsNotificationsPage(),
          ),
          GoRoute(
            path: '/stocks',
            name: 'stocks',
            builder: (context, state) => const StockManagementPage(),
          ),
          GoRoute(
            path: '/stocks/list',
            name: 'stockList',
            builder: (context, state) => const StockListPage(),
          ),
          GoRoute(
            path: '/stocks/invalid',
            name: 'invalidStocks',
            builder: (context, state) => const InvalidStocksPage(),
          ),
          GoRoute(
            path: '/stocks/new',
            name: 'stockNew',
            builder: (context, state) => const StockFormPage(),
          ),
          GoRoute(
            path: '/stocks/movements',
            name: 'stockMovements',
            builder: (context, state) => const StockMovementsPage(),
          ),
          GoRoute(
            path: '/stocks/import-export',
            name: 'stockImportExport',
            builder: (context, state) => const StockImportExportPage(),
          ),
          // Alias: /stocks/:id -> /stocks/:id/edit
          GoRoute(
            path: '/stocks/:id',
            name: 'stockAlias',
            redirect: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || !isValidUuid(id)) {
                return '/stocks/list';
              }
              return '/stocks/$id/edit';
            },
            // Bu builder, redirect çalıştığı için normalde kullanılmaz.
            builder: (context, state) => const StockListPage(),
          ),
          GoRoute(
            path: '/stocks/:id/edit',
            name: 'stockEdit',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return StockFormPage(stockId: id);
            },
          ),
          GoRoute(
            path: '/categories',
            name: 'categories',
            builder: (context, state) => const CategoryListPage(),
          ),
          GoRoute(
            path: '/categories/new',
            name: 'categoryNew',
            builder: (context, state) => const CategoryFormPage(),
          ),
          GoRoute(
            path: '/categories/:id/edit',
            name: 'categoryEdit',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return CategoryFormPage(categoryId: id);
            },
          ),
        ],
      ),
    ],
  );
});

AdminShellSection _sectionForState(GoRouterState state) {
  final path = state.uri.path;

  if (path.startsWith('/admin/customers')) {
    return AdminShellSection.customers;
  }
  if (path.startsWith('/admin/orders')) {
    return AdminShellSection.orders;
  }
  if (path.startsWith('/admin/invoices')) {
    return AdminShellSection.invoices;
  }
  if (path.startsWith('/stocks')) {
    return AdminShellSection.stocks;
  }
  if (path.startsWith('/orders')) {
    return AdminShellSection.orders;
  }
  if (path.startsWith('/invoices') || path.startsWith('/returns')) {
    return AdminShellSection.invoices;
  }
  if (path.startsWith('/customers') ||
      path.startsWith('/customer-')) {
    return AdminShellSection.customers;
  }
  if (path.startsWith('/settings')) {
    return AdminShellSection.settings;
  }
  if (path.startsWith('/admin/audit')) {
    return AdminShellSection.settings;
  }

  // Bildirimler, kullanıcılar, ayarlar vb. için dashboard sekmesini seçili tut.
  return AdminShellSection.dashboard;
}
