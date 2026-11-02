#!/usr/bin/env bash
# Linux/arm64 version of tools_pc/level_sweep.sh: boot each of the 21 solo
# levels with -level_XX, dump a few frames, and record PASS / STALLED /
# NO-FRAMES / CRASH. Results, logs and one screenshot per level go to
# sweep-pi/. Do not run it next to a build or another copy of the game.
cd "$(dirname "$0")"

SWEEP_SECS=${SWEEP_SECS:-60}
SWEEP_DUMP=${SWEEP_DUMP:-80-400:40}
STALL_SECS=${STALL_SECS:-20}
OUT=${SWEEP_OUT:-sweep-pi}
LV=${SWEEP_LEVELS:-"Dam:33 Facility:34 Runway:35 Surface1:36 Bunker1:09 Silo:20 Frigate:26 Surface2:43 Bunker2:27 Statue:22 Archives:24 Streets:29 Depot:30 Train:25 Jungle:37 Control:23 Caverns:39 Cradle:41 Aztec:28 Egypt:32 Cuba:54"}

_d=${SWEEP_DUMP%%:*}; _stride=${SWEEP_DUMP##*:}
EXPECT_FRAMES=$(( (${_d##*-} - ${_d%%-*}) / _stride + 1 ))

export MESA_GL_VERSION_OVERRIDE=3.3 MESA_GLSL_VERSION_OVERRIDE=330

rm -rf "$OUT"; mkdir -p "$OUT"
trap 'pkill -x ge007.aarch64 2>/dev/null' EXIT INT TERM

run_level() {
  local name=$1 num=$2
  rm -f ge007.crash.log; rm -rf ppm
  pkill -x ge007.aarch64 2>/dev/null; sleep 1

  GE_PCDUMP="$SWEEP_DUMP" ./build-pc/ge007.aarch64 -level_$num > "$OUT/$name.log" 2>&1 &
  local pid=$!

  local waited=0 fcnt=0 prev=0 stall=0 stalled=0
  while [ $waited -lt "$SWEEP_SECS" ] && kill -0 $pid 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    fcnt=$(ls ppm/*.ppm 2>/dev/null | wc -l)
    [ "$fcnt" -ge "$EXPECT_FRAMES" ] && break
    if [ "$fcnt" -gt 0 ] && [ "$fcnt" -eq "$prev" ]; then
      stall=$((stall + 1))
      [ $stall -ge "$STALL_SECS" ] && { stalled=1; break; }
    else
      stall=0
    fi
    prev=$fcnt
  done
  local alive=0
  kill -0 $pid 2>/dev/null && alive=1
  pkill -x ge007.aarch64 2>/dev/null
  wait $pid 2>/dev/null
  sleep 2

  local last
  last=$(ls ppm/*.ppm 2>/dev/null | sort -V | tail -1)
  [ -n "$last" ] && python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$last" "$OUT/$name.png" 2>/dev/null

  if [ -f ge007.crash.log ]; then
    local pc sym
    pc=$(grep -m1 -oE 'PC: .*\[(0x[0-9a-f]+)\]' ge007.crash.log | grep -oE '0x[0-9a-f]+' | tail -1)
    sym=$(addr2line -e build-pc/ge007.aarch64 -f -C "$pc" 2>/dev/null | head -1)
    cp ge007.crash.log "$OUT/$name.crash.log"
    echo "CRASH @ $sym ($pc)"
    return
  fi
  if [ -n "$last" ]; then
    local pcnt
    pcnt=$(python3 tools_pc/pixcount.py "$last" 2>/dev/null | grep -oE 'non-clear [0-9]+ \([0-9.]+%\)')
    if [ "$stalled" = 1 ] && [ "$alive" = 1 ] && [ "$fcnt" -lt "$EXPECT_FRAMES" ]; then
      echo "STALLED (froze at $fcnt/$EXPECT_FRAMES frames)  $pcnt"
    else
      echo "PASS  $pcnt"
    fi
  else
    echo "NO-FRAMES"
  fi
}

echo "Level sweep started $(date)" | tee "$OUT/results.txt"
for entry in $LV; do
  name=${entry%%:*}; num=${entry##*:}
  echo "--- $name ($num) ..."
  status=$(run_level "$name" "$num")
  case "$status" in
    NO-FRAMES|STALLED*)
      sleep 3
      retry=$(run_level "$name" "$num")
      case "$retry" in
        NO-FRAMES) status="NO-FRAMES (2 attempts)" ;;
        STALLED*)  status="$retry (2 attempts)" ;;
        *)         status="$retry  [passed on retry]" ;;
      esac ;;
  esac
  echo "$name ($num): $status" | tee -a "$OUT/results.txt"
done
rm -rf ppm
echo "SWEEP DONE $(date)" | tee -a "$OUT/results.txt"
