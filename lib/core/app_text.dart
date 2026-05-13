import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppText {
  static const String languageKey = 'app_language';
  static final ValueNotifier<String> languageCode = ValueNotifier<String>('en');

  static bool get isArabic => languageCode.value == 'ar';

  static Locale get locale => Locale(languageCode.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(languageKey);
    final legacyLanguage = prefs.getString('language');

    final code =
        savedCode ??
        (legacyLanguage == 'Arabic'
            ? 'ar'
            : legacyLanguage == 'English'
            ? 'en'
            : 'en');

    languageCode.value = _normalizeCode(code);
    await _persist(languageCode.value);
  }

  static Future<void> setLanguageCode(String code) async {
    final normalizedCode = _normalizeCode(code);
    if (languageCode.value != normalizedCode) {
      languageCode.value = normalizedCode;
    }
    await _persist(normalizedCode);
  }

  static Future<void> toggle() async {
    await setLanguageCode(isArabic ? 'en' : 'ar');
  }

  static String t(String english, String arabic) {
    return isArabic ? arabic : english;
  }

  static String enumText(String value) {
    if (!isArabic) return value;

    return switch (value) {
      'Income' => 'دخل',
      'Expense' => 'مصروف',
      'Transfer' => 'تحويل',
      'Cash' => 'نقد',
      'Bank' => 'بنك',
      'Manual' => 'يدوي',
      'Automated' => 'آلي',
      'Low' => 'منخفضة',
      'Medium' => 'متوسطة',
      'High' => 'عالية',
      'Pending' => 'قيد الانتظار',
      'Completed' => 'مكتملة',
      'active' => 'نشط',
      'paid' => 'مدفوع',
      'cancelled' => 'ملغي',
      'All' => 'الكل',
      'Daily' => 'يومي',
      'Monthly' => 'شهري',
      'None' => 'بدون',
      _ => value,
    };
  }

  static String languageLabel(String code) {
    return switch (_normalizeCode(code)) {
      'ar' => t('Arabic', 'العربية'),
      _ => t('English', 'الإنجليزية'),
    };
  }

  static String _normalizeCode(String code) {
    return code.toLowerCase().startsWith('ar') ? 'ar' : 'en';
  }

  static Future<void> _persist(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(languageKey, code);
    await prefs.setString('language', code == 'ar' ? 'Arabic' : 'English');
  }
}

class AppLanguageScope extends InheritedNotifier<ValueNotifier<String>> {
  AppLanguageScope({super.key, required super.child})
    : super(notifier: AppText.languageCode);

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
  }
}

extension AppTextContext on BuildContext {
  String t(String english, String arabic) {
    AppLanguageScope.watch(this);
    return AppText.t(english, arabic);
  }

  String enumText(String value) {
    AppLanguageScope.watch(this);
    return AppText.enumText(value);
  }
}
