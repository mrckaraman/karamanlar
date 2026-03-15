import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'otp_auth_controller.dart';

const String _rememberLoginKey = 'customer_remember_login';

/// Uygulama açıldığında, Supabase oturumu varsa ve kullanıcı
/// daha önce "Beni hatırla" seçtiyse, customerIdProvider'ı
/// otomatik doldurur.
final ensureRememberedCustomerSessionProvider =
    FutureProvider.autoDispose<void>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);

  // Oturum yoksa yapılacak bir şey yok.
  if (authRepo.currentUser == null) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final rememberLogin = prefs.getBool(_rememberLoginKey) ?? false;

  if (!rememberLogin) {
    // Kullanıcı oturumu var ama "Beni hatırla" dememişse,
    // customerId otomatik set edilmez; tekrar kod istenir.
    return;
  }

  final currentCustomerId = ref.read(customerIdProvider);
  if (currentCustomerId != null && currentCustomerId.isNotEmpty) {
    // Zaten set edilmişse tekrar sorgulama.
    return;
  }

  try {
    final customerId = await customerUserRepository.getCurrentCustomerId();
    ref.read(customerIdProvider.notifier).state = customerId;
  } catch (_) {
    // Cari eşleştirme hatası olursa sessizce bırak; kullanıcı
    // normal OTP akışıyla devam eder.
  }
});

class CustomerLoginPage extends ConsumerStatefulWidget {
  const CustomerLoginPage({super.key});

  @override
  ConsumerState<CustomerLoginPage> createState() => _CustomerLoginPageState();
}

