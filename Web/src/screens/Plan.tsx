import { useMemo, useState } from 'react'
import * as C from '../core'
import { Dec, Goal, Money, ZERO, isoDay, parseIsoDay } from '../core'
import {
  UserError, checkBudgetAlerts, contributeToGoal, copyBudgetsFromPrevious, deleteGoal, markPaid, revertContribution, saveGoal, setBudget,
} from '../app/actions'
import { useView } from '../app/hooks'
import { useApp } from '../app/store'
import { BillItem, billDots, billItems, billStatus, billTotals, billsIn, calendarWeeks, catColorVar, categoryName, webIcon } from '../app/logic'
import { cap, fmtDay, fmtDayShort, fmtMoney, fmtPercent, monthTitle } from '../app/format'
import { Amt, Badge, Bar, Button, Empty, Field, Group, Icon, Row, Sheet, SplitAmount, useConfirm } from '../ui/kit'
import { MonthSwitch, MonthSwitcher, PLAN_TABS, Page, SubNav } from '../ui/Shell'
import { navigate } from '../app/router'

// ---------- Orçamento ----------
export function BudgetScreen() {
  const v = useView()
  const data = useApp((s) => s.data)
  const [edit, setEdit] = useState<{ categoryId: string; current?: Dec } | null>(null)
  const byId = useMemo(() => new Map(v.categories.map((c) => [c.id, c])), [v.categories])
  const statuses = useMemo(() => C.budgetStatuses(v.month, data.budgets, v.transactions, v.categories), [data.budgets, v.transactions, v.categories, v.month])
  const totalLimit = C.sum(statuses.map((s) => s.limit)), totalSpent = C.sum(statuses.map((s) => s.spent))
  const available = totalLimit.minus(totalSpent)
  const without = v.categories.filter((c) => c.kind === 'expense' && !c.parentId && !statuses.some((s) => s.budget.categoryId === c.id))
  return (
    <Page title="Planejar" sub={<><SubNav items={PLAN_TABS} current="/orcamento" /><MonthSwitcher /></>}>
      <section className="hero">
        <p className="hero-label">Disponível em {monthTitle(v.month)}</p>
        <SplitAmount value={available} size="large" hide={v.hide} />
        <div style={{ marginTop: 10 }}><Bar fraction={totalLimit.gt(0) ? totalSpent.div(totalLimit).toNumber() : 0} label="Orçamento total usado" /></div>
        <p className="hero-sub">Gasto {fmtMoney(totalSpent, { hide: v.hide })} de {fmtMoney(totalLimit, { hide: v.hide })}</p>
      </section>
      <Group label="Por categoria">
        {statuses.sort((a, b) => b.percentUsed.comparedTo(a.percentUsed)).map((s) => {
          const cat = byId.get(s.budget.categoryId)
          const color = s.alert === 'exceeded' ? 'var(--danger)' : s.alert === 'warning' ? 'var(--warning-fill)' : catColorVar(cat, byId)
          return (
            <Row key={s.budget.id} icon={webIcon(cat?.icon)} color={catColorVar(cat, byId)} title={categoryName(v.lookup, s.budget.categoryId)} onClick={() => setEdit({ categoryId: s.budget.categoryId, current: s.limit })}
              sub={<Bar fraction={s.limit.gt(0) ? s.spent.div(s.limit).toNumber() : 1} color={color} mark={0.8} label={`${categoryName(v.lookup, s.budget.categoryId)}: ${s.percentUsed.toFixed(0)}% usado`} />}
              trailing={s.alert === 'exceeded' ? <><Badge tone="danger">Estourou {fmtMoney(s.spent.minus(s.limit), { hide: v.hide })}</Badge></> : s.alert === 'warning' ? <Badge tone="warn">{s.percentUsed.toFixed(0)}% usado</Badge> : <><Badge tone="ok">Restam {fmtMoney(s.remaining, { hide: v.hide })}</Badge></>} />
          )
        })}
        {statuses.length === 0 && <div className="empty"><p>Nenhum orçamento neste mês.</p></div>}
      </Group>
      <div className="btns">
        <Button variant="secondary" onClick={() => { const n = copyBudgetsFromPrevious(v.month); useApp.getState().toast(n ? `${n} orçamento(s) copiado(s) do mês anterior.` : 'Nada novo para copiar.') }}>Copiar do mês anterior</Button>
      </div>
      {without.length > 0 && (
        <Group label="Sem orçamento">
          {without.map((c) => <Row key={c.id} icon={webIcon(c.icon)} color={catColorVar(c, byId)} title={c.name} sub={`Gasto: ${fmtMoney(C.spentInCategory(c.id, v.month, v.transactions, v.categories), { hide: v.hide })}`} onClick={() => setEdit({ categoryId: c.id })} />)}
        </Group>
      )}
      {edit && <BudgetSheet categoryId={edit.categoryId} current={edit.current} month={v.month} onClose={() => setEdit(null)} />}
    </Page>
  )
}

