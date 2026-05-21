// lib/services/sms_listener_service.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

import '../core/supabase_config.dart';
import 'ai_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> finmindBackgroundSmsHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final isEnabled = prefs.getBool('sms_automation_enabled') ?? false;
  if (!isEnabled) return;

  try {
    await SupabaseConfig.ensureInitialized();
    await NotificationService().initNotification(requestPermissions: false);
    await SMSListenerService().processIncomingMessage(message);
  } catch (e) {
    try {
      await NotificationService().showSyncErrorNotification(
        "Background SMS sync failed: $e",
      );
    } catch (_) {}
    debugPrint("Background SMS sync failed: $e");
  }
}

class SMSListenerService {
  static final SMSListenerService _instance = SMSListenerService._internal();

  factory SMSListenerService() => _instance;

  SMSListenerService._internal();

  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  Timer? _smsSyncTimer;

  final Set<String> _processedInMemory = {};
  final Set<String> _ignoredInMemory = {};

  bool _isStarted = false;
  bool _isSyncing = false;
  bool _incomingSmsListenerRegistered = false;
  DateTime? _lastSyncAttemptAt;
  DateTime? _lastNetworkErrorAt;

  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static String lastSyncStatus = "Not started";

  static const Duration _syncInterval = Duration(seconds: 30);
  static const Duration _minSyncGap = Duration(seconds: 5);
  static const Duration _networkCooldown = Duration(seconds: 45);
  static const int _recentMessagesLimit = 25;

