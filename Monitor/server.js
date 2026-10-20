// Painel local de acompanhamento dos agentes (sem dependências). Uso: node Monitor/server.js
// Lê as transcrições dos subagentes em ~/.claude/projects/<projeto>/<sessão>/subagents/*.jsonl,
// de forma incremental, e serve um resumo em http://127.0.0.1:8765 (somente local).
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

const PORT = Number(process.env.PORT || 8765);
const HOST = '127.0.0.1';
const PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR ||
  path.join(os.homedir(), '.claude', 'projects', '-Users-macbookpro-Documents-App-Finance');
const MAX_EVENTS = 300;
const INDEX = path.join(__dirname, 'index.html');

// ---------- redação: nunca devolva segredos que apareçam em comandos ou saídas ----------
const REDACT = [
  /((?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY|JWT_SECRET)[A-Z_]*\s*[=:]\s*)("[^"]*"|'[^']*'|\S+)/gi,
  /(Authorization:\s*Bearer\s+)\S+/gi,
  /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}/g,
  /\bsk-[A-Za-z0-9_-]{16,}/g,
];
function redact(s) {
  if (typeof s !== 'string') return '';
  let out = s;
  out = out.replace(REDACT[0], '$1***');
  out = out.replace(REDACT[1], '$1***');
  out = out.replace(REDACT[2], '[jwt]');
  out = out.replace(REDACT[3], '[chave]');
  return out;
}
const clip = (s, n) => {
  s = redact(String(s ?? '')).replace(/\s+/g, ' ').trim();
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
};

// ---------- estado por agente ----------
const agents = new Map(); // id -> state

function newState(id, file) {
  return {
    id, file, offset: 0, tail: '', mtimeMs: 0,
    description: id, agentType: '', startedAt: null, lastTs: null,
    toolCalls: 0, errors: 0, tools: {}, files: new Set(),
    pending: new Map(), events: [], lastText: '', lastKind: null,
    badges: {}, finalText: '', handedBack: false,
    usage: new Map(), tokenLog: [],
  };
}

function loadMeta(st) {
  try {
    const meta = JSON.parse(fs.readFileSync(st.file.replace(/\.jsonl$/, '.meta.json'), 'utf8'));
    st.description = meta.description || st.id;
    st.agentType = meta.agentType || '';
  } catch { /* meta ainda não existe */ }
}

function pushEvent(st, ev) {
  st.events.push(ev);
  if (st.events.length > MAX_EVENTS) st.events.shift();
}

function describeTool(name, input) {
  input = input || {};
  switch (name) {
    case 'Bash': return { title: 'Terminal', detail: clip(input.description || input.command, 220) };
    case 'Read': return { title: 'Lendo', detail: clip(input.file_path, 200) };
    case 'Write': return { title: 'Criando', detail: clip(input.file_path, 200) };
    case 'Edit': return { title: 'Editando', detail: clip(input.file_path, 200) };
    case 'Grep': return { title: 'Buscando', detail: clip(input.pattern, 160) };
    case 'Glob': return { title: 'Procurando arquivos', detail: clip(input.pattern, 160) };
    case 'Skill': return { title: 'Skill', detail: clip(input.skill, 120) };
    default: return { title: name, detail: clip(JSON.stringify(input), 160) };
  }
}

