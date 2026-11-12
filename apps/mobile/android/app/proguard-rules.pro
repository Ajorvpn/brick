# ==============================================================================
# Brick VPN - apps/mobile Application ProGuard / R8 Release Hardening Rules
# Configured via buildTypes { release { isMinifyEnabled = true; isShrinkResources = true; } }
# ==============================================================================

# 1. Flutter Framework and Engine Embedding Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**

# 2. Gomobile Runtime & JNI Bridge
# libgojni.so resolves go.Seq, go.Universe, and inner classes via C/JNI FindClass & GetMethodID.
# Without these rules, R8 renames or strips Seq, causing immediate UnsatisfiedLinkError
# or NoClassDefFoundError when Go native code calls back into Java.
-keep class go.** { *; }
-dontwarn go.**

# 3. Sing-box / Libbox Gomobile Bound Classes and Interfaces
# io.nekohasekai.libbox contains BoxService, CommandClient, PlatformInterface, and proxy classes
# invoked dynamically across the Go/Java bridge.
-keep class io.nekohasekai.libbox.** { *; }
-keep interface io.nekohasekai.libbox.** { *; }
-dontwarn io.nekohasekai.libbox.**
-keep class libbox.** { *; }
-keep interface libbox.** { *; }
-dontwarn libbox.**

# 4. Brick VPN Android Native Harness, Pigeon Generated IPC & BrickVpnService
# Keeps foreground VpnService, Pigeon host APIs, CommandCoordinator, and secure storage channel.
-keep class dev.brickvpn.harness.** { *; }
-keep interface dev.brickvpn.harness.** { *; }

# 5. Kotlin Coroutines & Reflection-Adjacent Metadata
-dontwarn kotlinx.coroutines.**

# 6. Standard JNI Native Method Preservation
# Preserve native method names and containing classes so JNI symbols bind properly.
-keepclasseswithmembernames class * {
    native <methods>;
}

# 7. Attributes preservation for Gomobile inner classes, annotations, and signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exceptions,SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# 8. Preserve enum static methods required by Pigeon / JNI / Kotlin reflection under R8 optimize mode
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 9. Google ML Kit Barcode Scanning & Barhopper Native JNI Bridge (libbarhopper_v3.so)
# Used by mobile_scanner in QrScanScreen; native C++ code reflects on Barhopper fields & constructors.
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.vision.barhopper.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.libraries.barhopper.**
-dontwarn com.google.photos.vision.barhopper.**

# 10. AndroidX CameraX & DataStore Native JNI Bridges (libimage_processing_util_jni.so, libsurface_util_jni.so, libdatastore_shared_counter.so)
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class androidx.datastore.** { *; }
-dontwarn androidx.datastore.**

# 11. Application MainActivity & Flutter Plugin Registrants
-keep class dev.brickvpn.mobile.** { *; }



