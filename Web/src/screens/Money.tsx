import { useMemo, useState } from 'react'
import * as C from '../core'
import { ASSET_CLASSES, AssetClass, Debt, Dec, Investment, Money, assetClassName, dec } from '../core'
import { UserError, positionChange, recordNetWorth, saveDebt, saveInvestment, updateQuote } from '../app/actions'
import { useView } from '../app/hooks'
import { useApp } from '../app/store'
import { cap, fmtDay, fmtMoney, fmtPercent, monthTitle, MONTHS_SHORT } from '../app/format'
import { Amt, Badge, Button, Empty, Field, Group, Icon, Row, Segmented, Sheet, SplitAmount, useConfirm } from '../ui/kit'
import { Donut, LineChart } from '../ui/charts'
import { Page, SubNav, WALLET_TABS } from '../ui/Shell'
import { navigate } from '../app/router'

const fmt2 = (d: Dec) => d.toFixed(2).replace('.', ',')

// ---------- Dívidas ----------
export function DebtsScreen() {
  const v = useView()
  const debts = useApp((s) => s.data.debts)
  const [edit, setEdit] = useState<Debt | 'new' | null>(null)
  const [sim, setSim] = useState(false)
  const total = C.sum(debts.map((d) => d.balance))
  const mins = C.sum(debts.map((d) => d.minimumPayment))
  return (
    <Page title="Dívidas" actions={<button type="button" className="icon-btn" aria-label="Voltar" onClick={() => navigate('/mais')}><Icon name="chevL" /></button>}>
      <section className="hero"><p className="hero-label">Total devido</p><SplitAmount value={total} size="large" hide={v.hide} /></section>
      {debts.length === 0 && <Empty title="Nenhuma dívida" text="Cadastre para simular a quitação." />}
      {debts.length > 0 && (
        <Group>
          {debts.map((d) => (
            <Row key={d.id} icon="coins" title={d.name} onClick={() => setEdit(d)} sub={`${fmtPercent(d.monthlyInterestRate.times(100))} ao mês · mínimo ${fmtMoney(d.minimumPayment, { hide: v.hide })}${d.dueDay ? ` · dia ${d.dueDay}` : ''}`}
              trailing={<Amt value={d.balance} kind="expense" hide={v.hide} />} />
          ))}
        </Group>
      )}
      <div className="btns">
        <Button variant="secondary" onClick={() => setEdit('new')}><Icon name="plus" />Nova dívida</Button>
        <Button onClick={() => setSim(true)} disabled={debts.length === 0}>Simular quitação</Button>
      </div>
      {edit && <DebtSheet debt={edit === 'new' ? null : edit} onClose={() => setEdit(null)} />}
      {sim && <SimulatorSheet debts={debts} suggested={mins.times(1.2)} onClose={() => setSim(false)} />}
    </Page>
  )
}

