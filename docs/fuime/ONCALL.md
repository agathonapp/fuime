# On-call — how Fuime finds out something is broken

Last updated 2026-09-21.

Fuime is one person operating a payments platform for minors. The assumption
behind everything here is that **nobody is watching a dashboard**, so the
system has to come and find you, and it has to be trustworthy enough that when
it does find you, you believe it.

---

## The one-minute version

| | |
|---|---|
| Console | `/admin/oncall` — what is broken, who is being told, whether the last page landed |
| Roster | a row per person, edited from the console or `rake 'fuime:oncall:add[Name,email]'` |
| Cadence | every 5 minutes (`Fuime::Oncall::SweepJob`) |
| Channels | push (ntfy/Pushover/Slack), SMS, voice call, email |
| Test it | **Send a test page** on the console, or `rake fuime:oncall:test_page` |
| Status from a shell | `rake fuime:oncall:status` |

---

## Why this exists

Three separate alerting paths in this codebase had failed by reaching nobody
while reporting success:

* `AdminMailer` was addressed to a Hack Club Slack credential that was never set
  on Fuime, plus a Hack Club `public_id` that decodes against Fuime's salt to
  somebody else or to nobody.
* `ApplicationMailer.deliver_mail` returns early on an empty recipient list
  without raising, so all of the above was silent.
* `EARMUFFED_USER_IDS` held four Hack Club public_ids which, decoded here,
  silently subtracted real Fuime users from every recipient list.

Those were fixed on 2026-09-16. What remained was structural: **alert routing
lived in an environment variable** (`FUIME_OPS_EMAIL`) that had to be set
identically on two Render services, was set on neither, could not be inspected
from inside the app, and had no connection to who was an admin. An admin could
hold every permission in the console and never learn that a chargeback had
arrived.

And separately: email is not a page. Nothing in the app could wake anybody.

---

## The three observers, and why there must be three

Everything in `app/services/fuime/oncall/` runs **inside** the thing it is
monitoring. That arrangement detects an app that is broken. It can never detect
an app that is *gone* — a dead worker does not run the check that would say the
worker is dead, and the resulting silence is indistinguishable from a quiet,
healthy night.

So there are three independent observers, each covering the others' blind spot:

| Observer | Runs where | Catches | Blind to |
|---|---|---|---|
| The sweep | the Sidekiq worker | app up but broken: Stripe down, queues backing up, deadlines passing | the worker being dead |
| `/healthz` | the web process, polled externally | DB down, Redis down, no worker processes, un-migrated schema | the web process being dead |
| The heartbeat | outbound, from the worker | the worker, Redis, or the whole app being gone | anything that leaves the worker running |

**Two of the three need something outside Render**, and neither exists until you
set it up — see *Setup* below. Without them, a total outage pages nobody.

---

## Severity

Severity is about **consequence**, not about volume, and it decides the channel
rather than the recipient. Escalating a sev-3 by adding more people to it is how
a team learns to mute the tool.

| | Means | Reaches you by | Repeats every | Escalates after |
|---|---|---|---|---|
| **sev1** | money or the law is moving the wrong way, or the product is down for everybody | push + SMS + **a phone call** | 10 min | 15 min |
| **sev2** | one venture or one pipeline is broken, and every hour costs somebody something | push + SMS | 1 hour | 2 hours |
| **sev3** | a queue is growing, a deadline is approaching | tomorrow's digest | 1 day | never |

The test for putting a check at sev1 is whether you would genuinely want to be
woken for it. A sev1 that turns out not to be worth waking for is how the next
real one gets slept through — and worse, it is how the phone-call channel stops
being whitelisted through Do Not Disturb, after which nothing can wake anybody.

**Acknowledging stops the repeat pages** and leaves the incident open. That
contract is what makes acknowledging worth doing: if pages kept arriving after
"I am on it", the only way left to stop them would be to mute the channel, and a
muted channel is what the next incident arrives on.

---

## What is checked

| Check | Raises | Sev | Notes |
|---|---|---|---|
| `database` | slow round-trip, **pending migrations** | 2 / **1** | a failed release command serving traffic against an un-migrated schema |
| `redis` | unreachable or slow | 1 / 2 | Sidekiq's whole queue lives here |
| `workers` | **no worker processes**, queue latency | **1** / 1–2 | see the caveat below |
| `dead_jobs` | anything in Sidekiq's dead set | 2 | threshold is **one** — a dead job is work that will now never happen |
| `stripe` | unreachable, no credential, slow | **1** | under MoR, Stripe *is* money-in |
| `money_in` | no sales when sales were expected | 2 | **disarms itself below 14 sales/week** — see below |
| `webhook_deliveries` | a founder's endpoint failing repeatedly | 3 | their integration, not Fuime's money |
| `obligations` | chargeback and COPPA deadlines | **1** overdue / 2 soon | a dispute nobody answers is lost by default and Fuime pays it |
| `alerting` | empty roster, nobody pageable, SMTP unset, a dead channel | **1** / 2 | the check that watches the watchman |

Plus one that does not live in `Check.all`:

* **`money_in.webhook_gap`**, raised by `Fuime::MissedMorPaymentSweepJob`. This
  is the **strongest money-in check Fuime has.** Every other way of noticing a
  broken checkout is statistical and needs a baseline; this one compares
  Stripe's own record of succeeded PaymentIntents against Fuime's ledger, so
  **one** sale that Stripe took and Fuime never recorded is conclusive on the
  first day at any volume. `posted > 0` does not mean "the safety net worked" —
  it means the primary path is broken and the next sale will be dropped too.

