// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contract for field-level encryption of sensitive configuration properties.
///
/// Implemented for Android Keystore hardware-backed encryption with a pure-Dart
/// authenticated fallback for host-JVM/desktop test environments.
abstract interface class SensitiveFieldCipher {
  /// Encrypts [plaintext] into an authenticated ciphertext string starting
  /// with `enc:v1:`.
  Future<String> encrypt(String plaintext);

  /// Decrypts [ciphertext] back into plaintext.
  ///
  /// Throws [FormatException] if the ciphertext is corrupted, tampered with, or
  /// invalid.
  Future<String> decrypt(String ciphertext);

  /// Returns `true` if [value] has the prefix `enc:v1:`.
  bool isEncrypted(String value);
}

/// Hardware-backed Android Keystore cipher communicating over platform channel
/// `dev.brickvpn.harness/secure_storage`.
///
/// Falls back to [LocalAuthenticatedCipher] when running in non-Android or
/// headless test environments where the native plugin is unattached.
class AndroidKeystoreSensitiveFieldCipher implements SensitiveFieldCipher {
  /// Creates an [AndroidKeystoreSensitiveFieldCipher].
  const AndroidKeystoreSensitiveFieldCipher({
    this.customChannel,
    this.customFallback,
  });

  /// Optional custom method channel overriding the default.
  final MethodChannel? customChannel;

  /// Optional custom fallback cipher overriding the default.
  final SensitiveFieldCipher? customFallback;

  static const MethodChannel _defaultChannel = MethodChannel(
    'dev.brickvpn.harness/secure_storage',
  );
  static final SensitiveFieldCipher _defaultFallback =
      LocalAuthenticatedCipher();

  /// The active method channel for native keystore calls.
  MethodChannel get channel => customChannel ?? _defaultChannel;

  /// The fallback cipher used when native channel is unavailable.
  SensitiveFieldCipher get fallback => customFallback ?? _defaultFallback;

  @override
  bool isEncrypted(String value) => value.startsWith('enc:v1:');

  @override
  Future<String> encrypt(String plaintext) async {
    try {
      final result = await channel.invokeMethod<String>(
        'encrypt',
        <String, dynamic>{'plaintext': plaintext},
      );
      if (result != null) return result;
    } on PlatformException catch (e) {
      throw FormatException('Native keystore operation failed: ${e.code}');
    } on MissingPluginException {
      // Platform channel unavailable; fall back to deterministic local cipher.
      return await fallback.encrypt(plaintext);
      // Uninitialized binding in pure unit tests throws FlutterError; fallback.
      // ignore: avoid_catching_errors
    } on FlutterError {
      // Uninitialized binding in pure unit tests; fall back to local cipher.
      return await fallback.encrypt(plaintext);
    }
    return await fallback.encrypt(plaintext);
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    try {
      final result = await channel.invokeMethod<String>(
        'decrypt',
        <String, dynamic>{'ciphertext': ciphertext},
      );
      if (result != null) return result;
    } on PlatformException catch (e) {
      throw FormatException('Native keystore operation failed: ${e.code}');
    } on MissingPluginException {
      // Platform channel unavailable; fall back to deterministic local cipher.
      return await fallback.decrypt(ciphertext);
      // Uninitialized binding in pure unit tests throws FlutterError; fallback.
      // ignore: avoid_catching_errors
    } on FlutterError {
      // Uninitialized binding in pure unit tests; fall back to local cipher.
      return await fallback.decrypt(ciphertext);
    }
    return await fallback.decrypt(ciphertext);
  }
}

/// Pure-Dart authenticated stream cipher (HMAC-SHA256 Encrypt-then-MAC).
///
/// Uses an authenticated CTR envelope with a random 12-byte IV and a 32-byte
/// HMAC-SHA256 integrity tag to guarantee zero external plugin dependencies
/// and deterministic tamper resistance in unit and integration tests.
class LocalAuthenticatedCipher implements SensitiveFieldCipher {
  /// Creates a [LocalAuthenticatedCipher] with an optional [masterKey].
  LocalAuthenticatedCipher([Uint8List? masterKey])
    : _key = masterKey ?? _defaultKey;

  static final Uint8List _defaultKey = Uint8List.fromList(
    utf8.encode('brick-vpn-authenticated-storage-key-v1-fallback-32b'),
  );

  final Uint8List _key;
  final Random _random = Random.secure();

  @override
  bool isEncrypted(String value) => value.startsWith('enc:v1:');

  @override
  Future<String> encrypt(String plaintext) async {
    final iv = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      iv[i] = _random.nextInt(256);
    }
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = _applyKeystream(iv, plaintextBytes);

    final payloadForAuth = Uint8List(iv.length + ciphertext.length)
      ..setRange(0, iv.length, iv)
      ..setRange(iv.length, iv.length + ciphertext.length, ciphertext);
    final mac = HmacSha256.compute(_key, payloadForAuth);

    final combined = Uint8List(payloadForAuth.length + mac.length)
      ..setRange(0, payloadForAuth.length, payloadForAuth)
      ..setRange(
        payloadForAuth.length,
        payloadForAuth.length + mac.length,
        mac,
      );

