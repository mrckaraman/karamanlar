import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/crashlytics/crash_logger.dart';
import '../../constants/ui_copy_tr.dart';
import '../../widgets/form_widgets.dart';
import 'customer_general_tab.dart';
import 'customer_list_page.dart';

enum CustomerType { individual, commercial }

/// Yeni cari oluşturma için tablı ekran.
///
/// Tablar:
/// - Genel: Kimlik, iletişim, adres, vergi, satış, grupla, açılış, ticari ayarlar.
/// - Cari Hesap/Ekstre: Kilitli placeholder.
/// - Tahsilatlar: Kilitli placeholder.
/// - Aging/Vade: Kilitli placeholder.
/// - Risk & Limit: Limit, risk, pazarlamacı, diğer.
class CustomerCreateTabsPage extends ConsumerStatefulWidget {
  const CustomerCreateTabsPage({super.key});

  @override
  ConsumerState<CustomerCreateTabsPage> createState() => _CustomerCreateTabsPageState();
}

class _CustomerCreateTabsPageState extends ConsumerState<CustomerCreateTabsPage>
  with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _tradeTitleController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _limitAmountController = TextEditingController();
  final _dueDaysController = TextEditingController();
  final _taxOfficeController = TextEditingController();
  final _taxNoController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();
  final _riskNoteController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _subGroupNameController = TextEditingController();
  final _subSubGroupNameController = TextEditingController();
  final _marketerNameController = TextEditingController();

  int _priceListNo = 1;
  bool _warnOnLimitExceeded = false;

  CustomerType _customerType = CustomerType.commercial;

  bool _isActive = true;
  bool _saving = false;

  String? _nameError;
  String? _tradeTitleError;
  String? _phoneError;
  String? _taxNoError;
  String? _dueDaysError;
  String? _limitAmountError;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFormChanged);
    _tradeTitleController.addListener(_onFormChanged);
    _phoneController.addListener(_onFormChanged);

    // Yeni cari açılışında form default değerleri
    _limitAmountController.text = '0';
    _dueDaysController.text = '30';
    _priceListNo = 4; // Admin tarafında default fiyat listesi 4
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tradeTitleController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _limitAmountController.dispose();
    _dueDaysController.dispose();
    _taxOfficeController.dispose();
    _taxNoController.dispose();
    _contactNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _riskNoteController.dispose();
    _groupNameController.dispose();
    _subGroupNameController.dispose();
    _subSubGroupNameController.dispose();
    _marketerNameController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {
        _nameError = null;
        _tradeTitleError = null;
        _phoneError = null;
      });
    }
  }

  List<String>? _parseTagsForSave(String text) {
    final raw = text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (raw.isEmpty) return null;
    return raw;
  }

  bool get _isFormValid {
    final fullName = _nameController.text.trim();
    final tradeTitle = _tradeTitleController.text.trim();
    final phone = _phoneController.text.trim();

    final hasName = _customerType == CustomerType.individual
        ? fullName.isNotEmpty
        : tradeTitle.isNotEmpty;

    final isPhoneValid = _isValidTrPhoneLocal(phone);

    return hasName && isPhoneValid;
  }

  Future<void> _save() async {
    final fullName = _nameController.text.trim();
    final tradeTitle = _tradeTitleController.text.trim();
    final code = _codeController.text.trim();
    final phone = _phoneController.text.trim();
    final normalizedEmail = _emailController.text.trim().toLowerCase();

    final hasName = _customerType == CustomerType.individual
        ? fullName.isNotEmpty
        : tradeTitle.isNotEmpty;

    // Alan bazlı hataları sıfırla ve zorunlu alan validasyonu
    setState(() {
      _nameError = null;
      _tradeTitleError = null;
      _phoneError = null;
      _taxNoError = null;
      _dueDaysError = null;
      _limitAmountError = null;
    });

    bool hasError = false;

    if (!hasName) {
      if (_customerType == CustomerType.individual) {
        _nameError = 'Bu alan zorunludur';
      } else {
        _tradeTitleError = 'Bu alan zorunludur';
      }
      hasError = true;
    }
    try {
      // Geçerli bir 10 haneli GSM numarası olmalı (533xxxxxxx).
      normalizeTrPhone(phone);
    } catch (_) {
      _phoneError = phone.isEmpty
          ? 'Bu alan zorunludur'
          : 'Geçersiz telefon numarası (örn. 533 446 44 80)';
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(UiCopyTr.customerFormSaveDisabled),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });
    String currentStep = 'init';
    try {
      currentStep = 'validate_inputs';
      bool hasFieldError = false;

      // Vergi no / TCKN format ve uzunluk kontrolü (sadece rakam, VKN 10, TCKN 11)
      final rawTax = _taxNoController.text.trim();
      if (rawTax.isNotEmpty) {
        final isDigitsOnly = RegExp(r'^\d+?').hasMatch(rawTax);
        final isValidLength = rawTax.length == 10 || rawTax.length == 11;
        if (!isDigitsOnly || !isValidLength) {
          _taxNoError = 'Geçersiz değer';
          hasFieldError = true;
        }
      }

      double? limitAmount;
      final rawLimit = _limitAmountController.text.trim();
      if (rawLimit.isNotEmpty) {
        limitAmount = double.tryParse(rawLimit.replaceAll(',', '.'));
        if (limitAmount == null) {
          _limitAmountError = 'Geçersiz değer';
          hasFieldError = true;
        }
      }

      final rawDueDays = _dueDaysController.text.trim();
      final int dueDays = rawDueDays.isEmpty
          ? 30
          : int.tryParse(rawDueDays) ?? 30;

      if (hasFieldError) {
        setState(() {});
        return;
      }

      // Email doluysa, önce aynı email'e sahip bir cari var mı kontrol et.
      if (normalizedEmail.isNotEmpty) {
        currentStep = 'check_existing_customer_email';
        final existing = await supabaseClient
            .from('customers')
            .select('id, customer_code, trade_title')
        .eq('email', normalizedEmail)
            .maybeSingle();

        if (existing != null) {
          final existingMap = Map<String, dynamic>.from(existing as Map);
          final existingId = existingMap['id'] as String?;
          final existingCode =
              (existingMap['customer_code']?.toString() ?? '').trim();
          final existingTitle =
              (existingMap['trade_title']?.toString() ?? '').trim();

          if (!mounted) return;

            final message = existingId != null
              ? 'Bu email ile cari zaten mevcut: '
                '${existingCode.isEmpty ? '-' : existingCode} – '
                '${existingTitle.isEmpty ? '' : existingTitle}'
              : 'Bu email ile cari zaten mevcut.';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );

          if (existingId != null) {
            GoRouter.of(context).go('/customers/${existingId.toString()}?tab=0');
          }
          return;
        }
      }

      // Sadece customers tablosunda gercekten bulunan kolonlari gonder.
      currentStep = 'insert_customers_prepare_payload';
      final normalizedPhone = normalizeTrPhone(phone);
      final payload = <String, dynamic>{
        'customer_code': code.isEmpty ? null : code,
        'trade_title': tradeTitle.isEmpty ? null : tradeTitle,
        'full_name': fullName.isEmpty ? null : fullName,
        'phone': normalizedPhone,
        'customer_type': _customerType == CustomerType.individual
            ? 'individual'
            : 'commercial',
        'email': normalizedEmail.isEmpty ? null : normalizedEmail,
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'is_active': _isActive,
      };

      debugPrint('Customer create payload (core): $payload');

      // Ek alanlar: su anda Supabase customers tablosuna gonderilmiyor.
      // Ileride ayri bir customer_details tablosu veya view icin
      // kullanilabilir.
      final extraDetails = <String, dynamic>{
        'tax_office': _taxOfficeController.text.trim().isEmpty
            ? null
            : _taxOfficeController.text.trim(),
        'tax_no': _taxNoController.text.trim().isEmpty
            ? null
            : _taxNoController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'district': _districtController.text.trim().isEmpty
            ? null
            : _districtController.text.trim(),
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'tags': _parseTagsForSave(_tagsController.text),
        'limit_amount': limitAmount,
        'price_tier': _priceListNo,
        'due_days': dueDays,
        'risk_note': _riskNoteController.text.trim().isEmpty
            ? null
            : _riskNoteController.text.trim(),
        'group_name': _groupNameController.text.trim().isEmpty
            ? null
            : _groupNameController.text.trim(),
        'sub_group': _subGroupNameController.text.trim().isEmpty
            ? null
            : _subGroupNameController.text.trim(),
        'alt_group': _subSubGroupNameController.text.trim().isEmpty
            ? null
            : _subSubGroupNameController.text.trim(),
        'warn_on_limit_exceeded': _warnOnLimitExceeded,
        'marketer_name': _marketerNameController.text.trim().isEmpty
            ? null
            : _marketerNameController.text.trim(),
      };

      debugPrint(
        'Customer extra details (not sent): ${extraDetails.toString()}',
      );

      currentStep = 'insert_customers';
      final Map<String, dynamic> inserted = await supabaseClient
          .from('customers')
          .insert(payload)
          .select('id')
          .single();
      final insertedMap = inserted;
      final createdId = insertedMap['id'] as String?;
      debugPrint('[CUSTOMER][TABS CREATE RESULT] id=$createdId email=${_maskEmail(normalizedEmail)} tax_no=${_maskTaxNo(_taxNoController.text)} time=${DateTime.now().toIso8601String()}');

      // customers kaydi olustuktan sonra, varsa ekstra detaylari
      // customer_details tablosuna upsert et.
      if (createdId != null) {
        currentStep = 'upsert_customer_details_prepare_payload';
        final detailsPayload = <String, dynamic>{
          'customer_id': createdId,
          ...extraDetails,
        };

        // Tum alanlar null ise gereksiz insert'ten kacinmak icin kontrol et.
        final hasNonNull = detailsPayload.entries
            .any((e) => e.key != 'customer_id' && e.value != null);

        if (hasNonNull) {
          currentStep = 'upsert_customer_details';
          await supabaseClient
              .from('customer_details')
              .upsert(detailsPayload, onConflict: 'customer_id')
              .select('customer_id')
              .single();
          debugPrint('Customer details upserted for id: $createdId');
        }
      }

      // Eger email girildiyse, ilgili musteri icin
      // auth kullanicisini olusturmak uzere edge function cagir.
        if (createdId != null &&
          normalizedEmail.isNotEmpty) {
        try {
          currentStep = 'invoke_create_customer_user';
          final session = supabaseClient.auth.currentSession;
          final accessToken = session?.accessToken;

          if (accessToken == null) {
            debugPrint('create_customer_user: Admin oturumu yok');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Admin oturumu yok. Lütfen tekrar giriş yapın.',
                ),
              ),
            );
            return;
          }

          final response = await supabaseClient.functions.invoke(
            'create_customer_user',
            body: <String, dynamic>{
              'customer_id': createdId,
              'email': normalizedEmail,
            },
            headers: <String, String>{
              'Authorization': 'Bearer $accessToken',
            },
          );

          if (response.status == 401) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Yetkilendirme hatası (401). Lütfen tekrar giriş yapın.',
                ),
              ),
            );
            return;
          }
          final data = response.data;
          final bool success = data is Map && data['ok'] == true;
          debugPrint('create_customer_user success=$success data=$data');
          if (!success) {
            final message =
                data is Map && data['error'] != null
                    ? data['error'].toString()
                    : 'Müşteri kullanıcısı oluşturulamadı';

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('create_customer_user error: ${AppException.messageOf(e)}');
        }
      }

      if (createdId != null) {
        currentStep = 'navigate_with_id';
        if (!mounted) return;
        // Liste ve detay provider'larını tazeleyelim.
        ref.invalidate(customersFutureProvider);
        ref.invalidate(customerDetailProvider(createdId));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(UiCopyTr.customerFormSaveSuccess),
          ),
        );

        // Doğrudan edit ekranına git.
        GoRouter.of(context).go('/customers/$createdId/edit');
      } else {
        currentStep = 'navigate_without_id';
        if (!mounted) return;
        debugPrint('[CUSTOMER][TABS CREATE RESULT] id=null (kimlik alınamadı) time=${DateTime.now().toIso8601String()}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cari oluşturulamadı: kimlik alınamadı.')),
        );
      }
    } on PostgrestException catch (e, stackTrace) {
      debugPrint('CustomerCreateTabsPage _save Postgrest error at step $currentStep: '
          'code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;

      String message;
      switch (e.code) {
        case '23505':
          message = 'Bu e-posta/vergi no zaten kayıtlı.';
          break;
        case '42501':
          message = 'Yetki hatası (RLS).';
          break;
        default:
          message = 'Cari oluşturulamadı: ${e.message}';
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$message (adım: $currentStep)'),
        ),
      );
      return;
    } catch (e, stackTrace) {
      debugPrint(
        'CustomerCreateTabsPage _save error at step $currentStep: ${AppException.messageOf(e)}',
      );
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${UiCopyTr.customerFormSaveError} (adım: $currentStep)',
          ),
        ),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _maskEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 1) return '***@***';
    final visible = trimmed.substring(0, 2);
    return '$visible***@***';
  }

  String _maskTaxNo(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= 4) return '****';
    final last4 = trimmed.substring(trimmed.length - 4);
    return '***$last4';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: UiCopyTr.customerCreateHeaderTitle,
      actions: const [],
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s8,
              ),
              child: SectionHeader(
                title: UiCopyTr.customerCreateHeaderTitle,
                subtitle: UiCopyTr.customerCreateHeaderSubtitle,
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                final generalCard = Card(
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: CustomerGeneralFormSection(
                      customerType: _customerType,
                      onCustomerTypeChanged: (type) {
                        setState(() {
                          _customerType = type;
                        });
                      },
                      nameController: _nameController,
                      tradeTitleController: _tradeTitleController,
                      codeController: _codeController,
                      phoneController: _phoneController,
                      emailController: _emailController,
                      addressController: _addressController,
                      cityController: _cityController,
                      districtController: _districtController,
                      taxOfficeController: _taxOfficeController,
                      taxNoController: _taxNoController,
                      contactNameController: _contactNameController,
                      nameError: _nameError,
                      tradeTitleError: _tradeTitleError,
                      phoneError: _phoneError,
                      taxNoError: _taxNoError,
                      dueDaysError: _dueDaysError,
                      priceListNo: _priceListNo,
                      onPriceListChanged: (value) {
                        setState(() {
                          _priceListNo = value;
                        });
                      },
                      groupNameController: _groupNameController,
                      subGroupNameController: _subGroupNameController,
                      subSubGroupNameController: _subSubGroupNameController,
                      dueDaysController: _dueDaysController,
                    ),
                  ),
                );

                final riskCard = Card(
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: CustomerRiskLimitSection(
                      limitAmountController: _limitAmountController,
                      limitAmountError: _limitAmountError,
                      warnOnLimitExceeded: _warnOnLimitExceeded,
                      onWarnOnLimitExceededChanged: (value) {
                        setState(() {
                          _warnOnLimitExceeded = value;
                        });
                      },
                      marketerNameController: _marketerNameController,
                      riskNoteController: _riskNoteController,
                      tagsController: _tagsController,
                      isActive: _isActive,
                      onIsActiveChanged: (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                    ),
                  ),
                );

                if (isWide) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                      vertical: AppSpacing.s8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: generalCard),
                        const SizedBox(width: AppSpacing.s16),
                        Expanded(child: riskCard),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      generalCard,
                      const SizedBox(height: AppSpacing.s16),
                      riskCard,
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
      bottom: SafeArea(
        top: false,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: PrimaryButton(
              label: _saving
                  ? UiCopyTr.customerFormSaving
                  : (_isFormValid
                      ? UiCopyTr.customerFormSavePrimary
                      : UiCopyTr.customerFormSaveDisabled),
              expand: true,
              onPressed: _saving || !_isFormValid ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerFormPage extends ConsumerStatefulWidget {
  const CustomerFormPage({
    super.key,
    this.customerId,
    this.initialCustomer,
  });

  final String? customerId;
  final Customer? initialCustomer;

  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _nameController = TextEditingController();
  final _tradeTitleController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _limitAmountController = TextEditingController();
  final _dueDaysController = TextEditingController();
  final _taxOfficeController = TextEditingController();
  final _taxNoController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();
  final _riskNoteController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _subGroupNameController = TextEditingController();
  final _subSubGroupNameController = TextEditingController();
  final _marketerNameController = TextEditingController();

  int _priceListNo = 1;
  bool _warnOnLimitExceeded = false;

  CustomerType _customerType = CustomerType.commercial;

  bool _isActive = true;
  bool _saving = false;
  bool _deleting = false;
  bool _creatingCustomerUser = false;
  bool _hasCustomerUser = false;

  String? _originalEmailNormalized;

  String? _phoneError;

  bool _didFillFromCustomer = false;

  // Edge function artık şifre döndürmediği için, ilk şifre gösterimi
  // ile ilgili feature flag kullanımdan kaldırıldı.

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFormChanged);
    _codeController.addListener(_onFormChanged);
    // Yeni kayıt modunda başlangıç defaultları uygula
    _limitAmountController.text = '0';
    _dueDaysController.text = '30';
    _priceListNo = 4; // Admin tarafında default fiyat listesi 4
    // Ilk olarak varsa router'dan gelen musteriyi uygula.
    if (widget.initialCustomer != null) {
      _applyCustomer(widget.initialCustomer!);
      _didFillFromCustomer = true;
    }
  }

  @override
  void didUpdateWidget(covariant CustomerFormPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customerId != oldWidget.customerId) {
      _didFillFromCustomer = false;
      _originalEmailNormalized = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tradeTitleController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _limitAmountController.dispose();
    _dueDaysController.dispose();
    _taxOfficeController.dispose();
    _taxNoController.dispose();
    _contactNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _riskNoteController.dispose();
    _groupNameController.dispose();
    _subGroupNameController.dispose();
    _subSubGroupNameController.dispose();
    _marketerNameController.dispose();
    super.dispose();
  }

  void _applyCustomer(Customer customer) {
    final displayName = customer.displayName;
    final isIndividual = customer.customerType == 'individual';

    final rawFullName = (customer.fullName ?? '').trim();
    final rawTradeTitle = (customer.tradeTitle ?? '').trim();

    _nameController.text = rawFullName.isNotEmpty
      ? rawFullName
      : (isIndividual ? displayName : '');

    _tradeTitleController.text = rawTradeTitle.isNotEmpty
      ? rawTradeTitle
      : (!isIndividual ? displayName : '');

    _codeController.text = customer.code;

    final rawPhone = customer.phone ?? '';
    _phoneController.text = parseTrPhoneLocalPart(rawPhone) ?? '';

    _emailController.text = customer.email ?? '';
    _originalEmailNormalized = (customer.email ?? '').trim().toLowerCase();
    _taxOfficeController.text = customer.taxOffice ?? '';
    _taxNoController.text = customer.taxNo ?? '';
    _contactNameController.text = customer.contactName ?? '';
    _addressController.text = customer.address ?? '';
    _cityController.text = customer.city ?? '';
    _districtController.text = customer.district ?? '';
    _notesController.text = customer.notes ?? '';
    _tagsController.text = customer.tags.join(', ');
    _riskNoteController.text = customer.riskNote ?? '';
    // Sayısal alanlarda null gelirse de 0 göster.
    _limitAmountController.text =
      (customer.limitAmount ?? 0).toStringAsFixed(2);
    _dueDaysController.text = (customer.dueDays ?? 30).toString();
    _groupNameController.text = customer.groupName ?? '';
    _subGroupNameController.text = customer.subGroupName ?? '';
    _subSubGroupNameController.text = customer.subSubGroupName ?? '';
    _marketerNameController.text = customer.marketerName ?? '';
    _priceListNo = customer.priceListNo ?? 4;
    _warnOnLimitExceeded = customer.warnOnLimitExceeded ?? false;
    _customerType = _parseCustomerType(customer.customerType);
    _isActive = customer.isActive;
  }

  void _fillFromCustomerOnce(Customer customer) {
    if (_didFillFromCustomer) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didFillFromCustomer) return;
      setState(() {
        _applyCustomer(customer);
        _didFillFromCustomer = true;
      });
    });
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {
        _phoneError = null;
      });
    }
  }
  bool get _isFormValid {
    final fullName = _nameController.text.trim();
    final tradeTitle = _tradeTitleController.text.trim();
    final phone = _phoneController.text.trim();

    final hasName = _customerType == CustomerType.individual
        ? fullName.isNotEmpty
        : tradeTitle.isNotEmpty;

    final isPhoneValid = _isValidTrPhoneLocal(phone);

    // Formun geçerliliği create/edit modundan bağımsız; sadece alanlara göre.
    return hasName && isPhoneValid;
  }

  double? _parseDouble(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  List<String>? _parseTagsForSave(String text) {
    final raw = text.split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (raw.isEmpty) return null;
    return raw;
  }

  CustomerType _parseCustomerType(String? raw) {
    switch (raw) {
      case 'individual':
        return CustomerType.individual;
      case 'commercial':
        return CustomerType.commercial;
      default:
        return CustomerType.commercial;
    }
  }

  Future<void> _save() async {
    final customerId = widget.customerId;
    final isCreate = customerId == null || customerId == 'new';
    final isEdit = !isCreate;

    debugPrint('[CUSTOMER][FORM MODE] isCreate=$isCreate isEdit=$isEdit id=$customerId');

    final fullName = _nameController.text.trim();
    final tradeTitle = _tradeTitleController.text.trim();
    final code = _codeController.text.trim();
    final phone = _phoneController.text.trim();
    final normalizedEmail = _emailController.text.trim().toLowerCase();

    final hasName = _customerType == CustomerType.individual
        ? fullName.isNotEmpty
        : tradeTitle.isNotEmpty;

    if (!hasName || !_isValidTrPhoneLocal(phone)) {
      setState(() {
      _phoneError = !_isValidTrPhoneLocal(phone)
        ? (phone.isEmpty
          ? 'Bu alan zorunludur'
          : 'Geçersiz telefon numarası (örn. 533 446 44 80)')
            : null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(UiCopyTr.customerFormSaveDisabled),
        ),
      );
      return;
    }

    String? createdId;

    setState(() => _saving = true);
    try {

      // Email duplicate kontrolü:
      // - Create: email doluysa her zaman kontrol
      // - Edit: sadece email değiştiyse kontrol
      if (normalizedEmail.isNotEmpty) {
        final shouldCheckDuplicate = isCreate ||
            normalizedEmail != (_originalEmailNormalized ?? '');

        if (shouldCheckDuplicate) {
          final existing = await supabaseClient
              .rpc(
                'find_customer_by_email',
                params: <String, dynamic>{
                  'p_email': normalizedEmail,
                },
              )
              .maybeSingle();

          if (existing != null) {
            final existingMap = Map<String, dynamic>.from(existing as Map);
            final existingId = existingMap['id'] as String?;
            final existingCode =
                (existingMap['customer_code']?.toString() ?? '').trim();
            final existingTitle =
                (existingMap['trade_title']?.toString() ?? '').trim();

            // Aynı kayıt değilse kullanıcıyı mevcut cariye yönlendir.
            final isSameCustomer =
              isEdit && existingId != null && existingId == widget.customerId;

            if (!isSameCustomer && existingId != null) {
              if (!mounted) return;

              final message = 'Bu email ile cari zaten mevcut: '
                  '${existingCode.isEmpty ? '-' : existingCode} – '
                  '${existingTitle.isEmpty ? '' : existingTitle}';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );

                GoRouter.of(context)
                  .go('/customers/${existingId.toString()}?tab=0');
              return;
            }
          }
        }
      }

      final limitAmount = _parseDouble(_limitAmountController.text);
      final rawDueDays = _dueDaysController.text.trim();
      final int dueDays = rawDueDays.isEmpty
          ? 30
          : int.tryParse(rawDueDays) ?? 30;

      // A) customers tablosu için payload
      final normalizedPhone = normalizeTrPhone(phone);
      final customersPayload = <String, dynamic>{
        'full_name': fullName.isNotEmpty ? fullName : null,
        'trade_title': tradeTitle.isNotEmpty ? tradeTitle : null,
        'customer_code': code.isNotEmpty ? code : null,
        'phone': normalizedPhone,
        'customer_type': _customerType == CustomerType.individual
            ? 'individual'
            : 'commercial',
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'is_active': _isActive,
      };

        // Email alanını CREATE/EDIT kurallarına göre customersPayload'a ekle.
        if (!isEdit) {
        // CREATE: email doluysa gönder.
        if (normalizedEmail.isNotEmpty) {
          customersPayload['email'] = normalizedEmail;
        }
        } else {
        // EDIT: email doluysa gönder (opsiyonel olarak değiştirilmiş olabilir).
        if (normalizedEmail.isNotEmpty) {
          customersPayload['email'] = normalizedEmail;
        }
        }

        // B) customer_details tablosu için payload
        final detailsPayload = <String, dynamic>{
        'tax_office': _taxOfficeController.text.trim().isEmpty
          ? null
          : _taxOfficeController.text.trim(),
        'tax_no': _taxNoController.text.trim().isEmpty
          ? null
          : _taxNoController.text.trim(),
        'city': _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
        'district': _districtController.text.trim().isEmpty
          ? null
          : _districtController.text.trim(),
        'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
        'tags': _parseTagsForSave(_tagsController.text),
        // UI: risk_limit -> DB: limit_amount
        'limit_amount': limitAmount,
        'price_tier': _priceListNo,
        'due_days': dueDays,
        'risk_note': _riskNoteController.text.trim().isEmpty
          ? null
          : _riskNoteController.text.trim(),
        'group_name': _groupNameController.text.trim().isEmpty
          ? null
          : _groupNameController.text.trim(),
        'sub_group': _subGroupNameController.text.trim().isEmpty
          ? null
          : _subGroupNameController.text.trim(),
        'alt_group': _subSubGroupNameController.text.trim().isEmpty
          ? null
          : _subSubGroupNameController.text.trim(),
        'warn_on_limit_exceeded': _warnOnLimitExceeded,
        'marketer_name': _marketerNameController.text.trim().isEmpty
          ? null
          : _marketerNameController.text.trim(),
        };

      // CREATE / EDIT akışı
      if (isCreate) {
        // CREATE: önce customers, sonra customer_details
        final Map<String, dynamic> inserted = await supabaseClient
            .from('customers')
            .insert(customersPayload)
            .select('id')
            .single();
        final insertedMap = inserted;
        createdId = insertedMap['id'] as String;

        unawaited(
          auditService.logChange(
            entity: 'customers',
            entityId: createdId,
            action: 'create',
            oldValue: null,
            newValue: <String, dynamic>{
              'id': createdId,
              ...customersPayload,
            },
          ),
        );

        final detailsWithId = <String, dynamic>{
          'customer_id': createdId,
          ...detailsPayload,
        };

        final hasNonNull = detailsWithId.entries
            .any((e) => e.key != 'customer_id' && e.value != null);

        if (hasNonNull) {
          await supabaseClient
              .from('customer_details')
              .upsert(detailsWithId, onConflict: 'customer_id');

          unawaited(
            auditService.logChange(
              entity: 'limits',
              entityId: createdId,
              action: 'create',
              oldValue: null,
              newValue: <String, dynamic>{
                'customer_id': createdId,
                ...detailsPayload,
              },
            ),
          );
        }
      } else if (isEdit) {
        // EDIT: customers update + customer_details upsert
        final existingCustomerId = widget.customerId!;

        Map<String, dynamic>? oldCustomer;
        Map<String, dynamic>? oldDetails;

        try {
          final row = await supabaseClient
              .from('customers')
              .select(
                'id, full_name, trade_title, customer_code, phone, email, customer_type, address, is_active',
              )
              .eq('id', existingCustomerId)
              .maybeSingle();
          if (row != null) {
            oldCustomer = Map<String, dynamic>.from(row as Map);
          }
        } catch (_) {
          // Best-effort: audit için old_value alınamazsa ana akışı bozma.
        }

        try {
          final row = await supabaseClient
              .from('customer_details')
              .select(
                'customer_id, limit_amount, risk_note, warn_on_limit_exceeded, due_days, price_tier, tags, group_name, sub_group, alt_group',
              )
              .eq('customer_id', existingCustomerId)
              .maybeSingle();
          if (row != null) {
            oldDetails = Map<String, dynamic>.from(row as Map);
          }
        } catch (_) {
          // Best-effort: audit için old_value alınamazsa ana akışı bozma.
        }

        await supabaseClient
            .from('customers')
            .update(customersPayload)
            .eq('id', existingCustomerId)
            .select('id')
            .single();

        unawaited(
          auditService.logChange(
            entity: 'customers',
            entityId: existingCustomerId,
            action: 'update',
            oldValue: oldCustomer,
            newValue: <String, dynamic>{
              'id': existingCustomerId,
              ...customersPayload,
            },
          ),
        );

        final detailsWithId = <String, dynamic>{
          'customer_id': existingCustomerId,
          ...detailsPayload,
        };

        final hasNonNull = detailsWithId.entries
            .any((e) => e.key != 'customer_id' && e.value != null);

        if (hasNonNull) {
          await supabaseClient
              .from('customer_details')
              .upsert(detailsWithId, onConflict: 'customer_id');

          unawaited(
            auditService.logChange(
              entity: 'limits',
              entityId: existingCustomerId,
              action: 'update',
              oldValue: oldDetails,
              newValue: <String, dynamic>{
                'customer_id': existingCustomerId,
                ...detailsPayload,
              },
            ),
          );
        }
      }

      if (!mounted) return;

      // CREATE/UPDATE başarılı: provider'ları invalidate et ve log bas.
      if (isCreate && createdId == null) {
        debugPrint('[CUSTOMER][FORM CREATE RESULT] id=null (kimlik alınamadı) time=${DateTime.now().toIso8601String()}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cari oluşturulamadı: kimlik alınamadı.')),
        );
        return;
      }

      if (isCreate && createdId != null) {
        debugPrint('[CUSTOMER][FORM CREATE RESULT] id=$createdId email=${_maskEmail(normalizedEmail)} tax_no=${_maskTaxNo(_taxNoController.text)} time=${DateTime.now().toIso8601String()}');
        ref.invalidate(customersFutureProvider);
        ref.invalidate(customerDetailProvider(createdId));
      } else if (isEdit) {
        ref.invalidate(customersFutureProvider);
        ref.invalidate(customerDetailProvider(widget.customerId!));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(UiCopyTr.customerFormSaveSuccess)),
      );

      if (isCreate && createdId != null) {
        GoRouter.of(context).go('/customers/$createdId/edit');
      } else if (isCreate && createdId == null) {
        // Yukarıda zaten hata mesajı gösterildi.
        return;
      } else if (isEdit) {
        GoRouter.of(context).go('/customers/${widget.customerId!}');
      }
    } on PostgrestException catch (e, st) {
      unawaited(
        CrashLogger.recordSupabaseError(
          e,
          st,
          reason: 'supabase_customer_save_failed',
          operation: isCreate ? 'insert' : 'update',
          table: 'customers',
        ),
      );
      debugPrint('[CUSTOMER][FORM SAVE ERROR] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}');
      if (!mounted) return;

      String message;
      if (isCreate) {
        // CREATE özel mesajlar
        switch (e.code) {
          case '23505':
            message = 'Bu e-posta/vergi no zaten kayıtlı.';
            break;
          case '42501':
            message = 'Yetki hatası (RLS).';
            break;
          default:
            message = 'Cari oluşturulamadı: ${e.message}';
            break;
        }
      } else {
        // EDIT için mevcut genel mesajı koru
        message = UiCopyTr.customerFormSaveError;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    } catch (e, st) {
      unawaited(
        CrashLogger.recordError(
          e,
          st,
          reason: 'customer_form_save_unexpected',
          fatal: false,
        ),
      );
      debugPrint(
        '[CUSTOMER][FORM SAVE ERROR] unexpected=${AppException.messageOf(e)}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(UiCopyTr.customerFormSaveError)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _maskEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 1) return '***@***';
    final visible = trimmed.substring(0, 2);
    return '$visible***@***';
  }

  String _maskTaxNo(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= 4) return '****';
    final last4 = trimmed.substring(trimmed.length - 4);
    return '***$last4';
  }

  Future<void> _delete() async {
    final id = widget.customerId;
    if (id == null) return;

    setState(() => _deleting = true);
    try {
          await supabaseClient
            .from('customers')
            .delete()
            .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari silindi.')),
      );
      GoRouter.of(context).go('/customers');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme hatası: ${AppException.messageOf(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.customerId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cariyi sil'),
          content: const Text(
            'Bu cariyi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _delete();
    }
  }

  Future<void> _createCustomerUser() async {
    if (!mounted) return;

    final customerId = widget.customerId;
    if (customerId == null || customerId.isEmpty || customerId == 'new') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce cari kaydedilmeli.'),
        ),
      );
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir e-posta adresi girin.'),
        ),
      );
      return;
    }

    setState(() {
      _creatingCustomerUser = true;
    });

    try {
      final session = supabaseClient.auth.currentSession;
      final accessToken = session?.accessToken;

      if (accessToken == null) {
        debugPrint('create_customer_user (manual): Admin oturumu yok');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin oturumu yok. Lütfen tekrar giriş yapın.'),
          ),
        );
        return;
      }

      final edgePayload = <String, dynamic>{
        'customer_id': customerId,
        'email': email,
      };
      debugPrint('create_customer_user payload: ${edgePayload.toString()}');

      // core tarafındaki helper Authorization header'ını zaten ekliyor,
      // burada sadece oturumun varlığını garanti altına aldık.
      await customerUserRepository.createCustomerUserViaEdgeFunction(
        customerId: customerId,
        email: email,
      );

      if (!mounted) return;

      setState(() {
        _hasCustomerUser = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Müşteri kullanıcısı oluşturuldu.'),
        ),
      );

      // Şifre yönetimi e-posta ile Supabase Auth üzerinden yapılır; burada
      // yalnızca kullanıcının oluşturulduğunu bildiriyoruz.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Müşteri kullanıcısı oluşturulamadı: ${AppException.messageOf(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingCustomerUser = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customerId != null && widget.customerId != 'new';
    final customerId = widget.customerId;

    Widget body;
    if (!isEdit) {
      body = SingleChildScrollView(
        child: Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title:
                      isEdit ? 'Cari Düzenle' : UiCopyTr.customerCreateHeaderTitle,
                  subtitle: UiCopyTr.customerCreateHeaderSubtitle,
                ),
                const SizedBox(height: AppSpacing.s12),
                CustomerGeneralFormSection(
                  customerType: _customerType,
                  onCustomerTypeChanged: (type) {
                    setState(() {
                      _customerType = type;
                    });
                  },
                  nameController: _nameController,
                  tradeTitleController: _tradeTitleController,
                  codeController: _codeController,
                  phoneController: _phoneController,
                  emailController: _emailController,
                  addressController: _addressController,
                  cityController: _cityController,
                  districtController: _districtController,
                  taxOfficeController: _taxOfficeController,
                  taxNoController: _taxNoController,
                  contactNameController: _contactNameController,
                  isCodeReadOnly: isEdit,
                  phoneError: _phoneError,
                  priceListNo: _priceListNo,
                  onPriceListChanged: (value) {
                    setState(() {
                      _priceListNo = value;
                    });
                  },
                  groupNameController: _groupNameController,
                  subGroupNameController: _subGroupNameController,
                  subSubGroupNameController: _subSubGroupNameController,
                  dueDaysController: _dueDaysController,
                ),
                const SizedBox(height: AppSpacing.s16),
                CustomerRiskLimitSection(
                  limitAmountController: _limitAmountController,
                  warnOnLimitExceeded: _warnOnLimitExceeded,
                  onWarnOnLimitExceededChanged: (value) {
                    setState(() {
                      _warnOnLimitExceeded = value;
                    });
                  },
                  marketerNameController: _marketerNameController,
                  riskNoteController: _riskNoteController,
                  tagsController: _tagsController,
                  isActive: _isActive,
                  onIsActiveChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final asyncCustomer = ref.watch(customerDetailProvider(customerId!));
      body = asyncCustomer.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Cari yüklenemedi: ${AppException.messageOf(e)}',
          onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
        ),
        data: (customer) {
          _fillFromCustomerOnce(customer);
          return SingleChildScrollView(
            child: Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Cari Düzenle',
                      subtitle: UiCopyTr.customerCreateHeaderSubtitle,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    CustomerGeneralFormSection(
                      customerType: _customerType,
                      onCustomerTypeChanged: (type) {
                        setState(() {
                          _customerType = type;
                        });
                      },
                      nameController: _nameController,
                      tradeTitleController: _tradeTitleController,
                      codeController: _codeController,
                      phoneController: _phoneController,
                      emailController: _emailController,
                      addressController: _addressController,
                      cityController: _cityController,
                      districtController: _districtController,
                      taxOfficeController: _taxOfficeController,
                      taxNoController: _taxNoController,
                      contactNameController: _contactNameController,
                      isCodeReadOnly: true,
                      phoneError: _phoneError,
                      priceListNo: _priceListNo,
                      onPriceListChanged: (value) {
                        setState(() {
                          _priceListNo = value;
                        });
                      },
                      groupNameController: _groupNameController,
                      subGroupNameController: _subGroupNameController,
                      subSubGroupNameController: _subSubGroupNameController,
                      dueDaysController: _dueDaysController,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    CustomerRiskLimitSection(
                      limitAmountController: _limitAmountController,
                      warnOnLimitExceeded: _warnOnLimitExceeded,
                      onWarnOnLimitExceededChanged: (value) {
                        setState(() {
                          _warnOnLimitExceeded = value;
                        });
                      },
                      marketerNameController: _marketerNameController,
                      riskNoteController: _riskNoteController,
                      tagsController: _tagsController,
                      isActive: _isActive,
                      onIsActiveChanged: (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return AppScaffold(
      title: isEdit ? 'Cari Düzenle' : 'Yeni Cari Ekle',
      actions: [
        if (isEdit)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final id = widget.customerId;
              if (id == null) return;
              GoRouter.of(context).go('/customers/$id/statement');
            },
            child: const Text('Ekstre'),
          ),
        if (isEdit)
          IconButton(
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete),
            onPressed: _deleting ? null : _confirmDelete,
          ),
      ],
      body: body,
      bottom: SafeArea(
        top: false,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(
                  label: _saving
                      ? UiCopyTr.customerFormSaving
                      : (isEdit
                          ? 'Güncelle'
                          : (_isFormValid
                              ? UiCopyTr.customerFormSavePrimary
                              : UiCopyTr.customerFormSaveDisabled)),
                  expand: true,
                  onPressed: _saving || !_isFormValid ? null : _save,
                ),
                if (isEdit) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: _saving || _creatingCustomerUser
                          ? null
                          : _createCustomerUser,
                      child: _creatingCustomerUser
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Müşteri Kullanıcısı Oluştur'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Bu buton, cari ile ilişkili müşteri uygulaması kullanıcısını oluşturmak için kullanılır.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_hasCustomerUser) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'Bu cari için müşteri uygulaması kullanıcısı oluşturuldu.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.green),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerGeneralFormSection extends StatelessWidget {
  const CustomerGeneralFormSection({
    super.key,
    required this.customerType,
    required this.onCustomerTypeChanged,
    required this.nameController,
    required this.tradeTitleController,
    required this.codeController,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
    required this.cityController,
    required this.districtController,
    required this.taxOfficeController,
    required this.taxNoController,
    required this.contactNameController,
    this.nameError,
    this.tradeTitleError,
    this.phoneError,
    this.taxNoError,
    this.dueDaysError,
    this.isCodeReadOnly = false,
    required this.priceListNo,
    required this.onPriceListChanged,
    required this.groupNameController,
    required this.subGroupNameController,
    required this.subSubGroupNameController,
    required this.dueDaysController,
  });

  final CustomerType customerType;
  final ValueChanged<CustomerType> onCustomerTypeChanged;

  final TextEditingController nameController;
  final TextEditingController tradeTitleController;
  final TextEditingController codeController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController districtController;
  final TextEditingController taxOfficeController;
  final TextEditingController taxNoController;
  final TextEditingController contactNameController;
  final bool isCodeReadOnly;

  final String? nameError;
  final String? tradeTitleError;
  final String? phoneError;
  final String? taxNoError;
  final String? dueDaysError;

  final int priceListNo;
  final ValueChanged<int> onPriceListChanged;

  final TextEditingController groupNameController;
  final TextEditingController subGroupNameController;
  final TextEditingController subSubGroupNameController;

  final TextEditingController dueDaysController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Cari Kimliği',
          subtitle: UiCopyTr.customerGeneralIntro,
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Bireysel'),
              selected: customerType == CustomerType.individual,
              onSelected: (_) => onCustomerTypeChanged(CustomerType.individual),
            ),
            const SizedBox(width: AppSpacing.s8),
            ChoiceChip(
              label: const Text('Ticari'),
              selected: customerType == CustomerType.commercial,
              onSelected: (_) => onCustomerTypeChanged(CustomerType.commercial),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        if (customerType == CustomerType.individual)
          TextField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: AppInputDecorations.formField(
              label: UiCopyTr.customerFieldFullNameLabel,
              hint: UiCopyTr.customerFieldFullNameHint,
              helper: UiCopyTr.customerFieldFullNameHelper,
              errorText: nameError,
            ),
          ),
        if (customerType == CustomerType.commercial)
          TextField(
            controller: tradeTitleController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: AppInputDecorations.formField(
              label: UiCopyTr.customerFieldTradeTitleLabel,
              hint: UiCopyTr.customerFieldTradeTitleHint,
              helper: UiCopyTr.customerFieldTradeTitleHelper,
              errorText: tradeTitleError,
            ),
          ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: codeController,
          readOnly: isCodeReadOnly,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldCodeLabel,
            hint: UiCopyTr.customerFieldCodeHint,
            helper: UiCopyTr.customerFieldCodeHelper,
          ),
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'İletişim'),
        const SizedBox(height: AppSpacing.s8),
        PhoneTrFormField(
          controller: phoneController,
          textInputAction: TextInputAction.next,
          onSubmitted: () =>
              FocusScope.of(context).nextFocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldPhoneLabel,
            hint: UiCopyTr.customerFieldPhoneHint,
            helper: UiCopyTr.customerFieldPhoneHelper,
            errorText: phoneError,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: emailController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldEmailLabel,
            hint: UiCopyTr.customerFieldEmailHint,
            helper: UiCopyTr.customerFieldEmailHelper,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: AppSpacing.s8),
        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Vergi / Kimlik'),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: taxOfficeController,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: AppInputDecorations.formField(
                  label: UiCopyTr.customerFieldTaxOfficeLabel,
                  hint: UiCopyTr.customerFieldTaxOfficeHint,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: TextField(
                controller: taxNoController,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: AppInputDecorations.formField(
                  label: UiCopyTr.customerFieldTaxNoLabel,
                  hint: UiCopyTr.customerFieldTaxNoHint,
                  helper: UiCopyTr.customerFieldTaxNoHelper,
                  errorText: taxNoError,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: contactNameController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldContactLabel,
            hint: UiCopyTr.customerFieldContactHint,
          ),
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Adres'),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: addressController,
          maxLines: 2,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldAddressLabel,
            hint: UiCopyTr.customerFieldAddressHint,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: cityController,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'İl',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: TextField(
                controller: districtController,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'İlçe',
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Satış Ayarları'),
        const SizedBox(height: AppSpacing.s8),
        DropdownButtonFormField<int>(
          initialValue: priceListNo,
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldPriceListLabel,
            helper: UiCopyTr.customerFieldPriceListHelper,
          ),
          items: const [1, 2, 3, 4]
              .map(
                (value) => DropdownMenuItem<int>(
                  value: value,
                  child: Text('Fiyat Listesi $value'),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            onPriceListChanged(value);
          },
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Gruplama'),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: groupNameController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: const InputDecoration(
            labelText: 'Grup',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: subGroupNameController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: const InputDecoration(
            labelText: 'Ara Grup',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: subSubGroupNameController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: const InputDecoration(
            labelText: 'Alt Grup',
          ),
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Ticari Ayarlar'),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: dueDaysController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: AppInputDecorations.formField(
            label: UiCopyTr.customerFieldDueDaysLabel,
            hint: UiCopyTr.customerFieldDueDaysHint,
            helper: UiCopyTr.customerFieldDueDaysHelper,
            errorText: dueDaysError,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          UiCopyTr.customerRequiredNote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class CustomerRiskLimitSection extends StatelessWidget {
  const CustomerRiskLimitSection({
    super.key,
    required this.limitAmountController,
    this.limitAmountError,
    required this.warnOnLimitExceeded,
    required this.onWarnOnLimitExceededChanged,
    required this.marketerNameController,
    required this.riskNoteController,
    required this.tagsController,
    required this.isActive,
    required this.onIsActiveChanged,
  });

  final TextEditingController limitAmountController;
  final String? limitAmountError;
  final bool warnOnLimitExceeded;
  final ValueChanged<bool> onWarnOnLimitExceededChanged;
  final TextEditingController marketerNameController;
  final TextEditingController riskNoteController;
  final TextEditingController tagsController;
  final bool isActive;
  final ValueChanged<bool> onIsActiveChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Risk & Limit'),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: limitAmountController,
          decoration: AppInputDecorations.formField(
            label: 'Kredi limiti (TL)',
            errorText: limitAmountError,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const Expanded(
              child: Text('Limit aşıldığında uyar'),
            ),
            Switch(
              value: warnOnLimitExceeded,
              onChanged: onWarnOnLimitExceededChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: marketerNameController,
          decoration: const InputDecoration(
            labelText: 'Pazarlamacı adı soyadı',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: riskNoteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Risk notu (opsiyonel)',
          ),
        ),

        const SizedBox(height: AppSpacing.s16),
        const SectionHeader(title: 'Diğer'),
        const SizedBox(height: AppSpacing.s8),
        TextField(
          controller: tagsController,
          decoration: const InputDecoration(
            labelText: 'Etiketler (virgülle ayırın)',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const Text('Aktif'),
            Switch(
              value: isActive,
              onChanged: onIsActiveChanged,
            ),
          ],
        ),
      ],
    );
  }
}

bool _isValidTrPhoneLocal(String input) {
  try {
    normalizeTrPhone(input);
    return true;
  } catch (_) {
    return false;
  }
}

class CustomerLockedTabPlaceholder extends StatelessWidget {
  const CustomerLockedTabPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onGoToGeneral,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onGoToGeneral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.s8),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s16),
            OutlinedButton(
              onPressed: onGoToGeneral,
              child: const Text('Genel bilgilere git'),
            ),
          ],
        ),
      ),
    );
  }
}

