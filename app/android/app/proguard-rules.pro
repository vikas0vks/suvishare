# Suvi Share — R8 rules for the release build.

# Flutter engine entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_foreground_task starts its service by reflection from the manifest.
-keep class com.pravera.flutter_foreground_task.** { *; }

# Plugins that register via reflection or annotation processing.
-keep class dev.flutter.plugins.** { *; }

# Kotlin metadata used by plugin reflection.
-keepattributes *Annotation*, InnerClasses, Signature, RuntimeVisible*Annotations

# Play Core is referenced by the Flutter embedding for deferred components,
# which this app does not use — silence the missing-class warnings.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