function BudgetSheet({ categoryId, current, month, onClose }: { categoryId: string; current?: Dec; month: C.YearMonth; onClose: () => void }) {
  const v = useView()
  const [t, setT] = useState(current ? current.toFixed(2).replace('.', ',') : '')
  const [err, setErr] = useState('')
  const go = () => {
    const n = t.trim() === '' ? ZERO : Money.parse(t)
    if (!n || n.isNegative()) { setErr('Valor inválido. Exemplo: 1.500,00'); return }
    setBudget(categoryId, month, n)
    checkBudgetAlerts()
    onClose()
  }
  return (
    <Sheet title={`Orçamento de ${categoryName(v.lookup, categoryId)}`} onClose={onClose} short footer={<Button onClick={go}>Salvar</Button>}>
      <Field label={`Limite de ${monthTitle(month)} (R$)`} error={err} hint="Deixe em branco ou zero para remover.">{(id, d) => <input id={id} className="field num" inputMode="decimal" value={t} onChange={(e) => setT(e.target.value)} aria-describedby={d} aria-invalid={!!err} />}</Field>
    </Sheet>
  )
}

// ---------- Contas a pagar ----------
export function BillsScreen() {
  const v = useView()
  const [month, setMonth] = useState(v.month)
  const [day, setDay] = useState<Date | null>(null)
  const all = useMemo(() => billItems(v.transactions, v.activeCards, v.invoices, v.today, 6), [v.transactions, v.activeCards, v.invoices, v.today])
  const inMonth = billsIn(all, month)
  const shown = day ? inMonth.filter((b) => C.isSameDay(b.dueDate, day)) : inMonth
  const totals = billTotals(inMonth)
  const weeks = calendarWeeks(month)
  const wd = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
  const tone: Record<string, string> = { danger: 'var(--danger)', warning: 'var(--warning-fill)', brand: 'var(--brand-primary)', neutral: 'var(--neutral)', ok: 'var(--income)' }
  return (
    <Page title="Planejar" sub={<SubNav items={PLAN_TABS} current="/contas-a-pagar" />}>
      <div className="cal">
        <div className="cal-head"><MonthSwitch month={month} onChange={(m) => { setMonth(m); setDay(null) }} /></div>
        <div className="cal-grid" role="grid" aria-label={`Calendário de ${monthTitle(month)}`}>
          {wd.map((w, i) => <div key={i} className="cal-wd" role="columnheader">{w}</div>)}
          {weeks.flat().map((d, i) => d ? (
            <button key={i} type="button" className={`cal-day ${C.isSameDay(d, v.today) ? 'today' : ''}`} aria-pressed={!!day && C.isSameDay(d, day)}
              aria-label={`${d.getUTCDate()} de ${monthTitle(month)}${billDots(d, inMonth, v.today).length ? ', com contas' : ''}`} onClick={() => setDay(day && C.isSameDay(d, day) ? null : d)}>
              <span className="dn">{d.getUTCDate()}</span>
              <span className="dots">{billDots(d, inMonth, v.today).map((t) => <i key={t} style={{ ['--c' as string]: tone[t] }} />)}</span>
            </button>
          ) : <button key={i} type="button" className="cal-day" disabled aria-hidden="true" />)}
        </div>
      </div>
      <div className="legend"><span style={{ ['--c' as string]: tone.danger }}><i />Atrasado</span><span style={{ ['--c' as string]: tone.warning }}><i />Vence em até 3 dias</span><span style={{ ['--c' as string]: tone.brand }}><i />A receber</span><span style={{ ['--c' as string]: tone.neutral }}><i />Pendente</span><span style={{ ['--c' as string]: tone.ok }}><i />Pago</span></div>
      <div className="kv" style={{ padding: '12px 20px 0' }}><span>A pagar</span><span className="num">{fmtMoney(totals.toPay, { hide: v.hide })}</span></div>
      <div className="kv" style={{ padding: '0 20px' }}><span>A receber</span><span className="num income">{fmtMoney(totals.toReceive, { hide: v.hide })}</span></div>
      {day && <p className="note">Mostrando {fmtDay(day)}. <button type="button" className="link-btn" onClick={() => setDay(null)}>Ver mês todo</button></p>}
      <Group label={day ? 'Contas do dia' : `Contas de ${monthTitle(month)}`}>
        {shown.map((b) => <BillRow key={b.id} b={b} />)}
        {shown.length === 0 && <div className="empty"><p>Nenhuma conta {day ? 'neste dia' : 'neste mês'}.</p></div>}
      </Group>
    </Page>
  )
  function BillRow({ b }: { b: BillItem }) {
    const st = billStatus(b, v.today)
    const act = b.isPaid ? null : b.cardId
      ? <Button small onClick={() => navigate(`/cartoes/${b.cardId}?pagar=1`)}>Pagar</Button>
      : b.transactionId ? <Button small variant="secondary" onClick={() => markPaid(b.transactionId!)}>{b.direction === 'receivable' ? 'Recebi' : 'Pagar'}</Button> : null
    return (
      <Row icon={b.cardId ? 'card' : b.direction === 'receivable' ? 'download' : 'calendar'} title={b.title} sub={<>{fmtDayShort(b.dueDate)} · <span className={st.tone === 'danger' ? 'danger-text' : st.tone === 'warning' ? 'warn-text' : ''}>{st.label}</span></>}
        trailing={<span style={{ display: 'flex', gap: 10, alignItems: 'center' }}><Amt value={b.amount} kind={b.direction === 'receivable' ? 'income' : 'expense'} hide={v.hide} />{act}</span>} />
    )
  }
}

