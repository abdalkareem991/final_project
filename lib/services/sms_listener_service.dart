// lib/services/sms_listener_service.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

import '../core/supabase_config.dart';
import '../models/wallet_model.dart';
import 'ai_service.dart';
import 'notification_service.dart';
import 'sms_hash_service.dart';
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

class SMSListenerService with WidgetsBindingObserver {
  static final SMSListenerService _instance = SMSListenerService._internal();

  factory SMSListenerService() => _instance;

  SMSListenerService._internal();

  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  Timer? _smsSyncTimer;

  final Set<String> _processedInMemory = {};
  final Set<String> _ignoredInMemory = {};
  final Set<String> _processingHashes = {};

  bool _isStarted = false;
  bool _isSyncing = false;
  bool _incomingSmsListenerRegistered = false;
  DateTime? _lastSyncAttemptAt;
  DateTime? _lastNetworkErrorAt;
  DateTime? _remoteSmsUnavailableUntil;
  bool _lifecycleObserverRegistered = false;

  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static int lastDuplicateCount = 0;
  static String? lastErrorMessage;
  static String lastSyncStatus = "Not started";
  static final ValueNotifier<int> statusVersion = ValueNotifier<int>(0);

  static const Duration _syncInterval = Duration(seconds: 20);
  static const Duration _minSyncGap = Duration(seconds: 10);
  static const Duration _networkCooldown = Duration(seconds: 15);
  static const Duration _remoteSmsCooldown = Duration(minutes: 3);
  static const Duration _singleSmsTimeout = Duration(seconds: 12);
  static const int _recentMessagesLimit = 30;

  bool get isRunning => _isStarted && _smsSyncTimer != null;

  void _setStatus(String status) {
    lastSyncStatus = status;
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  void _setSyncResult({
    required String status,
    required int processedCount,
    int duplicateCount = 0,
    DateTime? syncTime,
  }) {
    lastSyncStatus = status;
    lastProcessedCount = processedCount;
    lastDuplicateCount = duplicateCount;
    lastErrorMessage = null;
    lastSyncTime = syncTime ?? DateTime.now();
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  void _setErrorStatus(String status, Object error, [StackTrace? stackTrace]) {
    lastSyncStatus = status;
    lastErrorMessage = error.toString();
    lastSyncTime = DateTime.now();
    statusVersion.value++;
    debugPrint("[$_smsLogTag] Error with full exception: $error");
    if (stackTrace != null) {
      debugPrint("[$_smsLogTag] Stack trace: $stackTrace");
    }
    unawaited(_persistSyncStatus());
  }

  Future<void> _persistSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sms_sync_status', lastSyncStatus);
      await prefs.setInt('sms_sync_processed_count', lastProcessedCount);
      await prefs.setInt('sms_sync_duplicate_count', lastDuplicateCount);
      await prefs.setBool('sms_listener_running', isRunning);
      if (lastSyncTime != null) {
        await prefs.setString(
          'sms_sync_last_scan_time',
          lastSyncTime!.toIso8601String(),
        );
      }
      final error = lastErrorMessage;
      if (error == null || error.isEmpty) {
        await prefs.remove('sms_sync_last_error');
      } else {
        await prefs.setString('sms_sync_last_error', error);
      }
    } catch (_) {
      // Keep status persistence best-effort; sync must not fail because of it.
    }
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
      debugPrint("[$_smsLogTag] Listener already running");
      if (syncImmediately) {
        unawaited(syncNow(force: true));
      }
      return true;
    }

    if (_isStarted) {
      debugPrint("[$_smsLogTag] Listener already running");
      return true;
    }

    if (_supabaseService.client.auth.currentUser == null) {
      debugPrint("[$_smsLogTag] Listener not started: no Supabase session.");
      _setStatus("Not logged in");
      return false;
    }

    _isStarted = true;
    _setStatus("Starting");

    debugPrint("[$_smsLogTag] Checking SMS permission");
    await NotificationService().initNotification(requestPermissions: true);
    final bool? permission = await telephony.requestPhoneAndSmsPermissions;

    if (permission != true) {
      debugPrint("[$_smsLogTag] SMS permission denied");
      _isStarted = false;
      _setStatus("Permission denied");
      return false;
    }

