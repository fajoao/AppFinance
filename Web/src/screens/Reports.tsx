import { useMemo, useState } from 'react'
import * as C from '../core'
import { CandidateTransaction, Category, civil, ymFirst, ymLast, ymPrev } from '../core'
import { addCategory, commitImport, updateCategory, UserError } from '../app/actions'
import { downloadText } from '../app/download'
import { useView } from '../app/hooks'
import { useApp } from '../app/store'
import { categoryKeywords, catColorVar, webIcon } from '../app/logic'
import { fmtDay, fmtMoney, fmtPercent, MONTHS_SHORT } from '../app/format'
import { Amt, Button, Chip, Field, Group, Icon, Row, Segmented, SplitAmount } from '../ui/kit'
import { LineChart } from '../ui/charts'
import { Page } from '../ui/Shell'
import { navigate } from '../app/router'

const backBtn = (to = '/mais') => <button type="button" className="icon-btn" aria-label="Voltar" onClick={() => navigate(to)}><Icon name="chevL" /></button>
type Period = 'month' | 'last' | '3m' | 'year' | 'custom'

export function ReportsScreen() {
  const v = useView()
  const [period, setPeriod] = useState<Period>('month')
  const [from, setFrom] = useState(''), [to, setTo] = useState('')
  const [cats, setCats] = useState<Set<string>>(new Set())
  const [members, setMembers] = useState<Set<string>>(new Set())
  const [accs, setAccs] = useState<Set<string>>(new Set())
  const range = useMemo(() => {
    const m = C.ymOf(v.today)
    switch (period) {
      case 'month': return [ymFirst(m), ymLast(m)] as const
      case 'last': return [ymFirst(ymPrev(m)), ymLast(ymPrev(m))] as const
      case '3m': return [ymFirst(C.ymAdd(m, -2)), ymLast(m)] as const
      case 'year': return [civil(m.year, 1, 1), civil(m.year, 12, 31)] as const
      default: return [C.parseIsoDay(from) ?? ymFirst(m), C.parseIsoDay(to) ?? ymLast(m)] as const
    }
  }, [period, from, to, v.today])
  const result = useMemo(() => C.runReport(C.reportFilter(range[0], range[1], { categoryIds: cats, memberIds: members, accountIds: accs }), v.transactions, v.categories), [range, cats, members, accs, v.transactions, v.categories])
  const toggle = (s: Set<string>, set: (n: Set<string>) => void, id: string) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); set(n) }
  const names: C.ReportNames = {
    categories: Object.fromEntries(v.categories.map((c) => [c.id, c.name])), members: Object.fromEntries(v.members.map((m) => [m.id, m.name])), accounts: Object.fromEntries(v.accounts.map((a) => [a.id, a.name])),
  }
  const doc = C.buildReportDocument(result, 'Relatório financeiro', names, v.today)
  const exportCsv = () => { downloadText(`relatorio-${C.isoDay(range[0])}_${C.isoDay(range[1])}.csv`, C.reportCSV(doc)); useApp.getState().toast('CSV do relatório baixado.') }
  const exportTx = () => downloadText(`lancamentos-${C.isoDay(range[0])}_${C.isoDay(range[1])}.csv`, C.exportCSV(result.transactions, v.accounts, v.categories, v.tags))
  const group = (label: string, list: C.GroupTotal[], lookup: Record<string, string>, none: string) => list.length > 0 && (
    <Group label={label}>
      {list.map((g) => <Row key={g.id ?? 'none'} title={g.id ? lookup[g.id] ?? 'Sem nome' : none} sub={g.expense.gt(0) ? `${fmtPercent(g.percentOfExpense)} das despesas · ${g.count} lançamentos` : `${g.count} lançamentos`}
        trailing={<Amt value={g.expense.gt(0) ? g.expense : g.income} kind={g.expense.gt(0) ? 'expense' : 'income'} hide={v.hide} />} />)}
    </Group>
  )
  return (
    <Page title="Relatórios" actions={backBtn()}>
      <div className="chips" role="group" aria-label="Período">
        {([['month', 'Este mês'], ['last', 'Mês passado'], ['3m', '3 meses'], ['year', 'Este ano'], ['custom', 'Personalizado']] as const).map(([k, l]) => <Chip key={k} pressed={period === k} onClick={() => setPeriod(k)}>{l}</Chip>)}
      </div>
      {period === 'custom' && <div className="field-row" style={{ padding: '0 20px' }}>
        <Field label="De">{(id) => <input id={id} type="date" className="field" value={from} onChange={(e) => setFrom(e.target.value)} />}</Field>
        <Field label="Até">{(id) => <input id={id} type="date" className="field" value={to} onChange={(e) => setTo(e.target.value)} />}</Field></div>}
      <details style={{ padding: '8px 20px' }}><summary style={{ cursor: 'pointer', minHeight: 44, display: 'flex', alignItems: 'center' }}>Filtros (categoria, membro, conta)</summary>
        <div className="chips wrap" role="group" aria-label="Categorias" style={{ padding: 0 }}>{v.categories.filter((c) => !c.parentId).map((c) => <Chip key={c.id} pressed={cats.has(c.id)} onClick={() => toggle(cats, setCats, c.id)}>{c.name}</Chip>)}</div>
        {v.hasFamily && <div className="chips wrap" role="group" aria-label="Membros" style={{ padding: 0 }}>{v.members.map((m) => <Chip key={m.id} pressed={members.has(m.id)} onClick={() => toggle(members, setMembers, m.id)}>{m.name}</Chip>)}</div>}
        <div className="chips wrap" role="group" aria-label="Contas" style={{ padding: 0 }}>{v.accounts.map((a) => <Chip key={a.id} pressed={accs.has(a.id)} onClick={() => toggle(accs, setAccs, a.id)}>{a.name}</Chip>)}</div>
      </details>
      <section className="hero"><p className="hero-label">Resultado de {fmtDay(range[0])} a {fmtDay(range[1])}</p><SplitAmount value={result.net} size="large" hide={v.hide} />
        <p className="hero-sub">Receitas <strong>{fmtMoney(result.income, { hide: v.hide })}</strong> · Despesas <strong>{fmtMoney(result.expense, { hide: v.hide })}</strong> · {result.count} lançamentos</p></section>
      {result.byMonth.length > 1 && <div style={{ padding: '12px 16px 0' }}><LineChart desc="Receitas e despesas mês a mês" labels={result.byMonth.map((m) => MONTHS_SHORT[m.month.month - 1]!)}
        series={[{ name: 'Receitas', color: 'var(--income)', points: result.byMonth.map((m) => m.income.toNumber()) }, { name: 'Despesas', color: 'var(--brand-primary)', dashed: true, points: result.byMonth.map((m) => m.expense.toNumber()) }]} />
        <div className="legend"><span style={{ ['--c' as string]: 'var(--income)' }}><i />Receitas (linha contínua)</span><span style={{ ['--c' as string]: 'var(--brand-primary)' }}><i />Despesas (tracejada)</span></div></div>}
      {group('Por categoria', result.byCategory, names.categories, 'Sem categoria')}
      {v.hasFamily && group('Por membro', result.byMember, names.members, 'Sem membro')}
      {group('Por conta', result.byAccount, names.accounts, 'Cartão ou sem conta')}
      <div className="btns"><Button onClick={exportCsv} data-testid="export-csv"><Icon name="download" />Exportar resumo (CSV)</Button><Button variant="secondary" onClick={exportTx}>Exportar lançamentos (CSV)</Button></div>
      <p className="note">CSV com ponto e vírgula e vírgula decimal, pronto para o Excel em português.</p>
    </Page>
  )
}

