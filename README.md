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

## It tells you one of three things

| | means | do |
|---|---|---|
| `OK` (exit 0) | every probe matched the recorded commit | nothing |
| `MISMATCH` (exit 1) | the site answered, and what it served is not what that commit holds — plus a `BREAKS` line for every probe you wrote one for | find out which deploy didn't land |
| `INCONCLUSIVE` (exit 2) | it could not decide: site unreachable, commit not in your checkout, config wrong or empty, or `curl`/`git` missing | read the line it printed; only the first is a network problem |

Exit 2 matters more than it looks. Without it you roll back a deploy that was
fine, because your wifi dropped. A dropped connection is never reported as a bad
deploy — there is a test for exactly that.

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
compiled sources there is nothing here to probe — deploy a tiny marker file next
time. Your host already knows the commit at build time and will hand it to you:

| host | build env var |
|---|---|
| Cloudflare Pages | `CF_PAGES_COMMIT_SHA` |
| Vercel | `VERCEL_GIT_COMMIT_SHA` |
| Netlify | `COMMIT_REF` |

Write it to a public file during the build — `echo "$CF_PAGES_COMMIT_SHA" >
public/build.txt` — and probe that file. It changes every deploy by definition,
which makes it the one probe that can never go stale.

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

### Header probes are a weaker, different thing

`HEADER_PROBES` check that a live response header contains a string. They never
read the commit, so they cannot tell you which build is live — a year-old header
still passes. Use them as a smoke test for config that ships with a build
(security headers, cache rules, redirects), never as proof of a deploy.

## Test

```sh
bash test.sh
```

Builds a throwaway repo, serves it, breaks it seven different ways, and checks
that the script says the right thing each time — including that an unreachable
site is never called a bad deploy.

## Not yet

- Picking probes for you automatically from the commit diff

## Deliberately not doing

**Asking the host which commit is live.** Cloudflare Pages, Vercel and Netlify all
know, and none of them will tell an anonymous visitor: no response header, no
well-known path, no injected file. Every one requires an API token, which would
cost this tool the thing that makes it easy to try — it needs nothing but `curl`
and `git`.

Beware the things that look like a commit and aren't: Cloudflare's
`{8hex}.pages.dev` and Vercel's 9-character `*.vercel.app` hash are random
deployment ids, `cf-ray` / `x-vercel-id` / `x-nf-request-id` are per-request ids,
and an asset `ETag` is a content hash. None of them move with your git history.
The marker file above is the honest way to get the same answer for free.

## Why it exists

I deployed the wrong thing more than once and found out weeks later. Every check
in here is a mistake that already happened.

MIT.
