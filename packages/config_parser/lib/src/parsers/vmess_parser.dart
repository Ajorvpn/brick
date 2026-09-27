// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Parses a `vmess://` link in the v2rayN base64-JSON form into a
/// [VmessOutbound].
///
/// Shape: `vmess://` + base64(JSON) where the JSON is
/// `{"v":"2","ps":..,"add":..,"port":"..","id":"..","aid":"0", ...}`.
///
/// Decoding goes through the P2-T1 helpers (`safeBase64DecodeToString` then
/// `safeJsonDecode`), so a hostile payload is size-bounded and depth-bounded
/// before any field is read, and every failure is an `Err` rather than an
/// exception.
Result<OutboundConfig, ConfigParseError> parseVmessUri(String uri) {
  final prefix = 'vmess://';
  if (!uri.startsWith(prefix)) {
    final scheme = uri.contains('://') ? uri.split('://').first : '';
    return Err(UnsupportedSchemeError(scheme));
  }

  final payload = uri.substring(prefix.length);
  final decoded = safeBase64DecodeToString(payload, field: 'vmess payload');
  if (decoded case Err(:final error)) {
    return Err(error);
  }
  final jsonText = (decoded as Ok<String, ConfigParseError>).value;

  final json = safeJsonDecode(jsonText, field: 'vmess payload');
  if (json case Err(:final error)) {
    return Err(error);
  }
  final value = (json as Ok<Object?, ConfigParseError>).value;
  if (value is! Map) {
    return Err(InvalidSyntaxError('vmess payload', 'not a JSON object'));
  }
  final map = value.cast<String, Object?>();

  final add = _stringField(map, 'add');
  if (add == null || add.isEmpty) {
    return Err(MissingRequiredFieldError('add'));
  }
  final hostCheck = validateHost(add, 'add');
  if (hostCheck case Err(:final error)) {
    return Err(error);
  }

  final portRaw = _stringField(map, 'port');
  if (portRaw == null || portRaw.isEmpty) {
    return Err(MissingRequiredFieldError('port'));
  }
  final portCheck = parsePort(portRaw, 'port');
  if (portCheck case Err(:final error)) {
    return Err(error);
  }
  final port = (portCheck as Ok<int, ConfigParseError>).value;

  final id = _stringField(map, 'id');
  if (id == null || id.isEmpty) {
    return Err(MissingRequiredFieldError('id'));
  }
  final uuidCheck = validateUuid(id, 'id');
  if (uuidCheck case Err(:final error)) {
    return Err(error);
  }

  // aid is optional; modern servers use 0.
  var alterId = 0;
  final aidRaw = _stringField(map, 'aid');
  if (aidRaw != null && aidRaw.isNotEmpty) {
    final parsed = int.tryParse(aidRaw);
    if (parsed == null || parsed < 0) {
      return Err(InvalidFieldValueError('aid', 'not a non-negative integer'));
    }
    alterId = parsed;
  }

  // v2rayN encodes booleans as the strings "true"/"false".
  final tlsField = _stringField(map, 'tls')?.toLowerCase();
  final wantsTls = tlsField == 'tls' || tlsField == 'true';
  final sni = _stringField(map, 'sni');
  final security = _stringField(map, 'scy') ?? 'auto';
  final net = _stringField(map, 'net')?.toLowerCase();

  // Reuse the shared transport builder so v2ray and v2rayN spellings agree.
  final query = <String, String>{
    if (net != null) 'type': net,
    if (sni != null) 'sni': sni,
    if (_stringField(map, 'path') != null) 'path': _stringField(map, 'path')!,
    if (_stringField(map, 'host') != null) 'host': _stringField(map, 'host')!,
    if (_stringField(map, 'serviceName') != null)
      'serviceName': _stringField(map, 'serviceName')!,
    if (wantsTls) 'security': 'tls',
  };
  final transport = buildTransportSettings(query);
  if (transport case Err(:final error)) {
    return Err(error);
  }

  return Ok<OutboundConfig, ConfigParseError>(
    VmessOutbound(
      server: add,
      serverPort: port,
      uuid: id,
      security: security,
      alterId: alterId,
      // `net` is the V2Ray TRANSPORT, not the L4 network. sing-box puts
      // transports under `transport.type`; leaving `network` null enables
      // both tcp and udp (the schema default).
      network: _l4Network(map['network']),
      tls: wantsTls
          ? TlsSettings(
              enabled: true,
              serverName: (sni?.isNotEmpty ?? false) ? sni : null,
            )
          : null,
      transport: (transport as Ok<TransportSettings?, ConfigParseError>).value,
    ),
  );
}

/// The remark (`ps`) carried by a v2rayN link, or a `host:port` fallback.
String parseVmessRemark(String uri) {
  final prefix = 'vmess://';
  if (!uri.startsWith(prefix)) {
    return '';
  }
  final decoded = safeBase64DecodeToString(uri.substring(prefix.length));
  if (decoded is Err) {
    return '';
  }
  final json = safeJsonDecode((decoded as Ok<String, ConfigParseError>).value);
  if (json is Err) {
    return '';
  }
  final value = (json as Ok<Object?, ConfigParseError>).value;
  if (value is! Map) {
    return '';
  }
  final ps = value.cast<String, Object?>()['ps'];
  if (ps is String && ps.isNotEmpty) {
    return ps;
  }
  final add = value.cast<String, Object?>()['add'];
  final port = value.cast<String, Object?>()['port'];
  return '$add:$port';
}

/// Resolves the sing-box L4 `network` from a v2rayN JSON field.
///
/// Returns null unless the value is a genuine L4 network. sing-box enables
/// both tcp and udp when `network` is absent, which is the correct default
/// for a VPN client, so this never invents a value.
String? _l4Network(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final value = raw.toLowerCase();
  return (value == 'tcp' || value == 'udp') ? value : null;
}

/// Reads a JSON field that may be a String or a number.
String? _stringField(Map<String, Object?> map, String key) {
  final raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return raw;
  }
  if (raw is num) {
    return raw.toString();
  }
  return null;
}
