# MCP_MEMORY_GUIDE.md — Memory MCP Setup & Usage Policy

> This document explains how AI coding agents working on this repository
> should use a Model Context Protocol (MCP) memory server, if one is
> available in the current tool/environment. It also provides setup
> instructions for the human maintainer.
>
> **Honesty notice**: MCP support varies by tool and changes over time.
> This guide describes the general mechanism and a known reference
> implementation, but the maintainer must verify actual availability and
> behavior in their specific coding agent/IDE before relying on it for
> architecture-critical continuity. Do not assume MCP memory works until
> it has been verified once in this project (see Section 5, Verification
> Task).

---

## 1. What This Solves

As this project grows across many tasks and many agent sessions, re-reading
full project history for every task is expensive and eventually infeasible
within a single context window. An MCP memory server provides a persistent,
queryable store of small, durable facts (architecture decisions, module
contracts, naming conventions already established) that an agent can query
at the start of a task instead of re-deriving or re-reading everything.

This is a **context-efficiency tool**, not a replacement for
`PROJECT_STATE.md`, `ARCHITECTURE.md`, or `ROADMAP.md`. Those files remain
the authoritative source of truth. Memory MCP is a fast index into
previously established facts, and it must never contradict what is written
in those governance files. If a conflict is ever found, the governance
files win, and the memory entry must be corrected or removed.

---

## 2. What Counts as MCP in This Project

MCP (Model Context Protocol) is a protocol, introduced by Anthropic, that
lets an AI coding tool connect to external "servers" providing extra
capabilities (tools, resources, persistent memory) beyond the model's
default context window.

Whether an agent has access to an MCP memory server depends entirely on
the **tool** being used to run the agent (e.g., Claude Code, Cursor,
Windsurf), not on the underlying model itself. Support and exact
configuration differ per tool and change frequently. The maintainer is
responsible for confirming, in their specific tool, that:

1. MCP servers are supported at all.
2. A memory-type MCP server has been installed and connected.
3. The agent can actually see and use its tools (query/store) during a
   real task — this must be empirically verified, not assumed (Section 5).

---

## 3. Reference Implementation (For the Human Maintainer to Install)

A commonly referenced open-source memory MCP server is
`@modelcontextprotocol/server-memory` (part of the official
Model Context Protocol reference servers collection). It implements a
simple persistent knowledge graph (entities, relations, observations)
that an agent can read from and write to across sessions.

### 3.1 Example Installation (Node.js-based reference server)

This requires Node.js to be installed on the development machine
(independent of the Flutter/Dart toolchain used for the app itself).

```bash
# Verify Node.js is available
node --version
npm --version

# The reference memory server can typically be run directly via npx
# without a separate global install:
npx -y @modelcontextprotocol/server-memory
3.2 Example Configuration (Tool-Specific — Verify Exact Format)
Most MCP-compatible tools expect a JSON configuration entry pointing to
the command that launches the MCP server. The exact file location and
schema differ per tool (e.g., a global config file for Claude Code, or a
project-level config file for Cursor/Windsurf). A representative example
of the kind of entry required looks like this:

JSON

{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "MEMORY_FILE_PATH": "/home/e60/Documents/Code/brick-vpn/.mcp-memory/memory.json"
      }
    }
  }
}
The maintainer must consult the specific coding tool's own
documentation for:

The exact config file name and path for that tool.
Whether the env/MEMORY_FILE_PATH option (or equivalent) is
supported by the version of the reference server being used.
Any tool-specific permission/approval step required before the agent
is allowed to actually call MCP tools during a session.
If the storage file path option is supported, it should point to a path
inside this repository but excluded from Git (e.g.,
.mcp-memory/memory.json, added to .gitignore) so memory persists
locally across sessions without being committed — this file may contain
architecture notes that are fine to exist locally, but committing an
auto-generated memory dump is not a substitute for properly maintaining
ARCHITECTURE.md and PROJECT_STATE.md as the real documentation.

4. What to Store vs. What NOT to Store
4.1 Safe and Useful to Store
Finalized architecture decisions and their one-line rationale (e.g.,
"VpnEngine abstraction uses Platform Channel on mobile, FFI planned for
desktop — see ARCHITECTURE.md Section 3").
Stable inter-module contracts (e.g., exact shape of the
VpnConnectionState sealed class once implemented, so future tasks
don't have to re-read the source file to know its shape).
Naming conventions once established for a new concept not yet in
CODING_STANDARDS.md.
Known environment quirks specific to this project setup (e.g., the
Melos/Dart Native Workspace resolution: workspace requirement
documented in ARCHITECTURE.md Section 2.1).
Task completion status summaries at the "one sentence" level (detailed
status belongs in PROJECT_STATE.md, not duplicated at length here).
4.2 Never Store (Hard Rule, Ties to SECURITY.md)
Server configurations, subscription URLs, credentials, tokens, or any
data classified as High sensitivity in SECURITY.md Section 2.
Full source code dumps (memory is for facts and decisions, not code
storage — the repository itself is the source of truth for code).
Anything that duplicates ROADMAP.md in full — store only pointers/
summaries, not the entire roadmap content, to avoid the memory store
becoming a stale second copy of a file that changes over time.
Personal or machine-specific information beyond what's needed for
engineering context (e.g., no need to store the maintainer's exact
file system username in long-term memory beyond what's operationally
necessary).
5. Mandatory Verification Task (Before Relying on This)
Before any task assumes Memory MCP is available and working, run a single
explicit verification task with the agent:

Ask the agent to store a trivial test fact (e.g., "Brick VPN uses
Flutter and Melos, established in Phase 0").
End the session / start a new one (or otherwise force a fresh context).
Ask the agent, in the new session, to query memory for that fact
without being reminded of it directly.
Confirm the agent successfully retrieves it.
Only after this test passes should AGENTS.md's instruction to "query
memory at the start of a task" be treated as reliably actionable in the
current tool setup. This verification is tracked as an explicit Phase 0
task in ROADMAP.md.

6. Graceful Degradation (Mandatory Fallback Behavior)
If Memory MCP is not available, not configured, or fails the verification
task above, agents must not block or repeatedly ask the maintainer to
set it up. Instead:

Rely entirely on PROJECT_STATE.md, ARCHITECTURE.md, and the current
ROADMAP.md task section for context, as described in AGENTS.md
Section 5.
Proceed with tasks normally — Memory MCP is a context-efficiency
optimization, not a hard dependency of the engineering process defined
in this repository.
7. Ownership of Truth
In case of any conflict between what is stored in Memory MCP and what is
written in ARCHITECTURE.md, PROJECT_STATE.md, CODING_STANDARDS.md,
or ROADMAP.md:

The Markdown governance files in AI_ROLES/ are always authoritative.
Memory MCP content is a convenience cache of facts derived from those
files and must be corrected to match them, never the other way around.