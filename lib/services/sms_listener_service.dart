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

class SmsSyncStatus {
  final bool isRunning;
  final bool listenerRunning;
  final bool autoSyncEnabled;
  final DateTime? lastStartedAt;
  final DateTime? lastFinishedAt;
  final String status;
  final int processedCount;
  final int duplicateCount;
  final int ignoredCount;
  final int errorCount;
  final String? lastError;

  const SmsSyncStatus({
    required this.isRunning,
    required this.listenerRunning,
    required this.autoSyncEnabled,
    required this.lastStartedAt,
    required this.lastFinishedAt,
    required this.status,
    required this.processedCount,
    required this.duplicateCount,
    required this.ignoredCount,
    required this.errorCount,
    required this.lastError,
  });

  factory SmsSyncStatus.initial() {
    return const SmsSyncStatus(
      isRunning: false,
      listenerRunning: false,
      autoSyncEnabled: false,
      lastStartedAt: null,
      lastFinishedAt: null,
      status: 'Not started',
      processedCount: 0,
      duplicateCount: 0,
      ignoredCount: 0,
      errorCount: 0,
      lastError: null,
    );
  }

  SmsSyncStatus copyWith({
    bool? isRunning,
    bool? listenerRunning,
    bool? autoSyncEnabled,
    DateTime? lastStartedAt,
    DateTime? lastFinishedAt,
    String? status,
    int? processedCount,
    int? duplicateCount,
    int? ignoredCount,
    int? errorCount,
    String? lastError,
  }) {
    return SmsSyncStatus(
      isRunning: isRunning ?? this.isRunning,
      listenerRunning: listenerRunning ?? this.listenerRunning,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lastStartedAt: lastStartedAt ?? this.lastStartedAt,
      lastFinishedAt: lastFinishedAt ?? this.lastFinishedAt,
      status: status ?? this.status,
      processedCount: processedCount ?? this.processedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      ignoredCount: ignoredCount ?? this.ignoredCount,
      errorCount: errorCount ?? this.errorCount,
      lastError: lastError ?? this.lastError,
    );
  }
}

class SmsSyncResult {
  final bool success;
  final bool skipped;
  final String reason;
  final int processedCount;
  final int duplicateCount;
  final int ignoredCount;
  final int errorCount;
  final String status;

  const SmsSyncResult({
    required this.success,
    required this.skipped,
    required this.reason,
    required this.processedCount,
    required this.duplicateCount,
    required this.ignoredCount,
    required this.errorCount,
    required this.status,
  });

  factory SmsSyncResult.skippedAlreadyRunning() {
    return const SmsSyncResult(
      success: false,
      skipped: true,
      reason: 'already_running',
      processedCount: 0,
      duplicateCount: 0,
      ignoredCount: 0,
      errorCount: 0,
      status: 'Skipped - already running',
    );
  }

  factory SmsSyncResult.skippedTooSoon() {
    return const SmsSyncResult(
      success: false,
      skipped: true,
      reason: 'too_soon',
      processedCount: 0,
      duplicateCount: 0,
      ignoredCount: 0,
      errorCount: 0,
      status: 'Skipped - too soon',
    );
  }

