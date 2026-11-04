# Referenced by build.gradle's release buildType but didn't exist before —
# Gradle was silently treating it as empty. Flutter's own plugins ship their
# own consumer-rules.pro (merged automatically), which is why release builds
# already worked with minifyEnabled true; these are just the additional
# app-level rules for the packages this app actually uses.

# pdf/printing: reflection-based font/format handling.
-keep class com.tekartik.sqflite.** { *; }

# mobile_scanner (ML Kit barcode scanning) — reflection-based model loading.
-keep class com.google.mlkit.vision.barcode.** { *; }
-dontwarn com.google.mlkit.**

# Supabase/gotrue/postgrest models are plain Dart, not Java reflection —
# nothing additional needed there.
