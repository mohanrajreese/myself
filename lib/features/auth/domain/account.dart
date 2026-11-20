import 'package:meta/meta.dart';

/// The Google account this device is bound to.
@immutable
final class Account {
  const Account({required this.id, this.email, this.displayName});

  factory Account.fromJson(Map<String, Object?> json) =>
      Account(id: json['id']! as String, email: json['email'] as String?, displayName: json['name'] as String?);

  /// Supabase user id; owns every synced row.
  final String id;
  final String? email;
  final String? displayName;

  Map<String, Object?> toJson() => {'id': id, 'email': email, 'name': displayName};

  @override
  bool operator ==(Object other) =>
      other is Account && other.id == id && other.email == email && other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, email, displayName);
}
