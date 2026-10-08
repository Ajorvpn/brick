package dev.brickvpn.harness.vpn

/**
 * Lifecycle state of the native Android VPN harness.
 *
 * This is a **sealed class, not an enum**, for two reasons:
 *
 *  1. `Error` carries a `reason`, so it cannot be a bare enum constant. An enum
 *     would force a parallel out-of-band "last error string", which is exactly
 *     the kind of loosely-associated data that lets a state machine lie.
 *  2. A sealed hierarchy makes the set of states exhaustive at compile time, so
 *     a `when` over [VpnState] cannot silently miss a case.
 *
 * ## Relationship to `core_domain`'s `ConnectionState`
 *
 * `core_domain` (Dart, FROZEN) defines the **authoritative, normative** graph
 * over five variants. This harness deliberately splits `Connecting` into
 * `Preparing` + `Starting` and `Disconnected` into `Idle` + `Stopped` so the
 * native side can distinguish "a teardown finished cleanly" ([Stopped]) from
 * "nothing has been attempted yet" ([Idle]) — a distinction the Dart side
 * collapses. [Revoked] has no `ConnectionState` counterpart and projects onto
 * `Error(PermissionDenied)`, which is semantically exact.
 *
 * | This file (`VpnState`) | `core_domain` (`ConnectionState`) | Note |
 * |---|---|---|
 * | `Idle`                | `Disconnected` | nothing attempted yet |
 * | `Preparing`           | `Connecting`   | config validation / TUN setup |
 * | `Starting`            | `Connecting`   | engine start in flight |
 * | `Running`             | `Connected`    | tunnel up |
 * | `Stopping`            | `Disconnecting`| teardown announced |
 * | `Stopped`             | `Disconnected` | teardown completed cleanly |
 * | `Error(reason)`       | `Error(reason)`| 1:1 |
 * | `Revoked`             | `Error(PermissionDenied)` | no native counterpart |
 *
 * Every [LEGAL] edge below is a refinement of `AI_ROLES/ARCHITECTURE.md`
 * Section 3.1.1's normative graph — no edge exists here that is illegal there.
 */
sealed class VpnState {

    /** Nothing has been attempted. Initial state, and the resting state after revocation is cleared. */
    object Idle : VpnState() {
        override fun toString() = "Idle"
    }

    /** A start attempt was accepted; validating config and building the TUN/engine. */
    object Preparing : VpnState() {
        override fun toString() = "Preparing"
    }

    /** Configuration accepted; the engine is starting. */
    object Starting : VpnState() {
        override fun toString() = "Starting"
    }

    /** Tunnel is up and traffic may flow. */
    object Running : VpnState() {
        override fun toString() = "Running"
    }

    /** Teardown announced. Converges on [Stopped] and nothing else. */
    object Stopping : VpnState() {
        override fun toString() = "Stopping"
    }

    /** Teardown completed cleanly. Distinguishes a finished session from [Idle]. */
    object Stopped : VpnState() {
        override fun toString() = "Stopped"
    }

    /** Failure, with a human-readable reason. */
    data class Error(val reason: String) : VpnState() {
        override fun toString() = "Error($reason)"
    }

    /** VPN permission was revoked (another app took the VPN slot, or the user withdrew it). */
    object Revoked : VpnState() {
        override fun toString() = "Revoked"
    }

    companion object {
        /**
         * The complete legal-transition table, keyed by a **stable string id**
         * rather than by the state objects themselves.
         *
         * ## Why a String key and not `Map<VpnState, ...>`
         *
         * This originally was `Map<VpnState, Set<VpnState>>` built in this
         * companion object, and it was **broken by JVM class-initialization
         * order**. `VpnStateMachine`'s field initializer touches `VpnState.Idle`
         * before anything else, so `VpnState$Idle.<clinit>` is entered *before*
         * `VpnState$Companion.<clinit>`. The companion's `mapOf(...)` then reads
         * the still-uninitialized `Idle` and `Revoked` singletons and captures
         * them as **`null`**, permanently:
         *
         * ```
         * key=null            -> [Preparing, Revoked]   // Idle, lost
         * key=Stopped         -> [Preparing, null, Revoked]
         * key=Revoked         -> [null]                 // Idle, lost
         * Idle.canTransitionTo(Preparing) == false       // silently wrong
         * ```
         *
         * Because the map is built once, the corruption is permanent and every
         * subsequent lookup misbehaves — a *silent* wrong answer, which is far
         * worse than a crash. `revoke` and `Idle -> Preparing` both failed this
         * way, and the bug only reproduced when `VpnStateMachine` (not a test
         * that touches `LEGAL` first) was the first class to load the states.
         *
         * Keying by a `const` String makes the table independent of object
         * initialization order entirely, and [legalTargets] does the kind-aware
         * matching explicitly so it is obvious and testable.
         */
        val LEGAL: Map<String, Set<String>> = mapOf(
            ID_IDLE to setOf(ID_PREPARING, ID_REVOKED),
            ID_PREPARING to setOf(ID_STARTING, ID_STOPPING, ID_ERROR, ID_REVOKED),
            ID_STARTING to setOf(ID_RUNNING, ID_STOPPING, ID_ERROR, ID_REVOKED),
            ID_RUNNING to setOf(ID_STOPPING, ID_ERROR, ID_REVOKED),
            ID_STOPPING to setOf(ID_STOPPED, ID_REVOKED),
            ID_STOPPED to setOf(ID_PREPARING, ID_IDLE, ID_REVOKED),
            ID_ERROR to setOf(ID_PREPARING, ID_STOPPING, ID_REVOKED),
            ID_REVOKED to setOf(ID_IDLE),
        )

        const val ID_IDLE = "Idle"
        const val ID_PREPARING = "Preparing"
        const val ID_STARTING = "Starting"
        const val ID_RUNNING = "Running"
        const val ID_STOPPING = "Stopping"
        const val ID_STOPPED = "Stopped"
        const val ID_ERROR = "Error"
        const val ID_REVOKED = "Revoked"
    }
}

/** This state's key in [VpnState.LEGAL]. Deliberately derived, never cached. */
val VpnState.id: String
    get() = when (this) {
        is VpnState.Idle -> VpnState.ID_IDLE
        is VpnState.Preparing -> VpnState.ID_PREPARING
        is VpnState.Starting -> VpnState.ID_STARTING
        is VpnState.Running -> VpnState.ID_RUNNING
        is VpnState.Stopping -> VpnState.ID_STOPPING
        is VpnState.Stopped -> VpnState.ID_STOPPED
        is VpnState.Error -> VpnState.ID_ERROR
        is VpnState.Revoked -> VpnState.ID_REVOKED
    }

/** The ids this state may legally move to. Empty if the id is unknown. */
fun VpnState.legalTargetIds(): Set<String> = VpnState.LEGAL[id] ?: emptySet()

/**
 * Whether [this] -> [next] is a legal transition.
 *
 * Matching is by state *identity of kind* (see [id]), so `Error` matches any
 * `Error` reason: the reason changes what is reported, never what is legal.
 */
fun VpnState.canTransitionTo(next: VpnState): Boolean = next.id in legalTargetIds()
