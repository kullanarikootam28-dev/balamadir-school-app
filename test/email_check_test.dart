import 'package:flutter_test/flutter_test.dart';

import 'package:school_management_app/utils/email_check.dart';

void main() {
  test('suggests fixes for common email typos', () {
    expect(emailTypoSuggestion('jabezgloria@gmail.con'), 'jabezgloria@gmail.com');
    expect(emailTypoSuggestion('Someone@GMIAL.com'), 'someone@gmail.com');
    expect(emailTypoSuggestion('a.b@gmail.co'), 'a.b@gmail.com');
    expect(emailTypoSuggestion('x@yahoo.cmo'), 'x@yahoo.com');
  });

  test('leaves real addresses alone', () {
    expect(emailTypoSuggestion('jabezgloria@gmail.com'), isNull);
    expect(emailTypoSuggestion('2008@students.balamandir.local'), isNull);
    expect(emailTypoSuggestion('teacher@school.co.in'), isNull);
    expect(emailTypoSuggestion('not-an-email'), isNull);
  });

  test('account email validator blocks typos and bad formats', () {
    expect(validateAccountEmail('jabezgloria@gmail.con'), contains('gmail.com'));
    expect(validateAccountEmail('no-at-sign'), isNotNull);
    expect(validateAccountEmail('ok@gmail.com'), isNull);
  });
}
