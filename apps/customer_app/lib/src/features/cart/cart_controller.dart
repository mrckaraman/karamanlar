import 'package:core/core.dart' show CustomerProduct, CustomerOrderItemDraft, customerOrderRepository;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
  });

  final CustomerProduct product;
  final int quantity;

  double get lineTotal => (product.effectivePrice ?? 0) * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartState {
  const CartState({
    required this.items,
  });

  final List<CartItem> items;

  double get total => items.fold(0, (sum, e) => sum + e.lineTotal);

  bool get isEmpty => items.isEmpty;

  factory CartState.empty() => const CartState(items: <CartItem>[]);
}

class CartController extends StateNotifier<CartState> {
  CartController() : super(CartState.empty());

  void addProduct(CustomerProduct product) {
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((e) => e.product.stockId == product.stockId);
    if (index == -1) {
      items.add(CartItem(product: product, quantity: 1));
    } else {
      final current = items[index];
      items[index] = current.copyWith(quantity: current.quantity + 1);
    }
    state = CartState(items: items);
  }

  void decrementProduct(String stockId) {
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((e) => e.product.stockId == stockId);
    if (index == -1) return;
    final current = items[index];
    if (current.quantity <= 1) {
      items.removeAt(index);
    } else {
      items[index] = current.copyWith(quantity: current.quantity - 1);
    }
    state = CartState(items: items);
  }

  void removeProduct(String stockId) {
    final items = state.items
        .where((e) => e.product.stockId != stockId)
        .toList(growable: false);
    state = CartState(items: items);
  }

  void clear() {
    state = CartState.empty();
  }

  Future<void> submitOrder({String? note}) async {
    if (state.isEmpty) {
      throw Exception('Sepetiniz boş. Lütfen önce ürün ekleyin.');
    }

    final items = state.items.map((item) {
      final unitPrice = item.product.effectivePrice ?? 0;
      return CustomerOrderItemDraft(
        stockId: item.product.stockId,
        name: item.product.name,
        unit: 'adet',
        quantity: item.quantity.toDouble(),
        unitPrice: unitPrice,
      );
    }).toList();

    await customerOrderRepository.createOrderFromCart(
      items: items,
      note: note,
    );

    clear();
  }
}

final cartControllerProvider =
    StateNotifierProvider<CartController, CartState>((ref) {
  return CartController();
});
