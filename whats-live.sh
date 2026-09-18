#!/usr/bin/env bash
# whats-live — is the site actually serving the commit you think it is?
#
# Read-only. Never deploys, never writes, never needs a token.
#
# Usage:  ./whats-live.sh [path/to/whats-live.conf]
#
# Exit codes:
#   0  live site matches the recorded commit
#   1  MISMATCH — an older or unexpected build is live
#   2  INCONCLUSIVE — could not reach the site, or the config is wrong
set -euo pipefail

CONF="${1:-$(dirname "$0")/whats-live.conf}"
[[ -f "$CONF" ]] || { echo "no config at $CONF — copy whats-live.conf.example"; exit 2; }
# shellcheck disable=SC1090
source "$CONF"

: "${SITE_ORIGIN:?SITE_ORIGIN missing from config}"
: "${DEPLOY_COMMIT:?DEPLOY_COMMIT missing from config}"
GIT_REPO="${GIT_REPO:-.}"
PROBES=("${PROBES[@]:-}")
HEADER_PROBES=("${HEADER_PROBES[@]:-}")

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

for tool in curl shasum git; do
  command -v "$tool" >/dev/null || { red "$tool is required"; exit 2; }
done

CURL=(curl -sS --max-time 20 --retry 2 --retry-delay 2)
GIT=(git -C "$GIT_REPO")

fail=0
inconclusive=0

"${GIT[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  red "$GIT_REPO is not a git repository. Set GIT_REPO in the config."; exit 2; }

if ! "${GIT[@]}" cat-file -e "${DEPLOY_COMMIT}^{commit}" 2>/dev/null; then
  red "commit ${DEPLOY_COMMIT:0:7} is not in this repo."
  red "Your record is wrong, or you are in the wrong checkout. Fetch, or fix DEPLOY_COMMIT."
  exit 2
fi

echo "=========================================="
echo " whats-live"
echo " site:   $SITE_ORIGIN"
echo " record: ${DEPLOY_BRANCH:-?} @ ${DEPLOY_COMMIT:0:7}"
echo "=========================================="

# --- File probes: a file's live bytes vs its bytes in the recorded commit ---
for probe in "${PROBES[@]}"; do
  [[ -n "$probe" ]] || continue
  IFS='|' read -r url_path repo_path breaks <<<"$probe"
  echo "→ $url_path"

  want="$("${GIT[@]}" show "${DEPLOY_COMMIT}:${repo_path}" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  if [[ -z "$want" || "$want" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    red "  CONFIG: ${repo_path} is empty or missing in ${DEPLOY_COMMIT:0:7}. Pick a different probe."
    fail=1
    continue
  fi

  # curl prints %{http_code} once per retry attempt, so keep only the last one.
  code="$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${SITE_ORIGIN}${url_path}" 2>/dev/null || true)"
  code="${code: -3}"
  if [[ -z "$code" || "$code" == "000" ]]; then
    red "  UNREACHABLE — could not contact ${SITE_ORIGIN}"
    inconclusive=1
  elif [[ "$code" != "200" ]]; then
    red "  FAIL: expected HTTP 200, got ${code} — this file is in ${DEPLOY_COMMIT:0:7}, so an older build is live."
    [[ -n "${breaks:-}" ]] && red "  BREAKS: ${breaks}"
    fail=1
  else
    live="$("${CURL[@]}" "${SITE_ORIGIN}${url_path}" | shasum -a 256 | awk '{print $1}')"
    if [[ "$live" == "$want" ]]; then
      green "  OK: matches the copy in ${DEPLOY_COMMIT:0:7}"
    else
      red "  FAIL: served, but the bytes differ from ${DEPLOY_COMMIT:0:7}"
      red "    want ${want}"
      red "    live ${live}"
      [[ -n "${breaks:-}" ]] && red "  BREAKS: ${breaks}"
      fail=1
    fi
  fi
done

# --- Header probes: config that ships with the build but never appears in a file ---
for probe in "${HEADER_PROBES[@]}"; do
  [[ -n "$probe" ]] || continue
  IFS='|' read -r url_path header expected breaks <<<"$probe"
  echo "→ ${header} on ${url_path}"

  got="$("${CURL[@]}" -I "${SITE_ORIGIN}${url_path}" 2>/dev/null | grep -i "^${header}:" | tr -d '\r' || true)"
  if [[ -z "$got" ]]; then
    red "  FAIL: no ${header} header came back — the header config did not ship."
    [[ -n "${breaks:-}" ]] && red "  BREAKS: ${breaks}"
    fail=1
  elif [[ "$got" == *"$expected"* ]]; then
    green "  OK: ${expected}"
  else
    red "  FAIL: expected ${expected}"
    red "    live ${got}"
    [[ -n "${breaks:-}" ]] && red "  BREAKS: ${breaks}"
    fail=1
  fi
done

# --- Advisory: is the checkout you are standing in the one you deployed? ---
head_commit="$("${GIT[@]}" rev-parse HEAD)"
if [[ "$head_commit" != "$DEPLOY_COMMIT" ]]; then
  yellow "  NOTE: HEAD (${head_commit:0:7}) is not the deployed commit. Undeployed work exists here."
fi

echo "=========================================="
if [[ "$fail" -ne 0 ]]; then
  red "MISMATCH: the site is NOT serving ${DEPLOY_COMMIT:0:7}."
  red "Either a deploy did not land, or your record is stale. Do not deploy again until you know which."
  exit 1
fi
if [[ "$inconclusive" -ne 0 ]]; then
  yellow "INCONCLUSIVE: could not reach the site. Network problem, not a deploy problem."
  exit 2
fi
green "OK: ${SITE_ORIGIN} is serving ${DEPLOY_BRANCH:-?} @ ${DEPLOY_COMMIT:0:7} as recorded."
exit 0