export function TaxScreen() {
  const v = useView()
  const [year, setYear] = useState(v.today.getUTCFullYear() - 1)
  const [who, setWho] = useState('')
  const s = useMemo(() => C.taxSummary(year, v.transactions, v.categories, C.DEFAULT_TAX_RULES, who || undefined), [year, who, v.transactions, v.categories])
  const names: C.ReportNames = { categories: Object.fromEntries(v.categories.map((c) => [c.id, c.name])), members: {}, accounts: {} }
  const doc = C.taxDocument(s, names, who ? v.lookup.members.get(who)?.name : undefined, v.today)
  const nm = (id: string | null) => (id && names.categories[id]) || 'Sem categoria'
  return (
    <Page title="Imposto de Renda" actions={backBtn()}>
      <div className="field-row" style={{ padding: '8px 20px 0' }}>
        <Field label="Ano-calendário">{(id) => <select id={id} className="field" value={year} onChange={(e) => setYear(+e.target.value)}>{[0, 1, 2, 3, 4].map((i) => v.today.getUTCFullYear() - i).map((y) => <option key={y}>{y}</option>)}</select>}</Field>
        {v.hasFamily && <Field label="Pessoa">{(id) => <select id={id} className="field" value={who} onChange={(e) => setWho(e.target.value)}><option value="">Toda a família</option>{v.members.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}</Field>}
      </div>
      <section className="hero"><p className="hero-label">Total dedutível</p><SplitAmount value={s.totalDeductible} size="large" hide={v.hide} /></section>
      <Group label="Rendimentos" aside={fmtMoney(s.totalIncome, { hide: v.hide })}>{s.incomeLines.map((l, i) => <Row key={i} title={nm(l.categoryId)} trailing={<Amt value={l.total} kind="income" hide={v.hide} />} />)}{s.incomeLines.length === 0 && <div className="empty"><p>Sem rendimentos no ano.</p></div>}</Group>
      <Group label="Despesas dedutíveis">
        {s.deductionLines.map((l, i) => <Row key={i} title={nm(l.categoryId)} sub={`${l.kind === 'health' ? 'Saúde' : 'Educação'} · ${l.count} lançamentos`} trailing={<Amt value={l.total} kind="expense" hide={v.hide} />} />)}
        {s.deductionLines.length === 0 && <div className="empty"><p>Nenhuma despesa dedutível. Marque categorias como Saúde ou Educação em Categorias.</p></div>}
      </Group>
      <Group label="Totais">
        <Row title="Saúde (sem limite)" trailing={<span className="num">{fmtMoney(s.healthTotal, { hide: v.hide })}</span>} />
        <Row title="Educação informada" trailing={<span className="num">{fmtMoney(s.educationTotal, { hide: v.hide })}</span>} />
        <Row title="Educação dedutível (limite por pessoa)" trailing={<span className="num">{fmtMoney(s.educationDeductible, { hide: v.hide })}</span>} />
      </Group>
      <p className="note" data-testid="tax-disclaimer">Este resumo é um auxílio e não substitui informes de rendimentos, recibos e notas fiscais. O limite de educação (R$ 3.561,50 por pessoa) muda por lei: confira a tabela vigente na Receita Federal.</p>
      <div className="btns"><Button onClick={() => downloadText(`ir-${year}.csv`, C.reportCSV(doc))}><Icon name="download" />Exportar CSV</Button><Button variant="secondary" onClick={() => navigate('/categorias')}>Marcar categorias</Button></div>
    </Page>
  )
}

// ---------- Importação ----------
export function ImportScreen() {
  const v = useView()
  const toast = useApp((s) => s.toast)
  const [accountId, setAccountId] = useState(v.activeAccounts[0]?.id ?? '')
  const [cands, setCands] = useState<CandidateTransaction[] | null>(null)
  const [issues, setIssues] = useState<C.ImportIssue[]>([])
  const [fileName, setFileName] = useState('')
  const [err, setErr] = useState('')
  const suggester = useMemo(() => new C.CategorySuggester(v.transactions, { ...categoryKeywords(v.categories, 'expense'), ...categoryKeywords(v.categories, 'income') }), [v.transactions, v.categories])

  const onFile = async (f: File | undefined) => {
    setErr(''); setCands(null)
    if (!f) return
    if (f.size > 5 * 1024 * 1024) { setErr('Arquivo grande demais (máximo 5 MB).'); return }
    const text = C.decodeText(await f.arrayBuffer())
    const isOfx = /\.(ofx|qfx)$/i.test(f.name) || /<OFX|OFXHEADER/i.test(text.slice(0, 2000))
    const r = isOfx ? C.parseOFX(text) : C.parseCSV(text)
    setFileName(f.name); setIssues(r.issues)
    if (r.candidates.length === 0) { setErr(r.issues[0]?.message ?? 'Nenhuma transação encontrada no arquivo.'); return }
    const marked = C.markDuplicates(r.candidates, v.transactions, accountId || undefined).map((c) => {
      const type = C.candidateType(c)
      return { ...c, suggestedCategoryId: suggester.suggest(c.title, type) }
    })
    setCands(marked)
  }
  const recheck = (id: string) => {
    setAccountId(id)
    if (cands) setCands(C.markDuplicates(cands.map((c) => ({ ...c, isDuplicate: false })), v.transactions, id))
  }
  const fresh = cands?.filter((c) => !c.isDuplicate) ?? []
  const dup = (cands?.length ?? 0) - fresh.length
  const confirm = () => {
    if (!accountId) { setErr('Escolha a conta de destino.'); return }
    const n = commitImport(cands!, accountId)
    toast(`${n} importados, ${dup} repetidos ignorados.`)
    setCands(null)
  }
  return (
    <Page title="Importar extrato" actions={backBtn()}>
      <p className="note">Aceita OFX e CSV (data, descrição, valor). Lançamentos já existentes são ignorados.</p>
      <Field label="Conta de destino">{(id) => <select id={id} className="field" value={accountId} onChange={(e) => recheck(e.target.value)}>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
      <Field label="Arquivo (.ofx, .qfx, .csv)">{(id) => <input id={id} className="field" type="file" accept=".ofx,.qfx,.csv,text/csv" onChange={(e) => void onFile(e.target.files?.[0])} data-testid="import-file" style={{ paddingTop: 10 }} />}</Field>
      {err && <p className="error" role="alert" style={{ padding: '0 20px' }}>{err}</p>}
      {cands && (
        <>
          <p className="list-summary" role="status">{fileName}: {fresh.length} novos, {dup} repetidos{issues.length ? `, ${issues.length} linhas com problema` : ''}</p>
          <Group>
            {cands.map((c, i) => (
              <Row key={i} icon={c.isDuplicate ? 'check' : 'download'} title={c.title} sub={<>{fmtDay(c.date)} · {c.isDuplicate ? 'Repetido (será ignorado)' : (c.suggestedCategoryId ? v.lookup.categories.get(c.suggestedCategoryId)?.name : 'Sem categoria')}</>}
                trailing={<span style={{ opacity: c.isDuplicate ? 0.5 : 1 }}><Amt value={c.amount.abs()} kind={c.amount.lt(0) ? 'expense' : 'income'} hide={v.hide} /></span>} />
            ))}
          </Group>
          {issues.length > 0 && <details style={{ padding: '8px 20px' }}><summary>Linhas com problema</summary><ul>{issues.map((x, i) => <li key={i}>Linha {x.line}: {x.message}</li>)}</ul></details>}
          <div className="btns"><Button onClick={confirm} disabled={fresh.length === 0} data-testid="import-confirm">Importar {fresh.length} lançamentos</Button><Button variant="plain" onClick={() => setCands(null)}>Cancelar</Button></div>
        </>
      )}
    </Page>
  )
}

// ---------- Categorias ----------
export function CategoriesScreen() {
  const v = useView()
  const [name, setName] = useState('')
  const [kind, setKind] = useState<'expense' | 'income'>('expense')
  const [err, setErr] = useState('')
  const byId = new Map(v.categories.map((c) => [c.id, c]))
  const row = (c: Category) => (
    <div key={c.id} className="row wrap-text" style={{ flexWrap: 'wrap' }}>
      <span className="ico" style={{ ['--c' as string]: catColorVar(c, byId) }}><Icon name={webIcon(c.icon)} /></span>
      <span className="main"><span className="t1">{c.name}</span></span>
      {c.kind === 'expense' && (
        <select aria-label={`Dedutível no IR: ${c.name}`} className="field" style={{ width: 'auto' }} value={c.taxKind ?? ''} onChange={(e) => updateCategory(c.id, { taxKind: (e.target.value || undefined) as C.TaxDeductionKind | undefined })}>
          <option value="">Não dedutível</option><option value="health">Saúde</option><option value="education">Educação</option>
        </select>
      )}
      {v.hasFamily && <Chip pressed={c.visibility === 'private'} onClick={() => updateCategory(c.id, { visibility: c.visibility === 'private' ? 'shared' : 'private' })}>{c.visibility === 'private' ? 'Privada' : 'Compartilhada'}</Chip>}
    </div>
  )
  return (
    <Page title="Categorias" actions={backBtn()}>
      <Group label="Despesas">{v.categories.filter((c) => c.kind === 'expense').map(row)}</Group>
      <Group label="Receitas">{v.categories.filter((c) => c.kind === 'income').map(row)}</Group>
      <Segmented label="Tipo da nova categoria" value={kind} onChange={setKind} options={[{ value: 'expense', label: 'Despesa' }, { value: 'income', label: 'Receita' }]} />
      <Field label="Nova categoria" error={err}>{(id, d) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} aria-describedby={d} />}</Field>
      <div className="btns"><Button onClick={() => { try { addCategory(name, kind); setName(''); setErr('') } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e } }}>Adicionar categoria</Button></div>
    </Page>
  )
}