  factory SmsSyncResult.success({
    required int processedCount,
    required int duplicateCount,
    required int ignoredCount,
    required int errorCount,
    required String status,
  }) {
    return SmsSyncResult(
      success: true,
      skipped: false,
      reason: 'success',
      processedCount: processedCount,
      duplicateCount: duplicateCount,
      ignoredCount: ignoredCount,
      errorCount: errorCount,
      status: status,
    );
  }
}

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
  static SMSListenerService get instance => _instance;

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

  static SmsSyncStatus currentStatus = SmsSyncStatus.initial();
  static final ValueNotifier<int> statusVersion = ValueNotifier<int>(0);

  static DateTime? get lastSyncTime => currentStatus.lastFinishedAt;
  static int get lastProcessedCount => currentStatus.processedCount;
  static int get lastDuplicateCount => currentStatus.duplicateCount;
  static int get lastIgnoredCount => currentStatus.ignoredCount;
  static int get lastErrorCount => currentStatus.errorCount;
  static String? get lastErrorMessage => currentStatus.lastError;
  static String get lastSyncStatus => currentStatus.status;
  static bool get listenerRunning => currentStatus.listenerRunning;
  static bool get autoSyncEnabled => currentStatus.autoSyncEnabled;

  // Android reality: this 30-second timer is reliable while the Flutter process
  // is alive/foreground. If Android kills or heavily backgrounds the app, timer
  // ticks can stop; RECEIVE_SMS broadcast handling remains the best-effort path
  // for incoming messages unless a foreground service/WorkManager is added.
  static const Duration _syncInterval = Duration(seconds: 30);
  static const Duration _minSyncGap = Duration(seconds: 10);
  static const Duration _networkCooldown = Duration(seconds: 15);
  static const Duration _remoteSmsCooldown = Duration(minutes: 3);
  static const Duration _singleSmsTimeout = Duration(seconds: 12);
  static const int _recentMessagesLimit = 30;

  bool get isRunning => _isStarted && _smsSyncTimer != null;

  void _setStatus(String status) {
    currentStatus = currentStatus.copyWith(status: status);
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  void _setSyncResult({
    required String status,
    required int processedCount,
    int duplicateCount = 0,
    int ignoredCount = 0,
    int errorCount = 0,
    DateTime? syncTime,
  }) {
    currentStatus = currentStatus.copyWith(
      status: status,
      processedCount: processedCount,
      duplicateCount: duplicateCount,
      ignoredCount: ignoredCount,
      errorCount: errorCount,
      lastError: null,
      lastFinishedAt: syncTime ?? DateTime.now(),
    );
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  void _setErrorStatus(String status, Object error, [StackTrace? stackTrace]) {
    currentStatus = currentStatus.copyWith(
      status: status,
      lastError: error.toString(),
      errorCount: currentStatus.errorCount + 1,
      lastFinishedAt: DateTime.now(),
    );
    statusVersion.value++;
    debugPrint("[$_smsLogTag] Error with full exception: $error");
    if (stackTrace != null) {
      debugPrint("[$_smsLogTag] Stack trace: $stackTrace");
    }
    unawaited(_persistSyncStatus());
  }

  void _incrementDuplicateCount() {
    currentStatus = currentStatus.copyWith(
      duplicateCount: currentStatus.duplicateCount + 1,
    );
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  void _incrementIgnoredCount() {
    currentStatus = currentStatus.copyWith(
      ignoredCount: currentStatus.ignoredCount + 1,
    );
    statusVersion.value++;
    unawaited(_persistSyncStatus());
  }

  Future<void> _persistSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sms_sync_status', currentStatus.status);
      await prefs.setInt(
        'sms_sync_processed_count',
        currentStatus.processedCount,
      );
      await prefs.setInt(
        'sms_sync_duplicate_count',
        currentStatus.duplicateCount,
      );
      await prefs.setInt('sms_sync_ignored_count', currentStatus.ignoredCount);
      await prefs.setInt('sms_sync_error_count', currentStatus.errorCount);
      await prefs.setBool(
        'sms_listener_running',
        currentStatus.listenerRunning,
      );
      await prefs.setBool(
        'sms_auto_sync_enabled',
        currentStatus.autoSyncEnabled,
      );
      if (currentStatus.lastStartedAt != null) {
        await prefs.setString(
          'sms_sync_last_started_at',
          currentStatus.lastStartedAt!.toIso8601String(),
        );
      }
      if (currentStatus.lastFinishedAt != null) {
        await prefs.setString(
          'sms_sync_last_scan_time',
          currentStatus.lastFinishedAt!.toIso8601String(),
        );
      }
      final error = currentStatus.lastError;
      if (error == null || error.isEmpty) {
        await prefs.remove('sms_sync_last_error');
      } else {
        await prefs.setString('sms_sync_last_error', error);
      }
    } catch (_) {
      // Keep status persistence best-effort; sync must not fail because of it.
    }
  }

  void markManualSyncStarted() {
    currentStatus = currentStatus.copyWith(
      lastStartedAt: DateTime.now(),
      status: "Syncing",
      isRunning: true,
    );
    _setStatus("Syncing");
  }

  SmsSyncResult markManualSyncTimedOut() {
    _setSyncResult(status: "Timed out", processedCount: 0, errorCount: 1);
    return const SmsSyncResult(
      success: false,
      skipped: false,
      reason: 'timeout',
      processedCount: 0,
      duplicateCount: 0,
      ignoredCount: 0,
      errorCount: 1,
      status: 'Timed out',
    );
  }

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
    currentStatus = currentStatus.copyWith(
      listenerRunning: true,
      autoSyncEnabled: true,
      lastStartedAt: DateTime.now(),
    );
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

  Future<SmsSyncResult> syncNow({
    String reason = 'manual',
    bool force = false,
  }) async {
    final now = DateTime.now();

    if (_isSyncing) {
      debugPrint("SMS sync skipped: previous sync still running.");
      return SmsSyncResult.skippedAlreadyRunning();
    }

    if (!force && _lastSyncAttemptAt != null) {
      final diff = now.difference(_lastSyncAttemptAt!);
      if (diff < _minSyncGap) {
        debugPrint("SMS sync skipped: too soon.");
        return SmsSyncResult.skippedTooSoon();
      }
    }

    _lastSyncAttemptAt = now;
    currentStatus = currentStatus.copyWith(
      lastStartedAt: now,
      status: 'Syncing',
    );
    _setStatus('Syncing');

    if (reason == 'manual') {
      debugPrint("[$_smsLogTag] Manual sync started");
    }

    final result = await _syncLatestBankSms(reason: reason);
    if (reason == 'manual') {
      debugPrint(
        "[$_smsLogTag] Manual sync finished. Processed: ${result.processedCount}, duplicates: ${result.duplicateCount}, ignored: ${result.ignoredCount}, errors: ${result.errorCount}",
      );
    }
    return result;
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
        _incrementDuplicateCount();
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
          _incrementIgnoredCount();
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
        _incrementIgnoredCount();
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
      sender: sender,
      body: body,
    );
    debugPrint("[$_smsLogTag] Raw sender: $rawSender");
    debugPrint("[$_smsLogTag] Monitored sender: $sender");
    debugPrint(
      "[$_smsLogTag] Normalized sender: ${SmsHashService.normalizeSender(rawSender)}",
    );
    debugPrint(
      "[$_smsLogTag] Normalized monitored sender: ${SmsHashService.normalizeSender(sender)}",
    );
    debugPrint("[$_smsLogTag] SMS hash: $localSmsKey");

    if (_processingHashes.contains(localSmsKey)) {
      _incrementDuplicateCount();
      debugPrint("[$_smsLogTag] Duplicate skipped");
      return false;
    }
    _processingHashes.add(localSmsKey);
    try {
      if (_processedInMemory.contains(localSmsKey) ||
          _ignoredInMemory.contains(localSmsKey)) {
        _incrementDuplicateCount();
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      if (await _supabaseService.isSmsAlreadyProcessed(localSmsKey)) {
        _processedInMemory.add(localSmsKey);
        _incrementDuplicateCount();
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
        _incrementDuplicateCount();
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
        _incrementDuplicateCount();
        debugPrint("[$_smsLogTag] Duplicate skipped");
        return false;
      }

      if (result.isSkipped) {
        _ignoredInMemory.add(localSmsKey);
        _incrementIgnoredCount();
        debugPrint("[$_smsLogTag] SMS backend skipped: ${result.message}");
        return false;
      }

      if (!result.processed) {
        _ignoredInMemory.add(localSmsKey);
        _incrementIgnoredCount();
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
          final key = SmsHashService.stableSmsHash(sender: sender, body: body);
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

  Future<SmsSyncResult> _syncLatestBankSms({String reason = 'manual'}) async {
    if (_isSyncing) {
      debugPrint("SMS sync skipped: previous sync still running.");
      return SmsSyncResult.skippedAlreadyRunning();
    }

    if (_lastNetworkErrorAt != null) {
      final diff = DateTime.now().difference(_lastNetworkErrorAt!);
      if (diff < _networkCooldown) {
        _setStatus("Offline");
        return SmsSyncResult.skippedTooSoon();
      }
    }

    _isSyncing = true;
    currentStatus = currentStatus.copyWith(isRunning: true, status: "Syncing");
    _setStatus("Syncing");

    int processedCount = 0;
    int ignoredCount = currentStatus.ignoredCount;
    int duplicateCountBefore = currentStatus.duplicateCount;
    int errorCount = currentStatus.errorCount;

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
          final messages = await _getMessagesForSender(sender);
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
              return SmsSyncResult.success(
                processedCount: processedCount,
                duplicateCount:
                    currentStatus.duplicateCount - duplicateCountBefore,
                ignoredCount: currentStatus.ignoredCount - ignoredCount,
                errorCount: currentStatus.errorCount - errorCount,
                status: currentStatus.status,
              );
            }
            if (processed) {
              processedCount++;
            }
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
        duplicateCount: currentStatus.duplicateCount - duplicateCountBefore,
        ignoredCount: currentStatus.ignoredCount - ignoredCount,
        errorCount: currentStatus.errorCount - errorCount,
      );

      final result = SmsSyncResult.success(
        processedCount: processedCount,
        duplicateCount: currentStatus.duplicateCount - duplicateCountBefore,
        ignoredCount: currentStatus.ignoredCount - ignoredCount,
        errorCount: currentStatus.errorCount - errorCount,
        status: currentStatus.status,
      );

      debugPrint(
        "[$_smsLogTag] SMS sync finished. Processed: $processedCount, duplicates: ${result.duplicateCount}, ignored: ${result.ignoredCount}, errors: ${result.errorCount}",
      );
      return result;
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
      return SmsSyncResult.success(
        processedCount: processedCount,
        duplicateCount: currentStatus.duplicateCount - duplicateCountBefore,
        ignoredCount: currentStatus.ignoredCount - ignoredCount,
        errorCount: currentStatus.errorCount - errorCount,
        status: currentStatus.status,
      );
    } finally {
      _isSyncing = false;
      currentStatus = currentStatus.copyWith(
        isRunning: false,
        lastFinishedAt: DateTime.now(),
      );
      statusVersion.value++;
    }
  }

  void stopListening() {
    // Call this method when the app is closing or when you want to stop the service
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    _isStarted = false;
    _isSyncing = false;
    _lastSyncAttemptAt = null;
    currentStatus = currentStatus.copyWith(
      isRunning: false,
      listenerRunning: false,
      autoSyncEnabled: false,
      status: 'Stopped',
    );
    _setStatus("Stopped");
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
    debugPrint("[$_smsLogTag] Listener stopped");
  }
}
