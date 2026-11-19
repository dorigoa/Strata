# Strata su 2× Intel Arc Pro B70 — percorso Terminal (nativo, senza Docker)

Stato: 2026-11-19. Engine 0.1.62 `linux-x86_64-sycl`, Terminal 0.2.16 / Control 0.1.62, Ubuntu, Ryzen 9 5950X, 112 GB RAM (109,7 usabili), 2× Arc Pro B70 32 GB, driver `xe`.

## Cosa è cambiato rispetto alla versione precedente di questo doc

La versione precedente descriveva build da sorgente con `icpx`, symlink `/work` e patch della config scritta da `./setup.sh`. **Tutto obsoleto.** Il repo è stato ristrutturato (`terminal/setup.py`, `engine/sycl/`) e il percorso nativo supportato è ora il Terminal, che scarica un pacchetto engine SYCL firmato con dentro le librerie runtime oneAPI.

- `./setup.sh --backend sycl` **è** il percorso Docker: `docs/INTEL_ARC.md` lo elenca sotto "Docker and the GPU driver", e `docs/SOURCE_INSTALL.md:3` classifica tutti gli script `setup.sh`/`update.sh` come roba da sviluppatori ("To just use Strata, install the desktop app or the Terminal"). `README.md` e `docs/INSTALL.md` non lo nominano più.
- `docs/INTEL.md:28` afferma ancora "`./setup.sh --backend sycl` is the one command for the first install": frase scritta prima che esistesse il pacchetto Intel firmato, non allineata. È la pagina a cui puntano i messaggi d'errore di `setup_intel.py`, quindi è una trappola.
- `--backend sycl` (di `setup.py`) e `--backend intel` (di `strata launch`) sono flag di **comandi diversi**. `setup.py` accetta solo `cuda|hip|sycl` (`terminal/setup.py:9966`); `strata launch --backend nvidia|amd|intel|auto` (`terminal/strata_cli/launch/cmd.py:116`) serve solo su un PC con schede di marche diverse. Con sole Intel, `auto` basta.

## 0. Prerequisiti di sistema

Driver `xe` + compute runtime + Level Zero: su Ubuntu `intel-opencl-icd libze1 libze-intel-gpu1`. L'utente deve stare nel gruppo `render`.

```sh
sycl-ls                 # devono uscire due righe [level_zero:gpu] con le B70
strata doctor --live    # controlla driver, gruppo render e schede
```

Se escono solo `opencl:*`, il problema è lo stack user-space, non Strata. Nota: `sycl-ls` qui serve solo come diagnostica; il pacchetto engine porta le proprie librerie oneAPI e **non** richiede `source setvars.sh`.

## 1. Terminal

```sh
curl -fsSL --connect-timeout 15 --max-time 120 \
  https://github.com/Niko1221/Strata/releases/latest/download/install.sh -o install.sh && sh install.sh
strata --version
```

Se `strata` non è nel PATH: `~/.local/bin/strata`.

## 2. Engine

```sh
strata update --check   # deve dire: selected for this PC: 0.1.62 linux-x86_64-sycl
strata update
```

Il feed firmato sceglie il pacchetto da sé e scarta cuda/hip/metal/windows con una riga di motivazione ciascuno. `strata update` fa test-start dell'engine (carica il modello e genera un token) prima di commutare, e tiene la versione precedente: `strata components rollback` torna indietro.

Il pacchetto è SPIR-V: i kernel GPU vengono compilati al **primo avvio**, non c'è AOT. Un crash del compilatore Intel si manifesta quindi all'avvio, non in build (vedi sezione Drafter).

## 3. Modelli — download manuale

Su scheda Intel Strata **non scarica modelli**: `docs/INTEL_ARC.md:27` ("Models are not downloaded for Intel cards yet. Give the folder with `--model-path`"). Non esiste un sottocomando `strata download`. Era `setup.sh` a farlo sui percorsi CUDA/HIP.

GGUF accettati (`terminal/setup.py:3465-3468`): ISTA-DASLab GSQ-RCO (Q2_0, IQ2_XS, IQ3_XXS, IQ3_S; Swift 1.5; Coder IQ1_M) e Unsloth UD-IQ1_M, UD-Q2_0, UD-IQ2_XS, UD-Q2_K_XL, UD-IQ3_XXS, UD-Q3_K_XL, UD-IQ4_XS, UD-Q4_K_XL, UD-Q5_K_XL, UD-Q6_K_XL, Q8_0. Altri K-quant vengono rifiutati; UD-IQ1_S mescola due formati di esperti in un layer e non è caricabile.

