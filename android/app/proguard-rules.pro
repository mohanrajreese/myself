# Release shrinking rules (R8). Plugins ship their own consumer rules; these
# cover what reflection or serialisation reaches that R8 cannot see.

# flutter_local_notifications stores scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Our own platform code: Pigeon APIs, receivers, services and workers are
# referenced from the manifest or by name from WorkManager.
-keep class com.mysticstack.fitbuddy.** { *; }

# Play Core (deferred components) is referenced by the Flutter embedding but not used.
-dontwarn com.google.android.play.core.**
