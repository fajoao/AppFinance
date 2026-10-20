#!/bin/bash
# Inicia o painel de agentes em http://127.0.0.1:8765 (somente local) e abre no navegador.
cd "$(dirname "$0")"
if curl -fs http://127.0.0.1:8765/api/docker >/dev/null 2>&1; then echo "Painel já está rodando."; else
  nohup node server.js > /tmp/agent-monitor.log 2>&1 &
  sleep 1
fi
open http://127.0.0.1:8765
