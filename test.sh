#!/usr/bin/env bash
# One check: a real repo, a real server, a real byte change.
# Passes only if the script says OK when the site matches and MISMATCH when it doesn't.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
PORT="${PORT:-8749}"
SRV=""
trap '[[ -n "$SRV" ]] && kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT
lsof -ti ":$PORT" >/dev/null 2>&1 && { echo "port $PORT is busy — set PORT=xxxx"; exit 1; }

cd "$TMP"
git init -q .
git config user.email t@test; git config user.name test
mkdir -p public
printf 'the new poster\n' > public/hello.txt
git add -A && git commit -qm "ship it"
COMMIT="$(git rev-parse HEAD)"

python3 -m http.server "$PORT" --directory "$TMP/public" >/dev/null 2>&1 &
SRV=$!
for _ in $(seq 20); do curl -sf "http://127.0.0.1:$PORT/hello.txt" >/dev/null && break; sleep 0.2; done

cat > "$TMP/t.conf" <<EOF
SITE_ORIGIN="http://127.0.0.1:$PORT"
DEPLOY_BRANCH="main"
DEPLOY_COMMIT="$COMMIT"
GIT_REPO="$TMP"
PROBES=( "/hello.txt|public/hello.txt|nobody can read the greeting" )
EOF

echo "--- case 1: site matches the commit (expect 0)"
bash "$HERE/whats-live.sh" "$TMP/t.conf" >/dev/null
echo "    ok"

echo "--- case 2: one byte differs (expect 1)"
printf 'the OLD poster\n' > "$TMP/public/hello.txt"
out="$(bash "$HERE/whats-live.sh" "$TMP/t.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT1"* ]] || { echo "FAILED: expected exit 1"; echo "$out"; exit 1; }
[[ "$out" == *"nobody can read the greeting"* ]] || { echo "FAILED: no BREAKS line"; exit 1; }
echo "    ok"

echo "--- case 3: file missing entirely (expect 1)"
rm "$TMP/public/hello.txt"
out="$(bash "$HERE/whats-live.sh" "$TMP/t.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT1"* ]] || { echo "FAILED: expected exit 1"; echo "$out"; exit 1; }
echo "    ok"

echo "--- case 4: site unreachable (expect 2)"
sed 's/127.0.0.1:'"$PORT"'/127.0.0.1:1/' "$TMP/t.conf" > "$TMP/dead.conf"
out="$(bash "$HERE/whats-live.sh" "$TMP/dead.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT2"* ]] || { echo "FAILED: expected exit 2"; echo "$out"; exit 1; }
echo "    ok"

echo "all passed"
