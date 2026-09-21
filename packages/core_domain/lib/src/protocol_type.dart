// SPDX-License-Identifier: GPL-3.0-or-later

/// Every VPN protocol the sing-box core integration supports.
///
/// Why an enum: the protocol set is closed and small, so modeling it as an
/// enum gives the whole app a single exhaustive switch point instead of
/// scattered string comparisons. The [scheme] of each value is its
/// canonical URI scheme, so the Phase 2 subscription parser can map a
/// parsed scheme back to a protocol without ad-hoc string tables.
///
/// There is intentionally no `toString` override at this level either:
/// enum values already render safely, and credential-bearing classes live
/// elsewhere (see SECURITY.md).
enum ProtocolType {
  vless('vless'),
  vmess('vmess'),
  trojan('trojan'),
  shadowsocks('ss'),
  hysteria2('hysteria2'),
  tuic('tuic');

  const ProtocolType(this.scheme);

  /// Canonical URI scheme for this protocol. Shadowsocks maps to `'ss'`
  /// per the SIP-002 de-facto standard used by subscription links.
  final String scheme;
}
