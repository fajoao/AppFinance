import { useMemo, useState } from 'react'
import * as C from '../core'
import { ACCOUNT_TYPES, Account, AccountType, CreditCard, Dec, Money, YearMonth, ZERO, accountTypeName } from '../core'
import { UserError, archiveAccount, archiveCard, payInvoice, reconcileAccount, saveAccount, saveCard } from '../app/actions'
import { useView } from '../app/hooks'
import { fmtDay, fmtDayShort, fmtMoney, monthTitle, cap } from '../app/format'
import { Amt, Badge, Bar, Button, Empty, Field, Group, Icon, Row, Segmented, Sheet, SplitAmount } from '../ui/kit'
import { Page, SubNav, WALLET_TABS } from '../ui/Shell'
import { navigate } from '../app/router'
import { useApp } from '../app/store'
import { catColorVar, categoryName, webIcon } from '../app/logic'

const parseMoney = (t: string, allowEmpty = true): Dec | null => (t.trim() === '' ? (allowEmpty ? ZERO : null) : Money.parse(t))

export function AccountsScreen() {
  const v = useView()
  const [edit, setEdit] = useState<Account | 'new' | null>(null)
  const [rec, setRec] = useState<Account | null>(null)
  const balances = useMemo(() => new Map(v.activeAccounts.map((a) => [a.id, C.balanceOf(a, v.transactions)])), [v.activeAccounts, v.transactions])
  const total = C.sum([...balances.values()])
  return (
    <Page title="Carteira" sub={<SubNav items={WALLET_TABS} current="/contas" />}>
      <section className="hero"><p className="hero-label">Patrimônio em contas</p><SplitAmount value={total} size="large" hide={v.hide} /></section>
      {ACCOUNT_TYPES.map((type) => {
        const list = v.activeAccounts.filter((a) => a.type === type)
        if (!list.length) return null
        const sub = C.sum(list.map((a) => balances.get(a.id)!))
        return (
          <Group key={type} label={accountTypeName[type]} aside={fmtMoney(sub, { hide: v.hide })}>
            {list.map((a) => (
              <Row key={a.id} icon={type === 'wallet' ? 'cash' : type === 'investment' ? 'trend' : type === 'savings' ? 'coins' : 'bank'} title={a.name}
                sub={a.visibility === 'private' ? 'Privada' : 'Saldo atual'} onClick={() => setEdit(a)}
                trailing={<Amt value={balances.get(a.id)!} kind="balance" hide={v.hide} />} />
            ))}
          </Group>
        )
      })}
      {v.activeAccounts.length === 0 && <Empty title="Nenhuma conta" text="Adicione sua primeira conta." />}
      <div className="btns"><Button variant="secondary" onClick={() => setEdit('new')}><Icon name="plus" />Nova conta</Button></div>
      {edit && <AccountSheet account={edit === 'new' ? null : edit} balance={edit === 'new' ? ZERO : balances.get(edit.id)!} onClose={() => setEdit(null)} onReconcile={(a) => { setEdit(null); setRec(a) }} />}
      {rec && <ReconcileSheet account={rec} onClose={() => setRec(null)} />}
    </Page>
  )
}

