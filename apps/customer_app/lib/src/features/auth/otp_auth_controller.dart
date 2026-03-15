import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Girişte kullanılan iletişim bilgisi modu.
///
/// email: E-posta ile giriş
/// phone: Telefon (SMS) ile giriş
enum LoginContactMode { email, phone }

enum OtpAuthStep { enterEmail, enterCode, done }

class OtpAuthState {
  const OtpAuthState({
    required this.step,
    required this.mode,
    required this.email,
    required this.phone,
    required this.isLoading,
    this.error,
    this.lastCodeSentAt,
    this.lastSentAt,
  });

  const OtpAuthState.initial()
      : step = OtpAuthStep.enterEmail,
        mode = LoginContactMode.email,
        email = '',
        phone = '',
        isLoading = false,
        error = null,
        lastCodeSentAt = null,
        lastSentAt = null;

  static const Object _lastCodeSentinel = Object();
  static const Object _errorSentinel = Object();

  final OtpAuthStep step;
  final LoginContactMode mode;
  final String email;
  final String phone;
  final bool isLoading;
  final String? error;
  final DateTime? lastCodeSentAt;
  final DateTime? lastSentAt;

  OtpAuthState copyWith({
    OtpAuthStep? step,
    LoginContactMode? mode,
    String? email,
    String? phone,
    bool? isLoading,
    Object? error = _errorSentinel,
    Object? lastCodeSentAt = _lastCodeSentinel,
    Object? lastSentAt = _lastCodeSentinel,
  }) {
    final String? resolvedError = identical(error, _errorSentinel)
        ? this.error
        : error as String?;

    return OtpAuthState(
      step: step ?? this.step,
      mode: mode ?? this.mode,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
      error: resolvedError,
      lastCodeSentAt: identical(lastCodeSentAt, _lastCodeSentinel)
          ? this.lastCodeSentAt
          : lastCodeSentAt as DateTime?,
      lastSentAt: identical(lastSentAt, _lastCodeSentinel)
          ? this.lastSentAt
          : lastSentAt as DateTime?,
    );
  }
}

class OtpAuthController extends StateNotifier<OtpAuthState> {
  OtpAuthController(this._ref) : super(const OtpAuthState.initial());

  final Ref _ref;

  bool _fail(String message, {String? where}) {
    if (where != null) {
      debugPrint('[OTP] verifyCode FAIL at $where: $message');
    } else {
      debugPrint('[OTP] verifyCode FAIL: $message');
    }
    state = state.copyWith(error: message);
    return false;
  }

