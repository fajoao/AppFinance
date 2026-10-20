import { Dec } from './decimal'
import { civil, components, daysInMonth, isSameDay, ym } from './calendar'
import * as Money from './money'
import { Account, Category, Tag, Transaction, TransactionStatus, TransactionType, UUID, mkTransaction, signedAmount } from './models'

export interface CandidateTransaction {
  date: Date
  title: string
  /** Valor com sinal como no extrato (negativo = saída). */
  amount: Dec
  externalId?: string
  isDuplicate: boolean
  suggestedCategoryId?: UUID
}
export interface ImportIssue { line: number; message: string }
export interface ImportResult { candidates: CandidateTransaction[]; issues: ImportIssue[] }

export const candidateType = (c: CandidateTransaction): TransactionType => (c.amount.lt(0) ? 'expense' : 'income')

export function candidateToTransaction(c: CandidateTransaction, accountId: UUID, status: TransactionStatus = 'paid', categoryId?: UUID): Transaction {
  return mkTransaction({
    type: candidateType(c), amount: c.amount.abs(), date: c.date, title: c.title, status, accountId,
    categoryId: categoryId ?? c.suggestedCategoryId, externalId: c.externalId,
  })
}

/** UTF-8 (com/sem BOM) com fallback para Windows-1252 (extratos brasileiros). */
export function decodeText(buf: ArrayBuffer): string {
  try {
    const s = new TextDecoder('utf-8', { fatal: true }).decode(buf)
    return s.startsWith('﻿') ? s.slice(1) : s
  } catch {
    return new TextDecoder('windows-1252').decode(buf)
  }
}

export function normalizeText(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim()
}

// MARK: Datas

/** dd/MM/yyyy, dd/MM/yy, dd-MM-yyyy, dd.MM.yyyy, yyyy-MM-dd, yyyy/MM/dd. Datas inválidas retornam null. */
export function parseDate(raw: string): Date | null {
  const s = raw.trim()
  const parts = s.split(/[/\-.]/)
  if (parts.length !== 3 || !parts.every((p) => /^[0-9]+$/.test(p))) return null
  let y: number, m: number, d: number
  if (parts[0]!.length === 4) { y = +parts[0]!; m = +parts[1]!; d = +parts[2]! }
  else if (parts[2]!.length === 4) { d = +parts[0]!; m = +parts[1]!; y = +parts[2]! }
  else if (parts[2]!.length === 2) { d = +parts[0]!; m = +parts[1]!; y = 2000 + +parts[2]! }
  else return null
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(ym(y, m))) return null
  return civil(y, m, d)
}

// MARK: CSV

export function csvRows(text: string, delimiter: string): string[][] {
  const rows: string[][] = []
  let row: string[] = []
  let field = ''
  let inQuotes = false
  const chars = [...text]
  if (chars[0] === '﻿') chars.shift()
  const pushRow = () => {
    row.push(field); field = ''
    if (!(row.length === 1 && row[0]!.trim() === '')) rows.push(row)
    row = []
  }
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i]!
    if (inQuotes) {
      if (c === '"') {
        if (chars[i + 1] === '"') { field += '"'; i++ } else inQuotes = false
      } else field += c
    } else if (c === '"') inQuotes = true
    else if (c === delimiter) { row.push(field); field = '' }
    else if (c === '\n') pushRow()
    else if (c === '\r') { if (chars[i + 1] === '\n') i++; pushRow() }
    else field += c
  }
  if (field !== '' || row.length > 0) {
    row.push(field)
    if (!(row.length === 1 && row[0]!.trim() === '')) rows.push(row)
  }
  return rows
}

export function detectDelimiter(text: string): string {
  const firstLine = text.split(/\r\n|\n|\r/).find((l) => l !== '') ?? ''
  let best = ';', bestCount = -1
  for (const d of [';', ',', '\t']) {
    let n = 0, q = false
    for (const c of firstLine) { if (c === '"') q = !q; else if (c === d && !q) n++ }
    if (n > bestCount) { best = d; bestCount = n }
  }
  return best
}

