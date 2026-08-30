import 'dart:convert';
import 'package:dula_auth/core/totp_engine.dart';

class TotpAccount {
  final String id;
  final String issuer;
  final String accountName;
  final String secret;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;

  TotpAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = TotpAlgorithm.sha1,
  });

  TotpAccount copyWith({
    String? id,
    String? issuer,
    String? accountName,
    String? secret,
    int? digits,
    int? period,
    TotpAlgorithm? algorithm,
  }) {
    return TotpAccount(
      id: id ?? this.id,
      issuer: issuer ?? this.issuer,
      accountName: accountName ?? this.accountName,
      secret: secret ?? this.secret,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      algorithm: algorithm ?? this.algorithm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'issuer': issuer,
      'accountName': accountName,
      'secret': secret,
      'digits': digits,
      'period': period,
      'algorithm': algorithm.index,
    };
  }

  factory TotpAccount.fromMap(Map<String, dynamic> map) {
    return TotpAccount(
      id: map['id'] ?? '',
      issuer: map['issuer'] ?? '',
      accountName: map['accountName'] ?? '',
      secret: map['secret'] ?? '',
      digits: map['digits']?.toInt() ?? 6,
      period: map['period']?.toInt() ?? 30,
      algorithm: TotpAlgorithm.values[map['algorithm'] ?? 0],
    );
  }

  String toJson() => json.encode(toMap());

  factory TotpAccount.fromJson(String source) => TotpAccount.fromMap(json.decode(source));
}
