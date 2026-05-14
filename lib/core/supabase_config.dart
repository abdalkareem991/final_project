import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://nkzcmxuthxwpgmhvnxcb.supabase.co';
  static const String anonKey =
      'sb_publishable_GaooL_VcN7UWg2HgPC2z9g_7v3Zb_en';

  static Future<void> ensureInitialized() async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