export function parseCSV(text: string, delimiter?: string): ImportResult {
  const delim = delimiter ?? detectDelimiter(text)
  const all = csvRows(text, delim)
  const result: ImportResult = { candidates: [], issues: [] }
  if (all.length === 0) return result
  const header = all[0]!.map(normalizeText)
  const index = (keys: string[]): number | undefined => {
    const i = header.findIndex((h) => keys.some((k) => h.includes(k)))
    return i < 0 ? undefined : i
  }
  const hasHeader = parseDate(all[0]![0] ?? '') === null
  let dateCol = 0, descCol = 1
  let amountCol: number | undefined = 2, debitCol: number | undefined, creditCol: number | undefined, idCol: number | undefined
  let startRow = 0
  if (hasHeader) {
    startRow = 1
    const dc = index(['data', 'date'])
    if (dc === undefined) { result.issues.push({ line: 1, message: 'Coluna de data não encontrada' }); return result }
    dateCol = dc
    descCol = index(['descricao', 'historico', 'description', 'memo', 'estabelecimento', 'lancamento', 'titulo', 'detalhe']) ?? (dc === 0 ? 1 : 0)
    amountCol = index(['valor', 'amount', 'value', 'quantia'])
    debitCol = index(['debito', 'saida', 'debit'])
    creditCol = index(['credito', 'entrada', 'credit'])
    idCol = index(['identificador', 'fitid', 'documento'])
    if (idCol === dc || idCol === descCol || idCol === amountCol) idCol = undefined
    if (amountCol === undefined && debitCol === undefined && creditCol === undefined) {
      result.issues.push({ line: 1, message: 'Coluna de valor não encontrada' })
      return result
    }
  }
  for (let r = startRow; r < all.length; r++) {
    const row = all[r]!
    const line = r + 1
    const cell = (i?: number): string | undefined => (i === undefined || i >= row.length ? undefined : row[i]!.trim())
    const dateText = cell(dateCol)
    const date = dateText === undefined ? null : parseDate(dateText)
    if (!date) { result.issues.push({ line, message: 'Data inválida' }); continue }
    let amount: Dec | null = null
    const a = cell(amountCol)
    if (a !== undefined && a !== '') amount = Money.parse(a)
    else {
      const dtxt = cell(debitCol), ctxt = cell(creditCol)
      const debit = dtxt ? Money.parse(dtxt) : null
      const credit = ctxt ? Money.parse(ctxt) : null
      if (debit) amount = debit.abs().neg()
      else if (credit) amount = credit.abs()
    }
    if (!amount) { result.issues.push({ line, message: 'Valor inválido' }); continue }
    const title = cell(descCol) ?? ''
    const ext = cell(idCol)
    result.candidates.push({ date, title: title === '' ? 'Sem descrição' : title, amount, externalId: ext ? ext : undefined, isDuplicate: false })
  }
  return result
}

// MARK: OFX

export function parseOFXDate(s: string): Date | null {
  const digits = s.slice(0, 8)
  if (digits.length !== 8 || !/^[0-9]{8}$/.test(digits)) return null
  const y = +digits.slice(0, 4), m = +digits.slice(4, 6), d = +digits.slice(6, 8)
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(ym(y, m))) return null
  return civil(y, m, d)
}

const decodeEntities = (s: string): string =>
  s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")

