# Strata on Intel Arc (SYCL) — bare-metal install, no container

Target: Ubuntu 26.10 (kernel 7.3.0), 2× Intel Arc Pro B70, Strata engine **0.1.59** prebuilt SYCL package, engine running
directly on the host (the `strata-sycl-dev` Docker image is **not** used).

Layout assumed throughout:

```
~/Strata/
├── Strata/        # the git checkout
├── engine/        # the prebuilt SYCL engine package
└── Strata-data/   # models, packs, mtp
```

`~/Strata` matters: it is what the container flow mounts at `/work`, and `setup.py` refuses anything outside it.
Keeping the layout makes the (temporary) container-style config valid before we convert it.

---

## 1. OS prerequisites

```sh
sudo apt install -y git python3 python3-venv build-essential
# build-essential: setup compiles the CPU image reader (tools/vision -> build-vision) on the host
sudo apt install -y libze1 libze-intel-gpu1 intel-opencl-icd
# libze1       = Level Zero loader
# libze-intel-gpu1 = Level Zero GPU backend (older name: intel-level-zero-gpu) — without it no device is found
# intel-opencl-icd = OpenCL runtime (second SYCL backend)
```

Everything else the engine needs (oneAPI DPC++ runtime, oneMKL, UR adapters) ships inside the package.
Check with `cat ~/Strata/engine/SYSTEM-LIBS.txt` — only base system libs plus `libze_loader.so.1` should be listed.

## 2. Clone the repo

```sh
mkdir -p ~/Strata && cd ~/Strata
git clone git@github.com:Niko1221/Strata.git        # or https://github.com/Niko1221/Strata.git
```

## 3. Download the prebuilt SYCL engine

Release assets are named `strata-engine-<version>-linux-x86_64-sycl.tar.gz`.
Check the actual version on <https://github.com/Niko1221/Strata/releases> first.

```sh
mkdir -p ~/Strata/engine && cd ~/Strata/engine
curl -LO https://github.com/Niko1221/Strata/releases/download/v0.1.59/strata-engine-0.1.59-linux-x86_64-sycl.tar.gz
tar xzf strata-engine-0.1.59-linux-x86_64-sycl.tar.gz
```

The package must end up **flat** in `~/Strata/engine/`: `strata`, `BUILD.json`, `engine-component.json`,
`SYSTEM-LIBS.txt` and the bundled `.so` files. Sanity check:

```sh
ldd ~/Strata/engine/strata | grep -i "not found"   # must print nothing
env -i ~/Strata/engine/strata --version            # must print: strata 0.1.59
```

`env -i` proves the bundled libs resolve through `RUNPATH $ORIGIN` without any environment help.

## 4. Make the engine visible to setup

`sycl/setup_intel.py` only accepts an in-repo build — it looks at `<repo>/build-sycl-aot/strata` and
`<repo>/build-sycl/strata`, nothing else, and there is no env var to override that detection.
A **relative** symlink satisfies it (absolute would break the container flow; relative works both ways):

```sh
cd ~/Strata/Strata
ln -s ../engine build-sycl          # NOT build-sycl-aot: this package is JIT from SPIR-V, not AOT
ls -l build-sycl/strata             # must resolve to ../engine/strata
```

## 5. Run setup

```sh
cd ~/Strata/Strata
./setup.sh --backend sycl --setup --no-start \
  --family unsloth --model UD-IQ4_XS-v31 \
  --kv int8 --context 262144 \ 
  --host 192.168.1.200 --port 8080 \
  --data-dir ~/Strata/Strata-data/ --models-dir ~/Strata/Strata-data/models/
```

Downloads the model (~94 GB), builds the pack and the MTP draft layer, compiles the CPU image reader,
and writes `strata-<model>.json` + `run-<model>.sh`.

The resulting config is written for the **container**: paths appear as `/work/...` (= `~/Strata/...`),
`exe` points at `sycl/serve/strata-sycl.sh`, `backend` is `sycl`. Step 6 converts it.

> **Do not run `setup.sh --setup` again on an existing SYCL config.** The conversion is one-way:
> `write_run_script()` re-reads the config and passes it through `to_sycl()` a second time, which fails with
> `/work/... is outside <mount>`, and `write_setup_config()` leaves the file half-converted
> (`backend: hip`, `exe` pointing at the `engine-sycl/` stub, `/work` paths carried into `user_args`).
> Recovery: `strata-<model>.json.bak` holds the previous good config.
> To change a setup option, move the config aside first so setup rebuilds it from scratch.

## 6. Convert the config to bare metal