class _CustomerLoginPageState extends ConsumerState<CustomerLoginPage> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  static const int _phoneOtpCooldownSeconds = 60;
  Timer? _otpCooldownTimer;
  int _otpCooldownRemaining = 0;
  bool _rememberMe = false;

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final otpState = ref.watch(otpAuthControllerProvider);
    final otpCtrl = ref.read(otpAuthControllerProvider.notifier);
    final codeLength = _codeController.text.trim().length;
    final isCodeValid = otpState.mode == LoginContactMode.email
      ? codeLength == 8
      : codeLength == 6;
    final bool isPhoneMode = otpState.mode == LoginContactMode.phone;
    final bool isCooldownActive = isPhoneMode && _otpCooldownRemaining > 0;

    // Uygulama ilk açıldığında, "Beni hatırla" seçilmiş ve
    // Supabase oturumu hala geçerliyse, customerIdProvider
    // otomatik doldurulsun.
    ref.watch(ensureRememberedCustomerSessionProvider);

    // customerIdProvider değiştiğinde (OTP doğrulama sonrası)
    // otomatik olarak ana sayfa (dashboard) ekranına yönlendir.
    ref.listen<String?>(customerIdProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        if (mounted) {
          context.go('/home/dashboard');
        }
      }
    });

    return AppScaffold(
      title: 'Müşteri Giriş',
      showBackButton: false,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  SizedBox(
                    height: 96,
                    child: Center(
                      child: Image.asset(
                        'assets/images/Karamanlar_Ticaret_Uygulama.png',
                        height: 96,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Karamanlar Ticaret',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Müşteri hesabınıza e-posta veya telefonunuza gelen tek kullanımlık kod ile güvenli şekilde giriş yapın.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (otpState.step == OtpAuthStep.enterEmail) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text(
                                      'E-posta ile giriş',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                    selected:
                                        otpState.mode == LoginContactMode.email,
                                    onSelected: (_) {
                                      otpCtrl.setMode(LoginContactMode.email);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text(
                                      'Telefon ile giriş',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                    selected:
                                        otpState.mode == LoginContactMode.phone,
                                    onSelected: (_) {
                                      otpCtrl.setMode(LoginContactMode.phone);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (otpState.mode == LoginContactMode.email)
                              TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'E-posta',
                                  hintText: 'ornek@firma.com',
                                ),
                                keyboardType: TextInputType.emailAddress,
                                onChanged: otpCtrl.setEmail,
                              )
                            else
                              PhoneTrFormField(
                                controller: _phoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Telefon',
                                  hintText: '5441234567',
                                ),
                                textInputAction: TextInputAction.next,
                                onSubmitted: () {},
                                // Değişiklikleri controller state'ine aktar.
                                // PhoneTrFormField içerisinde sadece 10 haneli
                                // yerel numara tutulur.
                                onChanged: otpCtrl.setPhone,
                              ),
                            const SizedBox(height: 24),
                            PrimaryButton(
                              label: otpState.isLoading
                                  ? 'Kod gönderiliyor...'
                                  : isCooldownActive && isPhoneMode
                                      ? 'Tekrar gönder (${_otpCooldownRemaining}s)'
                                      : 'Kodu Gönder',
                              onPressed: otpState.isLoading || isCooldownActive
                                  ? null
                                  : () async {
                                      final s0 = ref.read(
                                        otpAuthControllerProvider,
                                      );
                                      debugPrint(
                                        '[UI] SEND CODE BUTTON PRESSED mode=${s0.mode}',
                                      );
                                      debugPrint('[UI] Send code pressed');
                                      debugPrint(
                                        '[UI] pressed phoneController="${_phoneController.text}" statePhone="${otpState.phone}"',
                                      );

                                      final ok = await otpCtrl.sendCode();
                                      final s = ref.read(
                                        otpAuthControllerProvider,
                                      );
                                      debugPrint(
                                        '[UI] sendCode ok=$ok error=${s.error} step=${s.step} mode=${s.mode} lastSentAt=${s.lastSentAt}',
                                      );
                                      if (!context.mounted) return;
                                      if (ok) {
                                        debugPrint('[UI] OTP OK');
                                        if (isPhoneMode) {
                                          _startOtpCooldown();
                                          if (otpState.step ==
                                              OtpAuthStep.enterCode) {
                                            _codeController.clear();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Yeni kod gönderildi, önceki kod geçersiz.',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Kod gönderildi. Lütfen e-postanızı kontrol edin.',
                                            ),
                                          ),
                                        );
                                      } else {
                                        if (s.error != null &&
                                            s.error!.isNotEmpty) {
                                          debugPrint(
                                            '[UI] OTP FAIL: ${s.error}',
                                          );
                                        }
                                      }
                                    },
                            ),
                          ] else ...[
                            TextField(
                              controller: _codeController,
                              decoration: InputDecoration(
                                labelText:
                                    otpState.mode == LoginContactMode.email
                                        ? '8 haneli kod'
                                        : '6 haneli kod',
                              ),
                              keyboardType: TextInputType.number,
                              maxLength:
                                  otpState.mode == LoginContactMode.email
                                      ? 8
                                      : 6,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: const Text('Beni hatırla'),
                            ),
                            const SizedBox(height: 8),
                            if (otpState.error != null &&
                                otpState.error!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  otpState.error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: otpState.isLoading
                                        ? null
                                        : () {
                                            otpCtrl.backToEmail();
                                            _codeController.clear();
                                          },
                                    child: const Text('Geri'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: PrimaryButton(
                                    label: otpState.isLoading
                                        ? 'Doğrulanıyor...'
                                        : 'Doğrula',
                                    onPressed: otpState.isLoading || !isCodeValid
                                        ? null
                                        : () async {
                                            final success =
                                                await otpCtrl.verifyCode(
                                              _codeController.text,
                                            );
                                            final latestState = ref.read(
                                              otpAuthControllerProvider,
                                            );
                                            final latestCustomerId =
                                                ref.read(customerIdProvider);
                                            String? normalizedPhone;
                                            try {
                                              if (latestState.phone
                                                  .isNotEmpty) {
                                                normalizedPhone =
                                                    normalizeTrPhone(
                                                  latestState.phone,
                                                );
                                              }
                                            } catch (_) {}
                                            debugPrint(
                                              '[UI] verifyCode ok=$success error=${latestState.error} step=${latestState.step} mode=${latestState.mode}',
                                            );
                                            debugPrint(
                                              '[UI] verifyCode post-state step=${latestState.step} customerId=$latestCustomerId phoneE164=$normalizedPhone',
                                            );
                                            if (!context.mounted) return;
                                            if (success) {
                                              try {
                                                final prefs =
                                                    await SharedPreferences
                                                        .getInstance();
                                                await prefs.setBool(
                                                  _rememberLoginKey,
                                                  _rememberMe,
                                                );
                                              } catch (_) {}
                                            } else {
                                              // Başarısız doğrulamada inputu temizle.
                                              _codeController.clear();
                                              if (latestState.error != null &&
                                                  latestState.error!
                                                      .isNotEmpty) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      latestState.error!,
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (otpState.step == OtpAuthStep.enterEmail &&
                              otpState.error != null &&
                              otpState.error!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              otpState.error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Karamanlar Ticaret v0.1.0',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  void _startOtpCooldown() {
    _otpCooldownTimer?.cancel();
    setState(() {
      _otpCooldownRemaining = _phoneOtpCooldownSeconds;
    });
    _otpCooldownTimer =
        Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _otpCooldownRemaining--;
        if (_otpCooldownRemaining <= 0) {
          _otpCooldownRemaining = 0;
          timer.cancel();
        }
      });
    });
  }
}
