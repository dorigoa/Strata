#!/bin/bash
#
#./Strata/.venv/bin/python ./Strata/serve/server.py --engine strata --config ./strata-unsloth-ud-q4_k_xl.json --port 8080 --open
cd Strata
/usr/bin/yes n |./setup.sh --cuda 13\
 --model UD-Q4_K_XL --family unsloth\
 --vision no \
 --port 8080 --host 0.0.0.0  \
 --gpus 1,0 \
 --data-dir /nvme/Strata-data/ --models-dir /nvme/Strata-data/models/ \
 --draft-vocab en \
 --parallel 1 \
 --context 204800 \
 --kv int8 \
 --mtp on \
 --kv-streaming off \
 --vram-reserve-mib 1300 \
 --low-ram off