// Extrai sinais objetivos das saídas (testes, builds) sem guardar a saída inteira.
function scanResult(st, text, ts) {
  const set = (k, v, ok) => { st.badges[k] = { text: v, ok, ts }; };
  let m;
  if ((m = text.match(/Resultado:\s*(\d+) passaram,\s*(\d+) falharam/g))) {
    const last = m[m.length - 1].match(/(\d+) passaram,\s*(\d+) falharam/);
    set('Testes (swiftc)', `${last[1]} ok / ${last[2]} falhas`, last[2] === '0');
  }
  if (/\*\* BUILD SUCCEEDED \*\*/.test(text)) set('Build Xcode', 'sucesso', true);
  else if (/\*\* BUILD FAILED \*\*/.test(text)) set('Build Xcode', 'falhou', false);
  if (/\*\* TEST SUCCEEDED \*\*/.test(text)) set('Testes Xcode', 'sucesso', true);
  else if (/\*\* TEST FAILED \*\*/.test(text)) set('Testes Xcode', 'falhou', false);
  if ((m = text.match(/Executed (\d+) tests?, with (\d+) failures?/))) {
    set('XCTest', `${m[1]} testes / ${m[2]} falhas`, m[2] === '0');
  }
  if ((m = text.match(/Tests\s+(\d+) passed(?:\s*\|\s*(\d+) failed)?/i))) {
    set('Vitest/Node', `${m[1]} ok / ${m[2] || 0} falhas`, !m[2] || m[2] === '0');
  }
  if ((m = text.match(/#\s*pass\s+(\d+)[\s\S]{0,40}#\s*fail\s+(\d+)/))) {
    set('node:test', `${m[1]} ok / ${m[2]} falhas`, m[2] === '0');
  }
  if (/trycloudflare\.com/.test(text)) set('Túnel', 'URL pública gerada', true);
}

// Uso de tokens: o mesmo message.id aparece em vários registros (um por bloco) e o
// output_tokens cresce durante o streaming, então guardamos o MÁXIMO por mensagem.
function trackUsage(st, m, ts) {
  const u = m.usage;
  const cur = st.usage.get(m.id) || { i: 0, cc: 0, cr: 0, o: 0 };
  const next = {
    i: Math.max(cur.i, u.input_tokens || 0),
    cc: Math.max(cur.cc, u.cache_creation_input_tokens || 0),
    cr: Math.max(cur.cr, u.cache_read_input_tokens || 0),
    o: Math.max(cur.o, u.output_tokens || 0),
  };
  const delta = (next.i + next.cc + next.o) - (cur.i + cur.cc + cur.o);
  st.usage.set(m.id, next);
  if (delta > 0) {
    st.tokenLog.push({ t: Date.parse(ts) || Date.now(), d: delta });
    if (st.tokenLog.length > 5000) st.tokenLog.splice(0, 1000);
  }
}
function usageTotals(st, now) {
  const t = { input: 0, cacheWrite: 0, cacheRead: 0, output: 0, calls: st.usage.size, last5min: 0 };
  for (const v of st.usage.values()) { t.input += v.i; t.cacheWrite += v.cc; t.cacheRead += v.cr; t.output += v.o; }
  t.fresh = t.input + t.cacheWrite + t.output; // tokens novos processados/gerados
  const cut = now - 5 * 60 * 1000;
  for (const e of st.tokenLog) if (e.t >= cut) t.last5min += e.d;
  return t;
}

function handleRecord(st, o) {
  if (o.timestamp) {
    st.lastTs = o.timestamp;
    if (!st.startedAt) st.startedAt = o.timestamp;
  }
  const ts = o.timestamp || st.lastTs;
  if (o.type === 'assistant' && o.message && o.message.id && o.message.usage) trackUsage(st, o.message, ts);
  if (o.type === 'assistant' && o.message && Array.isArray(o.message.content)) {
    for (const b of o.message.content) {
      if (b.type === 'tool_use') {
        st.toolCalls++;
        st.handedBack = b.name === 'SubagentHandback';
        if (st.handedBack && b.input) st.finalText = String(b.input.report || b.input.message || b.input.text || st.finalText);
        st.tools[b.name] = (st.tools[b.name] || 0) + 1;
        const d = describeTool(b.name, b.input);
        if ((b.name === 'Write' || b.name === 'Edit') && b.input && b.input.file_path) st.files.add(b.input.file_path);
        st.pending.set(b.id, { name: b.name, title: d.title, detail: d.detail, ts });
        pushEvent(st, { ts, kind: 'tool', id: b.id, title: d.title, detail: d.detail, done: false });
        st.lastKind = 'tool';
      } else if (b.type === 'text' && b.text && b.text.trim()) {
        st.handedBack = false;
        st.lastText = clip(b.text, 400);
        st.finalText = b.text;
        pushEvent(st, { ts, kind: 'text', title: 'Agente', detail: clip(b.text, 400) });
        st.lastKind = 'text';
      }
    }
  } else if (o.type === 'user' && o.message && typeof o.message.content === 'string') {
    st.handedBack = false; // nova instrução (agente retomado)
  } else if (o.type === 'user' && o.message && Array.isArray(o.message.content)) {
    for (const b of o.message.content) {
      if (b.type !== 'tool_result') continue;
      const p = st.pending.get(b.tool_use_id);
      st.pending.delete(b.tool_use_id);
      const text = Array.isArray(b.content)
        ? b.content.map((c) => c.text || '').join('\n')
        : String(b.content || '');
      if (b.is_error) st.errors++;
      scanResult(st, text, ts);
      for (let i = st.events.length - 1; i >= 0; i--) {
        if (st.events[i].id === b.tool_use_id) {
          st.events[i].done = true;
          st.events[i].error = !!b.is_error;
          st.events[i].ms = p && p.ts ? Date.parse(ts) - Date.parse(p.ts) : null;
          break;
        }
      }
      st.lastKind = 'result';
    }
  }
}

function refreshFile(file) {
  const id = path.basename(file).replace(/^agent-/, '').replace(/\.jsonl$/, '');
  let st = agents.get(id);
  if (!st) { st = newState(id, file); agents.set(id, st); }
  let stat;
  try { stat = fs.statSync(file); } catch { return; }
  st.mtimeMs = stat.mtimeMs;
  if (!st.description || st.description === st.id) loadMeta(st);
  if (stat.size < st.offset) { Object.assign(st, newState(id, file)); loadMeta(st); }
  if (stat.size === st.offset) return;
  const fd = fs.openSync(file, 'r');
  try {
    const len = stat.size - st.offset;
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, st.offset);
    st.offset = stat.size;
    const chunk = st.tail + buf.toString('utf8');
    const lines = chunk.split('\n');
    st.tail = lines.pop();
    for (const line of lines) {
      if (!line || line.length > 4_000_000) continue;
      // blobs de requisição são enormes e inúteis aqui
      if (line.startsWith('{"type":"api-request')) continue;
      try { handleRecord(st, JSON.parse(line)); } catch { /* linha incompleta */ }
    }
  } finally { fs.closeSync(fd); }
}

function scanAll() {
  let sessions = [];
  try {
    sessions = fs.readdirSync(PROJECT_DIR, { withFileTypes: true }).filter((d) => d.isDirectory());
  } catch { return; }
  for (const s of sessions) {
    const dir = path.join(PROJECT_DIR, s.name, 'subagents');
    let files = [];
    try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')); } catch { continue; }
    for (const f of files) refreshFile(path.join(dir, f));
  }
}

function statusOf(st, now) {
  const age = (now - st.mtimeMs) / 1000;
  const pend = [...st.pending.values()];
  const failedText = /session limit|rate.?limit|hit your/i.test(st.lastText);
  if (failedText && st.lastKind === 'text') return { code: 'failed', label: 'Interrompido (limite de uso)' };
  if (st.handedBack) return { code: 'done', label: 'Concluído' };
  if (pend.length) {
    const p = pend[pend.length - 1];
    const secs = Math.max(0, Math.round((now - Date.parse(p.ts)) / 1000));
    if (age > 1800) return { code: 'stale', label: 'Parado há ' + Math.round(age / 60) + ' min' };
    return { code: 'running', label: `Executando: ${p.title}`, detail: p.detail, runningFor: secs };
  }
  if (st.lastKind === 'text' && age > 45) return { code: 'done', label: 'Concluído / aguardando' };
  if (age > 900) return { code: 'stale', label: 'Sem atividade há ' + Math.round(age / 60) + ' min' };
  return { code: 'working', label: 'Pensando / processando' };
}

function snapshot() {
  scanAll();
  const now = Date.now();
  const list = [...agents.values()].map((st) => {
    const status = statusOf(st, now);
    return {
      id: st.id,
      description: st.description,
      agentType: st.agentType,
      startedAt: st.startedAt,
      lastActivity: st.lastTs,
      status,
      toolCalls: st.toolCalls,
      usage: usageTotals(st, now),
      errors: st.errors,
      tools: st.tools,
      filesTouched: st.files.size,
      recentFiles: [...st.files].slice(-8).map((f) => redact(f)),
      badges: st.badges,
      lastText: st.lastText,
      events: st.events.slice(-40).map((e) => ({ ...e })),
      finalReport: status.code === 'done' ? clip(st.finalText, 1500) : '',
    };
  });
  list.sort((a, b) => (Date.parse(b.lastActivity || 0) || 0) - (Date.parse(a.lastActivity || 0) || 0));
  const total = { input: 0, cacheWrite: 0, cacheRead: 0, output: 0, fresh: 0, calls: 0, last5min: 0 };
  for (const a of list) for (const k of Object.keys(total)) total[k] += a.usage[k];
  return { now: new Date(now).toISOString(), totalUsage: total, agents: list };
}

// ---------- Docker (containers do backend/web) ----------
let dockerState = { ok: false, containers: [], ts: null, error: 'não consultado' };
function pollDocker() {
  execFile('docker', ['ps', '-a', '--format', '{{json .}}'], { timeout: 8000 }, (err, out) => {
    if (err) { dockerState = { ok: false, containers: [], ts: new Date().toISOString(), error: 'Docker indisponível' }; return; }
    const rows = out.split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    dockerState = {
      ok: true, ts: new Date().toISOString(), error: null,
      containers: rows.map((r) => ({
        name: r.Names, image: r.Image, state: r.State, status: r.Status,
        ports: String(r.Ports || '').replace(/0\.0\.0\.0:/g, ''),
      })),
    };
  });
}
setInterval(pollDocker, 5000); pollDocker();

// ---------- HTTP ----------
const server = http.createServer((req, res) => {
  // só aceita acesso local (defesa extra além do bind em 127.0.0.1)
  const host = (req.headers.host || '').split(':')[0];
  if (host !== '127.0.0.1' && host !== 'localhost') { res.writeHead(403).end('forbidden'); return; }
  const url = req.url.split('?')[0];
  const send = (code, type, body) => {
    res.writeHead(code, {
      'Content-Type': type, 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy': "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'",
    });
    res.end(body);
  };
  if (url === '/' || url === '/index.html') {
    try { send(200, 'text/html; charset=utf-8', fs.readFileSync(INDEX)); } catch { send(500, 'text/plain', 'index.html ausente'); }
  } else if (url === '/api/agents') {
    try { send(200, 'application/json', JSON.stringify(snapshot())); } catch (e) { send(500, 'application/json', JSON.stringify({ error: String(e) })); }
  } else if (url === '/api/docker') {
    send(200, 'application/json', JSON.stringify(dockerState));
  } else {
    send(404, 'text/plain', 'não encontrado');
  }
});
server.listen(PORT, HOST, () => console.log(`Painel de agentes em http://${HOST}:${PORT}`));
