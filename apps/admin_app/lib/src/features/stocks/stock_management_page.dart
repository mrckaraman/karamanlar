import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StockManagementPage extends StatelessWidget {
  const StockManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final columns = AppResponsive.gridColumns(context, mobile: 1, tablet: 2, desktop: 3);
    final childAspectRatio = columns == 1 ? 2.7 : 1.1;

    return AdminPageScaffold(
      title: 'Stok Yönetimi',
      icon: Icons.inventory_2,
      subtitle: 'Stok kartları, işlemler ve içe/dışa aktarma',
      child: GridView.count(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacing.s12,
        mainAxisSpacing: AppSpacing.s12,
        childAspectRatio: childAspectRatio,
        children: [
          AdminDashboardCard(
            icon: Icons.list_alt,
            title: 'Stok Bilgileri',
            subtitle: 'Stok kartlarını listele ve düzenle',
            onTap: () => context.goNamed('stockList'),
          ),
          AdminDashboardCard(
            icon: Icons.add_box,
            title: 'Stok Ekleme',
            subtitle: 'Yeni stok kartı oluştur',
            onTap: () => GoRouter.of(context).go('/stocks/new'),
          ),
          AdminDashboardCard(
            icon: Icons.swap_vert,
            title: 'Stok İşlemleri (Fiyat Yönetimi)',
            subtitle:
                'Tekli veya Excel ile fiyat güncelle. Her değişiklik fiyat geçmişine kaydedilir.\nBu ekranda miktar/giriş-çıkış yoktur.',
            onTap: () => GoRouter.of(context).go('/stocks/movements'),
          ),
          AdminDashboardCard(
            icon: Icons.import_export,
            title: 'Stok İçe/Dışa Aktarma (Excel Master)',
            subtitle:
                'Excel dosyası sistemin tam listesidir: olmayan silinir, yeni eklenir, mevcut güncellenir. Geri alınamaz — silme içerir.',
            onTap: () => GoRouter.of(context).go('/stocks/import-export'),
          ),
          AdminDashboardCard(
            icon: Icons.health_and_safety_outlined,
            title: 'Bozuk Stoklar',
            subtitle:
                'Barkodu olup paket/koli katsayısı eksik olan stokları listele.',
            onTap: () => GoRouter.of(context).go('/stocks/invalid'),
          ),
        ],
      ),
    );
  }
}