// ---------- Metas ----------
export function GoalsScreen() {
  const v = useView()
  const data = useApp((s) => s.data)
  const [edit, setEdit] = useState<Goal | 'new' | null>(null)
  const [contrib, setContrib] = useState<Goal | null>(null)
  const [hist, setHist] = useState<Goal | null>(null)
  const goals = data.goals.filter((g) => !v.hasFamily || !g.memberId || v.me?.role !== 'dependent' || g.memberId === v.me.id)
  return (
    <Page title="Planejar" sub={<SubNav items={PLAN_TABS} current="/metas" />}>
      {goals.length === 0 && <Empty title="Nenhuma meta" text="Defina um objetivo e acompanhe quanto falta." />}
      {goals.map((g) => {
        const p = C.goalProgress(g, v.today)
        const proj = C.goalProjection(g, data.goalContributions, v.today)
        const member = g.memberId ? v.lookup.members.get(g.memberId)?.name : undefined
        return (
          <article key={g.id} className="panel" aria-label={g.name}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
              <div><h3>{g.name}</h3><p className="meta">{member ? `Meta de ${member} · ` : ''}{g.deadline ? `Até ${fmtDay(g.deadline)}` : 'Sem prazo'}</p></div>
              <Badge tone={p.isComplete ? 'ok' : 'brand'}>{fmtPercent(p.percent).replace(',00', '')}</Badge>
            </div>
            <div style={{ marginTop: 10 }}><SplitAmount value={g.currentAmount} size="large" hide={v.hide} /> <span className="meta">de {fmtMoney(g.targetAmount, { hide: v.hide })}</span></div>
            <div style={{ marginTop: 10 }}><Bar fraction={p.fraction.toNumber()} label={`${g.name}: ${p.percent}% concluído`} /></div>
            {p.monthlyContributionNeeded && !p.isComplete && <div className="kv"><span>Guarde por mês</span><span className="num">{fmtMoney(p.monthlyContributionNeeded, { hide: v.hide })}</span></div>}
            {proj.projectedCompletion && !p.isComplete && <div className="kv"><span>No seu ritmo, conclui em</span><span className="num">{cap(monthTitle(C.ymOf(proj.projectedCompletion)))}{proj.onTrack === false ? ' (atrasada)' : proj.onTrack ? ' (no caminho)' : ''}</span></div>}
            <div className="row-actions">
              <Button small onClick={() => setContrib(g)} disabled={p.isComplete}>Guardar dinheiro</Button>
              <Button small variant="secondary" onClick={() => setHist(g)}>Histórico</Button>
              <Button small variant="plain" onClick={() => setEdit(g)}>Editar</Button>
            </div>
          </article>
        )
      })}
      <div className="btns"><Button variant="secondary" onClick={() => setEdit('new')}><Icon name="plus" />Nova meta</Button></div>
      {edit && <GoalSheet goal={edit === 'new' ? null : edit} onClose={() => setEdit(null)} />}
      {contrib && <ContribSheet goal={contrib} onClose={() => setContrib(null)} />}
      {hist && <HistorySheet goal={hist} onClose={() => setHist(null)} />}
    </Page>
  )
}