  void setMode(LoginContactMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode, error: null);
  }

  void setEmail(String value) {
    final normalized = value.trim().toLowerCase();
    state = state.copyWith(email: normalized, error: null);
  }

  void setPhone(String value) {
    final normalized = value.trim();
    state = state.copyWith(phone: normalized, error: null);
  }

  Future<bool> sendCode() async {
    debugPrint('[DEBUG] sendCode START mode=${state.mode} step=${state.step}');

    // Devam eden bir istek varken yeni istek atma.
    if (state.isLoading) {
      return false;
    }

    final mode = state.mode;

    final email = state.email.trim().toLowerCase();
    final phoneRaw = state.phone.trim();

    debugPrint('[SIGNATURE] OtpAuthController.sendCode reached mode=$mode email="$email" phoneRaw="$phoneRaw"');

    if (mode == LoginContactMode.email && email.isEmpty) {
      state = state.copyWith(error: 'E-posta zorunludur.');
      return false;
    }

    // Aynı adrese kısa sürede tekrar kod isteme için cooldown uygula.
    final now = DateTime.now();
    const cooldown = Duration(seconds: 60);
    final last = state.lastCodeSentAt;
    if (last != null) {
      final diff = now.difference(last);
      if (diff < cooldown) {
        // Cooldown süresi dolmadan tekrar istek gelirse yeni kod gönderme.
        state = state.copyWith(
          error: 'Kod zaten gönderildi. Lütfen 30 sn bekleyin.',
        );
        return false;
      }
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final client = supabaseClient;

      if (mode == LoginContactMode.email) {
        dynamic row;
        try {
          row = await client
              .rpc('check_customer_email', params: {'email_input': email})
              .maybeSingle();
        } catch (e, st) {
          debugPrint('[OTP] EMAIL FLOW: customer check RPC error: $e');
          debugPrint('$st');
          state = state.copyWith(
            error: 'Müşteri kontrolü başarısız. Lütfen tekrar deneyin.',
          );
          return false;
        }

        bool exists = false;
        bool isActive = true;

        if (row is Map<String, dynamic>) {
          final existsVal = row['exists'];
          final isActiveVal = row['is_active'];
          exists = existsVal == true;
          isActive = isActiveVal == null ? true : isActiveVal == true;
        }

        debugPrint('[OTP] EMAIL FLOW: rowExists=$exists isActive=$isActive rowType=${row.runtimeType}');

        if (!exists) {
          state = state.copyWith(
            error: 'Bu e-posta ile kayıtlı müşteri bulunamadı.',
          );
          return false;
        }

        if (!isActive) {
          state = state.copyWith(
            error:
                'Hesabınız pasif. Lütfen destek ile iletişime geçin.',
          );
          return false;
        }

        try {
          await client.auth.signInWithOtp(
            email: email,
            shouldCreateUser: false,
          );
        } on AuthException catch (e, st) {
          debugPrint('[OTP] EMAIL FLOW: OTP AUTH ERROR $e');
          debugPrint(st.toString());
          // AuthException türlerini dıştaki handler'a ilet.
          rethrow;
        } catch (e, st) {
          debugPrint('[OTP] EMAIL FLOW: OTP ERROR $e');
          debugPrint(st.toString());
          state = state.copyWith(
            error: 'Kod gönderilemedi. Lütfen tekrar deneyin.',
          );
          return false;
        }
      } else {
        // phoneRaw burada yalnızca 10 hanelik yerel GSM (örn. 5334464480)
        // olmalıdır. normalizeTrPhone ile E.164 '+90XXXXXXXXXX' formatına
        // çevrilir.
        String phoneE164;
        try {
          phoneE164 = normalizeTrPhone(phoneRaw);
          debugPrint('[DEBUG] phoneE164=$phoneE164 from raw=$phoneRaw');
        } catch (e, st) {
          debugPrint('[OTP] PHONE FLOW: normalize error: $e');
          debugPrint('$st');
          state = state.copyWith(
            error: 'Geçerli bir telefon girin (5334464480)',
          );
          return false;
        }

        dynamic row;
        try {
          row = await client
              .rpc(
                'check_customer_phone',
                params: {'phone_e164': phoneE164},
              )
              .maybeSingle();
        } catch (e, st) {
          debugPrint('[OTP] PHONE FLOW: customer check RPC error: $e');
          debugPrint('$st');

          final errText = e.toString().toLowerCase();
          if (errText.contains('failed host lookup') ||
              errText.contains('socketexception')) {
            state = state.copyWith(
              error:
                  'Sunucuya ulaşılamıyor. İnternet bağlantınızı / DNS-VPN ayarlarınızı kontrol edin.',
            );
            return false;
          }

          state = state.copyWith(
            error: 'Müşteri kontrolü başarısız. Lütfen tekrar deneyin.',
          );
          return false;
        }

        bool exists = false;
        bool isActive = true;

        if (row is Map<String, dynamic>) {
          final existsVal = row['exists'];
          final isActiveVal = row['is_active'];
          exists = existsVal == true;
          isActive = isActiveVal == null ? true : isActiveVal == true;
        }

        debugPrint('[OTP] PHONE FLOW: rowExists=$exists isActive=$isActive rowType=${row.runtimeType}');

        if (!exists) {
          state = state.copyWith(
            error: 'Bu telefon numarası sistemde kayıtlı değil.',
          );
          return false;
        }

        if (!isActive) {
          state = state.copyWith(
            error:
                'Hesabınız pasif. Lütfen destek ile iletişime geçin.',
          );
          return false;
        }

        try {
          await client.auth.signInWithOtp(
            phone: phoneE164,
            shouldCreateUser: true,
          );
        } on AuthException catch (e, st) {
          debugPrint('[OTP] PHONE FLOW: OTP AUTH ERROR $e');
          debugPrint(st.toString());
          // AuthException türlerini dıştaki handler'a ilet.
          rethrow;
        } catch (e, st) {
          debugPrint('[OTP] PHONE FLOW: OTP ERROR $e');
          debugPrint(st.toString());
          state = state.copyWith(
            error: 'Kod gönderilemedi. Lütfen tekrar deneyin.',
          );
          return false;
        }
      }
      state = state.copyWith(
        step: OtpAuthStep.enterCode,
        error: null,
        lastCodeSentAt: DateTime.now(),
        lastSentAt: DateTime.now(),
      );
      return true;
    } on AuthException catch (e) {
      final status = e.statusCode?.toString();
      final msg = e.message.toLowerCase();

      debugPrint(
        '[OTP] sendCode AuthException status=$status message=${e.message}',
      );

      if (msg.contains('otp_disabled')) {
        state = state.copyWith(
          error:
              'Telefon ile giriş şu anda aktif değil. Lütfen sistem yöneticisine başvurun.',
        );
      } else if (msg.contains('sms_provider_not_configured') ||
          msg.contains('sms_provider_disabled')) {
        state = state.copyWith(
          error:
              'SMS OTP servisi yapılandırılmamış. Lütfen sistem yöneticisine başvurun.',
        );
      } else if (status == '422') {
        state = state.copyWith(
          error: 'Bu email/telefon için müşteri kullanıcısı yok.',
        );
      } else if (status == '429') {
        state = state.copyWith(
          error: 'Çok fazla deneme. Bir süre bekleyin.',
        );
      } else if (status == '403') {
        state = state.copyWith(
          error: 'Kod süresi dolmuş veya geçersiz. Yeni kod isteyin.',
        );
      } else {
        state = state.copyWith(
          error: 'Kod gönderilemedi. Lütfen tekrar deneyin.',
        );
      }

      return false;
    } catch (e) {
      debugPrint('[OTP] sendCode generic exception: $e');
      state = state.copyWith(
        error: 'Kod gönderilemedi. Lütfen tekrar deneyin.',
      );
      return false;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> verifyCode(String code) async {
    final mode = state.mode;
    final email = state.email.trim().toLowerCase();
    final phoneRaw = state.phone.trim();
    final trimmedCode = code.trim();

    debugPrint(
      '[OTP] verifyCode start mode=$mode tokenLen=${trimmedCode.length}',
    );

    // Sadece kod uzunluğunu debug log'la (içeriği değil).
    assert(() {
      debugPrint('verifyCode length: ${trimmedCode.length}');
      return true;
    }());

    // Devam eden bir doğrulama isteği varsa yeni istek atma.
    if (state.isLoading) {
      return _fail(
        'Devam eden bir doğrulama isteği var. Lütfen bekleyin.',
        where: 'already_loading',
      );
    }

    if (mode == LoginContactMode.email && email.isEmpty) {
      return _fail('E-posta zorunludur.', where: 'email_empty');
    }
    // Email OTP için 8 hane, telefon OTP için 6 hane beklenir.
    if (mode == LoginContactMode.email && trimmedCode.length != 8) {
      return _fail('Kod 8 haneli olmalıdır.', where: 'email_code_length');
    }
    if (mode == LoginContactMode.phone && trimmedCode.length != 6) {
      return _fail('Kod 6 haneli olmalıdır.', where: 'phone_code_length');
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final client = supabaseClient;
      String? phoneE164ForLink;

      // 1) OTP'yi Supabase ile doğrula ve AuthResponse döndür.
      AuthResponse res;
      if (mode == LoginContactMode.email) {
        res = await client.auth.verifyOTP(
          email: email,
          token: trimmedCode,
          type: OtpType.email,
        );
      } else {
        // phoneRaw yine 10 hanelik yerel GSM; E.164'e çevir.
        try {
          phoneE164ForLink = normalizeTrPhone(phoneRaw);
        } on ArgumentError {
          state = state.copyWith(
            error: 'Geçerli bir telefon girin (5334464480)',
          );
          return false;
        }

        debugPrint('[OTP] verify sms phone=$phoneE164ForLink tokenLen=${trimmedCode.length}');

        res = await client.auth.verifyOTP(
          phone: phoneE164ForLink,
          token: trimmedCode,
          type: OtpType.sms,
        );
      }

      // 2) AuthResponse içinden session ve user'ı al.
      Session? session = res.session;
      User? user = res.user;

      debugPrint(
        '[OTP] verifyCode AuthResponse: hasSession=${session != null} hasUser=${user != null} userId=${user?.id}',
      );
      debugPrint(
        '[OTP] verifyCode auth userId=${user?.id} user.phone=${user?.phone}',
      );
      debugPrint(
        '[OTP] verifyCode current (before retry): hasSession=${client.auth.currentSession != null} hasUser=${client.auth.currentUser != null} currentUserId=${client.auth.currentUser?.id}',
      );

      // Web'de yaşanan race condition için 3 kez retry et.
      if (session == null || user == null) {
        for (var i = 0;
            i < 3 && (session == null || user == null);
            i++) {
          await Future.delayed(const Duration(milliseconds: 150));
          session = client.auth.currentSession;
          user = client.auth.currentUser;
        }
      }

      debugPrint(
        '[OTP] verifyCode current (after retry): hasSession=${session != null} hasUser=${user != null} sessionUserId=${user?.id}',
      );

      if (session == null || user == null) {
        return _fail(
          'OTP doğrulama hatası: Oturum oluşturulamadı. Lütfen yeni bir kod isteyin.',
          where: 'session_or_user_null',
        );
      }

      // 3) Kullanıcı ile müşteri kaydını eşleştir.
      String customerId = '';
      if (mode == LoginContactMode.phone) {
        // verifyOTP başarılı olduktan hemen sonra: otomatik müşteri bağlama.
        // Not: RPC param adı DB fonksiyonundaki argümanla uyumlu olmalı.
        // Bu projede signature: link_customer_phone_to_user(phone_e164 text)
        final currentUser = client.auth.currentUser ?? user;
        final rawPhone = (currentUser.phone?.trim().isNotEmpty ?? false)
            ? currentUser.phone!.trim()
            : phoneRaw;

        if (rawPhone.isEmpty) {
          debugPrint('[OTP] AUTO LINK: user.phone is empty');
          return _fail(
            'Geçerli bir telefon girin (5334464480)',
            where: 'no_phone_source',
          );
        }

        try {
          phoneE164ForLink = normalizeTrPhone(rawPhone);
        } catch (e) {
          debugPrint('[OTP] AUTO LINK: normalize failed err=$e');
          return _fail(
            'Geçerli bir telefon girin (5334464480)',
            where: 'normalize_verify',
          );
        }

        dynamic linkRow;
        try {
          linkRow = await client
              .rpc(
                'link_customer_phone_to_user',
                params: {'phone_e164': phoneE164ForLink},
              )
              .maybeSingle();
        } catch (e, st) {
          final errText = e.toString().toLowerCase();
          debugPrint('[OTP] AUTO LINK RPC error=$errText');
          debugPrint(st.toString());

          if (errText.contains('not_authenticated')) {
            return _fail(
              'Oturum geçersiz veya süresi dolmuş. Lütfen tekrar giriş yapın.',
              where: 'not_authenticated_rpc',
            );
          }
          if (errText.contains('customer_not_found')) {
            return _fail(
              'Bu telefon ile kayıtlı cari bulunamadı.',
              where: 'customer_not_found_phone_rpc',
            );
          }
          if (errText.contains('phone_linked_to_another_user')) {
            return _fail(
              'Bu telefon zaten başka hesaba bağlı. Yöneticiyle iletişime geçin.',
              where: 'phone_linked_to_another_user',
            );
          }

          return _fail(
            'Cari eşleştirme hatası. Lütfen tekrar deneyin.',
            where: 'link_phone_rpc_error',
          );
        }

        final linkedCustomerId = linkRow is Map<String, dynamic>
            ? linkRow['customer_id'] as String?
            : null;

        if (linkedCustomerId == null || linkedCustomerId.isEmpty) {
          debugPrint('[OTP] AUTO LINK: missing customer_id in rpc response');
          return _fail(
            'Cari eşleştirme hatası. Lütfen tekrar deneyin.',
            where: 'link_phone_rpc_missing_customer_id',
          );
        }

        customerId = linkedCustomerId;
      } else {
        // Email OTP sonrasında müşteri kaydı, doğrudan
        // customers.auth_user_id = auth.currentUser.id kuralına göre
        // repository üzerinden çözülür.
        final customer = await customerRepository.fetchCurrentCustomer();

        if (customer == null) {
          debugPrint(
            '[OTP] CUSTOMER LOOKUP AUTH: no customer for authUserId=${user.id}',
          );
          return _fail(
            'Bu hesap ile eşleştirilmiş cari bulunamadı. Lütfen firma ile iletişime geçin.',
            where: 'customer_not_found_auth_user',
          );
        }

        customerId = customer.id;
        debugPrint(
          '[OTP] CUSTOMER LOOKUP AUTH: authUserId=${user.id} customerId=$customerId',
        );
      }

      if (customerId.isEmpty) {
        debugPrint('[OTP] CUSTOMER LINK: customerId is null/empty');
        return _fail(
          'Cari eşleştirme hatası. Lütfen tekrar deneyin.',
          where: 'customer_id_null',
        );
      }

      _ref.read(customerIdProvider.notifier).state = customerId;
      state = state.copyWith(
        step: OtpAuthStep.done,
        error: null,
      );
      return true;
    } catch (e, st) {
      debugPrint('verifyCode error: $e');
      debugPrint(st.toString());
      return _fail(
        'OTP doğrulanamadı. Lütfen tekrar deneyin.',
        where: 'exception',
      );
    } finally {
      state = state.copyWith(isLoading: false, error: state.error);
    }
  }

  void backToEmail() {
    state = state.copyWith(
      step: OtpAuthStep.enterEmail,
      isLoading: false,
      error: null,
    );
  }
}
final otpAuthControllerProvider =
    StateNotifierProvider.autoDispose<OtpAuthController, OtpAuthState>(
  (ref) => OtpAuthController(ref),
);