function AccountSheet({ account, balance, onClose, onReconcile }: { account: Account | null; balance: Dec; onClose: () => void; onReconcile: (a: Account) => void }) {
  const v = useView()
  const [name, setName] = useState(account?.name ?? '')
  const [type, setType] = useState<AccountType>(account?.type ?? 'checking')
  const [bal, setBal] = useState('')
  const [vis, setVis] = useState<C.Visibility>(account?.visibility ?? 'shared')
  const [err, setErr] = useState('')
  const save = () => {
    const b = parseMoney(bal)
    if (!account && !b) { setErr('Saldo inválido. Exemplo: 1.234,56'); return }
    try { saveAccount({ id: account?.id, name, type, balance: b ?? ZERO, visibility: vis }); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={account ? 'Editar conta' : 'Nova conta'} onClose={onClose} footer={<Button onClick={save}>Salvar</Button>}>
      <Field label="Nome" error={err}>{(id, d) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} aria-describedby={d} aria-invalid={!!err} />}</Field>
      <Field label="Tipo">{(id) => <select id={id} className="field" value={type} onChange={(e) => setType(e.target.value as AccountType)}>{ACCOUNT_TYPES.map((t) => <option key={t} value={t}>{accountTypeName[t]}</option>)}</select>}</Field>
      {!account && <Field label="Saldo de hoje (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={bal} placeholder="0,00" onChange={(e) => setBal(e.target.value)} />}</Field>}
      {v.hasFamily && <><div className="field-wrap"><span className="field-label">Visibilidade</span></div><Segmented label="Visibilidade" value={vis} onChange={setVis} options={[{ value: 'shared', label: 'Compartilhada' }, { value: 'private', label: 'Privada' }]} /></>}
      {account && (
        <div className="btns">
          <Button variant="secondary" onClick={() => onReconcile(account)}>Conciliar saldo ({fmtMoney(balance, { hide: v.hide })})</Button>
          <Button variant="danger" onClick={() => { archiveAccount(account.id); onClose() }}>Arquivar conta</Button>
        </div>
      )}
    </Sheet>
  )
}

function ReconcileSheet({ account, onClose }: { account: Account; onClose: () => void }) {
  const [t, setT] = useState('')
  const [err, setErr] = useState('')
  const go = () => { const n = Money.parse(t); if (!n) { setErr('Valor inválido.'); return } reconcileAccount(account, n); onClose() }
  return (
    <Sheet title="Conciliar saldo" onClose={onClose} short footer={<Button onClick={go}>Conciliar</Button>}>
      <Field label="Saldo no extrato do banco (R$)" error={err} hint="O app lança um ajuste com a diferença.">{(id, d) => <input id={id} className="field num" inputMode="decimal" value={t} onChange={(e) => setT(e.target.value)} aria-describedby={d} />}</Field>
    </Sheet>
  )
}

export function CardsScreen() {
  const v = useView()
  const [edit, setEdit] = useState<CreditCard | 'new' | null>(null)
  return (
    <Page title="Carteira" sub={<SubNav items={WALLET_TABS} current="/cartoes" />}>
      {v.activeCards.length === 0 && <Empty title="Nenhum cartão" text="Cadastre um cartão para acompanhar fatura e limite." />}
      {v.activeCards.map((card) => {
        const ups = C.upcomingInvoices(card, v.transactions, v.invoices, v.today, 1)
        const cur = ups.find((s) => C.ymEq(s.invoice.month, C.currentInvoiceMonth(card, v.today))) ?? ups[0]!
        const used = C.usedLimit(card, v.transactions)
        const frac = card.limit.gt(0) ? used.div(card.limit).toNumber() : 0
        return (
          <article key={card.id} className="panel" aria-label={card.name}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <span className="plastic" aria-hidden="true" />
              <div style={{ flex: 1 }}><h3>{card.name}</h3><p className="meta">Fecha dia {card.closingDay}, vence dia {card.dueDay}</p></div>
              <StatusBadge status={cur.status} />
            </div>
            <div style={{ marginTop: 14 }}><SplitAmount value={cur.total.minus(cur.paidAmount).lt(0) ? ZERO : cur.total.minus(cur.paidAmount)} size="large" hide={v.hide} /></div>
            <p className="meta">Fatura de {C.ymLabel(cur.invoice.month)} · vence {fmtDayShort(cur.invoice.dueDate)}</p>
            <div style={{ marginTop: 12 }}><Bar fraction={frac} color={frac >= 1 ? 'var(--danger)' : frac >= 0.8 ? 'var(--warning-fill)' : undefined} label={`Limite usado ${(frac * 100).toFixed(0)}%`} /></div>
            <div className="kv"><span>Limite disponível</span><span className="num">{fmtMoney(card.limit.minus(used), { hide: v.hide })}</span></div>
            <div className="kv"><span>Limite total</span><span className="num">{fmtMoney(card.limit, { hide: v.hide })}</span></div>
            <div className="row-actions">
              <Button variant="secondary" small onClick={() => navigate(`/cartoes/${card.id}`)}>Ver fatura</Button>
              <Button small onClick={() => navigate(`/cartoes/${card.id}?pagar=1`)} disabled={cur.remaining.lte(0)}>Pagar fatura</Button>
              <Button variant="plain" small onClick={() => setEdit(card)}>Editar</Button>
            </div>
          </article>
        )
      })}
      <div className="btns"><Button variant="secondary" onClick={() => setEdit('new')}><Icon name="plus" />Novo cartão</Button></div>
      {edit && <CardSheet card={edit === 'new' ? null : edit} onClose={() => setEdit(null)} />}
    </Page>
  )
}

function StatusBadge({ status }: { status: C.InvoiceStatus }) {
  const m = { open: ['neutral', 'Aberta'], closed: ['warn', 'Fechada'], paid: ['ok', 'Paga'], overdue: ['danger', 'Atrasada'] } as const
  return <Badge tone={m[status][0]}>{m[status][1]}</Badge>
}

function CardSheet({ card, onClose }: { card: CreditCard | null; onClose: () => void }) {
  const v = useView()
  const [name, setName] = useState(card?.name ?? '')
  const [limit, setLimit] = useState(card ? card.limit.toFixed(2).replace('.', ',') : '')
  const [closing, setClosing] = useState(String(card?.closingDay ?? 5))
  const [due, setDue] = useState(String(card?.dueDay ?? 12))
  const [acc, setAcc] = useState(card?.paymentAccountId ?? '')
  const [err, setErr] = useState('')
  const save = () => {
    const l = Money.parse(limit)
    if (!l) { setErr('Limite inválido. Exemplo: 5.000,00'); return }
    try { saveCard({ id: card?.id, name, limit: l, closingDay: +closing, dueDay: +due, paymentAccountId: acc || undefined }); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title={card ? 'Editar cartão' : 'Novo cartão'} onClose={onClose} footer={<><Button onClick={save}>Salvar</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <Field label="Nome">{(id) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      <Field label="Limite (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={limit} onChange={(e) => setLimit(e.target.value)} />}</Field>
      <div className="field-wrap field-row" style={{ padding: '0 20px' }}>
        <Field label="Dia do fechamento">{(id) => <input id={id} className="field num" type="number" min={1} max={31} value={closing} onChange={(e) => setClosing(e.target.value)} />}</Field>
        <Field label="Dia do vencimento">{(id) => <input id={id} className="field num" type="number" min={1} max={31} value={due} onChange={(e) => setDue(e.target.value)} />}</Field>
      </div>
      <Field label="Conta para pagar a fatura">{(id) => <select id={id} className="field" value={acc} onChange={(e) => setAcc(e.target.value)}><option value="">Escolher no pagamento</option>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
      {card && <div className="btns"><Button variant="danger" onClick={() => { archiveCard(card.id); onClose() }}>Arquivar cartão</Button></div>}
    </Sheet>
  )
}

export function CardDetail({ id }: { id: string }) {
  const v = useView()
  const card = v.cards.find((c) => c.id === id)
  const [sel, setSel] = useState<number | null>(null)
  const [pay, setPay] = useState(() => location.hash.includes('pagar=1'))
  const ups = useMemo(() => (card ? C.upcomingInvoices(card, v.transactions, v.invoices, v.today, 3) : []), [card, v.transactions, v.invoices, v.today])
  if (!card) return <Page title="Cartão"><Empty title="Cartão não encontrado" action={<Button small onClick={() => navigate('/cartoes')}>Voltar</Button>} /></Page>
  const curIdx = ups.findIndex((s) => C.ymEq(s.invoice.month, C.currentInvoiceMonth(card, v.today)))
  const s = ups[sel ?? curIdx] ?? ups[0]!
  const byId = new Map(v.categories.map((c) => [c.id, c]))
  return (
    <Page title={card.name} actions={<button type="button" className="icon-btn" aria-label="Voltar aos cartões" onClick={() => navigate('/cartoes')}><Icon name="chevL" /></button>}>
      <div className="chips" role="tablist" aria-label="Faturas">
        {ups.map((u, i) => (
          <button key={i} type="button" role="tab" className="chip" aria-selected={u === s} aria-pressed={u === s} onClick={() => setSel(i)}>{cap(monthTitle(u.invoice.month).replace(/ de /, ' '))}</button>
        ))}
      </div>
      <section className="panel" aria-label="Fatura selecionada">
        <div style={{ display: 'flex', justifyContent: 'space-between' }}><h3>Fatura {C.ymLabel(s.invoice.month)}</h3><StatusBadge status={s.status} /></div>
        <div style={{ marginTop: 10 }}><SplitAmount value={s.total} size="large" hide={v.hide} /></div>
        <p className="meta">Fecha {fmtDay(s.invoice.closingDate)} · vence {fmtDay(s.invoice.dueDate)}</p>
        {s.paidAmount.gt(0) && <div className="kv"><span>Já pago</span><span className="num">{fmtMoney(s.paidAmount, { hide: v.hide })}</span></div>}
        <div className="row-actions"><Button disabled={s.remaining.lte(0)} onClick={() => setPay(true)}>Pagar fatura</Button></div>
      </section>
      <Group label="Compras da fatura">
        {s.transactions.map((t) => (
          <Row key={t.id} icon={webIcon(byId.get(t.categoryId ?? '')?.icon)} color={catColorVar(byId.get(t.categoryId ?? ''), byId)} title={t.title} sub={`${fmtDayShort(t.date)} · ${categoryName(v.lookup, t.categoryId)}`}
            trailing={<Amt value={t.amount} kind={t.type === 'income' ? 'income' : 'expense'} hide={v.hide} />} />
        ))}
        {s.transactions.length === 0 && <div className="empty"><p>Nenhuma compra nesta fatura.</p></div>}
      </Group>
      {pay && <PaySheet card={card} month={s.invoice.month} remaining={s.remaining} total={s.total} onClose={() => { setPay(false); if (location.hash.includes('pagar=1')) navigate(`/cartoes/${card.id}`, true) }} />}
    </Page>
  )
}

function PaySheet({ card, month, remaining, total, onClose }: { card: CreditCard; month: YearMonth; remaining: Dec; total: Dec; onClose: () => void }) {
  const v = useView()
  const toast = useApp((s) => s.toast)
  const min = C.rounded(total.times(0.15))
  const [opt, setOpt] = useState<'total' | 'min' | 'other'>('total')
  const [other, setOther] = useState('')
  const [acc, setAcc] = useState(card.paymentAccountId ?? v.activeAccounts[0]?.id ?? '')
  const [err, setErr] = useState('')
  const amount = opt === 'total' ? remaining : opt === 'min' ? C.dmin(min, remaining) : Money.parse(other)
  const bal = acc ? C.balanceOf(v.activeAccounts.find((a) => a.id === acc)!, v.transactions) : ZERO
  const insufficient = !!amount && amount.gt(bal)
  const go = () => {
    if (!amount || !amount.gt(0)) { setErr('Informe um valor válido.'); return }
    if (!acc) { setErr('Escolha a conta de origem.'); return }
    try { payInvoice(card, month, amount, acc); toast(`Fatura paga: ${fmtMoney(amount)}`); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title="Pagar fatura" onClose={onClose} footer={<><Button onClick={go} disabled={!amount}>Pagar {amount ? fmtMoney(amount) : ''}</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <div className="hero"><p className="hero-label">Total em aberto</p><SplitAmount value={remaining} size="large" /></div>
      <Group label="Quanto pagar">
        <button type="button" role="radio" aria-checked={opt === 'total'} className="row" onClick={() => setOpt('total')}><span className="radio-mark" /><span className="main"><span className="t1">Valor total</span></span><span className="num">{fmtMoney(remaining)}</span></button>
        <button type="button" role="radio" aria-checked={opt === 'min'} className="row" onClick={() => setOpt('min')}><span className="radio-mark" /><span className="main"><span className="t1">Mínimo (15%)</span><span className="t2" style={{ display: 'block' }}>O restante entra no rotativo, com juros altos.</span></span><span className="num">{fmtMoney(C.dmin(min, remaining))}</span></button>
        <button type="button" role="radio" aria-checked={opt === 'other'} className="row" onClick={() => setOpt('other')}><span className="radio-mark" /><span className="main"><span className="t1">Outro valor</span></span></button>
      </Group>
      {opt === 'other' && <Field label="Valor (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={other} onChange={(e) => setOther(e.target.value)} />}</Field>}
      <Field label="Pagar com">{(id) => <select id={id} className="field" value={acc} onChange={(e) => setAcc(e.target.value)}>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name} · {fmtMoney(C.balanceOf(a, v.transactions), { hide: v.hide })}</option>)}</select>}</Field>
      {insufficient && <p className="note warn-text" role="status">Saldo insuficiente nesta conta ({fmtMoney(bal)}). O pagamento ainda pode ser registrado.</p>}
    </Sheet>
  )
}