function GoalSheet({ goal, onClose }: { goal: Goal | null; onClose: () => void }) {
  const v = useView()
  const confirm = useConfirm()
  const [name, setName] = useState(goal?.name ?? '')
  const [target, setTarget] = useState(goal ? goal.targetAmount.toFixed(2).replace('.', ',') : '')
  const [deadline, setDeadline] = useState(goal?.deadline ? isoDay(goal.deadline) : '')
  const [owner, setOwner] = useState('')
  const [err, setErr] = useState('')
  const go = () => {
    const t = Money.parse(target)
    if (!t) { setErr('Valor inválido. Exemplo: 6.000,00'); return }
    try { saveGoal({ id: goal?.id, name, target: t, deadline: deadline ? parseIsoDay(deadline) ?? undefined : undefined, memberId: owner || undefined }); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={goal ? 'Editar meta' : 'Nova meta'} onClose={onClose} footer={<><Button onClick={go}>Salvar</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <Field label="Nome">{(id) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      <Field label="Valor-alvo (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} />}</Field>
      <Field label="Prazo (opcional)">{(id) => <input id={id} className="field" type="date" value={deadline} onChange={(e) => setDeadline(e.target.value)} />}</Field>
      {!goal && v.hasFamily && <Field label="Meta de">{(id) => <select id={id} className="field" value={owner} onChange={(e) => setOwner(e.target.value)}><option value="">Eu / casa</option>{v.members.filter((m) => m.role === 'dependent').map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}</Field>}
      {goal && <div className="btns"><Button variant="danger" onClick={() => confirm.ask('Excluir esta meta e o histórico de aportes?', () => { deleteGoal(goal.id); onClose() })}>Excluir meta</Button></div>}
      {confirm.node}
    </Sheet>
  )
}

function ContribSheet({ goal, onClose }: { goal: Goal; onClose: () => void }) {
  const v = useView()
  const [t, setT] = useState('')
  const [acc, setAcc] = useState(v.activeAccounts[0]?.id ?? '')
  const [err, setErr] = useState('')
  const amount = Money.parse(t)
  const go = () => {
    if (!amount || !amount.gt(0)) { setErr('Informe um valor maior que zero.'); return }
    if (!acc) { setErr('Escolha a conta de origem.'); return }
    try { contributeToGoal(goal.id, amount, acc); useApp.getState().toast(`${fmtMoney(amount)} guardados em ${goal.name}.`); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={`Guardar em ${goal.name}`} onClose={onClose} short footer={<><Button onClick={go}>Guardar {amount ? fmtMoney(amount) : ''}</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <div className="chips" role="group" aria-label="Valores rápidos">{[50, 100, 200, 500].map((n) => <button key={n} type="button" className="chip" onClick={() => setT(`${n},00`)}>R$ {n}</button>)}</div>
      <Field label="Valor (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={t} onChange={(e) => setT(e.target.value)} />}</Field>
      <Field label="Tirar de">{(id) => <select id={id} className="field" value={acc} onChange={(e) => setAcc(e.target.value)}>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
    </Sheet>
  )
}

function HistorySheet({ goal, onClose }: { goal: Goal; onClose: () => void }) {
  const v = useView()
  const entries = useApp((s) => s.data.goalContributions)
  const list = C.contributionHistory(goal.id, entries)
  const proj = C.goalProjection(goal, entries, v.today)
  return (
    <Sheet title="Histórico e projeção" onClose={onClose}>
      <Group label="Projeção">
        <Row title="Ritmo (últimos 3 meses)" trailing={<span className="num">{fmtMoney(proj.averageMonthlyContribution, { hide: v.hide })}/mês</span>} />
        <Row title="Conclusão prevista" trailing={<span className="num">{proj.projectedCompletion ? cap(monthTitle(C.ymOf(proj.projectedCompletion))) : '—'}</span>} />
        {proj.onTrack !== null && <Row title="Situação" trailing={<Badge tone={proj.onTrack ? 'ok' : 'warn'}>{proj.onTrack ? 'No caminho' : 'Atrasada'}</Badge>} />}
        {proj.extraPerMonthNeeded && proj.extraPerMonthNeeded.gt(0) && <Row title="Faltam por mês" trailing={<span className="num">{fmtMoney(proj.extraPerMonthNeeded, { hide: v.hide })}</span>} />}
      </Group>
      <Group label="Aportes">
        {list.map((e) => <Row key={e.id} title={fmtDay(e.date)} sub={e.accountId ? v.lookup.accounts.get(e.accountId)?.name : undefined} trailing={<span style={{ display: 'flex', gap: 8, alignItems: 'center' }}><Amt value={e.amount} kind="balance" hide={v.hide} /><Button small variant="plain" onClick={() => revertContribution(e.id)}>Desfazer</Button></span>} />)}
        {list.length === 0 && <div className="empty"><p>Nenhum aporte registrado.</p></div>}
      </Group>
    </Sheet>
  )
}

// ---------- Mais ----------
export function MoreScreen() {
  const items: [string, string, string][] = [
    ['/dividas', 'Dívidas', 'coins'], ['/fluxo', 'Fluxo de caixa', 'arrows'], ['/relatorios', 'Relatórios', 'download'], ['/ir', 'Imposto de Renda', 'book'],
    ['/patrimonio', 'Patrimônio', 'trend'], ['/familia', 'Família', 'house'], ['/categorias', 'Categorias', 'tag'], ['/importar', 'Importar extrato', 'upload'],
  ]
  return (
    <Page title="Planejar" sub={<SubNav items={PLAN_TABS} current="/mais" />}>
      <Group label="Mais ferramentas">{items.map(([p, l, i]) => <Row key={p} icon={i} title={l} href={'#' + p} />)}</Group>
    </Page>
  )
}
