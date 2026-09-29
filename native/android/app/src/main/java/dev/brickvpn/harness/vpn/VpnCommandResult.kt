package dev.brickvpn.harness.vpn

/**
 * Result of a command, describing ONLY whether the command was accepted for
 * processing — never what the final state will be.
 *
 * This mirrors the Dart `VpnCommandResult` sealed class from P1-T4
 * (`packages/core_vpn_engine`) one-for-one, satisfying `ARCHITECTURE.md`
 * Section 3.5: "Command acceptance is separate from final state ... the actual
 * resulting connected/stopped transition must be communicated exclusively via
 * the state stream."
 */
sealed class VpnCommandResult {
    /** Command accepted; the resulting state will arrive via [VpnStateMachine.state]. */
    object Accepted : VpnCommandResult() {
        override fun toString() = "Accepted"
    }

    /** A start was rejected because a session is already Preparing/Starting/Running/Stopping. */
    object RejectedBusy : VpnCommandResult() {
        override fun toString() = "RejectedBusy"
    }

    /** The supplied configuration is not usable. */
    object RejectedInvalidConfig : VpnCommandResult() {
        override fun toString() = "RejectedInvalidConfig"
    }

    /** VPN permission is not held (see [VpnState.Revoked]). */
    object RejectedPermissionDenied : VpnCommandResult() {
        override fun toString() = "RejectedPermissionDenied"
    }

    /** The command itself could not be processed. */
    object Failed : VpnCommandResult() {
        override fun toString() = "Failed"
    }
}
