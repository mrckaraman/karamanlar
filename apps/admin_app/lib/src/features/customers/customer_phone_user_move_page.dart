import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerPhoneUserMovePage extends ConsumerStatefulWidget {
  const CustomerPhoneUserMovePage({super.key});

  @override
  ConsumerState<CustomerPhoneUserMovePage> createState() => _CustomerPhoneUserMovePageState();
}

class _CustomerPhoneUserMovePageState extends ConsumerState<CustomerPhoneUserMovePage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _targetAuthUidController = TextEditingController();

  AsyncValue<void> _opState = const AsyncData<void>(null);
  String? _errorText;

  String? _customerId;
  String? _customerCode;
  String? _customerPhone;
  String? _currentAuthUserId;

  @override
  void dispose() {
    _phoneController.dispose();
    _targetAuthUidController.dispose();
    super.dispose();
  }

  Future<void> _findCustomer() async {
    setState(() {
      _opState = const AsyncLoading<void>();
      _errorText = null;
    });

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      setState(() {
        _opState = const AsyncData<void>(null);
        _errorText = 'Telefon numarası girin (örn. 5334464480).';
      });
      return;
    }

    String phoneE164;
    try {
      phoneE164 = normalizeTrPhone(rawPhone);
    } catch (e) {
      setState(() {
        _opState = const AsyncData<void>(null);
        _errorText = 'Geçerli bir telefon girin (5334464480).';
      });
      return;
    }

    Map<String, dynamic>? data;
    final result = await AsyncValue.guard(() async {
      data = await supabaseClient
          .from('customers')
          .select('id, customer_code, phone, auth_user_id')
          .eq('phone', phoneE164)
          .maybeSingle();
    });

    if (!mounted) return;

    if (result.hasError) {
      setState(() {
        _opState = result;
        _customerId = null;
        _customerCode = null;
        _customerPhone = null;
        _currentAuthUserId = null;
        _errorText = 'Cari arama hatası: ${AppException.messageOf(result.error!)}';
      });
      return;
    }

    if (data == null) {
      setState(() {
        _opState = const AsyncData<void>(null);
        _customerId = null;
        _customerCode = null;
        _customerPhone = null;
        _currentAuthUserId = null;
        _errorText = 'Bu telefon ile kayıtlı cari bulunamadı.';
      });
      return;
    }

    setState(() {
      _opState = const AsyncData<void>(null);
      _errorText = null;
      _customerId = data!['id'] as String?;
      _customerCode = data!['customer_code'] as String?;
      _customerPhone = data!['phone'] as String?;
      _currentAuthUserId = data!['auth_user_id'] as String?;
    });
  }

  Future<void> _moveAuthUser() async {
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce telefon ile bir cari bulun.')),
      );
      return;
    }

    final targetUid = _targetAuthUidController.text.trim();
    if (targetUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hedef auth uid değerini girin.')),
      );
      return;
    }

    setState(() {
      _opState = const AsyncLoading<void>();
      _errorText = null;
    });

    final result = await AsyncValue.guard(() async {
      await supabaseClient.rpc(
        'admin_move_customer_auth_user',
        params: <String, dynamic>{
          'customer_id': _customerId,
          'target_auth_user_id': targetUid,
        },
      );
    });

    if (!mounted) return;

    if (result.hasError) {
      setState(() {
        _opState = result;
        _errorText =
            'auth_user_id taşıma hatası: ${AppException.messageOf(result.error!)}';
      });
      return;
    }

    setState(() {
      _opState = result;
      _currentAuthUserId = targetUid;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cari $_customerCode artık auth uid=$targetUid ile eşleştirildi.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Telefon ile Cari Kullanıcı Taşı',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Telefon girerek ilgili cariyi bulup auth_user_id değerini başka bir kullanıcıya taşıyabilirsiniz.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Telefon (yerel, örn. 5334464480)',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _opState.isLoading ? null : _findCustomer,
                  child: const Text('Cariyi Bul'),
                ),
                const SizedBox(width: 16),
                if (_opState.isLoading) const CircularProgressIndicator(),
              ],
            ),
            const SizedBox(height: 16),
            if (_errorText != null) ...[
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
            ],
            if (_customerId != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cari ID: $_customerId'),
                      if (_customerCode != null)
                        Text('Cari Kodu: $_customerCode'),
                      if (_customerPhone != null)
                        Text('Telefon (E.164): $_customerPhone'),
                      Text('Mevcut auth_user_id: ${_currentAuthUserId ?? 'YOK'}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _targetAuthUidController,
                decoration: const InputDecoration(
                  labelText: 'Hedef auth uid',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _opState.isLoading
                    ? 'Taşınıyor...'
                    : 'Bu cariyi şu auth uid’ye taşı',
                onPressed: _opState.isLoading ? null : _moveAuthUser,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