function DebtSheet({ debt, onClose }: { debt: Debt | null; onClose: () => void }) {
  const confirm = useConfirm()
  const [name, setName] = useState(debt?.name ?? '')
  const [bal, setBal] = useState(debt ? fmt2(debt.balance) : '')
  const [rate, setRate] = useState(debt ? fmt2(debt.monthlyInterestRate.times(100)) : '')
  const [min, setMin] = useState(debt ? fmt2(debt.minimumPayment) : '')
  const [day, setDay] = useState(debt?.dueDay ? String(debt.dueDay) : '')
  const [err, setErr] = useState('')
  const go = () => {
    const b = Money.parse(bal), r = Money.parse(rate || '0'), m = Money.parse(min || '0')
    if (!b || !r || !m) { setErr('Confira os valores numéricos.'); return }
    try { saveDebt({ id: debt?.id, name, balance: b, ratePercent: r, minimum: m, dueDay: day ? +day : undefined }); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={debt ? 'Editar dívida' : 'Nova dívida'} onClose={onClose} footer={<><Button onClick={go}>Salvar</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <Field label="Nome">{(id) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      <Field label="Saldo devedor (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={bal} onChange={(e) => setBal(e.target.value)} />}</Field>
      <Field label="Juros ao mês (%)">{(id) => <input id={id} className="field num" inputMode="decimal" value={rate} onChange={(e) => setRate(e.target.value)} />}</Field>
      <Field label="Pagamento mínimo (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={min} onChange={(e) => setMin(e.target.value)} />}</Field>
      <Field label="Dia do vencimento (opcional)">{(id) => <input id={id} className="field num" type="number" min={1} max={31} value={day} onChange={(e) => setDay(e.target.value)} />}</Field>
      {debt && <div className="btns"><Button variant="danger" onClick={() => confirm.ask('Excluir esta dívida?', () => { useApp.getState().del('Debt', debt.id); onClose() })}>Excluir</Button></div>}
      {confirm.node}
    </Sheet>
  )
}

function SimulatorSheet({ debts, suggested, onClose }: { debts: Debt[]; suggested: Dec; onClose: () => void }) {
  const v = useView()
  const [t, setT] = useState(fmt2(C.rounded(suggested)))
  const budget = Money.parse(t)
  const result = useMemo(() => {
    if (!budget) return { error: 'Informe um valor válido.' as string }
    try { return { cmp: C.comparePayoff(debts, budget) } } catch (e) { if (e instanceof C.FinanceError) return { error: e.message }; throw e }
  }, [debts, budget])
  const names = new Map(debts.map((d) => [d.id, d.name]))
  const today = v.today
  const card = (r: C.PayoffResult, title: string, best: boolean) => (
    <article className="panel" data-testid={`sim-${r.strategy}`} aria-label={title}>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}><h3>{title}</h3>{r.feasible && best && <Badge tone="ok">Menos juros</Badge>}{!r.feasible && <Badge tone="danger">Não quita</Badge>}</div>
      {r.feasible ? <>
        <div className="kv"><span>Prazo</span><span className="num">{r.months} {r.months === 1 ? 'mês' : 'meses'} ({cap(monthTitle(C.ymOf(C.addMonths(today, r.months))))})</span></div>
        <div className="kv"><span>Juros pagos</span><span className="num">{fmtMoney(r.totalInterest, { hide: v.hide })}</span></div>
        <div className="kv"><span>Total pago</span><span className="num">{fmtMoney(r.totalPaid, { hide: v.hide })}</span></div>
        <div className="kv"><span>Ordem</span><span className="num" style={{ textAlign: 'right' }}>{r.payoffOrder.map((id) => names.get(id)).join(' → ')}</span></div>
      </> : <p className="meta" role="alert">Com este orçamento os juros superam os pagamentos e a dívida só cresce. Aumente o valor mensal.</p>}
    </article>
  )
  return (
    <Sheet title="Simular quitação" onClose={onClose}>
      <Field label="Orçamento mensal para dívidas (R$)" hint={`Sugestão: 120% dos mínimos (${fmtMoney(C.rounded(suggested))}).`} error={'error' in result ? result.error : undefined}>
        {(id, d) => <input id={id} className="field num" inputMode="decimal" value={t} onChange={(e) => setT(e.target.value)} aria-describedby={d} data-testid="sim-budget" />}
      </Field>
      {'cmp' in result && result.cmp && (
        <>
          {card(result.cmp.avalanche, 'Avalanche (maior juros primeiro)', result.cmp.interestSavedByAvalanche.gt(0) || !result.cmp.snowball.feasible)}
          {card(result.cmp.snowball, 'Bola de neve (menor saldo primeiro)', result.cmp.interestSavedByAvalanche.lt(0))}
          {result.cmp.interestSavedByAvalanche.gt(0) && <p className="note" role="status">A avalanche economiza {fmtMoney(result.cmp.interestSavedByAvalanche)} em juros.</p>}
          <div style={{ padding: '12px 16px 0' }}>
            <LineChart desc="Saldo devedor total mês a mês: avalanche (linha contínua) e bola de neve (tracejada)"
              labels={Array.from({ length: Math.max(result.cmp.avalanche.months, result.cmp.snowball.months) }, (_, i) => String(i + 1))}
              series={[
                { name: 'Avalanche', color: 'var(--brand-primary)', points: result.cmp.avalanche.monthlyBalances.map((x) => x.toNumber()) },
                { name: 'Bola de neve', color: 'var(--cat-lazer)', dashed: true, points: result.cmp.snowball.monthlyBalances.map((x) => x.toNumber()) },
              ]} />
          </div>
        </>
      )}
    </Sheet>
  )
}

// ---------- Fluxo de caixa ----------
export function CashFlowScreen() {
  const v = useView()
  const [days, setDays] = useState<30 | 60 | 90>(30)
  const p = useMemo(() => {
    const start = C.totalBalance(v.activeAccounts, v.transactions)
    const names = Object.fromEntries(v.cards.map((c) => [c.id, c.name]))
    const dues = C.invoiceDueItems(v.activeCards.flatMap((c) => C.upcomingInvoices(c, v.transactions, v.invoices, v.today, 4)), names)
    return C.projectCashFlow(start, v.today, days, v.transactions, dues)
  }, [v.activeAccounts, v.transactions, v.invoices, v.activeCards, v.cards, v.today, days])
  const headline = p.goesNegative ? `Atenção: o saldo fica negativo em ${fmtDay(p.lowestBalanceDate!)}` : `Saldo previsto em ${days} dias: ${fmtMoney(p.endingBalance, { hide: v.hide })}`
  return (
    <Page title="Fluxo de caixa" actions={<button type="button" className="icon-btn" aria-label="Voltar" onClick={() => navigate('/mais')}><Icon name="chevL" /></button>}>
      <Segmented label="Horizonte" value={String(days) as '30'} onChange={(x) => setDays(+x as 30)} options={[{ value: '30', label: '30 dias' }, { value: '60', label: '60 dias' }, { value: '90', label: '90 dias' }]} />
      <section className="hero"><p className="hero-label">Saldo previsto</p><SplitAmount value={p.endingBalance} size="large" hide={v.hide} />
        <p className={`hero-sub ${p.goesNegative ? 'danger-text' : ''}`} role="status">{headline}</p></section>
      <div style={{ padding: '12px 16px 0' }}>
        <LineChart step desc={`Saldo projetado para ${days} dias. Menor saldo ${fmtMoney(p.lowestBalance)}.`} labels={p.points.map((x) => `${x.date.getUTCDate()}/${MONTHS_SHORT[x.date.getUTCMonth()]}`)}
          series={[{ name: 'Saldo', color: p.goesNegative ? 'var(--danger)' : 'var(--brand-primary)', points: p.points.map((x) => x.balance.toNumber()) }]} />
      </div>
      <Group label="Resumo">
        <Row title="Entradas previstas" trailing={<Amt value={p.totalIn} kind="income" hide={v.hide} />} />
        <Row title="Saídas previstas" trailing={<Amt value={p.totalOut} kind="expense" hide={v.hide} />} />
        <Row title="Menor saldo" sub={p.lowestBalanceDate ? fmtDay(p.lowestBalanceDate) : 'Hoje'} trailing={<Amt value={p.lowestBalance} kind="balance" hide={v.hide} />} />
      </Group>
      <Group label="Lançamentos previstos">
        {p.items.map((i, k) => <Row key={k} icon={i.amount.gt(0) ? 'download' : 'calendar'} title={i.label} sub={fmtDay(i.date)} trailing={<Amt value={i.amount.abs()} kind={i.amount.gt(0) ? 'income' : 'expense'} hide={v.hide} />} />)}
        {p.items.length === 0 && <div className="empty"><p>Nada previsto neste período.</p></div>}
      </Group>
    </Page>
  )
}

// ---------- Patrimônio ----------
export function NetWorthScreen() {
  const v = useView()
  const data = useApp((s) => s.data)
  const nw = useMemo(() => C.computeNetWorth(v.activeAccounts, v.transactions, data.investments, data.debts, v.cards), [v.activeAccounts, v.transactions, data.investments, data.debts, v.cards])
  const pts = C.netWorthEvolution(data.netWorthSnapshots, 12, v.month)
  const change = C.netWorthChange(pts)
  return (
    <Page title="Patrimônio" actions={<button type="button" className="icon-btn" aria-label="Voltar" onClick={() => navigate('/mais')}><Icon name="chevL" /></button>}>
      <section className="hero"><p className="hero-label">Patrimônio líquido</p><SplitAmount value={nw.netWorth} hide={v.hide} /></section>
      <Group label="Ativos" aside={fmtMoney(nw.assets, { hide: v.hide })}>
        <Row title="Contas (saldos positivos)" trailing={<Amt value={nw.accountsAssets} hide={v.hide} />} />
        <Row title="Investimentos" trailing={<Amt value={nw.investmentsValue} hide={v.hide} />} />
      </Group>
      <Group label="Passivos" aside={fmtMoney(nw.liabilities, { hide: v.hide })}>
        <Row title="Dívidas" trailing={<Amt value={nw.debts} hide={v.hide} />} />
        <Row title="Faturas e parcelas de cartão" trailing={<Amt value={nw.cardBalances} hide={v.hide} />} />
        <Row title="Saldo negativo em contas" trailing={<Amt value={nw.overdraft} hide={v.hide} />} />
      </Group>
      <div className="sec"><div className="sec-head"><h2 className="sec-title">Evolução (12 meses)</h2></div>
        {pts.some((p) => p.netWorth) ? <div style={{ padding: '0 16px' }}><LineChart desc="Evolução mensal do patrimônio líquido" labels={pts.map((p) => MONTHS_SHORT[p.month.month - 1]!)} series={[{ name: 'Patrimônio', color: 'var(--brand-primary)', points: pts.map((p) => p.netWorth?.toNumber() ?? null) }]} /></div>
          : <p className="note">Registre o patrimônio para ver a evolução mês a mês.</p>}
        {change && <p className="note">Variação no período: {fmtMoney(change, { sign: 'plus', hide: v.hide })}</p>}
      </div>
      <div className="btns"><Button onClick={recordNetWorth}>Registrar patrimônio agora</Button></div>
    </Page>
  )
}

// ---------- Investimentos ----------
const CLASS_COLOR: Record<AssetClass, string> = { fixedIncome: 'var(--cat-moradia)', stock: 'var(--cat-transporte)', reit: 'var(--cat-lazer)', crypto: 'var(--cat-mercado)' }

export function InvestmentsScreen() {
  const v = useView()
  const list = useApp((s) => s.data.investments)
  const [edit, setEdit] = useState<Investment | 'new' | null>(null)
  const [detail, setDetail] = useState<Investment | null>(null)
  const t = C.portfolioTotals(list)
  const alloc = C.allocation(list)
  return (
    <Page title="Carteira" sub={<SubNav items={WALLET_TABS} current="/investimentos" />}>
      <section className="hero"><p className="hero-label">Valor da carteira</p><SplitAmount value={t.value} size="large" hide={v.hide} />
        <p className="hero-sub">Rentabilidade simples: <strong>{fmtPercent(t.returnPercent)}</strong> ({fmtMoney(t.gain, { sign: 'plus', hide: v.hide })})</p></section>
      <div className="btns"><Button variant="secondary" small onClick={() => navigate('/patrimonio')}>Ver patrimônio</Button></div>
      {alloc.length > 0 && (
        <div className="sec"><div className="sec-head"><h2 className="sec-title">Alocação</h2></div>
          <div style={{ display: 'flex', gap: 16, alignItems: 'center', padding: '0 20px', flexWrap: 'wrap' }}>
            <Donut desc={'Alocação: ' + alloc.map((a) => `${assetClassName[a.assetClass]} ${a.percent}%`).join(', ')} slices={alloc.map((a) => ({ label: a.assetClass, value: a.value.toNumber(), color: CLASS_COLOR[a.assetClass] }))} />
            <ul className="legend" style={{ listStyle: 'none', padding: 0, flexDirection: 'column' }}>{alloc.map((a) => <li key={a.assetClass}><span style={{ ['--c' as string]: CLASS_COLOR[a.assetClass] }}><i />{assetClassName[a.assetClass]} · {fmtPercent(a.percent)}</span></li>)}</ul>
          </div></div>
      )}
      {ASSET_CLASSES.map((cls) => {
        const items = list.filter((i) => i.assetClass === cls)
        if (!items.length) return null
        return (
          <Group key={cls} label={assetClassName[cls]}>
            {items.map((i) => (
              <Row key={i.id} icon="trend" title={i.name} sub={`${i.ticker ? i.ticker + ' · ' : ''}${i.quantity.toString()} × ${fmtMoney(i.quote ?? i.averagePrice, { hide: v.hide })}`} onClick={() => setDetail(i)}
                trailing={<><Amt value={C.marketValue(i)} hide={v.hide} /><span className={`amt-sub ${C.investmentGain(i).isNegative() ? 'danger-text' : 'income'}`}>{fmtPercent(C.investmentReturn(i))}</span></>} />
            ))}
          </Group>
        )
      })}
      {list.length === 0 && <Empty title="Nenhum ativo" text="Cadastre posições de renda fixa, ações, FIIs ou cripto." />}
      <div className="btns"><Button variant="secondary" onClick={() => setEdit('new')}><Icon name="plus" />Adicionar ativo</Button></div>
      {edit && <InvestmentSheet inv={edit === 'new' ? null : edit} onClose={() => setEdit(null)} />}
      {detail && <InvestmentDetail inv={list.find((x) => x.id === detail.id) ?? detail} onClose={() => setDetail(null)} onEdit={() => { setEdit(detail); setDetail(null) }} />}
    </Page>
  )
}

function InvestmentSheet({ inv, onClose }: { inv: Investment | null; onClose: () => void }) {
  const [cls, setCls] = useState<AssetClass>(inv?.assetClass ?? 'stock')
  const [name, setName] = useState(inv?.name ?? '')
  const [ticker, setTicker] = useState(inv?.ticker ?? '')
  const [qty, setQty] = useState(inv ? inv.quantity.toString().replace('.', ',') : '')
  const [avg, setAvg] = useState(inv ? fmt2(inv.averagePrice) : '')
  const [quote, setQuote] = useState(inv?.quote ? fmt2(inv.quote) : '')
  const [err, setErr] = useState('')
  const fixed = cls === 'fixedIncome'
  const go = () => {
    const q = fixed ? dec(1) : Money.parse(qty), a = Money.parse(avg), c = quote.trim() ? Money.parse(quote) : null
    if (!q || !a || (quote.trim() && !c)) { setErr('Confira os valores numéricos.'); return }
    try { saveInvestment({ id: inv?.id, name, ticker: ticker || undefined, assetClass: cls, quantity: q, averagePrice: a, quote: c ?? undefined }); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={inv ? 'Editar ativo' : 'Adicionar ativo'} onClose={onClose} footer={<><Button onClick={go}>Salvar</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <Field label="Classe">{(id) => <select id={id} className="field" value={cls} onChange={(e) => setCls(e.target.value as AssetClass)}>{ASSET_CLASSES.map((c) => <option key={c} value={c}>{assetClassName[c]}</option>)}</select>}</Field>
      <Field label="Nome">{(id) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      {!fixed && <Field label="Código (opcional)">{(id) => <input id={id} className="field" value={ticker} onChange={(e) => setTicker(e.target.value)} />}</Field>}
      {!fixed && <Field label="Quantidade">{(id) => <input id={id} className="field num" inputMode="decimal" value={qty} onChange={(e) => setQty(e.target.value)} />}</Field>}
      <Field label={fixed ? 'Valor aplicado (R$)' : 'Preço médio (R$)'}>{(id) => <input id={id} className="field num" inputMode="decimal" value={avg} onChange={(e) => setAvg(e.target.value)} />}</Field>
      <Field label={fixed ? 'Valor atual (R$)' : 'Cotação atual (R$)'}>{(id) => <input id={id} className="field num" inputMode="decimal" value={quote} onChange={(e) => setQuote(e.target.value)} />}</Field>
    </Sheet>
  )
}

function InvestmentDetail({ inv, onClose, onEdit }: { inv: Investment; onClose: () => void; onEdit: () => void }) {
  const v = useView()
  const confirm = useConfirm()
  const [mode, setMode] = useState<'quote' | 'buy' | 'sell' | null>(null)
  const [q, setQ] = useState(''), [p, setP] = useState('')
  const [err, setErr] = useState('')
  const apply = () => {
    try {
      if (mode === 'quote') { const n = Money.parse(q); if (!n) throw new UserError('Valor inválido.'); updateQuote(inv.id, n) }
      else { const qq = Money.parse(q), pp = Money.parse(p); if (!qq || !pp) throw new UserError('Confira os valores.'); positionChange(inv.id, mode!, qq, pp) }
      setMode(null); setQ(''); setP(''); setErr('')
    } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={inv.name} onClose={onClose}>
      <Group>
        <Row title="Custo" trailing={<Amt value={C.investmentCost(inv)} hide={v.hide} />} />
        <Row title="Valor atual" trailing={<Amt value={C.marketValue(inv)} hide={v.hide} />} />
        <Row title="Ganho" trailing={<Amt value={C.investmentGain(inv)} kind="balance" hide={v.hide} />} />
        <Row title="Rentabilidade" trailing={<span className="num">{fmtPercent(C.investmentReturn(inv))}</span>} />
        <Row title="Lucro realizado" trailing={<Amt value={inv.realizedProfit} kind="balance" hide={v.hide} />} />
      </Group>
      <div className="btns">
        <Button variant="secondary" small onClick={() => setMode('quote')}>Atualizar cotação</Button>
        <Button variant="secondary" small onClick={() => setMode('buy')}>Comprar mais</Button>
        <Button variant="secondary" small onClick={() => setMode('sell')}>Vender</Button>
        <Button variant="plain" small onClick={onEdit}>Editar</Button>
        <Button variant="danger" small onClick={() => confirm.ask('Excluir este ativo?', () => { useApp.getState().del('Investment', inv.id); onClose() })}>Excluir</Button>
      </div>
      {mode && (
        <div>
          <Field label={mode === 'quote' ? 'Nova cotação (R$)' : 'Quantidade'}>{(id) => <input id={id} className="field num" inputMode="decimal" value={q} onChange={(e) => setQ(e.target.value)} />}</Field>
          {mode !== 'quote' && <Field label="Preço unitário (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={p} onChange={(e) => setP(e.target.value)} />}</Field>}
          {err && <p className="error" role="alert" style={{ padding: '0 20px' }}>{err}</p>}
          <div className="btns"><Button onClick={apply}>Confirmar</Button></div>
        </div>
      )}
      {confirm.node}
    </Sheet>
  )
}
