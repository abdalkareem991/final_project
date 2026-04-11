// lib/screens/register_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // --- Theme Constants (Pixel-Perfect match to your image) ---
  static const Color _bgColor = Color(
    0xFF061414,
  ); // Dark background matching the app
  static const Color _inputColor = Color(
    0xFF000000,
  ); // Pure black for input fields
  static const Color _cardColor = Color(
    0xFF111D1D,
  ); // Slightly lighter for the biometrics card
  static const Color _accentGreen = Color(0xFF34EAB9); // Vibrant Mint Green
  static const Color _textGrey = Color(
    0xFF8B92A5,
  ); // Soft grey for labels and subtitles

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

  @override
  void dispose() {
    _userNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Logic: Validates inputs and handles user registration
  Future<void> _handleRegister() async {
    if (_userNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showErrorSnackBar('Please fill in all fields.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('Passwords do not match.');
      return;
    }

    if (!_agreeToTerms) {
      _showErrorSnackBar('You must agree to the Terms and Privacy Policy.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse response = await _supabaseService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (response.user != null) {
        await _supabaseService.createUserProfile(
          response.user!.id,
          _userNameController.text.trim(),
          _phoneController.text.trim(),
        );

        await _storage.write(key: 'email', value: _emailController.text.trim());
        await _storage.write(
          key: 'password',
          value: _passwordController.text.trim(),
        );

        if (_enableBiometrics) {
          await _storage.write(key: 'use_biometrics', value: 'true');
        } else {
          await _storage.delete(key: 'use_biometrics');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registration Successful!',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: _accentGreen,
            ),
          );
          Navigator.pop(context);
        }
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Logo & Brand Name
              Row(
                children: [
                  const Icon(Icons.lock, color: _accentGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Financial Mind',
                    style: TextStyle(
                      color: _accentGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // 2. Main Title (RichText for mixed colors)
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: 'Join '),
                    TextSpan(
                      text: 'Financial\nMind',
                      style: TextStyle(color: _accentGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),

              // 3. Subtitle
              const Text(
                'Secure your future with the sovereign\npulse of wealth management.',
                style: TextStyle(color: _textGrey, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 40),

              // 4. Form Fields (No icons inside, simple and dark)
              _buildInputField(
                label: 'USER NAME',
                controller: _userNameController,
                hint: 'John Doe',
              ),
              const SizedBox(height: 20),

              _buildInputField(
                label: 'EMAIL ADDRESS',
                controller: _emailController,
                hint: 'example@email.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),

              _buildInputField(
                label: 'PHONE NUMBER',
                controller: _phoneController,
                hint: '07 XXXX XXXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              _buildInputField(
                label: 'PASSWORD',
                controller: _passwordController,
                hint: '••••••••',
                isPassword: true,
              ),
              const SizedBox(height: 20),

              _buildInputField(
                label: 'CONFIRM PASSWORD',
                controller: _confirmPasswordController,
                hint: '••••••••',
                isPassword: true,
              ),
              const SizedBox(height: 30),

              // 5. Terms and Conditions
              Row(
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: Checkbox(
                      value: _agreeToTerms,
                      activeColor: _accentGreen,
                      checkColor: Colors.black,
                      side: const BorderSide(color: _textGrey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (value) =>
                          setState(() => _agreeToTerms = value ?? false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'I agree to the ',
                        style: TextStyle(color: _textGrey, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Terms and Privacy Policy',
                            style: TextStyle(
                              color: _accentGreen,
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

              // 6. Biometrics Toggle Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: Colors.blueAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Text(
                        'Enable Biometrics for future\nlogins',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _enableBiometrics,
                      activeThumbColor: _accentGreen,
                      inactiveTrackColor: Colors.black,
                      onChanged: (value) =>
                          setState(() => _enableBiometrics = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 35),

              // 7. Submit Button (With glowing effect)
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accentGreen),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: _accentGreen.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        onPressed: _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0, // Handled by container shadow
                        ),
                        child: const Text(
                          'Create Account',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),

              const SizedBox(height: 30),

              // 8. Login Navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(color: _textGrey, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        color: _accentGreen,
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

  /// UI Helper: Custom input field exactly matching the image
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textGrey,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.15)),
            filled: true,
            fillColor: _inputColor, // Pure black background
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _accentGreen, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
