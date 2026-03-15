import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _customerSearchProvider = StateProvider<String>((ref) => '');
final _userSearchProvider = StateProvider<String>((ref) => '');

final _customersFutureProvider = FutureProvider.autoDispose((ref) async {
  final repo = customerRepository;
  final search = ref.watch(_customerSearchProvider);
  return repo.fetchCustomers(search: search, isActive: true, limit: 100);
});

final _userSearchResultsProvider = FutureProvider.autoDispose((ref) async {
  final repo = customerUserRepository;
  final query = ref.watch(_userSearchProvider);
  if (query.trim().isEmpty) return <AuthUserSummary>[];
  return repo.searchUsersByEmail(query.trim());
});

class CustomerUserMappingPage extends ConsumerStatefulWidget {
  const CustomerUserMappingPage({super.key});

  @override
  ConsumerState<CustomerUserMappingPage> createState() => _CustomerUserMappingPageState();
}

class _CustomerUserMappingPageState extends ConsumerState<CustomerUserMappingPage> {
  Customer? _selectedCustomer;
  AuthUserSummary? _selectedUser;
  AsyncValue<void> _actionState = const AsyncData<void>(null);

  Future<void> _link() async {
    if (_selectedCustomer == null || _selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce cari ve kullanıcı seçin.')),
      );
      return;
    }

    setState(() => _actionState = const AsyncLoading<void>());

    final result = await AsyncValue.guard(() async {
      await customerUserRepository.linkCustomerToUser(
        customerId: _selectedCustomer!.id,
        userId: _selectedUser!.id,
      );
    });

    if (!mounted) return;
    setState(() => _actionState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Eşleme hatası: ${AppException.messageOf(result.error!)}'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cari ${_selectedCustomer!.name} başarıyla ${_selectedUser!.email} kullanıcısına bağlandı.',
        ),
      ),
    );
  }

  Future<void> createAndLink() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce bir cari seçin.')),
      );
      return;
    }

    final email = ref.read(_userSearchProvider).trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir e-posta girin.')),
      );
      return;
    }

    setState(() => _actionState = const AsyncLoading<void>());

    String? authUserId;
    final result = await AsyncValue.guard(() async {
      final payload =
          await customerUserRepository.createCustomerUserViaEdgeFunction(
        customerId: _selectedCustomer!.id,
        email: email,
      );

      authUserId = payload is Map<String, dynamic>
          ? payload['auth_user_id'] as String?
          : null;

      if (authUserId == null || authUserId!.isEmpty) {
        throw AppException('Edge fonksiyonu geçerli bir auth_user_id döndürmedi.');
      }

      await customerUserRepository.linkCustomerToUser(
        customerId: _selectedCustomer!.id,
        userId: authUserId!,
      );
    });

    if (!mounted) return;
    setState(() => _actionState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kullanıcı oluşturma/bağlama hatası: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Yeni müşteri kullanıcısı oluşturuldu ve cari ${_selectedCustomer!.name} ile bağlandı.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(_customersFutureProvider);
    final usersAsync = ref.watch(_userSearchResultsProvider);

    return AppScaffold(
      title: 'Cari - Kullanıcı Eşleme',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Cari seçin',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari adı / kodu ara',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                ref.read(_customerSearchProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: customersAsync.when(
                data: (customers) {
                  if (customers.isEmpty) {
                    return const Center(child: Text('Kriterlere uyan cari bulunamadı.'));
                  }
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final selected = _selectedCustomer?.id == customer.id;
                      return ListTile(
                        title: Text(customer.name),
                        subtitle: Text(customer.code),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedCustomer = customer;
                          });
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Cari yüklenirken hata: ${AppException.messageOf(e)}',
                  ),
                ),
              ),
            ),
            const Divider(height: 32),
            const Text(
              '2. Kullanıcı (auth.users) arayın',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'E-posta ile ara',
                prefixIcon: Icon(Icons.email),
              ),
              onChanged: (value) {
                ref.read(_userSearchProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: usersAsync.when(
                data: (users) {
                  if (users.isEmpty) {
                    return const Center(child: Text('Sonuç yok veya arama yapmadınız.'));
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final selected = _selectedUser?.id == user.id;
                      return ListTile(
                        title: Text(user.email),
                        subtitle: Text(user.id),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedUser = user;
                          });
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Kullanıcı ararken hata: ${AppException.messageOf(e)}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label:
                  _actionState.isLoading ? 'Eşleme yapılıyor...' : 'Eşlemeyi Kaydet',
              onPressed: _actionState.isLoading ? null : _link,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(
                _actionState.isLoading
                    ? 'Kullanıcı oluşturuluyor...'
                    : 'Yeni müşteri kullanıcısı oluştur & bağla',
              ),
              onPressed: _actionState.isLoading ? null : createAndLink,
            ),
          ],
        ),
      ),
    );
  }
}