    final b64 = base64Url.encode(combined).replaceAll('=', '');
    return 'enc:v1:$b64';
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    if (!isEncrypted(ciphertext)) {
      throw FormatException('Not an encrypted ciphertext: $ciphertext');
    }
    final rawB64 = ciphertext.substring(7);
    final normalizedB64 = base64Url.normalize(rawB64);
    final combined = base64Url.decode(normalizedB64);

    if (combined.length < 12 + 32) {
      throw const FormatException('Ciphertext payload too short');
    }

    final iv = combined.sublist(0, 12);
    final cipherLength = combined.length - 12 - 32;
    final cipherBytes = combined.sublist(12, 12 + cipherLength);
    final mac = combined.sublist(12 + cipherLength);

    final payloadForAuth = Uint8List(12 + cipherLength)
      ..setRange(0, 12, iv)
      ..setRange(12, 12 + cipherLength, cipherBytes);

    final expectedMac = HmacSha256.compute(_key, payloadForAuth);
    if (!_constantTimeEquals(mac, Uint8List.fromList(expectedMac))) {
      throw const FormatException(
        'Ciphertext authentication failed (tampered)',
      );
    }

    final decryptedBytes = _applyKeystream(iv, cipherBytes);
    return utf8.decode(decryptedBytes);
  }

  Uint8List _applyKeystream(Uint8List iv, Uint8List input) {
    final output = Uint8List(input.length);
    var blockIndex = 0;
    var offset = 0;

    while (offset < input.length) {
      final blockData = Uint8List(iv.length + 4)..setRange(0, iv.length, iv);
      ByteData.sublistView(blockData).setUint32(iv.length, blockIndex);

      final keystream = HmacSha256.compute(_key, blockData);
      final count = (input.length - offset < 32) ? input.length - offset : 32;
      for (var i = 0; i < count; i++) {
        output[offset + i] = input[offset + i] ^ keystream[i];
      }
      offset += count;
      blockIndex++;
    }
    return output;
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// In-memory sensitive field cipher for testing purposes.
class InMemorySensitiveFieldCipher extends LocalAuthenticatedCipher {
  /// Creates an [InMemorySensitiveFieldCipher].
  InMemorySensitiveFieldCipher([super.masterKey]);
}

/// Reactive provider exposing the system [SensitiveFieldCipher].
final sensitiveFieldCipherProvider = Provider<SensitiveFieldCipher>((ref) {
  return const AndroidKeystoreSensitiveFieldCipher();
});

/// Pure-Dart SHA-256 implementation (FIPS 180-4).
@visibleForTesting
class Sha256 {
  static const List<int> _k = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static Uint8List hash(Uint8List data) {
    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final length = data.length;
    final bitLength = length * 8;
    final padLength = ((length + 8) ~/ 64 + 1) * 64;
    final padded = Uint8List(padLength)
      ..setRange(0, length, data)
      ..[length] = 0x80;

    ByteData.sublistView(padded).setUint64(padLength - 8, bitLength);

    final w = Uint32List(64);

    for (var i = 0; i < padLength; i += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = ByteData.sublistView(padded).getUint32(i + t * 4);
      }
      for (var t = 16; t < 64; t++) {
        final s0 =
            _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ _shr(w[t - 15], 3);
        final s1 =
            _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ _shr(w[t - 2], 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var t = 0; t < 64; t++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + _k[t] + w[t]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = Uint8List(32);
    ByteData.sublistView(out)
      ..setUint32(0, h0)
      ..setUint32(4, h1)
      ..setUint32(8, h2)
      ..setUint32(12, h3)
      ..setUint32(16, h4)
      ..setUint32(20, h5)
      ..setUint32(24, h6)
      ..setUint32(28, h7);
    return out;
  }

  static int _shr(int x, int n) => (x & 0xffffffff) >>> n;

  static int _rotr(int x, int n) {
    final ux = x & 0xffffffff;
    return ((ux >>> n) | (ux << (32 - n))) & 0xffffffff;
  }
}

/// Pure-Dart HMAC-SHA256 implementation (RFC 2104 / RFC 4231).
@visibleForTesting
class HmacSha256 {
  static Uint8List compute(Uint8List key, Uint8List message) {
    var k = key;
    if (k.length > 64) {
      k = Sha256.hash(k);
    }
    final kPad = Uint8List(64)..setRange(0, k.length, k);

    final ipad = Uint8List(64);
    final opad = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      ipad[i] = kPad[i] ^ 0x36;
      opad[i] = kPad[i] ^ 0x5c;
    }

    final inner = Uint8List(64 + message.length)
      ..setRange(0, 64, ipad)
      ..setRange(64, 64 + message.length, message);
    final innerHash = Sha256.hash(inner);

    final outer = Uint8List(64 + 32)
      ..setRange(0, 64, opad)
      ..setRange(64, 64 + 32, innerHash);
    return Sha256.hash(outer);
  }
}
