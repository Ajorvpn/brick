// SPDX-License-Identifier: GPL-3.0-or-later

/// High-level network reachability state.
///
/// In accordance with P4-T4 and architectural decoupling requirements, the UI
/// and domain layers depend solely on this enum and never on third-party
/// plugin types (such as `ConnectivityResult` from `connectivity_plus`).
enum NetworkStatus {
  /// The device has at least one active network interface (e.g. Wi-Fi,
  /// cellular, ethernet, VPN).
  online,

  /// The device has no active network interfaces.
  offline,

  /// Initial or indeterminate state while network status is being probed.
  checking,
}
