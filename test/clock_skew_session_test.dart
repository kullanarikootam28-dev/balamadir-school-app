import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';

/// Exercises the [BALAMANDIR PATCH] in third_party/gotrue: a PC whose clock
/// is wrong must still treat a freshly issued token as valid for its real
/// lifetime (the bug that left the login page "doing nothing" on other PCs).

String _fakeJwt({required int iat, required int exp}) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': 'u1', 'role': 'authenticated', 'iat': iat, 'exp': exp})}.sig';
}

Map<String, dynamic> _tokenResponse(String jwt) => {
      'access_token': jwt,
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh',
      'user': {
        'id': 'u1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    };

void main() {
  int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  test('PC clock 3 hours ahead: a fresh token is not treated as expired', () {
    // By this PC's clock the server issued the token 3 hours "ago".
    final iat = nowSec() - 3 * 3600;
    final session =
        Session.fromServerJson(_tokenResponse(_fakeJwt(iat: iat, exp: iat + 3600)))!;
    expect(session.isExpired, isFalse);
    expect(session.expiresAt! - nowSec(), inInclusiveRange(3590, 3610));
  });

  test('PC clock 2 hours behind: token still expires an hour from now', () {
    final iat = nowSec() + 2 * 3600;
    final session =
        Session.fromServerJson(_tokenResponse(_fakeJwt(iat: iat, exp: iat + 3600)))!;
    expect(session.isExpired, isFalse);
    expect(session.expiresAt! - nowSec(), inInclusiveRange(3590, 3610));
  });

  test('correct clock: expiry is exactly the token\'s own exp', () {
    final iat = nowSec() - 5;
    final exp = iat + 3600;
    final session = Session.fromServerJson(_tokenResponse(_fakeJwt(iat: iat, exp: exp)))!;
    expect(session.expiresAt, exp);
  });

  test('the corrected expiry survives saving and restoring the session', () {
    final iat = nowSec() - 3 * 3600;
    final session =
        Session.fromServerJson(_tokenResponse(_fakeJwt(iat: iat, exp: iat + 3600)))!;
    final restored = Session.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>)!;
    expect(restored.expiresAt, session.expiresAt);
    expect(restored.isExpired, isFalse);
  });

  test('sign-in responses go through the clock-safe path', () {
    final iat = nowSec() - 3 * 3600;
    final response =
        AuthResponse.fromJson(_tokenResponse(_fakeJwt(iat: iat, exp: iat + 3600)));
    expect(response.session!.isExpired, isFalse);
  });
}