  Future<bool> startListening({bool syncImmediately = false}) async {
    if (_isStarted && _smsSyncTimer != null) {
      debugPrint("SMS Auto Sync already running.");
      if (syncImmediately) {
        await syncNow(force: true);
      }
      return true;
    }

    if (_isStarted) {
      debugPrint("SMS Auto Sync is already starting.");
      return true;
    }

    _isStarted = true;
    lastSyncStatus = "Starting";

    final bool? permission = await telephony.requestPhoneAndSmsPermissions;
    // debugPrint("SMS permission: $permission");

    if (permission != true) {
      _isStarted = false;
      lastSyncStatus = "Permission denied";
      return false;
    }

    _smsSyncTimer?.cancel();

    _startForegroundIncomingSmsListener();

    _smsSyncTimer = Timer.periodic(_syncInterval, (_) async {
      await syncNow();
    });

    if (syncImmediately) {
      await syncNow(force: true);
    } else {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (_isStarted) {
            await syncNow(force: true);
          }
        }),
      );
    }

    return true;
  }

  void _startForegroundIncomingSmsListener() {
    if (_incomingSmsListenerRegistered) return;

    try {
      telephony.listenIncomingSms(
        listenInBackground: true,
        onBackgroundMessage: finmindBackgroundSmsHandler,
        onNewMessage: (message) {
          if (!_isStarted) return;
          unawaited(processIncomingMessage(message));
        },
      );
      _incomingSmsListenerRegistered = true;
    } catch (e) {
      debugPrint("Incoming SMS listener setup failed: $e");
    }
  }

  Future<bool> processIncomingMessage(SmsMessage message) async {
    final address = message.address?.trim();
    if (address == null || address.isEmpty) return false;

    try {
      final wallets = await _supabaseService.getWallets();
      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      });

      for (final wallet in automatedWallets) {
        final sender = wallet.smsSenderId!.trim();
        if (!_senderMatches(sender, address)) continue;

        lastSyncStatus = "Syncing";
        final processed = await _processSmsMessageForSender(
          message: message,
          sender: sender,
        );

        _lastNetworkErrorAt = null;
        lastSyncTime = DateTime.now();
        lastProcessedCount = processed ? 1 : 0;
        lastSyncStatus = "Active";

        return processed;
      }
    } catch (e) {
      final errorText = e.toString();
      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        lastSyncStatus = "Offline";
      } else {
        lastSyncStatus = "Error";
      }
      debugPrint("Incoming SMS sync error: $e");
    }

    return false;
  }

  Future<void> syncNow({bool force = false}) async {
    final now = DateTime.now();

    if (!force && _lastSyncAttemptAt != null) {
      final diff = now.difference(_lastSyncAttemptAt!);
      if (diff < _minSyncGap) {
        debugPrint("SMS sync skipped: too soon.");
        return;
      }
    }

    _lastSyncAttemptAt = now;
    await _syncLatestBankSms();
  }

  String _stableSmsHash({
    required String sender,
    required int smsDate,
    required String body,
  }) {
    int hash = 0;

    for (int i = 0; i < body.length; i++) {
      hash = 0x1fffffff & (hash + body.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash = hash ^ (hash >> 6);
    }

    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));

    return "${sender.trim().toLowerCase()}_${smsDate}_$hash";
  }

  List<String> _senderCandidates(String sender) {
    final trimmed = sender.trim();
    final noSpaces = trimmed.replaceAll(' ', '');

    return {
      trimmed,
      noSpaces,
      trimmed.toLowerCase(),
      noSpaces.toLowerCase(),
      trimmed.toUpperCase(),
      noSpaces.toUpperCase(),
    }.where((value) => value.isNotEmpty).toList();
  }

  bool _senderMatches(String savedSender, String incomingSender) {
    final normalizedIncoming = incomingSender.replaceAll(' ', '').toLowerCase();

    return _senderCandidates(savedSender).any(
      (candidate) =>
          candidate.replaceAll(' ', '').toLowerCase() == normalizedIncoming,
    );
  }

  Future<bool> _processSmsMessageForSender({
    required SmsMessage message,
    required String sender,
  }) async {
    final String? normalizedBody = message.body
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final int smsDate = message.date ?? 0;

    if (normalizedBody == null || normalizedBody.isEmpty) {
      return false;
    }

    final String smsHash = _stableSmsHash(
      sender: sender,
      smsDate: smsDate,
      body: normalizedBody,
    );

    if (_processedInMemory.contains(smsHash) ||
        _ignoredInMemory.contains(smsHash)) {
      return false;
    }

    final bool alreadyProcessed = await _supabaseService.isSmsAlreadyProcessed(
      smsHash,
    );

    if (alreadyProcessed) {
      _processedInMemory.add(smsHash);
      return false;
    }

    final Map<String, dynamic>? parsedData = _aiService.parseBankSmsLocally(
      normalizedBody,
      sender: sender,
    );

    if (parsedData == null) {
      _ignoredInMemory.add(smsHash);
      return false;
    }

    parsedData['sms_timestamp'] = smsDate;

    await _supabaseService.processAutomatedTransaction(
      parsedData,
      sender,
      smsHash: smsHash,
    );

    _processedInMemory.add(smsHash);
    return true;
  }

  Future<List<SmsMessage>> _getMessagesForSender(String sender) async {
    final Map<String, SmsMessage> uniqueMessages = {};

    for (final candidate in _senderCandidates(sender)) {
      try {
        final messages = await telephony.getInboxSms(
          columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
          filter: SmsFilter.where(SmsColumn.ADDRESS).equals(candidate),
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );

        for (final message in messages) {
          final key =
              "${message.address}_${message.date}_${message.body?.hashCode}";
          uniqueMessages[key] = message;
        }

        // Keep release logging quiet; only errors are printed below.
      } catch (e) {
        debugPrint("Sender candidate failed: $candidate => $e");
      }
    }

    final result = uniqueMessages.values.toList();

    result.sort((a, b) {
      final aDate = a.date ?? 0;
      final bDate = b.date ?? 0;
      return bDate.compareTo(aDate);
    });

    return result;
  }

  Future<void> _syncLatestBankSms() async {
    if (_isSyncing) {
      debugPrint("SMS sync skipped: previous sync still running.");
      return;
    }

    if (_lastNetworkErrorAt != null) {
      final diff = DateTime.now().difference(_lastNetworkErrorAt!);
      if (diff < _networkCooldown) {
        lastSyncStatus = "Offline";
        return;
      }
    }

    _isSyncing = true;
    lastSyncStatus = "Syncing";

    int processedCount = 0;

    try {
      // debugPrint("SMS SYNC TICK STARTED");

      final wallets = await _supabaseService.getWallets();

      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      }).toList();

      for (final wallet in automatedWallets) {
        final String sender = wallet.smsSenderId!.trim();

        try {
          final messages = await _getMessagesForSender(
            sender,
          ); // This method now handles multiple sender candidates and deduplicates messages

          if (messages.isEmpty) continue;

          final recentMessages = messages
              .take(_recentMessagesLimit)
              .toList()
              .reversed;

          for (final message in recentMessages) {
            final processed = await _processSmsMessageForSender(
              message: message,
              sender: sender,
            );
            if (processed) processedCount++;
          }
        } catch (walletError) {
          debugPrint("SMS sync error for sender $sender: $walletError");
          continue;
        }
      }

      _lastNetworkErrorAt = null;
      lastSyncTime = DateTime.now();
      lastProcessedCount = processedCount;
      lastSyncStatus = "Active";

      debugPrint("SMS SYNC FINISHED. Processed: $processedCount");
    } catch (e) {
      final errorText = e.toString();

      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        lastSyncStatus = "Offline";

        debugPrint("SMS sync offline: $e");
      } else {
        lastSyncStatus = "Error";

        debugPrint("SMS auto sync error: $e");
      }
    } finally {
      _isSyncing = false;
    }
  }

  void stopListening() {
    // Call this method when the app is closing or when you want to stop the service
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    _isStarted = false;
    _isSyncing = false;
    _lastSyncAttemptAt = null;
    try {
      telephony.listenIncomingSms(
        listenInBackground: false,
        onNewMessage: (_) {},
      );
      _incomingSmsListenerRegistered = false;
    } catch (e) {
      debugPrint("Incoming SMS listener stop failed: $e");
    }
    lastSyncStatus = "Stopped";
    // debugPrint("SMS Auto Sync stopped.");
  }
}
