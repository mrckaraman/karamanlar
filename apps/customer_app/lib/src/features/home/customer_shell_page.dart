import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CustomerShellPage extends StatelessWidget {
  const CustomerShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Ürünler',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_shopping_cart_outlined),
            label: 'Yeni Sipariş',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Cari',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Bilgilerim',
          ),
        ],
      ),
    );
  }
}