export function parseOFX(text: string): ImportResult {
  const result: ImportResult = { candidates: [], issues: [] }
  const up = text.toUpperCase()
  if (!up.includes('<OFX') && !up.includes('<STMTTRN')) {
    result.issues.push({ line: 0, message: 'Não parece um arquivo OFX' })
    return result
  }
  const tokens: { tag: string; value: string }[] = []
  let i = 0
  while (i < text.length) {
    if (text[i] === '<') {
      let j = i + 1
      while (j < text.length && text[j] !== '>') j++
      if (j >= text.length) break
      const tag = text.slice(i + 1, j).toUpperCase()
      let k = j + 1
      while (k < text.length && text[k] !== '<') k++
      tokens.push({ tag, value: text.slice(j + 1, k).trim() })
      i = k
    } else i++
  }
  let cur: Record<string, string> | null = null
  let n = 0
  const flush = () => {
    const c = cur
    if (!c) return
    n++
    cur = null
    const dt = c.DTPOSTED
    const date = dt && dt.length >= 8 ? parseOFXDate(dt) : null
    if (!date) { result.issues.push({ line: n, message: `Data inválida na transação ${n}` }); return }
    const amtText = c.TRNAMT
    const amt = amtText ? Money.parse(amtText, amtText.includes(',') ? 'comma' : 'dot') : null
    if (!amt) { result.issues.push({ line: n, message: `Valor inválido na transação ${n}` }); return }
    const name = decodeEntities(c.NAME ?? ''), memo = decodeEntities(c.MEMO ?? '')
    const title = memo !== '' ? (name === '' || name === memo ? memo : `${name} - ${memo}`) : name === '' ? 'Sem descrição' : name
    result.candidates.push({ date, title, amount: amt, externalId: c.FITID ? c.FITID : undefined, isDuplicate: false })
  }
  for (const { tag, value } of tokens) {
    switch (tag) {
      case 'STMTTRN': flush(); cur = {}; break
      case '/STMTTRN': case '/BANKTRANLIST': case '/CCSTMTRS': case '/STMTRS': flush(); break
      default:
        if (cur && !tag.startsWith('/') && value !== '') cur[tag] = value
    }
  }
  flush()
  return result
}

// MARK: Duplicatas

export function markDuplicates(candidates: CandidateTransaction[], existing: Transaction[], accountId?: UUID): CandidateTransaction[] {
  const pool = existing.filter((t) => accountId === undefined || t.accountId === accountId || t.destinationAccountId === accountId)
  const used = new Set<UUID>()
  const signed = (t: Transaction): Dec => (t.type === 'transfer' ? (t.accountId === accountId ? t.amount.neg() : t.amount) : signedAmount(t))
  return candidates.map((orig) => {
    const c = { ...orig }
    if (c.externalId) {
      const hit = pool.find((t) => t.externalId === c.externalId && !used.has(t.id))
      if (hit) { used.add(hit.id); c.isDuplicate = true; return c }
    }
    const ct = normalizeText(c.title)
    const hit = pool.find((t) => {
      if (used.has(t.id) || !isSameDay(t.date, c.date) || !signed(t).eq(c.amount)) return false
      const tt = normalizeText(t.title)
      return tt === ct || tt.includes(ct) || ct.includes(tt)
    })
    if (hit) { used.add(hit.id); c.isDuplicate = true }
    return c
  })
}

// MARK: Exportação CSV

export interface CSVExportOptions { delimiter: string; decimalComma: boolean }
export const CSV_HEADER = ['data', 'descricao', 'tipo', 'valor', 'status', 'conta', 'categoria', 'tags', 'observacao']

export const formatDateBR = (d: Date): string => {
  const c = components(d)
  return `${String(c.day).padStart(2, '0')}/${String(c.month).padStart(2, '0')}/${String(c.year).padStart(4, '0')}`
}

