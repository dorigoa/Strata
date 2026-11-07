#!/bin/sh
export STRATA_ALLOWED_HOSTS=ai.exocomet-boga.ts.net
#cd "/home/alvise/Strata/Strata"
exec "/home/alvise/Strata/Strata/.venv/bin/python" "/home/alvise/Strata/Strata/serve/server.py" "--engine" "strata" "--config" "/home/alvise/Strata/strata-unsloth-ud-iq4_xs-v31.json" "--port" "8080" "--open" "--host" "192.168.1.200"
