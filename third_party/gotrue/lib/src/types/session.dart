import 'package:gotrue/src/constants.dart';
import 'package:gotrue/src/helper.dart';
import 'package:gotrue/src/types/user.dart';
import 'package:meta/meta.dart';

class Session {
  final String? providerToken;
  final String? providerRefreshToken;
  final String accessToken;

  /// The number of seconds until the token expires (since it was issued).
  /// Returned when a login is confirmed.
  final int? expiresIn;

  final String? refreshToken;
  final String tokenType;
  final User user;

  Session({
    required this.accessToken,
    this.expiresIn,
    this.refreshToken,
    required this.tokenType,
    this.providerToken,
    this.providerRefreshToken,
    required this.user,
  });

  /// Returns a `Session` object from a map of json
  /// returns `null` if there is no `access_token` present
  static Session? fromJson(Map<String, dynamic> json) {
    if (json['access_token'] == null) {
      return null;
    }
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw FormatException(
        'Expected user to be an object, got ${userJson.runtimeType}',
      );
    }
    final user = User.fromJson(userJson);
    if (user == null) {
      throw FormatException(
        'Failed to parse user: missing required id field',
      );
    }
    final session = Session(
      accessToken: json['access_token'] as String,
      expiresIn: (json['expires_in'] as num?)?.toInt(),
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String,
      providerToken: json['provider_token'] as String?,
      providerRefreshToken: json['provider_refresh_token'] as String?,
      user: user,
    );
    // [BALAMANDIR PATCH] A session saved by this app carries its expiry on
    // this device's clock; keep it rather than re-reading the JWT.
    final localExpiry = json['expires_at_local'];
    if (localExpiry is num) session.expiresAt = localExpiry.toInt();
    return session;
  }

  /// [BALAMANDIR PATCH] For sessions that just arrived from the auth server.
  ///
  /// The JWT's `exp` is in server time but [isExpired] compares it with this
  /// device's clock, so a PC whose clock or time zone is wrong sees every
  /// token as already expired and refreshes in a loop until the server rate-
  /// limits it and the user is signed out. Measuring the token's lifetime
  /// from the moment it arrived, on the device's own clock, removes that
  /// dependency entirely.
  static Session? fromServerJson(Map<String, dynamic> json) {
    final session = fromJson(json);
    if (session == null) return null;
    try {
      final payload = decodeJwtPayload(session.accessToken);
      final exp = payload.exp;
      final iat = payload.iat;
      if (exp != null && iat != null) {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final skew = nowSec - iat;
        // Only correct a real clock difference, not ordinary network delay.
        if (skew.abs() > 60) session.expiresAt = exp + skew;
      }
    } catch (_) {
      // Leave the upstream behaviour in place if the token can't be read.
    }
    return session;
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'expires_in': expiresIn,
      'expires_at': expiresAt,
      // [BALAMANDIR PATCH] See fromJson / fromServerJson.
      'expires_at_local': expiresAt,
      'refresh_token': refreshToken,
      'token_type': tokenType,
      'provider_token': providerToken,
      'provider_refresh_token': providerRefreshToken,
      'user': user.toJson(),
    };
  }

  /// The Unix timestamp, in **seconds**, of when the token will expire.
  /// Returned when a login is confirmed.
  ///
  /// To convert this to a [DateTime], multiply by 1000 since
  /// [DateTime.fromMillisecondsSinceEpoch] expects milliseconds:
  /// `DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)`.
  late int? expiresAt = _expiresAt;

  int? get _expiresAt {
    try {
      return decodeJwtPayload(accessToken).exp;
    } catch (_) {
      return null;
    }
  }

  /// Returns 'true` if the token is expired or will expire in the next 10 seconds.
  ///
  /// The 10 second buffer is to account for latency issues.
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now()
        .add(Constants.expiryMargin)
        .isAfter(
          DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000),
        );
  }

  /// Returns `true` if the token is expired right now, without applying the
  /// [Constants.expiryMargin] buffer used by [isExpired].
  @internal
  bool get isExpiredWithoutMargin {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(
      DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000),
    );
  }

  Session copyWith({
    String? accessToken,
    int? expiresIn,
    String? refreshToken,
    String? tokenType,
    String? providerToken,
    String? providerRefreshToken,
    User? user,
  }) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      expiresIn: expiresIn ?? this.expiresIn,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      providerToken: providerToken ?? this.providerToken,
      providerRefreshToken: providerRefreshToken ?? this.providerRefreshToken,
      user: user ?? this.user,
    );
  }

  @override
  String toString() {
    return 'Session(providerToken: $providerToken, providerRefreshToken: $providerRefreshToken, expiresIn: $expiresIn, tokenType: $tokenType, user: $user, accessToken: $accessToken, refreshToken: $refreshToken)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Session &&
        other.providerToken == providerToken &&
        other.providerRefreshToken == providerRefreshToken &&
        other.accessToken == accessToken &&
        other.expiresIn == expiresIn &&
        other.refreshToken == refreshToken &&
        other.tokenType == tokenType &&
        other.user == user;
  }

  @override
  int get hashCode {
    return providerToken.hashCode ^
        providerRefreshToken.hashCode ^
        accessToken.hashCode ^
        expiresIn.hashCode ^
        refreshToken.hashCode ^
        tokenType.hashCode ^
        user.hashCode;
  }
}
