# ==============================================================================
# Brick VPN - packages/vpn_engine_android Consumer ProGuard/R8 Rules
# Automatically exported to consuming applications (apps/mobile) via
# consumerProguardFiles in build.gradle.kts.
# ==============================================================================

# 1. Gomobile Runtime & JNI Bridge
# libgojni.so resolves go.Seq, go.Universe, and inner classes via C/JNI FindClass & GetMethodID.
# Without these rules, R8 renames or strips Seq, causing immediate UnsatisfiedLinkError
# or NoClassDefFoundError when Go native code calls back into Java.
-keep class go.** { *; }
-dontwarn go.**

# 2. Sing-box / Libbox Gomobile Bound Classes and Interfaces
# io.nekohasekai.libbox contains BoxService, CommandClient, PlatformInterface, and proxy classes
# invoked dynamically across the Go/Java bridge.
-keep class io.nekohasekai.libbox.** { *; }
-keep interface io.nekohasekai.libbox.** { *; }
-dontwarn io.nekohasekai.libbox.**
-keep class libbox.** { *; }
-keep interface libbox.** { *; }
-dontwarn libbox.**

# 3. Brick VPN Android Native Harness, Pigeon Generated IPC & BrickVpnService
# Keeps foreground VpnService, Pigeon host APIs, CommandCoordinator, and secure storage channel.
-keep class dev.brickvpn.harness.** { *; }
-keep interface dev.brickvpn.harness.** { *; }

# 4. Attributes preservation for Gomobile inner classes, annotations, and signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exceptions,SourceFile,LineNumberTable

# 5. Preserve enum static methods required by Pigeon / JNI / Kotlin reflection under R8 optimize mode
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}


