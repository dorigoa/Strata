#!/bin/bash
#
#./Strata/.venv/bin/python ./Strata/serve/server.py --engine strata --config ./strata-unsloth-ud-q4_k_xl.json --port 8080 --open
# cd Strata
# /usr/bin/yes n |./setup.sh --cuda 13\
#  --model UD-Q4_K_XL --family unsloth\
#  --vision no \
#  --port 8080 --host 0.0.0.0  \
#  --gpus 1,0 \
#  --data-dir /nvme/Strata-data/ --models-dir /nvme/Strata-data/models/ \
#  --draft-vocab en \
#  --parallel 1 \
#  --context 204800 \
#  --kv int8 \
#  --mtp on \
#  --kv-streaming off \
#  --vram-reserve-mib 1300 \
#  --low-ram off

#!/usr/bin/env bash

set -euo pipefail

VALID_FAMILIES=(unsloth nvfp4)

usage() {
    echo "Usage: $0 <model family> " >&2
    echo "Available families: ${VALID_FAMILIES[*]}" >&2
    exit 1
}

is_valid_provider() {
    local p
    for p in "${VALID_PROVIDERS[@]}"; do
        [[ "$1" == "$p" ]] && return 0
    done
    return 1
}

[[ -n "$1" ]] || usage

is_valid_provider "$1" || { echo "Invalid model: $1" >&2; usage; }

./Strata/.venv/bin/python ./Strata/serve/server.py \
    --engine strata \
    --config ./strata-$1.json \
    --port 8080 --host 0.0.0.0 \
    --open
