/// Catches the email typos that create accounts nobody can receive mail at
/// (a student was registered as "…@gmail.con"). Returns a corrected
/// suggestion, or null if nothing looks wrong.
String? emailTypoSuggestion(String email) {
  final value = email.trim().toLowerCase();
  final at = value.lastIndexOf('@');
  if (at <= 0 || at == value.length - 1) return null;
  final local = value.substring(0, at);
  var domain = value.substring(at + 1);
  final original = domain;

  const domainFixes = {
    'gmial.com': 'gmail.com',
    'gamil.com': 'gmail.com',
    'gmal.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'gmaill.com': 'gmail.com',
    'gmail.co': 'gmail.com',
    'yaho.com': 'yahoo.com',
    'yahooo.com': 'yahoo.com',
    'hotmial.com': 'hotmail.com',
    'outlok.com': 'outlook.com',
  };
  const endingFixes = {
    '.con': '.com',
    '.cmo': '.com',
    '.ocm': '.com',
    '.comm': '.com',
    '.coom': '.com',
    '.vom': '.com',
    '.xom': '.com',
  };

  for (final entry in endingFixes.entries) {
    if (domain.endsWith(entry.key)) {
      domain = domain.substring(0, domain.length - entry.key.length) + entry.value;
      break;
    }
  }
  domain = domainFixes[domain] ?? domain;
  return domain == original ? null : '$local@$domain';
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Form validator for new/edited accounts: format plus the typo check.
String? validateAccountEmail(String? value) {
  final email = value?.trim() ?? '';
  if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
  final suggestion = emailTypoSuggestion(email);
  if (suggestion != null) return 'Looks like a typo — did you mean $suggestion?';
  return null;
}
