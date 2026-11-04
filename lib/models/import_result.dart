/// One row-level failure from a spreadsheet import — 1-indexed against the
/// data rows (excluding the header row) so it matches what the admin sees
/// when they open the file in Excel/Sheets.
class ImportRowError {
  const ImportRowError({required this.row, required this.message});

  final int row;
  final String message;
}

/// A newly-created login, surfaced once so the admin can hand it out —
/// this is the only place the generated password is ever shown.
class GeneratedAccount {
  const GeneratedAccount({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;
}

class ImportResult {
  const ImportResult({
    required this.successCount,
    required this.errors,
    this.newAccounts = const [],
  });

  final int successCount;
  final List<ImportRowError> errors;
  final List<GeneratedAccount> newAccounts;
}
