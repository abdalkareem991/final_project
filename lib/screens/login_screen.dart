import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../services/supabase_service.dart';
import 'update_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  late final StreamSubscription<AuthState> _authStateSubscription;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _accentColor => _colors.primary;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;
  Color get _panelColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1E293B)
      : _colors.surface;
  Color get _inputColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF000000)
      : _colors.field;

  @override
  void initState() {
    super.initState();

    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((data) {
          if (data.event == AuthChangeEvent.passwordRecovery && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UpdatePasswordScreen(),
              ),
            );
          }
        });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null && mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
        return;
      }
      await _checkAutoBiometricLogin();
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(
      r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$",
      caseSensitive: false,
    ).hasMatch(email);
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _colors.expense : _colors.surface,
      ),
    );
  }

  Future<void> _checkAutoBiometricLogin() async {
    final useBio = await _storage.read(key: 'use_biometrics');
    if (useBio == 'true') {
      await _handleBiometricLogin();
    }
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage(
        context.t(
          'Please enter email and password.',
          'يرجى إدخال البريد الإلكتروني وكلمة المرور.',
        ),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage(
        context.t(
          'Please enter a valid email address.',
          'يرجى إدخال بريد إلكتروني صحيح.',
        ),
      );
      return;
    }

    if (password.length < 6) {
      _showMessage(
        context.t(
          'Password must be at least 6 characters.',
          'يجب أن تكون كلمة المرور 6 أحرف على الأقل.',
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _supabaseService.signIn(email, password);
      final user = response.user ?? Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw Exception(
          context.t(
            'Login failed. Please try again.',
            'فشل تسجيل الدخول. حاول مرة أخرى.',
          ),
        );
      }

      await _supabaseService.ensureUserProfile(userId: user.id);
      await _storage.write(key: 'email', value: email);
      // TODO(security): Replace password-backed biometric login with a
      // Supabase session/refresh-token unlock flow after the current release.
      await _storage.write(key: 'password', value: password);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      _showMessage(
        context.t(
          'Login failed. Check your email and password.',
          'فشل تسجيل الدخول. تحقق من البريد الإلكتروني وكلمة المرور.',
        ),
      );
      debugPrint('Login error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_isLoading) return;

    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) return;

      final didAuthenticate = await _auth.authenticate(
        localizedReason: context.t(
          'Please authenticate to access your account.',
          'يرجى التحقق للوصول إلى حسابك.',
        ),
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!didAuthenticate) return;

      final savedEmail = await _storage.read(key: 'email');
      final savedPassword = await _storage.read(key: 'password');

      if (savedEmail == null || savedPassword == null) {
        _showMessage(
          context.t(
            'Please log in with password first to enable biometrics.',
            'يرجى تسجيل الدخول بكلمة المرور أولاً لتفعيل البصمة.',
          ),
        );
        return;
      }

      setState(() => _isLoading = true);
      final response = await _supabaseService.signIn(savedEmail, savedPassword);
      final user = response.user ?? Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw Exception('Biometric login failed');
      }

      await _supabaseService.ensureUserProfile(userId: user.id);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController();

    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.t('Reset Password', 'إعادة تعيين كلمة المرور'),
          style: TextStyle(color: _textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(
                'Enter your email to receive a password reset link.',
                'أدخل بريدك الإلكتروني لاستلام رابط إعادة التعيين.',
              ),
              style: TextStyle(color: _secondaryTextColor, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              style: TextStyle(color: _textColor),
              decoration: InputDecoration(
                hintText: 'name@domain.com',
                hintStyle: TextStyle(color: _mutedTextColor),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.t('Cancel', 'إلغاء')),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (!_isValidEmail(email)) {
                _showMessage(
                  context.t(
                    'Please enter a valid email address.',
                    'يرجى إدخال بريد إلكتروني صحيح.',
                  ),
                );
                return;
              }

              try {
                await _supabaseService.sendPasswordResetEmail(email);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showMessage(
                  context.t(
                    'Reset link sent. Please check your email.',
                    'تم إرسال رابط إعادة التعيين. تحقق من بريدك.',
                  ),
                  isError: false,
                );
              } catch (e) {
                _showMessage(
                  context.t(
                    'Could not send reset email right now.',
                    'تعذر إرسال بريد إعادة التعيين الآن.',
                  ),
                );
                debugPrint('Reset password error: $e');
              }
            },
            child: Text(context.t('Send', 'إرسال')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: AppTheme.isLightMode
                          ? context.t(
                              'Switch to dark mode',
                              'التبديل إلى الوضع الداكن',
                            )
                          : context.t(
                              'Switch to light mode',
                              'التبديل إلى الوضع الفاتح',
                            ),
                      onPressed: () =>
                          AppTheme.setLightMode(!AppTheme.isLightMode),
                      icon: Icon(
                        AppTheme.isLightMode
                            ? Icons.dark_mode
                            : Icons.light_mode,
                        color: _accentColor,
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('Switch language', 'تبديل اللغة'),
                      onPressed: AppText.toggle,
                      icon: Icon(Icons.language, color: _accentColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, color: _accentColor, size: 30),
                  const SizedBox(width: 10),
                  Text(
                    context.t('Financial Mind', 'فايننشال مايند'),
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),
              Text(
                context.t('Welcome Back', 'مرحبًا بعودتك'),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.t(
                  'Enter your credentials to access your vault',
                  'أدخل بياناتك للوصول إلى حسابك',
                ),
                style: TextStyle(color: _secondaryTextColor, fontSize: 14),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _colors.subtleBorder),
                  boxShadow: Theme.of(context).brightness == Brightness.light
                      ? [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('EMAIL', 'البريد الإلكتروني'),
                      style: TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _emailController,
                      hint: 'name@domain.com',
                      icon: Icons.person,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.t('PASSWORD', 'كلمة المرور'),
                          style: TextStyle(
                            color: _secondaryTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: Text(
                            context.t('Forgot Password?', 'نسيت كلمة المرور؟'),
                            style: TextStyle(color: _accentColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    _buildTextField(
                      controller: _passwordController,
                      hint: '••••••••',
                      icon: Icons.lock,
                      isPassword: true,
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        ),
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: _mutedTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    _isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: _accentColor,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentColor,
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              context.t('Log In', 'تسجيل الدخول'),
                              style: TextStyle(
                                color: _colors.onPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 50),
              GestureDetector(
                onTap: _handleBiometricLogin,
                child: _buildQuickLoginIcon(Icons.fingerprint),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword && !_isPasswordVisible,
      style: TextStyle(color: _textColor),
      decoration: InputDecoration(
        filled: true,
        fillColor: _inputColor,
        hintText: hint,
        hintStyle: TextStyle(color: _mutedTextColor),
        prefixIcon: Icon(icon, color: _mutedTextColor),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildQuickLoginIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colors.subtleBorder),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: _accentColor, size: 30),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      color: _bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.login, context.t('LOGIN', 'الدخول'), true),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/register'),
            child: _buildNavItem(
              Icons.person_add_outlined,
              context.t('REGISTER', 'التسجيل'),
              false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    final color = isActive ? _accentColor : _mutedTextColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        Text(label, style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}
