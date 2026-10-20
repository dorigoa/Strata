#!/bin/bash

if [ -d Strata/.git ]; then
    git -C Strata pull --ff-only
else
    git clone https://github.com/Niko1221/Strata.git
fi
cd Strata
#./update.sh
/usr/bin/yes n | STRATA_ALLOWED_HOSTS=ai.exocomet-boga.ts.net ./setup.sh \
    --host 0.0.0.0 --port 8000 \
    --pack /nvme/Strata-data/packs/unsloth-ud-q4_k_xl \
    --native /nvme/Strata-data/models/unsloth-UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
    --export-profile ~/Strata/Strata/data/expert-profile.bin \
    --expert-chache auto --prefill auto --spec 4 --spec-min-p 0.5 \
    --mtp /nvme/Strata-data/mtp/rt \
    --max-context 131072 --context 131072 \
    --parallel 1 \
    --cuda 13  --gpu 1,0 \
    --model UD-Q4_K_XL --family unsloth \
    --kv int8 --kv-resident 32768 \
    --draft-vocab en \
    --vision yes
