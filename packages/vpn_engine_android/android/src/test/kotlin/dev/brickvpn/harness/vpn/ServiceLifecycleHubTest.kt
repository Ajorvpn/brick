package dev.brickvpn.harness.vpn

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Host-JVM unit tests for [ServiceLifecycleHub] (P3-T13 Part A seam). No
 * emulator, no Robolectric; the hub's only Android touch is the default
 * `Log.w` fallback, which these tests bypass by overriding [errorLogger]
 * exactly as the seam contract requires.
 */
class ServiceLifecycleHubTest {

    private val events = mutableListOf<String>()
    private val logged = mutableListOf<String>()
    private lateinit var machine: VpnStateMachine

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

    private fun recordingObserver() = object : ServiceLifecycleObserver {
        override fun onCreated(machine: VpnStateMachine) {
            events += "created"
        }

        override fun onDestroyed() {
            events += "destroyed"
        }
    }

    @Before
    fun setUp() {
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        events.clear()
        logged.clear()
        machine = VpnStateMachine()
    }

    @After
    fun tearDown() {
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        events.clear()
        logged.clear()
        machine.close()
    }

    /** [ServiceLifecycleHub.created] hands over the live machine; [ServiceLifecycleHub.destroyed] fires too. */
    @Test
    fun `onCreated delivers the live machine and onDestroyed fires`() {
        var seen: VpnStateMachine? = null
        var destroyedCount = 0
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                seen = machine
                events += "created"
            }

            override fun onDestroyed() {
                destroyedCount++
                events += "destroyed"
            }
        }

        ServiceLifecycleHub.created(machine)
        ServiceLifecycleHub.destroyed()

        assertSame("onCreated must receive the exact live machine", machine, seen)
        assertEquals(listOf("created", "destroyed"), events)
        assertEquals(1, destroyedCount)
    }

    /** With no observer (the default), lifecycle calls record nothing and a later observer sees no replay. */
    @Test
    fun `lifecycle calls with no observer throw nothing and are dropped`() {
        assertNull(ServiceLifecycleHub.observer)
        assertNoThrow {
            ServiceLifecycleHub.created(machine)
            ServiceLifecycleHub.destroyed()
        }

        // A later observer does not replay missed events.
        ServiceLifecycleHub.observer = recordingObserver()
        assertTrue(events.isEmpty())
    }

    /** Exactly one observer: registering a second replaces the first. */
    @Test
    fun `exactly one observer - a second registration replaces the first`() {
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                events += "first-created"
            }

            override fun onDestroyed() {
                events += "first-destroyed"
            }
        }
        ServiceLifecycleHub.observer = recordingObserver()

        ServiceLifecycleHub.created(machine)
        ServiceLifecycleHub.destroyed()

        assertEquals(listOf("created", "destroyed"), events)
    }

    /** A throwing observer is caught and routed to [ServiceLifecycleHub.errorLogger]. */
    @Test
    fun `a throwing observer is routed to errorLogger and calls still return`() {
        ServiceLifecycleHub.errorLogger = { msg, t -> logged += "$msg|${t.javaClass.simpleName}" }
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                throw IllegalStateException("boom-created")
            }

            override fun onDestroyed() {
                throw IllegalStateException("boom-destroyed")
            }
        }

        assertNoThrow { ServiceLifecycleHub.created(machine) }
        assertNoThrow { ServiceLifecycleHub.destroyed() }

        assertEquals(2, logged.size)
        assertTrue("first log should name onCreated: ${logged[0]}", logged[0].contains("onCreated"))
        assertTrue(
            "first log should name the throwable: ${logged[0]}",
            logged[0].contains("IllegalStateException"),
        )
        assertTrue("second log should name onDestroyed: ${logged[1]}", logged[1].contains("onDestroyed"))
    }

    /** Default fallback is `Log.w` — unmocked on the host JVM, and still swallowed. */
    @Test
    fun `lifecycle calls never throw when errorLogger is null`() {
        // errorLogger is deliberately null (reset state): the fallback path
        // touches android.util.Log, which throws on the host JVM — the hub
        // must swallow even that, per its never-throws contract.
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                throw RuntimeException("kaboom")
            }

            override fun onDestroyed() {
                throw RuntimeException("kaboom")
            }
        }
        assertNull(ServiceLifecycleHub.errorLogger)

        assertNoThrow {
            ServiceLifecycleHub.created(machine)
            ServiceLifecycleHub.destroyed()
        }
    }

    /** Even a failing errorLogger cannot escape the lifecycle calls. */
    @Test
    fun `a throwing errorLogger cannot escape lifecycle calls`() {
        ServiceLifecycleHub.errorLogger = { _, _ -> throw UnsupportedOperationException("logger down") }
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                throw IllegalArgumentException("observer down")
            }

            override fun onDestroyed() {
                throw IllegalArgumentException("observer down")
            }
        }

        assertNoThrow {
            ServiceLifecycleHub.created(machine)
            ServiceLifecycleHub.destroyed()
        }
    }

    /** [ServiceLifecycleHub.reset] clears both hooks; later events record nothing. */
    @Test
    fun `reset clears observer and errorLogger`() {
        ServiceLifecycleHub.observer = recordingObserver()
        ServiceLifecycleHub.errorLogger = { msg, _ -> logged += msg }

        ServiceLifecycleHub.reset()

        assertNull(ServiceLifecycleHub.observer)
        assertNull(ServiceLifecycleHub.errorLogger)

        ServiceLifecycleHub.created(machine)
        ServiceLifecycleHub.destroyed()
        assertTrue(events.isEmpty())
        assertTrue(logged.isEmpty())
    }
}
