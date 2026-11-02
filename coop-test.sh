#!/usr/bin/env bash
# Co-op prototype test: rebuild, then boot a solo mission with GE_COOP=1 and a
# virtual second controller. Player 2 is scripted to walk forward. Logs, any
# crash report and screenshots go to coop-test/.
#   ./coop-test.sh            Dam
#   ./coop-test.sh 34         Facility (any -level_NN number)
cd "$(dirname "$0")"
LEVEL=${1:-33}
SECS=${COOP_SECS:-60}
DUMP=${COOP_DUMP:-80-1760:120}
OUT=coop-test

echo "=== Rebuilding ==="
nice -n 10 cmake --build build-pc -j3 > build-pc/coop-build.log 2>&1 || {
  tail -30 build-pc/coop-build.log; echo "=== BUILD FAILED ==="; exit 1; }
echo "build ok"

rm -rf "$OUT" ppm ge007.crash.log; mkdir -p "$OUT"
pkill -x ge007.aarch64 2>/dev/null; sleep 1

# Player 2 walks forward. This port runs the "natural look" control style,
# where the analog stick looks and D-pad/C-up walks, so hold D-pad up by
# re-pulsing it (button tokens last 6 reads; 64 entries max). Later it
# taps fire (Z), which also rejoins after being knocked out.
P2SCRIPT=$( { seq 200 6 398 | sed 's/$/:UP/'; seq 1000 20 1580 | sed 's/$/:Z/'; } | paste -sd';')
# Death rules: knock out player 2, let it rejoin, then knock out both.
KILL=${COOP_KILL-2@700,1@2400,2@2400}

echo "=== Running level $LEVEL with 2 players (up to ${SECS}s) ==="
MESA_GL_VERSION_OVERRIDE=3.3 MESA_GLSL_VERSION_OVERRIDE=330 \
GE_COOP=1 GE_MPVIRT=1 GE_PCDUMP="$DUMP" GE_COOP_KILL="$KILL" \
GE_INPUTSCRIPT_P1="$P2SCRIPT" \
  ./build-pc/ge007.aarch64 -level_$LEVEL > "$OUT/game.log" 2>&1 &
pid=$!

waited=0
while [ $waited -lt "$SECS" ] && kill -0 $pid 2>/dev/null; do
  sleep 1; waited=$((waited + 1))
  grep -q 'kernel heartbeat' "$OUT/game.log" && { echo "freeze detected"; break; }
done
alive=0; kill -0 $pid 2>/dev/null && alive=1
pkill -x ge007.aarch64 2>/dev/null; wait $pid 2>/dev/null; sleep 1

frames=$(ls ppm/*.ppm 2>/dev/null | wc -l)
for f in $(ls ppm/*.ppm 2>/dev/null | sort -V); do
  python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$f" "$OUT/$(basename "${f%.ppm}").png"
done
rm -rf ppm

{
  echo "level=$LEVEL seconds=$waited still_running=$alive screenshots=$frames"
  grep -m1 'GE_COOP' "$OUT/game.log" || echo "GE_COOP line: MISSING (switch not active?)"
  grep -m3 -E 'D416 split|spawns' "$OUT/game.log"
  grep -E 'knocks out|rejoins|all players down' "$OUT/game.log"
  echo "guard speed (ticks per frame, should be about 1): $(grep -E 'guard -?[0-9]+ ticks=' "$OUT/game.log" | sed -n '5,$p' | awk -F'ticks=| frames=' '{t+=$2; f+=$3} END {if (f) printf "%.2f", t/f; else print "n/a"}')"
  echo "guard target switches: $(grep -c 'now targets player' "$OUT/game.log")"
  grep -E 'GE_COOP t=' "$OUT/game.log" | head -2
  grep -E 'GE_COOP t=' "$OUT/game.log" | tail -2
  if [ -f ge007.crash.log ]; then
    cp ge007.crash.log "$OUT/crash.log"
    pc=$(grep -m1 -oE 'PC: .*\[(0x[0-9a-f]+)\]' ge007.crash.log | grep -oE '0x[0-9a-f]+' | tail -1)
    echo "RESULT: CRASH at $(addr2line -e build-pc/ge007.aarch64 -f -C -i "$pc" 2>/dev/null | head -2 | tr '\n' ' ')"
  elif grep -q 'kernel heartbeat' "$OUT/game.log"; then
    echo "RESULT: FROZE"
  elif [ "$frames" -gt 0 ]; then
    echo "RESULT: RAN ($frames screenshots)"
  else
    echo "RESULT: NO FRAMES"
  fi
} | tee "$OUT/result.txt"
echo "=== COOP TEST DONE ==="
