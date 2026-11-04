import 'package:supabase_flutter/supabase_flutter.dart';

/// This project's PostgREST caps every response at 1000 rows
/// (`max_rows = 1000`), silently — a school-wide attendance or grades read
/// past that just comes back short, with no error. Anything that aggregates
/// a whole table (analytics, rankings, reports, exports) must page through
/// it instead.
///
/// [build] must return a fresh query each call (builders aren't reusable
/// across pages) with a stable, unique `.order(...)` — usually `id` — or
/// pages can overlap or skip rows.
const int kPostgrestPageSize = 1000;

Future<List<Map<String, dynamic>>> fetchAllRows(
  PostgrestTransformBuilder<PostgrestList> Function() build,
) async {
  final rows = <Map<String, dynamic>>[];
  var from = 0;
  while (true) {
    final page = await build().range(from, from + kPostgrestPageSize - 1);
    rows.addAll(page);
    if (page.length < kPostgrestPageSize) break;
    from += kPostgrestPageSize;
  }
  return rows;
}
