# Security notes — `config_parser` adversarial pass (P2-T11)

This file records the adversarial-input hardening pass performed in P2-T11:
what was attacked, what was found, and what invariants are now enforced by
machine. The test suite is `test/fuzz_adversarial_test.dart` (104 tests).

## Threat model

Every byte this package parses is untrusted. `SECURITY.md` §1 names a *malicious
or compromised subscription provider* as an explicit threat actor, so a
subscription body is attacker-controlled by assumption, not by exception. The
fetcher (P2-T10) adds a second untrusted surface: the response body and the
redirect chain.

## The two enforced invariants

Every test in the fuzz suite asserts both, across **all 15 public entry points**
(`parseUri`, each of the 9 protocol parsers, `parseConfigContent`,
`parseSubscription`, `parseUriRemark`, `decodeSubscriptionBody`,
`SubscriptionUserInfo.parse`, `readSingBoxOutboundJson`):

1. **Zero unhandled throws.** No `ArgumentError`, `StateError`,
   `FormatException`, `RangeError`, `TypeError` or `CastError` may escape. Each
   input must produce a typed `Err(ConfigParseError)` or a safe partial-success
   `SubscriptionParseResult`.
2. **Zero secret leaks.** A canary string is planted in every credential
   position of every hostile input. No `error.message` and no `error.code` may
   contain it.

The suite also asserts the corpus is *doing something*: each entry point must
actually produce errors, so the tests cannot pass by silently not exercising
the code.

## Adversarial categories covered

| Category | Examples |
|---|---|
| **Size extremes** | 8 KB+1, 64 KB and 1 MB URIs; a 10 MB delimiter-free string; a 40 000-line subscription; 100 000-element JSON array; JSON nested 200 levels (cap is 32) |
| **Corrupted encoding** | invalid base64 (`!@#$`), broken padding, URL-safe alphabet, base64 of raw non-UTF-8 bytes, malformed (`%`, `%zz`), truncated (`%A`) and non-UTF-8 (`%C3%28`) percent escapes, double-encoded and 1000× nested escapes |
| **Byte hazards** | embedded NUL, `\r\n` header injection, every control char `\x01`–`\x1F`, `\x7F`, vertical tab, form feed |
| **Unicode trickery** | RTL/LTR override (`U+202E`/`U+202D`), zero-width space/joiner/non-joiner, word joiner, BOM, lone high and low surrogates, emoji in host *and* password, combining-mark confusables |
| **Malformed URI components** | ports `-1`, `0`, `65536`, `999999`, `abc`, `0x1BB`, `443.5`; empty/unbracketed/empty-bracket IPv6, IPv6 zone IDs; hosts containing space, `/`, `@`, `#`, `?`; missing userinfo; many `@`; all 12 URI-reserved characters raw *and* percent-encoded; misspelled/unsupported schemes |
| **Malformed JSON** | `"port": "443"` (string where int expected), float/negative/null ports, `type` as number or object, missing mandatory fields, truncated JSON, trailing garbage, duplicate keys, `\ud800` escapes, numbers beyond 64-bit, `__proto__` |
| **Deep links** | no params, unknown param, empty value, self-referential recursion, canary in both raw and encoded form |
| **Randomised fuzz** | 5 000 deterministic (seeded) byte-soup inputs, each 1–64 chars over a 60+ symbol alphabet of URI metacharacters, control chars, bidi marks and surrogates, run through **all 15** entry points; plus 500 random JSON nesting depths |

## Bugs found and fixed in this pass

### 1. Unhandled `FormatException` from percent-decoding — 7 public APIs

`Uri.decodeComponent` throws **two** different exception types: `ArgumentError`
for a malformed escape (`%`, `%zz`), and `FormatException` for a *well-formed*
escape that decodes to invalid UTF-8 (`%C3%28`). The package had **seven**
separate private copies of a `_percentDecode` helper, and every one of them
caught only `ArgumentError`.

Result: inputs such as `trojan://%C3%28@host:443` threw an unhandled
`FormatException` out of `parseUri`, `parseTrojanUri`, `parseTuicUri`,
`parseWireguardUri`, `parseAmneziaWgUri` and `parseConfigContent` — a
remote-triggerable crash from a single pasted link.

**Fixed** by adding one total `percentDecodeOrRaw` to the shared
`uri_parsing_support.dart` (catching both types) and deleting all seven
duplicates, so there is now a single implementation that cannot throw.

### 2. Unhandled `FormatException` from `Uri.queryParameters` — 9 call sites

`Uri.queryParameters` internally calls `Uri.decodeQueryComponent`, which throws
`FormatException` on the same class of input. Nine call sites across six
parsers read `value.queryParameters` directly and unguarded, so
`vless://uuid@host:443?host=%C3%28` crashed the parse even after fix #1.

**Fixed** by adding `safeQueryParameters`, which falls back to a lenient manual
decode on `FormatException`, and routing every site through it. There are now
zero raw `Uri.decodeComponent` / `Uri.decodeQueryComponent` calls in the
package outside that one module.

Both are pinned by dedicated regression tests in the fuzz suite, so neither can
silently return.

## Known residual limitations (not fixed, not claimed as fixed)

- **Sub-delimiter confusion is not rejected, only tolerated.** A host or
  password containing raw `@`, `/`, `?` or `#` is accepted and may resolve to a
  different host/port than a human would read off the link. Providers that emit
  unencoded reserved characters exist, so this is currently permissive by
  design; tightening it would be a behaviour change, not a fuzz fix.
- **The canary checks `message` and `code`, not the whole error object.** An
  error's *typed fields* (e.g. `HttpStatusError.statusCode`) are structural and
  safe by construction, but the suite does not reflectively walk every field.
- **Fuzzing is not a proof.** 5 000 seeded iterations plus a curated corpus
  found two real escaping bugs; they are not a formal argument that no third
  input class exists.
- **No differential or mutation testing** was performed, and no fuzzing was run
  under a sanitizer or on a real device.

## Re-running

```bash
cd packages/config_parser && dart test test/fuzz_adversarial_test.dart
```

The random fuzz uses a **fixed seed** (`20260927`) on purpose: a failure
reproduces exactly. Change the seed deliberately when hunting for new bugs, and
never leave it random in CI.
