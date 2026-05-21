import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../services/supabase_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _storage = const FlutterSecureStorage();
  final _supabaseService = SupabaseService();

  bool _isLoading = false;
  bool _agreeToTerms = false;
  bool _enableBiometrics = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _accentColor => _colors.primary;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;
  Color get _panelColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF111D1D)
      : _colors.surface;
  Color get _inputColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF000000)
      : _colors.field;

  @override
  void dispose() {
    _userNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _handleRegister() async {
    if (_isLoading) return;

    final fullName = _userNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty || email.isEmpty || phone.isEmpty) {
      _showMessage(
        context.t(
          'Please complete all required fields.',
          'يرجى تعبئة جميع الحقول المطلوبة.',
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

    if (password != confirmPassword) {
      _showMessage(
        context.t(
          'Password confirmation does not match.',
          'تأكيد كلمة المرور غير مطابق.',
        ),
      );
      return;
    }

    if (!_agreeToTerms) {
      _showMessage(
        context.t(
          'Please agree to the terms first.',
          'يرجى الموافقة على الشروط أولاً.',
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _supabaseService.signUp(email, password);
      final user = response.user;

      if (user == null) {
        throw Exception('User creation failed');
      }

      await _supabaseService.ensureUserProfile(
        userId: user.id,
        fullName: fullName,
        phone: phone,
      );

      await _storage.write(key: 'email', value: email);
      await _storage.write(key: 'password', value: password);
      await _storage.write(
        key: 'use_biometrics',
        value: _enableBiometrics ? 'true' : 'false',
      );

      if (response.session != null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      } else {
        _showMessage(
          context.t(
            'Account created. Please verify your email, then log in.',
            'تم إنشاء الحساب. يرجى تأكيد البريد الإلكتروني ثم تسجيل الدخول.',
          ),
          isError: false,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      _showMessage(
        context.t(
          'Could not create the account right now.',
          'تعذر إنشاء الحساب الآن.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.lock, color: _accentColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.t('Financial Mind', 'فايننشال مايند'),
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.t('Switch language', 'تبديل اللغة'),
                    onPressed: AppText.toggle,
                    icon: Icon(Icons.language, color: _accentColor),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: context.t('Join ', 'انضم إلى ')),
                    TextSpan(
                      text: context.t('Financial\nMind', 'فايننشال\nمايند'),
                      style: TextStyle(color: _accentColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Text(
                context.t(
                  'Create your account and keep your money flow organized.',
                  'أنشئ حسابك ونظّم تدفقك المالي بشكل واضح وآمن.',
                ),
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _colors.subtleBorder),
                  boxShadow: Theme.of(context).brightness == Brightness.light
                      ? [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.07),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputField(
                      label: context.t('USER NAME', 'اسم المستخدم'),
                      controller: _userNameController,
                      hint: 'John Doe',
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      label: context.t('EMAIL ADDRESS', 'البريد الإلكتروني'),
                      controller: _emailController,
                      hint: 'example@email.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      label: context.t('PHONE NUMBER', 'رقم الهاتف'),
                      controller: _phoneController,
                      hint: '07XXXXXXXX',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      label: context.t('PASSWORD', 'كلمة المرور'),
                      controller: _passwordController,
                      hint: '••••••••',
                      isPassword: true,
                      isVisible: _isPasswordVisible,
                      onToggleVisibility: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      label: context.t('CONFIRM PASSWORD', 'تأكيد كلمة المرور'),
                      controller: _confirmPasswordController,
                      hint: '••••••••',
                      isPassword: true,
                      isVisible: _isConfirmPasswordVisible,
                      onToggleVisibility: () => setState(
                        () => _isConfirmPasswordVisible =
                            !_isConfirmPasswordVisible,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: Checkbox(
                            value: _agreeToTerms,
                            onChanged: (value) =>
                                setState(() => _agreeToTerms = value ?? false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: context.t('I agree to the ', 'أوافق على '),
                              style: TextStyle(
                                color: _mutedTextColor,
                                fontSize: 13,
                              ),
                              children: [
                                TextSpan(
                                  text: context.t(
                                    'Terms and Privacy Policy',
                                    'الشروط وسياسة الخصوصية',
                                  ),
                                  style: TextStyle(
                                    color: _accentColor,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _inputColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _colors.subtleBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.fingerprint,
                              color: _accentColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              context.t(
                                'Enable biometrics for future logins',
                                'فعّل البصمة لتسجيل الدخول لاحقًا',
                              ),
                              style: TextStyle(
                                color: _textColor,
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Switch(
                            value: _enableBiometrics,
                            onChanged: (value) =>
                                setState(() => _enableBiometrics = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 35),
                    _isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: _accentColor,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentColor,
                              minimumSize: const Size(double.infinity, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              context.t('Create Account', 'إنشاء الحساب'),
                              style: TextStyle(
                                color: _colors.onPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.t(
                      'Already have an account? ',
                      'لديك حساب بالفعل؟ ',
                    ),
                    style: TextStyle(color: _mutedTextColor, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      context.t('Log In', 'تسجيل الدخول'),
                      style: TextStyle(
                        color: _accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _mutedTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword && !isVisible,
          keyboardType: keyboardType,
          style: TextStyle(color: _textColor, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _mutedTextColor),
            filled: true,
            fillColor: _inputColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    onPressed: onToggleVisibility,
                    icon: Icon(
                      isVisible ? Icons.visibility : Icons.visibility_off,
                      color: _mutedTextColor,
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