### Two caveats worth knowing before you trust a green board

**`workers` cannot report that the worker is dead** when it runs inside the
worker. That is why it is also in `Check.infrastructure` and served from
`/healthz` by the *web* process, and why the outbound heartbeat exists.

**`money_in` is deliberately disarmed at low volume.** Zero sales in six hours
is the signature of a broken checkout *and* of a quiet afternoon, and right now
it is overwhelmingly the second. Below 14 sales/week it returns nothing and says
so in the log. Do not "fix" this by lowering the threshold to make the check feel
useful — an unarmed silence detector is correct at launch volume, and the day it
arms itself is a good day. `money_in.webhook_gap` covers the gap meanwhile.

---

## Setup

### 1. Put yourself on the roster

```
rake 'fuime:oncall:add[Rushil Chopra,rushil@fuime.com]'
```

This alone fixes the daily digest — `ApplicationMailer.ops_recipients` now reads
the roster, so every operational alert and the 13:00 UTC digest go to you. It
does **not** make you pageable: email is not a page.

### 2. Add a channel that can actually wake you

At `/admin/oncall`, on your row:

* **ntfy** (free). Create a topic with a name nobody would guess, install the
  app, set `push_kind: ntfy` and `push_url: https://ntfy.sh/<topic>`. On iOS,
  turn on Critical Alerts for the app or Do Not Disturb will still swallow it.
  **Without a bearer token in `push_credential` the topic is world-readable**,
  so Fuime reduces those pages to a severity and a link — no venture names, no
  amounts.
* **Pushover** ($5 once). `push_kind: pushover`,
  `push_url: https://api.pushover.net/1/messages.json`,
  `push_credential: <apptoken>:<userkey>`. Sev-1 goes out at emergency priority,
  which re-alerts every 60s for 30 minutes until acknowledged. Closest of the
  four to a real pager.
* **Phone** (`phone_number`, E.164). SMS on a sev-2; an actual call on a sev-1.
  Needs `TWILIO__ACCOUNT_SID`, `TWILIO__AUTH_TOKEN` and `TWILIO__PHONE_NUMBER` —
  a Fuime Twilio account, not Hack Club's (Rule 4). **Set your Fuime number to
  Emergency Bypass on your phone.** A call you can whitelist per-contact is the
  one channel Do Not Disturb cannot eat.

### 3. The external watchdog — the part nothing in this repo can do for you

Create two checks at healthchecks.io (free) or Better Stack:

1. **Heartbeat.** A "cron"-style check expecting a ping every ~5 minutes with
   ~15 minutes of grace. Put its ping URL in `FUIME_HEARTBEAT_URL`
   **on the worker service**. `Fuime::Oncall::SweepJob` pings it after every
   successful sweep, so pings stopping means the worker, Redis, or the whole app
   is gone.
2. **Uptime.** An HTTP check on `https://fuime.com/healthz` every minute. That
   endpoint runs `Check.infrastructure` and answers **503** when any of it is
   sev-1, so it catches a web process that is listening but cannot reach its
   database — which `/up` answers 200 for.

Point both at your phone in that provider's own settings. **This is the only
part of the system that can page you when Fuime itself is down.**

### 4. Fire a test page

**Send a test page** on `/admin/oncall`, or `rake fuime:oncall:test_page`.

This raises a genuine sev-1 through the genuine pager and then resolves it. A
pager is a control you use once a quarter, at the worst possible moment, after
months in which nothing exercised it — and every part of it rots silently. A
push topic gets deleted, a Twilio number lapses, a phone reinstalls the app and
loses its subscription, an SMTP key rotates. None of that produces an error
anywhere until the night it matters.

Press it after any change to the roster, and about monthly otherwise.

> A `delivered` in the console means the **relay accepted** the message, not
> that a phone made a noise. No push service will tell you the phone was
> face-down in another room. The honest end-to-end test is whether you heard it.

---

## Environment variables

| Variable | Service | Without it |
|---|---|---|
| `FUIME_HEARTBEAT_URL` | **worker** | nothing outside the app notices if it dies |
| `FUIME_OPS_EMAIL` | web **and** worker | still works — the roster is the primary source now. Kept as an escape hatch for a mailing list that should not be a responder |
| `TWILIO__ACCOUNT_SID` / `__AUTH_TOKEN` / `__PHONE_NUMBER` | worker | no SMS, no voice call — push and email only |

---

## What this does not do

Named so nobody discovers them at 3am:

* **No on-call schedule or rotation.** Escalation positions are fixed. One
  person does not need a rotation, and a rotation nobody maintains is worse than
  none.
* **No quiet hours beyond severity.** Sev-3 waits for the digest; sev-2 will
  text you at 2am if a chargeback deadline is three days out. If that becomes a
  problem the fix is to reclassify the check, not to add a mute window — a mute
  window applies to the sev-1 you did want.
* **No error-rate or 500 monitoring.** `APPSIGNAL_PUSH_API_KEY` is still the
  thing standing between a 500 and anybody knowing, and remains unset. This
  subsystem watches *conditions*, not *exceptions*, and the two do not overlap
  much.
* **No auto-remediation.** Nothing here restarts, retries or rolls back. A pager
  that acts on its own is a pager whose failures you cannot reason about.
