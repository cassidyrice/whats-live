#!/usr/bin/env bash
# One check: a real repo, a real server, a real byte change.
# Passes only if the script says OK when the site matches and MISMATCH when it doesn't.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
PORT="${PORT:-8749}"
SRV=""
trap '[[ -n "$SRV" ]] && kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q .
git config user.email t@test; git config user.name test
mkdir -p public
printf 'the new poster\n' > public/hello.txt
git add -A && git commit -qm "ship it"
COMMIT="$(git rev-parse HEAD)"

python3 -m http.server "$PORT" --directory "$TMP/public" >/dev/null 2>&1 &
SRV=$!
ready=0
for _ in $(seq 20); do
  sleep 0.2
  kill -0 "$SRV" 2>/dev/null || { echo "test server failed to start on port $PORT — it may be busy; set PORT=xxxx"; exit 1; }
  if curl -sf "http://127.0.0.1:$PORT/hello.txt" >/dev/null; then ready=1; break; fi
done
[[ "$ready" -eq 1 ]] || { echo "test server did not become ready on port $PORT — check python3 and set PORT=xxxx if busy"; exit 1; }

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

echo "--- case 5: a header probe on an unreachable site is NOT a bad deploy (expect 2)"
cat > "$TMP/hdr.conf" <<EOF
SITE_ORIGIN="http://127.0.0.1:1"
DEPLOY_COMMIT="$COMMIT"
GIT_REPO="$TMP"
PROBES=( "/hello.txt|public/hello.txt|nobody can read the greeting" )
HEADER_PROBES=( "/|x-frame-options|DENY|clickjacking protection is gone" )
EOF
out="$(bash "$HERE/whats-live.sh" "$TMP/hdr.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT2"* ]] || { echo "FAILED: expected exit 2, a dropped connection is not a mismatch"; echo "$out"; exit 1; }
echo "    ok"

echo "--- case 6: a probe path that is not in the commit (expect 2, not a crash)"
sed 's|public/hello.txt|public/typo.txt|' "$TMP/t.conf" > "$TMP/bad.conf"
out="$(bash "$HERE/whats-live.sh" "$TMP/bad.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT2"* ]] || { echo "FAILED: expected exit 2, got: $out"; exit 1; }
[[ "$out" == *"CONFIG"* ]] || { echo "FAILED: no CONFIG line"; exit 1; }
echo "    ok"

echo "--- case 7: a config with no probes must refuse, not print OK (expect 2)"
printf 'SITE_ORIGIN="http://127.0.0.1:%s"\nDEPLOY_COMMIT="%s"\nGIT_REPO="%s"\n' "$PORT" "$COMMIT" "$TMP" > "$TMP/empty.conf"
out="$(bash "$HERE/whats-live.sh" "$TMP/empty.conf" 2>&1 && echo "EXIT0" || echo "EXIT$?")"
[[ "$out" == *"EXIT2"* ]] || { echo "FAILED: an empty config printed a green light"; echo "$out"; exit 1; }
echo "    ok"

echo "all passed"
