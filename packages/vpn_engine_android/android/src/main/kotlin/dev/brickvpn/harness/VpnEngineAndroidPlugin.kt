package dev.brickvpn.harness

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * P3-T11 — structural plugin registration ONLY.
 *
 * This class exists because Flutter's `pubspec.yaml` `pluginClass` field is
 * what registers an Android plugin with the engine, and ROADMAP P3-T11 AC #3
 * requires the plugin to register correctly. It deliberately:
 *
 *  - opens **no** platform channel,
 *  - defines **no** method names, argument shapes, or event types, and
 *  - adds **no** lifecycle behaviour.
 *
 * Any of those would be P3-T12's (Pigeon schema) and P3-T14's (Dart engine)
 * work, and inventing them here would preempt both. This is a placeholder that
 * satisfies registration and nothing more.
 */
class VpnEngineAndroidPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Intentionally empty — see class docs.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Intentionally empty — see class docs.
    }
}