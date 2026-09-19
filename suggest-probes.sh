#!/usr/bin/env bash
# suggest-probes — paste-ready PROBES for a commit whats-live can actually check.
#
# A probe must have changed in that commit, and the server must return those
# exact bytes. Files under public/, static/, or dist/ qualify. Compiled sources
# do not. Usage: ./suggest-probes.sh <commit> [repo-dir]
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: ./suggest-probes.sh <commit> [repo-dir]" >&2
  exit 2
fi

commit="$1"
repo="${2:-.}"

git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "not a git repository: $repo" >&2
  exit 2
}
git -C "$repo" cat-file -e "${commit}^{commit}" 2>/dev/null || {
  echo "not a commit: $commit" >&2
  exit 2
}

# 40 images, 30 fonts, 25 .well-known, 20 txt/json, 10 anything else static.
score_for() {
  local path="$1" base lower score=10
  base="${path##*/}"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.ico|*.avif) score=40 ;;
    *.woff|*.woff2|*.ttf|*.otf|*.eot) score=30 ;;
    *.txt|*.json) score=20 ;;
  esac
  case "$path" in
    .well-known/*|*/.well-known/*)
      if [[ "$score" -lt 25 ]]; then
        score=25
      fi
      ;;
  esac
  case "$lower" in
    favicon.ico|robots.txt|sitemap.xml|manifest.json) score=$((score - 5)) ;;
  esac
  printf '%s' "$score"
}

# 0 = keep. Static tree only; drop sources, docs, tests, dotfiles, lockfiles.
qualifies() {
  local path="$1" lower base part rest
  lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

  case "$path" in
    public/*|static/*|dist/*) ;;
    *) return 1 ;;
  esac

  case "$lower" in
    *.tsx|*.jsx|*.ts|*.scss|*.vue|*.svelte) return 1 ;;
    .github/*|*/.github/*|node_modules/*|*/node_modules/*) return 1 ;;
    test/*|tests/*|*/test/*|*/tests/*|__tests__/*|*/__tests__/*) return 1 ;;
    *.test.*|*.spec.*) return 1 ;;
  esac

  rest="$path"
  while [[ "$rest" == */* ]]; do
    part="${rest%%/*}"
    rest="${rest#*/}"
    if [[ "$part" == .* && "$part" != ".well-known" ]]; then
      return 1
    fi
  done
  if [[ "$rest" == .* && "$rest" != ".well-known" ]]; then
    return 1
  fi

  base="${lower##*/}"
  case "$base" in
    readme|readme.*|license|license.*|licence|licence.*|copying|copying.*) return 1 ;;
    package-lock.json|yarn.lock|pnpm-lock.yaml|npm-shrinkwrap.json|bun.lock|bun.lockb) return 1 ;;
    cargo.lock|composer.lock|gemfile.lock|poetry.lock|*.lock) return 1 ;;
  esac

  case "$path" in
    *'|'*|*'\\'*|*'"'*) return 1 ;;
  esac
  return 0
}

url_for() {
  local path="$1"
  case "$path" in
    public/*) path="${path#public/}" ;;
    static/*) path="${path#static/}" ;;
    dist/*) path="${path#dist/}" ;;
  esac
  printf '/%s' "$path"
}

candidates=()
seen=""
while IFS= read -r -d '' path; do
  [[ -n "$path" ]] || continue
  case "$seen" in
    *"|$path|"*) continue ;;
  esac
  qualifies "$path" || continue
  seen="${seen}|${path}|"
  candidates+=("$(score_for "$path")"$'\t'"$(printf '%05d' "${#path}")"$'\t'"$path")
done < <(git -C "$repo" diff-tree -r --root -m --no-commit-id --name-only --diff-filter=ACMR -z "$commit")

if [[ ${#candidates[@]} -eq 0 ]]; then
  short="$(git -C "$repo" rev-parse --short "$commit")"
  echo "No file changed in ${short} can be probed byte-for-byte."
  echo "Need a static file this commit changed under public/, static/, or dist/."
  echo "Compiled sources (.tsx .jsx .ts .scss .vue .svelte) do not qualify."
  echo "Use HEADER_PROBES instead (see whats-live.conf.example)."
  exit 1
fi

echo "PROBES=("
n=0
TAB=$'\t'
while IFS= read -r path; do
  [[ "$n" -ge 3 ]] && break
  printf '  "%s|%s|TODO"\n' "$(url_for "$path")" "$path"
  n=$((n + 1))
done < <(printf '%s\n' "${candidates[@]}" | sort -t "$TAB" -k1,1nr -k2,2nr -k3,3 | cut -f3-)
echo ")"
