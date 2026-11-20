import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// A push message. Payloads carry a type code and an optional opaque id,
/// never health data (PRD §5.15I, privacy rules).
typedef PushMessage = ({String type, String? id});

PushMessage? pushMessageFrom(Map<String, dynamic> data) {
  final type = data['type'];
  if (type is! String || type.isEmpty) return null;
  final id = data['id'];
  return (type: type, id: id is String ? id : null);
}

/// FCM, or nothing when push is not set up.
abstract interface class PushMessaging {
  bool get available;
  Future<String?> token();
  Stream<String> get tokenRefresh;
  Stream<PushMessage> get foreground;
  Stream<PushMessage> get opened;
  Future<PushMessage?> initialMessage();
  Future<void> deleteToken();
}

final class DisabledPushMessaging implements PushMessaging {
  const DisabledPushMessaging();
  @override
  bool get available => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get foreground => const Stream.empty();
  @override
  Stream<PushMessage> get opened => const Stream.empty();
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Future<void> deleteToken() async {}
}

final class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Initialises Firebase from build-time options (no google-services.json).
  static Future<PushMessaging> create(FirebaseOptions options) async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
    return FirebasePushMessaging._();
  }

  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  bool get available => true;
  String? _last;

  /// Registers with FCM and waits for the token (or null after 20 s).
  @override
  Future<String?> token() async {
    final last = _last;
    if (last != null) return last;
    final next = _m.onRegistered.first.timeout(const Duration(seconds: 20));
    await _m.register();
    try {
      return _last = await next;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefresh => _m.onRegistered.map((t) => _last = t);
  @override
  Stream<PushMessage> get foreground =>
      FirebaseMessaging.onMessage.map((m) => pushMessageFrom(m.data)).where((m) => m != null).cast();
  @override
  Stream<PushMessage> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => pushMessageFrom(m.data)).where((m) => m != null).cast();
  @override
  Future<PushMessage?> initialMessage() async {
    final m = await _m.getInitialMessage();
    return m == null ? null : pushMessageFrom(m.data);
  }

  @override
  Future<void> deleteToken() {
    _last = null;
    return _m.unregister();
  }
}
