package dev.brickvpn.harness.vpn

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Host-JVM unit tests for [CommandVerdictHub] (P3-T13 Part A seam). No
 * emulator, no Robolectric; the hub's only Android touch is the default
 * `Log.w` fallback, which these tests bypass by overriding [errorLogger]
 * exactly as the seam contract requires.
 */
class CommandVerdictHubTest {

    private val recorded = mutableListOf<Pair<CommandKind, VpnCommandResult>>()
    private val logged = mutableListOf<String>()

    /**
     * Version-proof stand-in for `Assert.assertDoesNotThrow`: AGP resolves
     * JUnit 4.13.2's **android** variant, which does not contain that 4.13
     * API, and `build.gradle.kts` must not be edited for a test-only need.
     * Fails loudly if [block] throws.
     */
    private fun assertNoThrow(block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            throw AssertionError("expected no throw, but got ${t.javaClass.name}: ${t.message}", t)
        }
    }

    @Before
    fun setUp() {
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        recorded.clear()
        logged.clear()
    }

    @After
    fun tearDown() {
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        recorded.clear()
        logged.clear()
    }

    /** All 5 [VpnCommandResult] variants, published under both [CommandKind]s. */
    @Test
    fun `all five verdict variants are published for both command kinds`() {
        CommandVerdictHub.listener = { kind, result -> recorded += kind to result }

        val all = listOf(
            VpnCommandResult.Accepted,
            VpnCommandResult.RejectedBusy,
            VpnCommandResult.RejectedInvalidConfig,
            VpnCommandResult.RejectedPermissionDenied,
            VpnCommandResult.Failed,
        )
        for (result in all) {
            CommandVerdictHub.publish(CommandKind.START, result)
            CommandVerdictHub.publish(CommandKind.STOP, result)
        }

        val expected = all.flatMap { listOf(CommandKind.START to it, CommandKind.STOP to it) }
        assertEquals(expected, recorded)
    }

    /** With no listener installed (the default), publishing records nothing. */
    @Test
    fun `publish without a listener throws nothing and changes nothing`() {
        assertNull(CommandVerdictHub.listener)
        assertNoThrow {
            CommandVerdictHub.publish(CommandKind.START, VpnCommandResult.Accepted)
            CommandVerdictHub.publish(CommandKind.STOP, VpnCommandResult.Failed)
        }
        assertNull(CommandVerdictHub.listener)
        assertTrue(recorded.isEmpty())
    }

    /** Adding a listener later does not replay missed events. */
    @Test
    fun `a listener attached after a publish does not replay missed events`() {
        CommandVerdictHub.publish(CommandKind.START, VpnCommandResult.Accepted)

        CommandVerdictHub.listener = { kind, result -> recorded += kind to result }

        assertTrue(recorded.isEmpty())
    }

    /** A throwing listener is caught and routed to [CommandVerdictHub.errorLogger]. */
    @Test
    fun `a throwing listener is routed to errorLogger and publish still returns`() {
        CommandVerdictHub.errorLogger = { msg, t -> logged += "$msg|${t.javaClass.simpleName}" }
        CommandVerdictHub.listener = { _, _ -> throw IllegalStateException("boom") }

        assertNoThrow {
            CommandVerdictHub.publish(CommandKind.STOP, VpnCommandResult.RejectedBusy)
        }

        assertEquals(1, logged.size)
        assertTrue("message should name the kind: ${logged[0]}", logged[0].contains("STOP"))
        assertTrue("message should name the result: ${logged[0]}", logged[0].contains("RejectedBusy"))
        assertTrue(
            "message should name the throwable: ${logged[0]}",
            logged[0].contains("IllegalStateException"),
        )
    }

    /** Default fallback is `Log.w` — unmocked on the host JVM, and still swallowed. */
    @Test
    fun `publish never throws when errorLogger is null`() {
        // errorLogger is deliberately null (reset state): the fallback path
        // touches android.util.Log, which throws on the host JVM — publish()
        // must swallow even that, per its never-throws contract.
        CommandVerdictHub.listener = { _, _ -> throw RuntimeException("kaboom") }
        assertNull(CommandVerdictHub.errorLogger)

        assertNoThrow {
            CommandVerdictHub.publish(CommandKind.START, VpnCommandResult.Failed)
        }
    }

    /** Even a failing errorLogger cannot escape [CommandVerdictHub.publish]. */
    @Test
    fun `a throwing errorLogger cannot escape publish`() {
        CommandVerdictHub.errorLogger = { _, _ -> throw UnsupportedOperationException("logger down") }
        CommandVerdictHub.listener = { _, _ -> throw IllegalArgumentException("listener down") }

        assertNoThrow {
            CommandVerdictHub.publish(CommandKind.START, VpnCommandResult.Accepted)
        }
    }

    /** [CommandVerdictHub.reset] clears both hooks; publishes after it record nothing. */
    @Test
    fun `reset clears listener and errorLogger`() {
        CommandVerdictHub.listener = { kind, result -> recorded += kind to result }
        CommandVerdictHub.errorLogger = { msg, _ -> logged += msg }

        CommandVerdictHub.reset()

        assertNull(CommandVerdictHub.listener)
        assertNull(CommandVerdictHub.errorLogger)

        CommandVerdictHub.publish(CommandKind.START, VpnCommandResult.Accepted)
        assertTrue(recorded.isEmpty())
        assertTrue(logged.isEmpty())
    }
}