Dimensioni Unsloth (`docs/MODELS.md:136-142`):

| Size | Download | Esperti | RAM per tutti gli esperti | Top token = Q8_0 |
| --- | ---: | ---: | ---: | ---: |
| UD-IQ4_XS | 94 GB | 55 GiB | ~72 GB | 88,9% |
| UD-Q4_K_XL | 111 GB | 72 GiB | ~88 GB | 93,1% |
| UD-Q5_K_XL | 158 GB | 92 GiB | ~108 GB | 94,6% |
| UD-Q6_K_XL | 169 GB | 102 GiB | ~118 GB | 94,6% |
| Q8_0 | 188 GB | 120 GiB | ~136 GB | 100% (riferimento) |

Con 109,7 GB di RAM usabile, da Q6 in su gli esperti non stanno tutti in memoria e una parte viene letta dall'SSD a ogni token. Q5 e Q6 hanno la stessa percentuale di top token: Q6 costa 11 GB in più senza guadagno su quella metrica.

Download, fissando la revisione documentata (`docs/UNSLOTH_Q6.md:7`):

```sh
hf download unsloth/Qwen3.8-Flash-Next-GGUF \
  --include "UD-Q6_K_XL/*" \
  --revision 38bb39ee97821de2c9009abb7e93950eec396e66 \
  --local-dir ~/Strata/Strata-data/models
```

Finisce in `~/Strata/Strata-data/models/UD-Q6_K_XL/`. Da lanciare in `tmux`/`screen`; `hf` riprende i download interrotti. Per verificare il nome esatto di una cartella di quantizzazione prima di muovere centinaia di GB:

```sh
python3 -c "from huggingface_hub import list_repo_files; print(sorted({f.split('/')[0] for f in list_repo_files('unsloth/Qwen3.8-Flash-Next-GGUF')}))"
```

Il *pack* (formato interno di Strata) viene costruito dai GGUF al primo avvio, una volta sola, senza scaricare altro.

## 4. Avvio

```sh
strata launch --model-path ~/Strata/Strata-data/models/unsloth-UD-Q5_K_XL \
  --context 256k --kv int8 --vision off --parallel 1 \
  --gpu 0,1 --access lan --port 8000 --listen 192.168.1.200 \
  --no-tui --no-api-key --mtp on --drafting auto \
  --save-preset B70-Q5
```

Poi basta `strata launch --preset B70-Q5`.

- `--plan` mostra cosa farebbe senza cambiare nulla: usarlo sempre al primo giro con un modello nuovo.
- Non esiste `--host`: l'esposizione in rete è `--access local|lan|cloudflare|tailscale` più `--port`.
- `--no-api-key` toglie la chiave: chiunque raggiunga la porta può usare il modello **e i suoi tool**, cioè leggere e scrivere file su questo PC. In LAN non fidata lasciarla attiva.
- Opzioni engine non esposte come flag: `--set CHIAVE=VALORE` (ripetibile).

## 5. Split sulle due schede

È **pipeline parallelism, non tensor parallelism** (`docs/MULTI_GPU.md:101`): un token attraversa da una scheda all'altra una volta per verify window, i tensori non vengono divisi dentro il layer.

Dal log del 2026-11-19 (engine 0.1.62, UD-Q5_K_XL, 256K):

- `layer split auto: K=24` → layer 0-23 su CUDA0, `session [24, 48)` più la testa su CUDA1. La scelta K=24 vs K=23 è a parità di tempo predetto (42,8 ms per finestra di decode) ma lascia più margine alla scheda più stretta.
- `--pipeline-windows 2` attivo di default per due Arc B-series: le schede lavorano su due finestre diverse invece di attendersi. Si spegne con `--pipeline-windows 0` o `STRATA_PIPELINE_AUTO=0`.
- PCIe misurato dall'engine: 14,4 GB/s host→device → `pcie_frac 0.40` (default 0.55).
- Cache esperti: 11.997 coppie profilate su 24.576, ≈97,9% della massa routata, su 46 piazzamenti valutati.
- `STRATA_STAGE_TRIM` attivo di default: ogni scheda carica solo i pesi densi dei propri layer e la VRAM liberata va alla cache esperti.

