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

const String _smsLogTag = 'FinMindSMS';

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
        "A background SMS could not be synced.",
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
  DateTime? _remoteSmsUnavailableUntil;

  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static String lastSyncStatus = "Not started";
  static final ValueNotifier<int> statusVersion = ValueNotifier<int>(0);

  static const Duration _syncInterval = Duration(seconds: 20);
  static const Duration _minSyncGap = Duration(seconds: 10);
  static const Duration _networkCooldown = Duration(seconds: 15);
  static const Duration _remoteSmsCooldown = Duration(minutes: 3);
  static const Duration _singleSmsTimeout = Duration(seconds: 12);
  static const int _recentMessagesLimit = 8;

  void _setStatus(String status) {
    lastSyncStatus = status;
    statusVersion.value++;
  }

  void _setSyncResult({
    required String status,
    required int processedCount,
    DateTime? syncTime,
  }) {
    lastSyncStatus = status;
    lastProcessedCount = processedCount;
    lastSyncTime = syncTime ?? DateTime.now();
    statusVersion.value++;
  }

  void markManualSyncStarted() => _setStatus("Syncing");

  void markManualSyncTimedOut() =>
      _setSyncResult(status: "Timed out", processedCount: 0);

  bool _isTransientNetworkError(Object error) {
    final text = error.toString();
    return text.contains("Failed host lookup") ||
        text.contains("SocketException") ||
        text.contains("Connection timed out") ||
        text.contains("Software caused connection abort") ||
        text.contains("Connection reset");
  }

  Future<bool> startListening({bool syncImmediately = false}) async {
    if (_isStarted && _smsSyncTimer != null) {
      debugPrint("SMS Auto Sync already running.");
      if (syncImmediately) {
        unawaited(syncNow(force: true));
      }
      return true;
    }

    if (_isStarted) {
      debugPrint("SMS Auto Sync is already starting.");
      return true;
    }

    _isStarted = true;
    _setStatus("Starting");

    final bool? permission = await telephony.requestPhoneAndSmsPermissions;
    // debugPrint("SMS permission: $permission");

    if (permission != true) {
      _isStarted = false;
      _setStatus("Permission denied");
      return false;
    }

    _smsSyncTimer?.cancel();

    _startForegroundIncomingSmsListener();

    _smsSyncTimer = Timer.periodic(_syncInterval, (_) async {
      await syncNow();
    });

    if (syncImmediately) {
      unawaited(syncNow(force: true));
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

    debugPrint("[$_smsLogTag] SMS received.");

    try {
      final wallets = await _supabaseService.getWallets().timeout(
        const Duration(seconds: 8),
      );
      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      });

      for (final wallet in automatedWallets) {
        final sender = wallet.smsSenderId!.trim();
        if (!_senderMatches(sender, address)) continue;

        _setStatus("Syncing");
        final processed =
            await _processSmsMessageForSender(
              message: message,
              sender: sender,
              walletId: wallet.id,
            ).timeout(
              _singleSmsTimeout,
              onTimeout: () {
                debugPrint("[$_smsLogTag] Incoming SMS processing timed out.");
                _lastNetworkErrorAt = DateTime.now();
                _setStatus("Timed out");
                return false;
              },
            );

        if (_lastNetworkErrorAt != null) {
          return false;
        }

        _lastNetworkErrorAt = null;
        _setSyncResult(status: "Active", processedCount: processed ? 1 : 0);

        return processed;
      }
    } catch (e) {
      final errorText = e.toString();
      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");
      } else {
        _setStatus("Error");
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

  bool get _canUseRemoteSmsProcessing {
    final unavailableUntil = _remoteSmsUnavailableUntil;
    return unavailableUntil == null || DateTime.now().isAfter(unavailableUntil);
  }

  Future<bool> _processSmsLocally({
    required String localSmsKey,
    required String sender,
    required String body,
    required int smsDate,
    required String walletId,
  }) async {
    try {
      final parsedData = _aiService.parseBankSmsLocally(body, sender: sender);
      final receivedAt = smsDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(smsDate)
          : DateTime.now();

      if (parsedData == null) {
        final result = await _supabaseService
            .processParsedSmsTransactionAtomically(
              smsHash: localSmsKey,
              senderId: sender,
              smsBody: body,
              receivedAt: receivedAt,
              walletId: walletId,
            )
            .timeout(const Duration(seconds: 20));
        if (result.isDuplicate) {
          _processedInMemory.add(localSmsKey);
        } else {
          _ignoredInMemory.add(localSmsKey);
        }
        debugPrint(
          "[$_smsLogTag] Local parser failed; atomic RPC status: ${result.status}",
        );
        return false;
      }

      parsedData['sms_timestamp'] = smsDate;

      final result = await _supabaseService
          .processParsedSmsTransactionAtomically(
            smsHash: localSmsKey,
            senderId: sender,
            smsBody: body,
            receivedAt: receivedAt,
            walletId: walletId,
            parsedData: parsedData,
          )
          .timeout(const Duration(seconds: 20));

      if (result.isDuplicate) {
        _processedInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] SMS duplicate skipped by atomic RPC.");
        return false;
      }

      if (!result.processed) {
        _ignoredInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] Atomic RPC status: ${result.status}");
        return false;
      }

      _processedInMemory.add(localSmsKey);
      await _showProcessedSmsNotification(result);
      return true;
    } catch (error) {
      debugPrint("[$_smsLogTag] Local SMS processing failed: $error");
      if (_isTransientNetworkError(error)) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");
      }
      return false;
    }
  }

  Future<void> _showProcessedSmsNotification(SmsProcessingResult result) async {
    if (result.isInternalTransfer ||
        result.type == null ||
        result.amount == null) {
      return;
    }

    await NotificationService().showTransactionNotification(
      type: result.type!,
      amount: result.amount!,
      walletName: result.walletName ?? 'Account',
      description: result.description,
      balanceAfter: result.balanceAfter,
    );
  }

  Future<bool> _processSmsMessageForSender({
    required SmsMessage message,
    required String sender,
    required String walletId,
  }) async {
    final String? body = message.body?.replaceAll(RegExp(r'\s+'), ' ').trim();

    final int smsDate = message.date ?? 0;

    if (body == null || body.isEmpty) {
      return false;
    }

    final String localSmsKey = _stableSmsHash(
      sender: sender,
      smsDate: smsDate,
      body: body.toLowerCase(),
    );

    if (_processedInMemory.contains(localSmsKey) ||
        _ignoredInMemory.contains(localSmsKey)) {
      return false;
    }

    if (!_canUseRemoteSmsProcessing) {
      return _processSmsLocally(
        localSmsKey: localSmsKey,
        sender: sender,
        body: body,
        smsDate: smsDate,
        walletId: walletId,
      );
    }

    try {
      final receivedAt = smsDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(smsDate)
          : DateTime.now();

      final result = await _supabaseService
          .processSmsTransactionRemotely(
            senderId: sender,
            smsBody: body,
            receivedAt: receivedAt,
            walletId: walletId,
          )
          .timeout(_singleSmsTimeout);

      if (result.isDuplicate) {
        _processedInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] SMS duplicate skipped by backend.");
        return false;
      }

      if (!result.processed) {
        if (result.status == 'invalid_response') {
          debugPrint(
            "[$_smsLogTag] SMS backend status: ${result.status}; trying local parser.",
          );
          return _processSmsLocally(
            localSmsKey: localSmsKey,
            sender: sender,
            body: body,
            smsDate: smsDate,
            walletId: walletId,
          );
        }

        _ignoredInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] SMS backend status: ${result.status}");
        return false;
      }

      _processedInMemory.add(localSmsKey);
      await _showProcessedSmsNotification(result);

      return true;
    } catch (e) {
      debugPrint("[$_smsLogTag] SMS processing failed: $e");
      if (_isTransientNetworkError(e)) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");
        return false;
      }

      _remoteSmsUnavailableUntil = DateTime.now().add(_remoteSmsCooldown);
      debugPrint("[$_smsLogTag] Remote SMS unavailable; using local fallback.");
      return _processSmsLocally(
        localSmsKey: localSmsKey,
        sender: sender,
        body: body,
        smsDate: smsDate,
        walletId: walletId,
      );
    }
  }

  Future<List<SmsMessage>> _getMessagesForSender(String sender) async {
    final Map<String, SmsMessage> uniqueMessages = {};

    for (final candidate in _senderCandidates(sender)) {
      try {
        final messages = await telephony
            .getInboxSms(
              columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
              filter: SmsFilter.where(SmsColumn.ADDRESS).equals(candidate),
              sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
            )
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () {
                debugPrint("Sender candidate query timed out: $candidate");
                return <SmsMessage>[];
              },
            );

        for (final message in messages) {
          final key =
              "${message.address}_${message.date}_${message.body?.hashCode}";
          uniqueMessages[key] = message;
        }

        // Keep release logging quiet; only errors are printed below.
      } catch (e) {
        debugPrint("Sender candidate query failed: $e");
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
        _setStatus("Offline");
        return;
      }
    }

    _isSyncing = true;
    _setStatus("Syncing");

    int processedCount = 0;

    try {
      // debugPrint("SMS SYNC TICK STARTED");

      final wallets = await _supabaseService.getWallets().timeout(
        const Duration(seconds: 8),
      );

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
            final processed =
                await _processSmsMessageForSender(
                  message: message,
                  sender: sender,
                  walletId: wallet.id,
                ).timeout(
                  _singleSmsTimeout + const Duration(seconds: 2),
                  onTimeout: () {
                    debugPrint("[$_smsLogTag] SMS processing timed out.");
                    _lastNetworkErrorAt = DateTime.now();
                    _setStatus("Timed out");
                    return false;
                  },
                );
            if (_lastNetworkErrorAt != null) {
              return;
            }
            if (processed) processedCount++;
          }
        } catch (walletError) {
          debugPrint("SMS sync error for monitored sender: $walletError");
          continue;
        }
      }

      _lastNetworkErrorAt = null;
      _setSyncResult(status: "Active", processedCount: processedCount);

      debugPrint("SMS SYNC FINISHED. Processed: $processedCount");
    } catch (e) {
      final errorText = e.toString();

      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");

        debugPrint("SMS sync offline: $e");
      } else {
        _setStatus("Error");

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
    _setStatus("Stopped");
    // debugPrint("SMS Auto Sync stopped.");
  }
}
