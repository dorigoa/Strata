#!/bin/bash

strata launch --model-path ~/Strata/Strata-data/models/unsloth-UD-Q5_K_XL   --context 256k --kv int8 --vision off --parallel 1   --gpu 0,1 --access lan --port 8000 --no-tui --no-api-key  --mtp on --listen 192.168.1.200  --draft-vocab en --drafting mtp  --vision off
