#!/bin/bash

if [ -d Strata/.git ]; then
    git -C Strata pull --ff-only
else
    git clone https://github.com/Niko1221/Strata.git
fi
cd Strata
#./update.sh
/usr/bin/yes n | STRATA_ALLOWED_HOSTS=ai.exocomet-boga.ts.net ./setup.sh --host 0.0.0.0 --port 8000 --gpu 1 --model UD-Q4_K_XL --family unsloth --resident-budget-gib 80 --kv int8 --context 262144 --draft-vocab en --vision yes