Replaces the container wrapper with the engine binary, rewrites `/work/...` to host paths (also in
`user_args`/`args_written`, so a later setup run cannot re-inject them), and moves the runtime defaults that
`strata-sycl.sh` used to export into the config's `env`.

```sh
cd ~/Strata/Strata
cp strata-unsloth-ud-iq4_xs-v31.json strata-unsloth-ud-iq4_xs-v31.json.container

python3 - <<'EOF'
import json, pathlib

p = pathlib.Path("strata-unsloth-ud-iq4_xs-v31.json")
c = json.loads(p.read_text(encoding="utf-8"))

def host(x):
    return "/home/alvise/Strata/" + x[len("/work/"):] if isinstance(x, str) and x.startswith("/work/") else x

for k in ("args", "user_args", "args_written"):
    if isinstance(c.get(k), list):
        c[k] = [host(v) for v in c[k]]

c["exe"] = "/home/alvise/Strata/engine/strata"
c.pop("sycl_root", None)                      # written by to_sycl(), read by nothing but the wrapper

env = c.setdefault("env", {})
env.pop("STRATA_SYCL_BIN", None)              # meaningless without the wrapper
env.update({"STRATA_VERIFY_DEVICE_PLAN": "1",
            "STRATA_VERIFY_NO_HOST": "1",
            "STRATA_STAGER_THREADS": "12",
            "STRATA_CACHE_DIR": "/home/alvise/Strata/.strata-cache"})

p.write_text(json.dumps(c, indent=1), encoding="utf-8")
print(json.dumps({k: c[k] for k in ("exe", "backend", "env")}, indent=1))
EOF
```

Notes:

- `backend` stays `"sycl"`: `sycl/serve/server_intel.py` keys the Intel telemetry and layer-split handling on it.
- `engine_binary()` in `serve/server.py` special-cases only the filename `strata-sycl.sh`; any other `exe` is
  treated as the engine itself, so a direct binary path is fine.
- `ONEAPI_DEVICE_SELECTOR=level_zero:0` picks the first Arc. Use `level_zero:0,1` (plus a layer split) for both.
- The CPU image reader (`vision.exe`) stays at `engine-sycl/strata-vision` — it is a host binary built by setup.

## 7. Start

```sh
cd ~/Strata/Strata
./run-unsloth-ud-iq4_xs-v31.sh
```

First start is slow: experts are read from disk and the SPIR-V kernels are JIT-compiled (this package is the JIT
build, not AOT). Compiled kernels are cached under `STRATA_CACHE_DIR`.

Endpoints:

- OpenAI: `http://<host>:8080/v1`
- Anthropic: `http://<host>:8080/v1/messages`

Engine log: `~/Strata/Strata/strata-<model>.log`.

---

## Troubleshooting seen in practice

| Symptom | Cause | Fix |
|---|---|---|
| `Strata's SYCL engine cannot be used: it is not built` | setup only looks at `build-sycl[-aot]/strata` in the repo | step 4 symlink |
| `No CMAKE_C_COMPILER could be found` | no host toolchain for the image reader | `sudo apt install build-essential` |
| `/work/... is outside <mount>` | `--setup` re-run over an already converted config | restore `.bak`, or move the config aside and re-run setup |
| `exec: docker: cannot execute: Is a directory` | `docker` not installed; lookup fell back to the repo's own `docker/` folder | not needed on this path — step 6 removes the wrapper |
| `pull access denied for strata-sycl-dev` | the dev image is built locally, never pulled | not needed on this path |

Container route instead (if ever needed): `docker build --pull -t strata-sycl-dev sycl/tools` (~13 GB), keep the
config as setup wrote it, and skip step 6.


## DEPRECATED
### Installation
```
cd ~
git clone git@github.com:dorigoa/Strata.git
cd Strata
git clone https://github.com/Niko1221/Strata.git
cd Strata
./setup.sh --no-start # then answer the questions
```
Based on the selected model, a json config file is generated, e.g. `strata-unsloth-ud-q4_k_xl.json`.
```
cp strata-unsloth-ud-q4_k_xl.json ~/Strata/
cd ~/Strata
./Strata/.venv/bin/python ./Strata/serve/server.py --engine strata --config ./strata-unsloth-ud-q4_k_xl.json --port 8080 --open
```

Install the port-forwarding socat service file into systemd config directory:

```
sudo cp strata-socat.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now strata-socat.service
```
The `socat` port forwarder is needed as Strata must bind to local address `127.0.0.1` (otherwise an API key is mandatory).
So, to connect to the Strata's web server on the public IP (`192.168.1.200`) we need a `socat` proxy.
