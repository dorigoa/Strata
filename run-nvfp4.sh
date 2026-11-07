#!/bin/sh
cd "/home/alvise/Strata/Strata"
export STRATA_ALLOWED_HOSTS=ai.exocomet-boga.ts.net
exec "/home/alvise/Strata/Strata/.venv/bin/python" "/home/alvise/Strata/Strata/serve/server.py" "--engine" "strata" "--config" "strata-nvfp4.json" "--port" "8000" "--host" "192.168.1.200" "--open"