export function csvEscape(s: string, delimiter: string): string {
  let v = s
  if (v.length > 0 && '=@'.includes(v[0]!)) v = "'" + v
  if (v.includes(delimiter) || v.includes('"') || v.includes('\n') || v.includes('\r')) return '"' + v.replace(/"/g, '""') + '"'
  return v
}

export function exportCSV(
  txs: Transaction[], accounts: Account[] = [], categories: Category[] = [], tags: Tag[] = [],
  options: CSVExportOptions = { delimiter: ';', decimalComma: true },
): string {
  const accName = new Map(accounts.map((a) => [a.id, a.name]))
  const catName = new Map(categories.map((c) => [c.id, c.name]))
  const tagName = new Map(tags.map((t) => [t.id, t.name]))
  const d = options.delimiter
  const lines = [CSV_HEADER.join(d)]
  for (const tx of [...txs].sort((a, b) => a.date.getTime() - b.date.getTime())) {
    const signed = tx.type === 'transfer' ? tx.amount.neg() : signedAmount(tx)
    const amount = Money.plain(signed, options.decimalComma ? ',' : '.')
    const tipo = tx.type === 'income' ? 'receita' : tx.type === 'expense' ? 'despesa' : 'transferencia'
    const fields = [
      formatDateBR(tx.date), tx.title, tipo, amount, tx.status === 'paid' ? 'pago' : 'pendente',
      (tx.accountId && accName.get(tx.accountId)) || '', (tx.categoryId && catName.get(tx.categoryId)) || '',
      tx.tagIds.map((t) => tagName.get(t)).filter((x): x is string => !!x).join('|'), tx.note ?? '',
    ]
    lines.push(fields.map((f) => csvEscape(f, d)).join(d))
  }
  return lines.join('\n') + '\n'
}

// MARK: Sugestão de categoria

const STOPWORDS = new Set(['de', 'da', 'do', 'das', 'dos', 'em', 'no', 'na', 'para', 'com', 'por', 'pix', 'compra', 'pagamento', 'pag', 'the', 'and', 'ltda', 'sa'])

export function tokens(s: string): string[] {
  return normalizeText(s).split(/[^\p{L}\p{M}\p{N}]+/u).filter((t) => t.length >= 3 && !STOPWORDS.has(t) && !/^\p{N}+$/u.test(t))
}

export class CategorySuggester {
  private exact = new Map<string, Map<UUID, number>>()
  private tokenCounts = new Map<TransactionType, Map<string, Map<UUID, number>>>()
  constructor(history: Transaction[] = [], public keywords: Record<UUID, string[]> = {}) {
    for (const t of history) this.learn(t)
  }
  learn(tx: Transaction): void {
    if (!tx.categoryId || tx.type === 'transfer') return
    const key = normalizeText(tx.title)
    inc(this.exact, key, tx.categoryId)
    let byTok = this.tokenCounts.get(tx.type)
    if (!byTok) this.tokenCounts.set(tx.type, (byTok = new Map()))
    for (const t of new Set(tokens(tx.title))) inc(byTok, t, tx.categoryId)
  }
  suggest(title: string, type: TransactionType = 'expense'): UUID | undefined {
    const norm = normalizeText(title)
    if (norm === '') return undefined
    for (const [cat, words] of Object.entries(this.keywords).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
      if (words.some((w) => norm.includes(normalizeText(w)))) return cat
    }
    const m = this.exact.get(norm)
    if (m) { const b = best(m); if (b) return b }
    const score = new Map<UUID, number>()
    for (const t of new Set(tokens(title))) {
      const mm = this.tokenCounts.get(type)?.get(t)
      if (!mm) continue
      const total = [...mm.values()].reduce((a, b2) => a + b2, 0)
      for (const [cat, n] of mm) score.set(cat, (score.get(cat) ?? 0) + n / total)
    }
    let top: [UUID, number] | undefined
    for (const e of score) {
      if (!top || e[1] > top[1] || (e[1] === top[1] && e[0] < top[0])) top = e
    }
    return top?.[0]
  }
}
function inc(map: Map<string, Map<UUID, number>>, key: string, cat: UUID) {
  let m = map.get(key)
  if (!m) map.set(key, (m = new Map()))
  m.set(cat, (m.get(cat) ?? 0) + 1)
}
function best(m: Map<UUID, number>): UUID | undefined {
  let top: [UUID, number] | undefined
  for (const e of m) if (!top || e[1] > top[1] || (e[1] === top[1] && e[0] < top[0])) top = e
  return top?.[0]
}

