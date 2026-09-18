# whats-live

**Is your site actually serving the commit you think it is?**

Your host's dashboard labels every deploy `main`. It cannot tell you which snapshot
is live. So this goes and looks: it fetches a few files from the real site and
compares their bytes to the same files in the commit you recorded.

No account, no token, no agent. One bash script, read-only. It never deploys.

```
$ ./whats-live.sh
==========================================
 whats-live
 site:   https://example.com
 record: main @ 999dfe6
==========================================
→ /og/home.png
  OK: matches the copy in 999dfe6
→ /pricing
  FAIL: expected HTTP 200, got 404 — this file is in 999dfe6, so an older build is live.
  BREAKS: Customers see last month's prices
==========================================
MISMATCH: the site is NOT serving 999dfe6.
```

## It tells you one of four things

| | means | do |
|---|---|---|
| `OK` (exit 0) | the recorded commit is live | nothing |
| `MISMATCH` (exit 1) | an older or unexpected build is live, **and what that costs you** | find out which deploy didn't land |
| `INCONCLUSIVE` (exit 2) | couldn't reach the site | check your network — this is not a deploy problem |
| `commit not in this repo` (exit 2) | your record is stale or you're in the wrong checkout | fix the config |

The third one matters more than it looks. Without it you roll back a deploy that
was fine, because your wifi dropped.

## Install

```sh
git clone https://github.com/cassidyrice/whats-live.git
cd whats-live
cp whats-live.conf.example whats-live.conf   # then edit it
./whats-live.sh
```

Needs `bash`, `curl`, `shasum`, `git`. Run it from anywhere; point `GIT_REPO` at
the checkout that holds the commit.

## Picking probes — the part that matters

A probe is a file that **changed in the commit you deployed**. That's the whole
trick: a file that has been identical for a year proves nothing, because it
matches whether or not your deploy landed.

```sh
git show --stat --name-only <commit>   # candidates
```

**A probe has to be a file your server returns byte-for-byte.** Static assets —
anything under `public/`, `static/`, or your build output — work. Source files
that get compiled on the way out (a `.tsx` page, a `.scss` file) do not: the repo
bytes and the served bytes were never meant to match. If a commit only touched
compiled sources, use `HEADER_PROBES`, or deploy a tiny marker file next time.

Two or three is plenty. Good ones: an image or asset added in that commit, a page
whose text changed, a `.well-known` file. Each probe carries a plain sentence
saying what a real person loses when it fails:

```
PROBES=(
  "/og/home.png|public/og/home.png|Shared links show the old preview image"
)
```

That sentence is the point. `file mismatch on /og/home.png` makes you squint.
*Shared links show the old preview image* makes you act.

For things that ship with a build but never appear as a file — security headers,
cache rules, redirects — use `HEADER_PROBES`.

## Test

```sh
bash test.sh
```

Builds a throwaway repo, serves it, changes one byte, and checks that the script
says the right thing four times. If that passes, it works.

## Not yet

- Picking probes for you automatically from the commit diff
- Reading the live version from a host's API (Cloudflare, Vercel, Netlify)

## Why it exists

I deployed the wrong thing more than once and found out weeks later. Every check
in here is a mistake that already happened.

MIT.
