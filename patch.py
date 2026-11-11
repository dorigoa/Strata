#!/usr/bin/env python3
"""Riporta una config Strata SYCL dalla forma Docker a quella nativa.
Da rieseguire dopo ogni ./setup.sh --backend sycl."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BIN = ROOT / "build-sycl" / "sycl" / "strata"          # il binario buildato nativamente


def fix(path: Path) -> None:
    cfg = json.loads(path.read_text(encoding="utf-8-sig"))
    if cfg.get("backend") != "sycl":
        print(f"{path.name}: non e' una config sycl, salto")
        return

    cfg["exe"] = str(BIN)                              # al posto di sycl/serve/strata-sycl.sh (che usa Docker)
    cfg["cwd"] = str(ROOT)
    cfg["gpu"] = 0                                     # una scheda sola: il layer split rifiuta con NO_HOST=1

    args, seen = [], False                             # to_sycl accumula --stream-experts a ogni passaggio
    for a in cfg.get("args", []):
        if a == "--stream-experts":
            if seen:
                continue
            seen = True
        args.append(a)
    cfg["args"] = args

    env = cfg.setdefault("env", {})
    env["STRATA_VERIFY_NO_HOST"] = "1"                 # obbligatorio su xe: senza, i logit vanno a NaN
    for k in ("STRATA_SYCL_BIN", "STRATA_STAGE_TRIM"):
        env.pop(k, None)                               # servono solo al wrapper Docker / al layer split

    path.write_text(json.dumps(cfg, indent=1), encoding="utf-8")
    print(f"{path.name}: exe={cfg['exe']} gpu={cfg['gpu']}")
    print("  args:", " ".join(cfg["args"]))


def main() -> int:
    if not BIN.is_file():
        print(f"errore: binario non trovato: {BIN}", file=sys.stderr)
        return 1
    targets = [Path(a) for a in sys.argv[1:]] or sorted(ROOT.glob("strata-*.json"))
    targets = [p for p in targets if not p.name.endswith(".shared-settings.json")]
    if not targets:
        print("errore: nessuna config strata-*.json trovata", file=sys.stderr)
        return 1
    for p in targets:
        if not p.is_file():
            print(f"errore: {p} non esiste", file=sys.stderr)
            return 1
        fix(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
