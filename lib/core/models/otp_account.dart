import 'dart:convert';

import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';

/// A stored one-time-password credential.
///
/// Covers every supported [OtpType]; [counter] is meaningful only for HOTP,
/// and [period] only for time-based types.
class OtpAccount {
  final String id;
  final String issuer;
  final String accountName;

  /// Base32-encoded shared secret. Held encrypted at rest; plaintext only
  /// while the vault is unlocked.
  final String secret;

  final OtpType type;
  final int digits;
  final int period;
  final OtpAlgorithm algorithm;

  /// HOTP moving factor. Advances on use, not with the clock.
  final int counter;

  const OtpAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secret,
    this.type = OtpType.totp,
    this.digits = 6,
    this.period = 30,
    this.algorithm = OtpAlgorithm.sha1,
    this.counter = 0,
  });

  /// A display label that is never empty.
  String get displayName => accountName.isNotEmpty
      ? accountName
      : (issuer.isNotEmpty ? issuer : 'Account');

  /// Generates the current code.
  ///
  /// For time-based credentials the counter is derived from [time]; for HOTP
  /// the stored [counter] is used and [time] is ignored.
  String generateCode({DateTime? time}) {
    final generator = OtpGenerator.forType(type);
    final effectiveCounter = type == OtpType.hotp
        ? counter
        : generator.counterFor(
            time: time ?? DateTime.now(),
            period: period,
          );

    return generator.generate(
      secret: secret,
      counter: effectiveCounter,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Seconds until a time-based code refreshes. Zero for HOTP.
  int secondsRemaining({DateTime? time}) {
    if (!type.isTimeBased) return 0;
    return OtpGenerator.forType(type)
        .secondsRemaining(time: time ?? DateTime.now(), period: period);
  }

  OtpAccount copyWith({
    String? id,
    String? issuer,
    String? accountName,
    String? secret,
    OtpType? type,
    int? digits,
    int? period,
    OtpAlgorithm? algorithm,
    int? counter,
  }) {
    return OtpAccount(
      id: id ?? this.id,
      issuer: issuer ?? this.issuer,
      accountName: accountName ?? this.accountName,
      secret: secret ?? this.secret,
      type: type ?? this.type,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      algorithm: algorithm ?? this.algorithm,
      counter: counter ?? this.counter,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'issuer': issuer,
        'accountName': accountName,
        'secret': secret,
        'type': type.name,
        'digits': digits,
        'period': period,
        'algorithm': algorithm.name,
        'counter': counter,
      };

  factory OtpAccount.fromMap(Map<String, dynamic> map) => OtpAccount(
        id: map['id'] as String? ?? '',
        issuer: map['issuer'] as String? ?? '',
        accountName: map['accountName'] as String? ?? '',
        secret: map['secret'] as String? ?? '',
        type: OtpType.fromName(map['type'] as String?),
        digits: (map['digits'] as num?)?.toInt() ?? 6,
        period: (map['period'] as num?)?.toInt() ?? 30,
        algorithm: OtpAlgorithm.fromName(map['algorithm'] as String?),
        counter: (map['counter'] as num?)?.toInt() ?? 0,
      );

  String toJson() => json.encode(toMap());

  factory OtpAccount.fromJson(String source) =>
      OtpAccount.fromMap(json.decode(source) as Map<String, dynamic>);
}
