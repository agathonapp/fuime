# Dependency triage — the 28 dependabot alerts (2026-08-05)

Written for two audiences: whoever maintains this next, and a school IT
department running a scanner during procurement diligence. The headline number
("28 open alerts, 1 critical") overstates the production exposure by a wide
margin, and this file is the reasoning, so the claim is checkable rather than
taken on faith.

## The one production-runtime vulnerability: fixed

**faraday 1.10.4 → 1.10.6** (Gemfile now pins `~> 1.10, >= 1.10.6`). Faraday is
the HTTP client behind the DocuSeal contract integration — actual serving-path
code. 1.10.5/1.10.6 fix an SSRF via protocol-relative URL host override and an
uncontrolled-recursion DoS in NestedParamsEncoder. Pinned to the patched v1
line deliberately: `bundle update --conservative` wanted to jump to 2.x, which
changes the middleware/adapter API the DocuSeal client was written against,
and a security patch must not smuggle in a breaking upgrade.

## Everything else is the JavaScript build toolchain

The remaining 27 alerts are all npm packages under webpack/postcss — the
pipeline that produces `app/assets/builds/*` at build time. Production serves
those precompiled files; no npm package executes while the app serves a
request. A ReDoS in a glob matcher is a CI/developer-machine concern here, not
a production attack surface. (Dependabot's "runtime" scope label describes the
npm dependency graph, not this app's serving path.)

Fixed anyway where a forced resolution stays within one major version —
verified by running the full `yarn build` and `yarn build:css` afterwards:

| package | resolution | note |
|---|---|---|
| shell-quote | ^1.9.0 | **the critical**, plus its high — same v1 line |
| serialize-javascript | ^7.0.5 | both advisories |
| postcss | ^8.5.23 | same major throughout the tree |
| d3-color | ^3.1.0 | satisfies the `1 - 3` range consumers |

## Deliberately not blanket-forced (still open, build-time only)

`brace-expansion`, `minimatch`, `picomatch`, `svgo`, `cross-spawn`, `ajv` each
have BOTH majors in the tree with consumers written against each. A yarn
resolution is a single blanket version, so forcing one line breaks the other's
consumers (ajv 6→8 and minimatch 3→9 are hard API breaks). Fixing these
properly means upgrading the parents that pin them — webpack plugin chain,
mostly — which is an ordinary maintenance task, not an emergency, for the
reason above. Re-run this triage after any webpack/postcss upgrade; several
will disappear on their own.