Le schede vengono numerate due volte e non coincidono: `Main: GPU 2 (--gpu 1)`, `Helper: GPU 1 (--gpu 0)`. Nel comando vale la numerazione `--gpu`.

## 6. Drafter — DFlash2 non va con due schede

`--drafting dflash2` richiede **una scheda e una richiesta per volta**: incompatibile con `--layer-split`, `--batch` e `--pipeline-windows`. L'engine stampa il diagnostico e poi prosegue comunque:

```
strata generate: --draft dflash2 is for one card and one request at a time
                 (not --batch, --pipeline-windows or a layer split) in this build
PLEASE submit a bug report to https://software.intel.com/en-us/support/priority-support
```

Quel secondo messaggio è il banner di crash del compilatore Intel DPC++/IGC, non un errore di Strata: i kernel si compilano al primo avvio e il compilatore muore su quelli del drafter. Su 0.1.59 lo stesso scenario dava `exit code -11` con ripiego automatico su MTP; su 0.1.62 l'avvio termina con exit code 1. **È un bug da segnalare**: una combinazione che l'engine riconosce come non supportata dovrebbe essere rifiutata, non far esplodere il compilatore. Il vincolo è dichiarato "in this build", quindi va ricontrollato a ogni aggiornamento.

Misure precedenti (2026-11-13, engine 0.1.59, UD-IQ4_XS, 262144, KV int8, `--stream-experts`, `--kv-resident 32768`):

| configurazione | t/s | note |
| --- | --- | --- |
| 1 scheda, DFlash2 (`--spec 6 --draft-conf 0.6`) | 14 sostenuti | cache esperti 21,43 GiB = 9384 slot su 16130; il resto via PCIe |
| 2 schede, MTP (`--spec 2 --spec-min-p 0.5`) | picchi 70 | esposta ai reset `ccs`, vedi `b70-engine-reset-sintesi.md` |
| **2 schede, nessun drafter** | **44** | scelta operativa |

Il divario 14 → 44 viene dalla cache degli esperti: con il layer split arriva a ~43 GiB, quindi tutti gli esperti residenti e traffico PCIe quasi nullo. Su una scheda sola ne restano fuori ~6700, letti dalla RAM pinnata.

Caveat: togliere il drafter riduce la frequenza dei guasti, non li esclude. Tenere il watch `sudo dmesg -wT | grep -iE 'xe .*(reset|timedout|fault|CAT)'` per qualche sessione. Non misurato: MTBF a `--spec 2` sotto Strata.

## 7. Errori e cause

Log dell'engine: `~/.local/state/strata/launch/<preset>.engine.log`.

| Messaggio | Causa |
| --- | --- |
| `Strata's SYCL engine cannot be used: it is not built` | stai usando `./setup.sh`, non il Terminal. `strata launch` non stampa mai questo messaggio: esiste solo in `engine/sycl/setup_intel.py:149` |
| `/work/... is outside /home/<user>/Strata` | residuo del vecchio percorso: `setup_intel.py` ritraduce path già tradotti al secondo run |
| `No device of requested type available` | l'engine sta girando dove le schede non si vedono (tipicamente dentro il container). Nativamente `sycl-ls` le mostra |
| `--draft dflash2 is for one card...` + crash IGC | DFlash2 con layer split o pipeline-windows → sezione 6 |
| `cannot pin N MiB, nor place it in VRAM` | conseguenza di "No device", oppure `RLIMIT_MEMLOCK` troppo basso (`ulimit -l`) |

`RLIMIT_MEMLOCK` a 0 lascia la tabella PLE non lockata in RAM: funziona con le pagine faultate e reclaimable, ma l'engine dichiara fino al 6% in meno in decode. `ulimit -l unlimited`, o `LimitMEMLOCK=infinity` in un servizio systemd.

## 8. Residui del vecchio percorso da rimuovere

Nel checkout `~/Strata/Strata` e dintorni, non più usati dal Terminal:

- il symlink `/work` → `~/Strata` (serviva a rendere validi sull'host i path tradotti per il container)
- `build-sycl/` e i symlink `build-sycl/strata`
- `strata-*.json`, `strata-*.json.bak`, `run-*.sh` scritti da `setup.sh`
- `engine-0.1.6x/` scaricati a mano fuori dalla gestione del Terminal

Il Terminal tiene le sue cose altrove: engine in `~/.local/share/strata/components/`, stato e log in `~/.local/state/strata/`, preset in `launch-presets/` accanto alla cartella dei profili.