    debugPrint("[$_smsLogTag] SMS permission granted");
    debugPrint("[$_smsLogTag] Starting listener");
    _smsSyncTimer?.cancel();

    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverRegistered = true;
    }

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
    } catch (e, stackTrace) {
      _setErrorStatus("Error", e, stackTrace);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('sms_automation_enabled') ?? false;
      if (!enabled) return;

      if (_supabaseService.client.auth.currentUser == null) {
        debugPrint("[$_smsLogTag] Resume ignored: no Supabase session.");
        return;
      }

      await startListening(syncImmediately: true);
    }());
  }

  Future<bool> processIncomingMessage(SmsMessage message) async {
    final address = message.address?.trim();
    if (address == null || address.isEmpty) return false;

    debugPrint("[$_smsLogTag] Incoming SMS received");
    debugPrint("[$_smsLogTag] Raw sender: $address");
    debugPrint(
      "[$_smsLogTag] Normalized sender: ${SmsHashService.normalizeSender(address)}",
    );

    try {
      final wallets = await _supabaseService.getWallets().timeout(
        const Duration(seconds: 8),
      );
      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      }).toList();

      debugPrint(
        "[$_smsLogTag] Monitored senders: ${_formatMonitoredSenders(automatedWallets)}",
      );

      WalletModel? matchedWallet;
      String? matchedSender;
      for (final wallet in automatedWallets) {
        final sender = wallet.smsSenderId!.trim();
        if (SmsHashService.senderMatches(sender, address)) {
          matchedWallet = wallet;
          matchedSender = sender;
          break;
        }
      }

      if (matchedWallet == null || matchedSender == null) {
        debugPrint(
          "[$_smsLogTag] Matched wallet or ignored sender: ignored $address",
        );
        debugPrint("[$_smsLogTag] Sender ignored: $address");
        return false;
      }

      debugPrint(
        "[$_smsLogTag] Matched wallet or ignored sender: ${matchedWallet.name} ($matchedSender)",
      );
      debugPrint("[$_smsLogTag] Matched monitored sender: $matchedSender");
      _setStatus("Syncing");
      final processed =
          await _processSmsMessageForSender(
            message: message,
            sender: matchedSender,
            walletId: matchedWallet.id,
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
    } catch (e, stackTrace) {
      final errorText = e.toString();
      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");
      } else {
        _setStatus("Error");
      }
      _setErrorStatus(lastSyncStatus, e, stackTrace);
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

  String _formatMonitoredSenders(List<WalletModel> wallets) {
    if (wallets.isEmpty) return 'none';

    return wallets
        .map((wallet) {
          final raw = wallet.smsSenderId?.trim() ?? '';
          return '${wallet.name}:$raw=>${SmsHashService.normalizeSender(raw)}';
        })
        .join(', ');
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
      if (await _supabaseService.isSmsAlreadyProcessed(localSmsKey)) {
        _processedInMemory.add(localSmsKey);
        lastDuplicateCount++;
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      final parsedData = _aiService.parseBankSmsLocally(body, sender: sender);
      debugPrint(
        "[$_smsLogTag] Parser result: ${parsedData == null ? 'not_matched' : 'matched'}",
      );
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
      debugPrint(
        "[$_smsLogTag] Transaction created: ${result.transactionId ?? 'unknown'}",
      );
      if (result.status == 'created') {
        await _showProcessedSmsNotification(result);
      }
      return true;
    } catch (error, stackTrace) {
      _setErrorStatus("Error", error, stackTrace);
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
    final rawSender = message.address?.trim().isNotEmpty == true
        ? message.address!.trim()
        : sender;

    final int smsDate = message.date ?? 0;

    if (body == null || body.isEmpty) {
      return false;
    }

    final String localSmsKey = SmsHashService.stableSmsHash(
      sender: rawSender,
      body: body,
    );
    debugPrint("[$_smsLogTag] Raw sender: $rawSender");
    debugPrint(
      "[$_smsLogTag] Normalized sender: ${SmsHashService.normalizeSender(rawSender)}",
    );
    debugPrint("[$_smsLogTag] SMS hash: $localSmsKey");

    if (_processingHashes.contains(localSmsKey)) {
      lastDuplicateCount++;
      debugPrint("[$_smsLogTag] Duplicate skipped");
      return false;
    }

    _processingHashes.add(localSmsKey);
    try {
      if (_processedInMemory.contains(localSmsKey) ||
          _ignoredInMemory.contains(localSmsKey)) {
        lastDuplicateCount++;
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      if (await _supabaseService.isSmsAlreadyProcessed(localSmsKey)) {
        _processedInMemory.add(localSmsKey);
        lastDuplicateCount++;
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      if (await _wasProcessedWithLegacyTimestampHash(
        stableSmsKey: localSmsKey,
        rawSender: rawSender,
        monitoredSender: sender,
        body: body,
        smsDate: smsDate,
      )) {
        _processedInMemory.add(localSmsKey);
        lastDuplicateCount++;
        debugPrint("[$_smsLogTag] Duplicate skipped");
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

      final receivedAt = smsDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(smsDate)
          : DateTime.now();

      debugPrint("[$_smsLogTag] Parser result: remote");
      final result = await _supabaseService
          .processSmsTransactionRemotely(
            smsHash: localSmsKey,
            senderId: sender,
            smsBody: body,
            receivedAt: receivedAt,
            walletId: walletId,
          )
          .timeout(_singleSmsTimeout);

      if (result.isDuplicate) {
        _processedInMemory.add(localSmsKey);
        lastDuplicateCount++;
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      if (result.isSkipped) {
        _ignoredInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] SMS backend skipped: ${result.message}");
        return false;
      }

      if (!result.processed) {
        _ignoredInMemory.add(localSmsKey);
        debugPrint("[$_smsLogTag] SMS backend status: ${result.status}");
        return false;
      }

      _processedInMemory.add(localSmsKey);
      debugPrint(
        "[$_smsLogTag] Transaction created: ${result.transactionId ?? 'unknown'}",
      );
      if (result.status == 'created') {
        await _showProcessedSmsNotification(result);
      }

      return true;
    } catch (e, stackTrace) {
      _setErrorStatus("Error", e, stackTrace);
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
    } finally {
      _processingHashes.remove(localSmsKey);
    }
  }

  Future<bool> _wasProcessedWithLegacyTimestampHash({
    required String stableSmsKey,
    required String rawSender,
    required String monitoredSender,
    required String body,
    required int smsDate,
  }) async {
    if (smsDate <= 0) return false;

    final legacyHashes = <String>{
      SmsHashService.legacyTimestampedSmsHashForLookup(
        sender: rawSender,
        body: body,
        smsDate: smsDate,
      ),
      SmsHashService.legacyTimestampedSmsHashForLookup(
        sender: monitoredSender,
        body: body,
        smsDate: smsDate,
      ),
    }..remove(stableSmsKey);

    for (final legacyHash in legacyHashes) {
      if (await _supabaseService.isSmsAlreadyProcessed(legacyHash)) {
        debugPrint("[$_smsLogTag] Duplicate skipped using legacy SMS hash.");
        return true;
      }
    }

    return false;
  }

  Future<List<SmsMessage>> _getMessagesForSender(String sender) async {
    final Map<String, SmsMessage> uniqueMessages = {};
    debugPrint("[$_smsLogTag] Reading inbox");

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
          final body = message.body;
          if (body == null || body.trim().isEmpty) continue;
          final key = SmsHashService.stableSmsHash(
            sender: message.address ?? candidate,
            body: body,
          );
          uniqueMessages[key] = message;
        }

        // Keep release logging quiet; only errors are printed below.
      } catch (e, stackTrace) {
        _setErrorStatus("Error", e, stackTrace);
      }
    }

    final result = uniqueMessages.values.toList();

    result.sort((a, b) {
      final aDate = a.date ?? 0;
      final bDate = b.date ?? 0;
      return aDate.compareTo(bDate);
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
    final duplicateCountBefore = lastDuplicateCount;

    try {
      final wallets = await _supabaseService.getWallets().timeout(
        const Duration(seconds: 8),
      );

      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      }).toList();

      debugPrint(
        "[$_smsLogTag] Monitored senders: ${_formatMonitoredSenders(automatedWallets)}",
      );

      for (final wallet in automatedWallets) {
        final String sender = wallet.smsSenderId!.trim();
        debugPrint("[$_smsLogTag] Reading inbox for monitored sender: $sender");

        try {
          final messages = await _getMessagesForSender(
            sender,
          ); // This method now handles multiple sender candidates and deduplicates messages

          if (messages.isEmpty) continue;

          final recentMessages = messages.length > _recentMessagesLimit
              ? messages.sublist(messages.length - _recentMessagesLimit)
              : messages;

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
        } catch (walletError, stackTrace) {
          _setErrorStatus("Error", walletError, stackTrace);
          continue;
        }
      }

      _lastNetworkErrorAt = null;
      _setSyncResult(
        status: "Active",
        processedCount: processedCount,
        duplicateCount: lastDuplicateCount - duplicateCountBefore,
      );

      debugPrint(
        "[$_smsLogTag] SMS sync finished. Processed: $processedCount, duplicates: ${lastDuplicateCount - duplicateCountBefore}",
      );
    } catch (e, stackTrace) {
      final errorText = e.toString();

      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        _setStatus("Offline");

        _setErrorStatus("Offline", e, stackTrace);
      } else {
        _setStatus("Error");

        _setErrorStatus("Error", e, stackTrace);
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
    } catch (e, stackTrace) {
      _setErrorStatus("Error", e, stackTrace);
    }
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
    _setStatus("Stopped");
    debugPrint("[$_smsLogTag] Listener stopped");
  }
}
