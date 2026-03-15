import 'package:core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens/app_radius.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _rememberMe = false;
  String? _inlineError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _inlineError = null;
    });

    final repo = ref.read(authRepositoryProvider);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final res = await repo.signInWithEmail(
        email: email,
        password: password,
      );

      // Debug: oturum ve kullanıcı bilgisini yazdır.
      repo.debugPrintCurrentAuthState(label: 'LOGIN');
      if (kDebugMode) {
        debugPrint('[LOGIN] res.session=${res.session} userId=${res.user?.id}');
      }

      if (!mounted) return;

      final session = res.session ?? Supabase.instance.client.auth.currentSession;
      if (session == null) {
        // Oturum oluşmadıysa, generic hata göster.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş başarısız: oturum oluşturulamadı.'),
          ),
        );
        return;
      }

      // Başarılı login sonrası, admin kontrolü ayrı bir gate/RPC üzerinden
      // yapılacağından burada sadece dashboard'a yönlendiriyoruz.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hoş geldiniz, yönlendiriliyorsunuz…')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      context.go('/dashboard');
    } on AuthException catch (e) {
      if (!mounted) return;
      final code = e.code?.toLowerCase() ?? '';
      final message = e.message;

      final isCredentialError =
          code.contains('invalid') ||
          message.toLowerCase().contains('invalid login') ||
          message.toLowerCase().contains('invalid credentials');

      if (isCredentialError) {
        setState(() {
          _inlineError = 'E-posta veya şifre hatalı. Lütfen tekrar deneyin.';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Giriş hatası: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beklenmeyen hata: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF020617),
                Color(0xFF111827),
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 96,
                        child: Center(
                          child: Image.asset(
                            'assets/images/Karamanlar_Yonetici_Uygulama.png',
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Text(
                        'Karamanlar Ticaret – Yönetim Paneli',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        'E-posta ve şifrenizle yönetim paneline güvenli giriş yapın.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s24),
                      Card(
                        color: colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.card),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.s16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_inlineError != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(
                                      AppSpacing.s8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.chip),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color:
                                            colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(
                                          width: AppSpacing.s8),
                                      Expanded(
                                        child: Text(
                                          _inlineError!,
                                          style: TextStyle(
                                            color: colorScheme
                                                .onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s12),
                              ],
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'E-posta',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Şifre',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: _loading
                                        ? null
                                        : (v) {
                                            setState(() {
                                              _rememberMe = v ?? false;
                                            });
                                          },
                                  ),
                                  const SizedBox(width: AppSpacing.s4),
                                  Expanded(
                                    child: Text(
                                      'Bu cihazda oturum açık kalsın',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s16),
                              PrimaryButton(
                                label: _loading
                                    ? 'Giriş yapılıyor…'
                                    : 'Giriş yap',
                                onPressed: _loading ? null : _signIn,
                                expand: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Text(
                        'Karamanlar Ticaret v0.1.0',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
