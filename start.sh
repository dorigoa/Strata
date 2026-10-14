#!/bin/bash
#
# start.sh — gestore CLI di Strata (basato su tmux, nascosto all'utente)
#
# Uso: ./start.sh {start|stop|restart|status|attach|logs|help}
#

set -u

SESSION="strata"
REPO_URL="https://github.com/Niko1221/Strata.git"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$BASE_DIR/Strata"
LOG_DIR="$BASE_DIR/.strata"
LOG_FILE="$LOG_DIR/strata.log"
EXIT_FILE="$LOG_DIR/last_exit"

mkdir -p "$LOG_DIR"

# ---------- utility ----------

is_running() {
    tmux has-session -t "$SESSION" 2>/dev/null
}

require_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "Errore: tmux non è installato (es. 'sudo apt install tmux')." >&2
        exit 1
    fi
}

update_repo() {
    if [ -d "$APP_DIR/.git" ]; then
        git -C "$APP_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$APP_DIR"
    fi
}

# ---------- comandi ----------

cmd_start() {
    require_tmux
    update_repo || { echo "Errore: aggiornamento del repository fallito." >&2; exit 1; }

    if is_running; then
        echo "Strata è già in esecuzione (pid: $(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null))."
        echo "Usa './start.sh attach' per collegarti o './start.sh restart' per riavviarlo."
        return 0
    fi

    local inner
    inner="cd \"$APP_DIR\" && exec env STRATA_ALLOWED_HOSTS=ai.exocomet-boga.ts.net ./setup.sh --host 0.0.0.0 --port 8000 --parallel 1 --cuda 13 --gpu 1,0 --model UD-Q4_K_XL --family unsloth --resident-budget-gib 80 --kv int8 --context 262144 --draft-vocab en --vision yes"

    tmux new-session -d -s "$SESSION" \
        "bash -c 'yes n | { $inner; }; _code=\$?; echo \"[strata] terminato con exit code \$_code\"; echo \$_code > \"$EXIT_FILE\"; sleep 10' 2>&1 | tee -a '$LOG_FILE'"
    # Nota: il pipe a tee fa terminare la sessione quando setup.sh termina.

    rm -f "$EXIT_FILE"
    echo "Strata avviato in background."
    echo "  Log:      ./start.sh logs"
    echo "  Stato:    ./start.sh status"
    echo "  Terminal: ./start.sh attach"
}

cmd_stop() {
    require_tmux
    if ! is_running; then
        echo "Strata non è in esecuzione."
        return 0
    fi
    # Tentativo di arresto gentile (Ctrl+C), poi kill della sessione.
    tmux send-keys -t "$SESSION" C-c 2>/dev/null
    for _ in {1..10}; do
        is_running || { echo "Strata fermato."; return 0; }
        sleep 1
    done
    tmux kill-session -t "$SESSION" 2>/dev/null
    echo "Strata fermato (arresto forzato)."
}

cmd_restart() {
    cmd_stop
    cmd_start
}

cmd_status() {
    require_tmux
    if is_running; then
        local pid up
        pid="$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)"
        up="$(tmux display-message -p -t "$SESSION" '#{session_created}' 2>/dev/null)"
        echo "Strata: IN ESECUZIONE"
        echo "  PID processo:   ${pid:-n/d}"
        echo "  Avviato il:     ${up:-n/d}"
        echo "  Ultimi log:"
        tail -n 5 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || echo "    (nessun log)"
    else
        if [ -f "$EXIT_FILE" ]; then
            echo "Strata: FERMO (ultimo exit code: $(cat "$EXIT_FILE"))"
        else
            echo "Strata: FERMO"
        fi
        echo "  Avvia con: ./start.sh start"
    fi
}

cmd_attach() {
    require_tmux
    if ! is_running; then
        echo "Strata non è in esecuzione. Avvalo con './start.sh start'." >&2
        exit 1
    fi
    if [ -t 1 ]; then
        exec tmux attach -t "$SESSION"
    else
        echo "Output non interattivo: usa './start.sh logs'." >&2
        exit 1
    fi
}

cmd_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "Nessun log disponibile." >&2
        exit 1
    fi
    exec tail -n "${1:-50}" -f "$LOG_FILE"
}

cmd_help() {
    cat <<EOF
Gestore di Strata

Uso: ./start.sh <comando>

Comandi:
  start     Aggiorna il repo e avvia Strata in background
  stop      Ferma Strata (arresto gentile, poi forzato)
  restart   Ferma e riavvia Strata
  status    Mostra se Strata è in esecuzione e gli ultimi log
  attach    Si collega alla sessione di Strata (Ctrl+b, poi d per staccarsi)
  logs [N]  Mostra i log in tempo reale (ultimi N, default 50)
  help      Mostra questo aiuto
EOF
}

# ---------- dispatch ----------

case "${1:-help}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    status)  cmd_status ;;
    attach)  cmd_attach ;;
    logs)    shift; cmd_logs "${1:-}" ;;
    help|-h|--help) cmd_help ;;
    *) echo "Comando sconosciuto: '$1'" >&2; cmd_help; exit 1 ;;
esac
