#!/usr/bin/env bash
# Co-op version of pi-level-sweep.sh: rebuild, then boot every solo mission
# with 2 players (GE_COOP=1, virtual second controller) and record
# PASS / STALLED / NO-FRAMES / CRASH per level. Results, logs and one
# screenshot per level go to sweep-coop/ (montage: sweep-coop/all-levels.png).
cd "$(dirname "$0")"

echo "=== Rebuilding ==="
nice -n 10 cmake --build build-pc -j3 > build-pc/coop-build.log 2>&1 || {
  tail -30 build-pc/coop-build.log; echo "=== BUILD FAILED ==="; exit 1; }
echo "build ok"

GE_COOP=1 GE_MPVIRT=1 SWEEP_OUT=sweep-coop ./pi-level-sweep.sh

python3 - <<'PY'
import glob, os
from PIL import Image
fs = sorted(glob.glob('sweep-coop/*.png'))
fs = [f for f in fs if not f.endswith('all-levels.png')]
if fs:
    ims = [Image.open(f) for f in fs]
    w, h = ims[0].size; s = 0.25; tw, th = int(w*s), int(h*s); cols = 5
    m = Image.new('RGB', (tw*cols, th*((len(ims)+cols-1)//cols)))
    for i, im in enumerate(ims):
        m.paste(im.resize((tw, th)), ((i % cols)*tw, (i//cols)*th))
    m.save('sweep-coop/all-levels.png')
PY
echo "=== COOP SWEEP DONE ==="
