#!/bin/bash

/home/alvise/.local/bin/strata launch --model-path ~/Strata/Strata-data/models/unsloth-UD-Q8_K_XL   --context 256k --kv int8 --vision off --parallel 1   --gpu 1,2 --access lan --port 8000 --no-tui --no-api-key  --mtp on --listen 192.168.1.200  --draft-vocab en --drafting mtp  --vision off  --set STRATA_PIPELINE_AUTO=0
