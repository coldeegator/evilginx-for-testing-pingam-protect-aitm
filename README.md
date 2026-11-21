# Evilginx AITM test harness - PingAM / PingOne Advanced Identity Cloud (ex-ForgeRock)

Validate whether **PingOne Protect's Adversary-in-the-Middle (AiTM) predictor** actually catches
an AiTM proxy sitting in front of your PingAM / Advanced Identity Cloud login tree.

This is a sibling to Ping Identity's own public
[evilginx-for-testing-p1-aitm](https://github.com/pingidentity/evilginx-for-testing-p1-aitm),
which targets a **PingOne (P1)** hosted-login tenant. This repo targets **PingAM / Advanced
Identity Cloud** instead - a different product with a materially different login flow, so this
is not just a find-and-replace of their template. See
["How this differs from Ping's P1 version"](#how-this-differs-from-pings-p1-version) below.

**_As with any pen testing tool, without proper authorization, a penetration tester is considered
to be engaging in unethical hacking. It's illegal to test a website or app for a vulnerability
without the owner's permission._** Only ever point this at a tenant you own or are explicitly
authorized to test, run it locally or on infrastructure you control, and never expose it to the
public internet without real access control in front of it.

## What you need before starting

- A PingAM / Advanced Identity Cloud tenant with a login tree that invokes a
  **Protect/risk-evaluation node** (a `PingOneProtectInitializeCallback` +
  `PingOneProtectEvaluationCallback` pair in the tree's callbacks). Any ordinary login tree
  without that node won't exercise Protect at all.
- Docker (Docker Desktop on Mac/Windows, or plain Docker on Linux).
- A domain to use as the phishing domain. Two options, see
  [Choosing a phishing domain](#choosing-a-phishing-domain):
  - A real domain/subdomain you own, tested entirely locally via `/etc/hosts` - recommended, no
    public exposure, no ongoing cost.
  - A shared, already-running instance someone else stood up for you to try without any setup of
    your own - see [Using a shared instance instead](#using-a-shared-instance-instead-of-running-your-own).

## Quick start (run it yourself, locally)

**1. Preflight - confirm your tree's real request shapes first.** Don't skip this; the defaults
below are filled in from one real tenant and are very likely wrong for yours in some detail. Open
your tree's URL normally in a browser, DevTools open, Network tab, "Preserve log" on, and log in
with a throwaway test account:

- Find the exact `POST` your login makes (likely `.../authenticate` under `/am/json/realms/...`
  somewhere - Identity Cloud nests realms under `root`, e.g.
  `/am/json/realms/root/realms/<realm>/authenticate`, but confirm the exact path for your tenant).
  Look at the request body's `callbacks[].type` and `input[].name` and confirm which `IDTokenN`
  carries the username and which carries the password **on your tree** - don't assume
  IDToken1/IDToken2. A Protect-enabled tree is more likely than most to insert extra callbacks
  (device profiling, a hidden step) before the password field, shifting the numbering.
- Note whether anything in the flow calls `/am/oauth2/access_token` or `/am/oauth2/authorize`. A
  bare tree login (no relying app requesting an OAuth2 code) usually doesn't - if yours doesn't
  either, delete the `auth_tokens` block in the phishlet, it'll never match.
- Note the URL/state you land on right after a successful login.

**2. Set your tenant/journey/phishing-domain values in one place.** Copy the example settings
file and fill in your own values - every field is explained inline and in the
[Configuration reference](#configuration-reference) table below:
```
cp settings.env.example settings.env
$EDITOR settings.env
```

**3. Generate the real config from your settings:**
```
./generate-config.sh
```
This fills in `evilginx/config/config.json` and `evilginx/phishlets/am-phishlet.yaml` from their
`.template` counterparts and prints the exact `/etc/hosts` line, build/run commands, and lure URL
for YOUR settings - copy them straight from its output. Both generated files are gitignored
(`settings.env` is too), so your tenant's details never get committed back to this repo. Re-run
this script any time you change `settings.env` - it always regenerates cleanly from the
templates.

**Worked example output**, using the included `settings.env.example` values
(`phish.iamworld.co.uk`, blank `phish_sub`):
```
$ ./generate-config.sh
Generated evilginx/config/config.json and evilginx/phishlets/am-phishlet.yaml.

Next steps, using your settings:

  sudo -- sh -c -e "echo '127.0.0.1 phish.iamworld.co.uk' >> /etc/hosts"

  cd evilginx && docker build -f Dockerfile -t aitm-am-demo:edge .
  tail -f /dev/null | docker run --rm -i -p 443:443 aitm-am-demo:edge

  https://phish.iamworld.co.uk/YStcNrSR
```
Run the `/etc/hosts` line it gives you (real domain, local-only override - see
[Choosing a phishing domain](#choosing-a-phishing-domain) for why it should be a real domain, not
`.local`). Remove it again when you're done:
```
sudo sed -i '' '/phish.iamworld.co.uk/d' /etc/hosts
```

**4. Build and run** exactly as printed above. If running interactively (`-it`) exits immediately
after printing the phishlet table, Evilginx's own CLI is reading EOF from stdin and quitting -
that's why the printed command pipes `tail -f /dev/null` into it to keep stdin open. Developer
mode is already set in `docker-entrypoint.sh` via `-developer -debug` (self-signed certs, verbose
logging) - keep those flags for local/dev-mode runs.

**5. Browse to the lure URL** `generate-config.sh` printed (accept the self-signed cert warning -
expected in dev mode; on Chrome, click the warning page body and type `thisisunsafe`, or use
Advanced -> Proceed). This should redirect you straight into your tree (the `login.path` query
string trick explained below makes the lure redirect carry your full tree URL, not just a bare
path). Log in with a throwaway test account - **a tree built specifically for a Protect demo may
be intentionally tuned to flag things, so don't use an account you rely on elsewhere.**

**6. Check the result.** Evilginx's `-debug` log (stdout) will show the full `/authenticate` POST
bodies, including captured `NameCallback`/`PasswordCallback` values and the
`PingOneProtectEvaluationCallback`'s `IDToken1signals` token once a login completes. Check
Protect's own evaluation result on the tenant side (console or API) for the
`adversaryInTheMiddle` predictor result.

**7. Clean up:** stop the container, remove the `/etc/hosts` line, and consider whether you want
to clear any risk history Protect recorded for the test account on your tenant.

## Configuration reference

Everything below is set **once**, in `settings.env` - `generate-config.sh` fans each value out to
every place it's needed in `evilginx/config/config.json` and `evilginx/phishlets/am-phishlet.yaml`
(generated from their `.template` counterparts, which still show the raw `<placeholder>` names if
you want to see exactly where each value lands).

| `settings.env` variable | What it is | Example |
|---|---|---|
| `TARGET_SUB` | The subdomain of your REAL tenant | `openam-mycompany` |
| `TARGET_DOMAIN` | The base domain of your REAL tenant | `forgeblocks.com` |
| `REALM` | The AM realm your tree lives in | `alpha` |
| `TREE_NAME` | The named tree (`authIndexValue`) that has the Protect node | `Demo-Protect-Latest` |
| `PHISHING_DOMAIN` | The domain Evilginx serves the phished page on | `phish.example.com` |
| `PHISH_SUB` | Subdomain prefix on the PHISHING side (not your real tenant's) - see below | `login` or empty |

**`PHISH_SUB` (blank vs a value):** Evilginx builds the browser-facing hostname as
`PHISH_SUB + "." + PHISHING_DOMAIN`, or just `PHISHING_DOMAIN` alone if `PHISH_SUB` is left
blank. Use blank if you want the phished page to appear on the bare domain itself (e.g.
`phish.example.com` with nothing in front); use a real prefix if you want it to look like a
subdomain, the same way your real tenant has one. Either works - this only affects what shows in
the browser's address bar, not whether the proxy functions.

**Where each value lands, if you want to check `generate-config.sh`'s output by hand:**
- `config.json`: `general.domain` = `PHISHING_DOMAIN`; `general.unauth_url` and
  `phishlets.am-phishlet.hostname` as shown in the file.
- `am-phishlet.yaml`: `redirect_url`, `proxy_hosts[0]`, `auth_tokens[0].domain`, `login.domain`,
  `login.path`.

## Preflight checklist (don't skip this)

AM's REST auth API drives a dynamic `callbacks` array per tree - there is no universal
"username is always field X" rule. Confirm, via a real DevTools trace against your own tenant,
before trusting any capture from this tool:

1. The real path of the `authenticate` POST (realm nesting varies by tenant config).
2. Which `IDTokenN` is the username and which is the password **for your specific tree** - a
   Protect-enabled tree is more likely than most to insert extra callbacks first.
3. Whether `/am/oauth2/*` is ever called at all (delete `auth_tokens` if not).
4. What you land on after a successful login (used to shape `login.path`, though Evilginx
   captures the session cookie regardless of whether this field ever matches).

## How this differs from Ping's P1 version

Ping's original phishlet targets PingOne's hosted login, which POSTs clean JSON
(`{"identifier": "...", "password": "..."}`) to a fixed endpoint. PingAM's REST API is a
`callbacks` array whose shape depends on the tree, and its XUI frontend touches several
subsystems (`/am/json/...`, `/openidm/...`, bundled config) that Ping's simpler template never
had to deal with. Three bugs below were only discoverable by building and testing against a real
AM tenant, and are fixed in this repo so you don't have to rediscover them:

### 1. The `/s/<id>` path collision (fixed by renaming Evilginx's reserved prefix)

Evilginx reserves the path shape `/s/<anything-with-no-further-slash>` internally, for its own
session-redirect / js_inject mechanism (`core/http_proxy.go`, `redir_re` /
`js_inject_re`). PingAM's own Signals SDK bootstrap script happens to live at exactly
`/s/<hash>[.js]` on a real tenant - a genuine path-namespace collision. Evilginx intercepts those
requests for itself (treating the SDK's own asset hash as if it were an Evilginx session ID)
instead of proxying them to the real backend, so the SDK's own init request hangs until timeout
and never completes - which means Protect never gets a real signals payload to evaluate at all.

**Fix applied:** the Dockerfile patches Evilginx's source at build time (`sed`, see
`evilginx/Dockerfile`) to rename its reserved prefix from `/s/` to `/__eg3k9f__/` in all five
places it's matched or constructed (`core/http_proxy.go` x4, `core/scripts.go` x1). Confirmed
before/after with a direct timed test: the real asset path hung 30s with zero response before the
fix, and returned in 0.16s after it.

If your tenant's Signals SDK (or any other asset you depend on) lives under a path shaped like
`/<two-chars>/<hash>` with no further segments, check for the same kind of collision before
assuming everything "just works."

### 2. The lure drops its own query string

Evilginx's lure-to-login redirect (`Phishlet.GetLoginUrl()`, `core/phishlet.go`) is built as
plain string concatenation - `"https://" + login.domain + login.path` - with no query-string
field anywhere in the YAML schema. If your tree needs a query string to reach the right flow
(e.g. `?realm=...&authIndexType=service&authIndexValue=...` for a *named* tree, as opposed to the
default), it has to be baked directly into `login.path` in the phishlet, because there's nowhere
else to put it. This repo's `am-phishlet.yaml` already does this - adapt the path string in
`login.path` if your own tree needs a different query string, or leave it off if your tenant
needs no query string to reach the tree you're testing.

### 3. The IP whitelist is per-process, wiped on every restart

Evilginx only creates a tracked session (which is required for credential/signals capture to
happen at all) when a request matches a configured **lure path**. Once that happens, your IP is
whitelisted in memory for that phishlet, and *subsequent* requests to any other path on the same
phishing domain are allowed through without re-matching the lure. This means:
- You must hit the lure path (`/YStcNrSR` in `config.json`) **at least once** before navigating
  directly to any other URL on the phishing domain - a fresh container has no whitelist yet, and
  a direct hit to anything else gets silently bounced to `unauth_url` (the real site), which can
  look like the proxy is "redirecting to the real site" for no reason.
- Every container restart wipes this whitelist (it's in-memory, not persisted), so you need to
  re-hit the lure after every restart, even if you didn't before.

## Verifying it actually captured something

With `-debug` on, Evilginx's stdout log shows full POST bodies. A successful capture through a
Protect-enabled tree looks like this sequence (values will differ):
```
PingOneProtectInitializeCallback | in:[IDToken1clientError=]
NameCallback     | in:[IDToken1=<username>]
PasswordCallback | in:[IDToken2=<password>]
PingOneProtectEvaluationCallback | in:[IDToken1signals=<short opaque token>, IDToken1clientError=]
```
The `IDToken1signals` value is a short correlation token (tens of characters), **not** the real
telemetry payload - the actual device/behavioral data goes out via a separate, unproxied beacon
request straight from the browser to `apps.pingone.com/signals/sdk/pong.css?body=...` (disguised
as a CSS fetch so it survives ad-blockers). That beacon returning `200` is what tells you the SDK
genuinely ran and reported data, independent of anything Evilginx captured.

### Expected noise, not a sign anything is broken

`WARN: Cannot handshake client <target>: remote error: tls: unknown certificate`, repeating every
10-40s even with no user action, comes from a separate/vestigial internal mechanism inside
Evilginx's vendored `goproxy` library (its generic forward-proxy CONNECT-MITM path, reused
awkwardly for Evilginx's own SNI-routing architecture) - confirmed by reading the vendored source.
It is not related to the real backend, your tenant's certificate, or anything blocking actual
proxying, which runs through a separate, working code path.

## Choosing a phishing domain

A `.local` (or any non-public) TLD is NOT a good choice if you actually want to see Protect's
AiTM predictor return a real classification. During development, using `aitm-test.local`
consistently produced `status=URL_NOT_FOUND` from Protect - most likely because whatever
domain-reputation/registration lookup backs that predictor has nothing to match against a
non-public TLD, so it silently falls back rather than detecting anything. Switching to a real,
publicly-registered domain (even a `127.0.0.1`-only `/etc/hosts` override of one you don't need
to be reachable - confirmed working with one real registered domain during development) produced
a proper `status=UNKNOWN_DOMAIN` - a genuine AiTM detection, with the expected
`"Unusual domain ... If this is a known domain it should be added to the predictor's allow List"`
reasoning. **Use a real, registered domain**, even if the specific hostname you add to
`/etc/hosts` has never existed as a subdomain anywhere (an apex domain you control, or a
`phish_sub` you make up under it, both work - what seems to matter is the base registrable domain
being real, not the exact label in front of it).

Only point `/etc/hosts` at a domain you own, or at `127.0.0.1` only (never change real DNS, never
make this reachable from the actual internet unless it's on infrastructure you control with
proper access restrictions in front of it - see below).

## Using a shared instance instead of running your own

If someone on your team has already stood up a running instance of this against their own
sandbox tenant (not yours), you can try the demo against theirs without any local setup - ask
them for the URL. Note that in that case you are testing against **their** tenant and **their**
test account, not your own, which is fine for seeing the demo work but doesn't tell you anything
about your own tenant's Protect configuration.

`phish.iamworld.co.uk` is intended to become one such shared instance against the repo author's
own sandbox tenant, for anyone who wants to see the demo without setting anything up locally -
ask the author whether it's live and for the lure URL/test account to use.

If you want to stand up a shared instance yourself for others: **Lambda will not work** -
Evilginx is a long-running TCP/TLS listener with in-memory session state across a multi-step
login, none of which fits Lambda's request/response, stateless, cold-starting model. A
long-running container platform (ECS Fargate, or plain EC2) is the right fit - same image, just
run continuously instead of locally. If you do this:
- Use a **Network Load Balancer in TCP passthrough mode**, not an ALB - Evilginx needs the raw
  TLS bytes itself (it does its own SNI-based routing and cert generation); an ALB would
  terminate TLS and break that entirely.
- Point real DNS at the NLB, and switch to production mode (remove `-developer -debug` from
  `docker-entrypoint.sh`, let `autocert: "on"` do real Let's Encrypt issuance - this needs real
  inbound reachability for HTTP-01/TLS-ALPN-01 validation).
- **Restrict who can reach it.** This is a live, working credential/AiTM-capture tool with no
  login of its own in front of it. Put it behind your corporate VPN or restrict the NLB's
  security group to known ranges - don't leave it open to the whole internet even for an
  internal demo, and tear it down or disable the lure when it's not actively being used for a
  demo.

## Disclaimer

Carried over from Ping's original, and it applies here too: Evilginx can be used for very
nefarious purposes and should be used only in legitimate testing against systems you own or are
explicitly authorized to test. Run it locally, or on infrastructure you control with real access
restrictions in front of it - never leave an instance of this reachable by the open internet
without them.
