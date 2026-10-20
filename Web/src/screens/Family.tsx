import { useState } from 'react'
import * as C from '../core'
import { FamilyMember, MemberRole, Money, roleName } from '../core'
import {
  UserError, addMember, changeMemberRole, createAllowance, createFamily, createSplit, decideApproval, removeMember, setMemberLimit, settleTransfer,
} from '../app/actions'
import { householdApi, errorText } from '../app/api'
import { useView } from '../app/hooks'
import { useApp } from '../app/store'
import { fmtDay, fmtMoney, monthTitle } from '../app/format'
import { Amt, Badge, Button, Chip, Empty, Field, Group, Icon, Row, Segmented, Sheet, useConfirm } from '../ui/kit'
import { Page } from '../ui/Shell'
import { navigate } from '../app/router'

type Tab = 'pessoas' | 'acerto' | 'mesada' | 'aprovacoes'

export function FamilyScreen() {
  const v = useView()
  const data = useApp((s) => s.data)
  const setSettings = useApp((s) => s.setSettings)
  const settings = useApp((s) => s.settings)
  const [tab, setTab] = useState<Tab>('pessoas')
  const back = <button type="button" className="icon-btn" aria-label="Voltar" onClick={() => navigate('/mais')}><Icon name="chevL" /></button>
  if (!v.hasFamily) return <Page title="Família" actions={back}><SetupForm /></Page>
  const house = data.households[0]
  const pending = C.pendingApprovals(data.approvalRequests)
  return (
    <Page title={house?.name ?? 'Família'} actions={back}>
      <div className="field-row" style={{ padding: '8px 20px 0' }}>
        <Field label="Perfil ativo">{(id) => <select id={id} className="field" value={v.me?.id ?? ''} onChange={(e) => setSettings({ activeMemberId: e.target.value })}>{v.members.map((m) => <option key={m.id} value={m.id}>{m.name} ({roleName[m.role]})</option>)}</select>}</Field>
        <Field label="Visão">{(id) => <select id={id} className="field" disabled={v.me?.role === 'dependent'} value={v.me?.role === 'dependent' ? 'individual' : settings.scope} onChange={(e) => setSettings({ scope: e.target.value as 'family' | 'individual' })}><option value="family">Família (compartilhado)</option><option value="individual">Individual</option></select>}</Field>
      </div>
      <Segmented label="Seção" value={tab} onChange={setTab} options={[{ value: 'pessoas', label: 'Pessoas' }, { value: 'acerto', label: 'Acerto' }, { value: 'mesada', label: 'Mesada' }, { value: 'aprovacoes', label: `Aprovações${pending.length ? ` (${pending.length})` : ''}` }]} />
      {tab === 'pessoas' && <People />}
      {tab === 'acerto' && <Settle />}
      {tab === 'mesada' && <Allowances />}
      {tab === 'aprovacoes' && <Approvals />}
    </Page>
  )
}

function SetupForm() {
  const [name, setName] = useState('')
  const [me, setMe] = useState(useApp.getState().session?.user.name ?? '')
  const [err, setErr] = useState('')
  return (
    <>
      <Empty title="Crie o grupo da família" text="Divida despesas, defina mesadas e limites para dependentes." />
      <Field label="Nome da família">{(id) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      <Field label="Seu nome" error={err}>{(id, d) => <input id={id} className="field" value={me} onChange={(e) => setMe(e.target.value)} aria-describedby={d} />}</Field>
      <div className="btns"><Button onClick={() => { try { createFamily(name, me) } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e } }}>Criar família</Button></div>
    </>
  )
}

function People() {
  const v = useView()
  const session = useApp((s) => s.session)
  const [add, setAdd] = useState(false)
  const [detail, setDetail] = useState<FamilyMember | null>(null)
  const [invite, setInvite] = useState<string>('')
  const [join, setJoin] = useState('')
  const [msg, setMsg] = useState('')
  const month = C.ymOf(v.today)
  const doInvite = async (role: 'member' | 'dependent') => {
    try { const r = await householdApi.invite(session!.accessToken, role); setInvite(`${r.code} (válido por 48 h)`); setMsg('') } catch (e) { setMsg(errorText(e)) }
  }
  const doJoin = async () => {
    try { await householdApi.join(session!.accessToken, join.trim()); setMsg('Você entrou na família. Atualize para sincronizar os dados.'); setJoin('') } catch (e) { setMsg(errorText(e)) }
  }
  return (
    <>
      <Group label="Pessoas">
        {v.members.map((m) => (
          <Row key={m.id} icon="house" title={m.name} sub={`${roleName[m.role]} · gasto no mês ${fmtMoney(C.memberSpent(m.id, month, v.transactions), { hide: v.hide })}${m.monthlySpendingLimit ? ` de ${fmtMoney(m.monthlySpendingLimit, { hide: v.hide })}` : ''}`} onClick={() => setDetail(m)} />
        ))}
      </Group>
      <div className="btns"><Button variant="secondary" onClick={() => setAdd(true)} disabled={!C.can(v.me?.role ?? 'member', 'manageMembers')}><Icon name="plus" />Adicionar pessoa</Button></div>
      {session && (
        <Group label="Convidar para a conta (outro dispositivo)">
          <div className="row wrap-text" style={{ flexWrap: 'wrap', gap: 8 }}>
            <Button small variant="secondary" onClick={() => void doInvite('member')}>Convite de membro</Button>
            <Button small variant="secondary" onClick={() => void doInvite('dependent')}>Convite de dependente</Button>
          </div>
          {invite && <Row title="Código do convite" sub={invite} />}
          <div className="row"><input className="field" aria-label="Código de convite" placeholder="Tenho um código: K7QM-X2PD" value={join} onChange={(e) => setJoin(e.target.value)} /><Button small onClick={() => void doJoin()} disabled={!join.trim()}>Entrar</Button></div>
        </Group>
      )}
      {msg && <p className="note" role="status">{msg}</p>}
      {add && <AddMember onClose={() => setAdd(false)} />}
      {detail && <MemberDetail m={v.members.find((x) => x.id === detail.id) ?? detail} onClose={() => setDetail(null)} />}
    </>
  )
}

function AddMember({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('')
  const [role, setRole] = useState<MemberRole>('member')
  const [limit, setLimit] = useState('')
  const [err, setErr] = useState('')
  const go = () => {
    const l = limit.trim() ? Money.parse(limit) : undefined
    if (limit.trim() && !l) { setErr('Limite inválido.'); return }
    try { addMember(name, role, l ?? undefined); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title="Adicionar pessoa" onClose={onClose} footer={<Button onClick={go}>Adicionar</Button>}>
      <Field label="Nome" error={err}>{(id, d) => <input id={id} className="field" value={name} onChange={(e) => setName(e.target.value)} aria-describedby={d} />}</Field>
      <Field label="Papel">{(id) => <select id={id} className="field" value={role} onChange={(e) => setRole(e.target.value as MemberRole)}>{(['admin', 'member', 'dependent'] as MemberRole[]).map((r) => <option key={r} value={r}>{roleName[r]}</option>)}</select>}</Field>
      {role === 'dependent' && <Field label="Limite mensal de gastos (R$)" hint="Acima do limite, o gasto vira pedido de aprovação.">{(id, d) => <input id={id} className="field num" inputMode="decimal" value={limit} onChange={(e) => setLimit(e.target.value)} aria-describedby={d} />}</Field>}
    </Sheet>
  )
}

function MemberDetail({ m, onClose }: { m: FamilyMember; onClose: () => void }) {
  const v = useView()
  const confirm = useConfirm()
  const [limit, setLimit] = useState(m.monthlySpendingLimit ? m.monthlySpendingLimit.toFixed(2).replace('.', ',') : '')
  const [err, setErr] = useState('')
  const run = (f: () => void) => { try { f(); setErr('') } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e } }
  return (
    <Sheet title={m.name} onClose={onClose}>
      <Group>
        <Row title="Papel" trailing={<select aria-label="Papel" className="field" style={{ width: 'auto' }} value={m.role} onChange={(e) => run(() => changeMemberRole(m, e.target.value as MemberRole))}>{(['admin', 'member', 'dependent'] as MemberRole[]).map((r) => <option key={r} value={r}>{roleName[r]}</option>)}</select>} />
        <Row title="Gasto no mês" trailing={<span className="num">{fmtMoney(C.memberSpent(m.id, C.ymOf(v.today), v.transactions), { hide: v.hide })}</span>} />
      </Group>
      {m.role === 'dependent' && <Field label="Limite mensal (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={limit} onChange={(e) => setLimit(e.target.value)} onBlur={() => run(() => setMemberLimit(m, limit.trim() ? Money.parse(limit) ?? undefined : undefined))} />}</Field>}
      {err && <p className="error" role="alert" style={{ padding: '0 20px' }}>{err}</p>}
      <div className="btns">
        <Button variant="secondary" onClick={() => { useApp.getState().setSettings({ activeMemberId: m.id }); onClose() }}>Usar este perfil</Button>
        <Button variant="danger" onClick={() => confirm.ask(`Remover ${m.name}?`, () => run(() => { removeMember(m); onClose() }))}>Remover</Button>
      </div>
      {confirm.node}
    </Sheet>
  )
}

function Settle() {
  const v = useView()
  const data = useApp((s) => s.data)
  const [open, setOpen] = useState(false)
  const bal = C.settlementBalances(data.expenseSplits, data.splitSettlements)
  const plan = C.settlementPlan(data.expenseSplits, data.splitSettlements)
  const name = (id: string) => v.lookup.members.get(id)?.name ?? 'Alguém'
  return (
    <>
      <Group label="Saldo de cada pessoa">
        {v.members.map((m) => <Row key={m.id} title={m.name} sub={(bal.get(m.id) ?? C.ZERO).gt(0) ? 'Tem a receber' : (bal.get(m.id) ?? C.ZERO).lt(0) ? 'Deve' : 'Quite'} trailing={<Amt value={bal.get(m.id) ?? C.ZERO} kind="balance" hide={v.hide} />} />)}
      </Group>
      <Group label="Para zerar as contas">
        {plan.map((t, i) => <Row key={i} icon="arrows" title={`${name(t.from)} paga a ${name(t.to)}`} trailing={<span style={{ display: 'flex', gap: 8, alignItems: 'center' }}><Amt value={t.amount} hide={v.hide} /><Button small variant="secondary" onClick={() => settleTransfer(t)}>Paguei</Button></span>} />)}
        {plan.length === 0 && <div className="empty"><p>Tudo certo, ninguém deve nada.</p></div>}
      </Group>
      <Group label="Despesas divididas">
        {data.expenseSplits.map((s) => <Row key={s.id} title={s.title} sub={`${fmtDay(s.date)} · pago por ${name(s.paidBy)} · ${s.mode === 'equal' ? 'igual' : 'percentual'}`} trailing={<Amt value={s.total} kind="expense" hide={v.hide} />} />)}
      </Group>
      <div className="btns"><Button onClick={() => setOpen(true)}>Dividir uma despesa</Button></div>
      {open && <SplitSheet onClose={() => setOpen(false)} />}
    </>
  )
}

function SplitSheet({ onClose }: { onClose: () => void }) {
  const v = useView()
  const [title, setTitle] = useState('')
  const [total, setTotal] = useState('')
  const [paidBy, setPaidBy] = useState(v.me?.id ?? v.members[0]?.id ?? '')
  const [parts, setParts] = useState<Set<string>>(new Set(v.members.map((m) => m.id)))
  const [mode, setMode] = useState<C.SplitMode>('equal')
  const [pct, setPct] = useState<Record<string, string>>({})
  const [acc, setAcc] = useState('')
  const [err, setErr] = useState('')
  const t = Money.parse(total)
  const ids = [...parts]
  let preview: C.Dec[] | null = null
  try {
    if (t && t.gt(0) && ids.length) {
      preview = mode === 'equal' ? C.Money.split(t, ids.length) : C.makeSplit({ title: 'x', total: t, date: v.today, paidBy, participants: ids, mode, percentages: Object.fromEntries(ids.map((i) => [i, Money.parse(pct[i] ?? '') ?? C.dec(-1)])) }).shares.map((s) => s.amount)
    }
  } catch { preview = null }
  const go = () => {
    if (!t) { setErr('Valor inválido.'); return }
    try {
      createSplit({ title: title.trim() || 'Despesa dividida', total: t, date: v.today, paidBy, participants: ids, mode, percentages: Object.fromEntries(ids.map((i) => [i, Money.parse(pct[i] ?? '') ?? C.dec(-1)])) }, acc ? { accountId: acc } : null)
      onClose()
    } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title="Dividir despesa" onClose={onClose} footer={<><Button onClick={go}>Dividir</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      <Field label="Descrição">{(id) => <input id={id} className="field" value={title} onChange={(e) => setTitle(e.target.value)} />}</Field>
      <Field label="Valor total (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} />}</Field>
      <Field label="Quem pagou">{(id) => <select id={id} className="field" value={paidBy} onChange={(e) => setPaidBy(e.target.value)}>{v.members.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}</Field>
      <div className="field-wrap"><span className="field-label">Quem divide</span></div>
      <div className="chips wrap" role="group" aria-label="Participantes">{v.members.map((m) => <Chip key={m.id} pressed={parts.has(m.id)} onClick={() => { const n = new Set(parts); n.has(m.id) ? n.delete(m.id) : n.add(m.id); setParts(n) }}>{m.name}</Chip>)}</div>
      <Segmented label="Modo" value={mode} onChange={setMode} options={[{ value: 'equal', label: 'Igual' }, { value: 'percentage', label: 'Percentual' }]} />
      {ids.map((i, k) => (
        <div key={i} className="row">
          <span className="main"><span className="t1">{v.lookup.members.get(i)?.name}</span></span>
          {mode === 'percentage' && <input aria-label={`Percentual de ${v.lookup.members.get(i)?.name}`} className="field num" style={{ width: 90 }} inputMode="decimal" placeholder="%" value={pct[i] ?? ''} onChange={(e) => setPct({ ...pct, [i]: e.target.value })} />}
          <span className="num">{preview ? fmtMoney(preview[k]!) : '—'}</span>
        </div>
      ))}
      <Field label="Lançar também como despesa na conta (opcional)">{(id) => <select id={id} className="field" value={acc} onChange={(e) => setAcc(e.target.value)}><option value="">Não lançar</option>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
    </Sheet>
  )
}

function Allowances() {
  const v = useView()
  const list = useApp((s) => s.data.allowances)
  const [open, setOpen] = useState(false)
  return (
    <>
      <Group label="Mesadas">
        {list.map((a) => <Row key={a.id} icon="coins" title={`${v.lookup.members.get(a.memberId)?.name ?? 'Dependente'} · dia ${a.dayOfMonth}`} sub={`${v.lookup.accounts.get(a.fromAccountId)?.name ?? '?'} → ${v.lookup.accounts.get(a.toAccountId)?.name ?? '?'}${a.lastPaidMonth ? ` · pago até ${C.ymLabel(a.lastPaidMonth)}` : ''}`} trailing={<Amt value={a.amount} hide={v.hide} />} />)}
        {list.length === 0 && <div className="empty"><p>Nenhuma mesada.</p></div>}
      </Group>
      <div className="btns"><Button variant="secondary" onClick={() => setOpen(true)} disabled={!C.can(v.me?.role ?? 'member', 'manageAllowances')}>Nova mesada</Button></div>
      {open && <AllowanceSheet onClose={() => setOpen(false)} />}
    </>
  )
}
function AllowanceSheet({ onClose }: { onClose: () => void }) {
  const v = useView()
  const deps = v.members.filter((m) => m.role === 'dependent')
  const [member, setMember] = useState(deps[0]?.id ?? '')
  const [amount, setAmount] = useState('')
  const [day, setDay] = useState('5')
  const [from, setFrom] = useState(v.activeAccounts[0]?.id ?? '')
  const [to, setTo] = useState(v.activeAccounts[1]?.id ?? '')
  const [err, setErr] = useState('')
  const go = () => {
    const a = Money.parse(amount)
    if (!a || !member) { setErr('Escolha o dependente e informe o valor.'); return }
    try { createAllowance(member, a, +day, from, to); onClose() } catch (e) { if (e instanceof UserError) setErr(e.message); else throw e }
  }
  return (
    <Sheet title="Nova mesada" onClose={onClose} footer={<><Button onClick={go}>Criar</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      {deps.length === 0 && <p className="note">Adicione um dependente em Pessoas primeiro.</p>}
      <Field label="Dependente">{(id) => <select id={id} className="field" value={member} onChange={(e) => setMember(e.target.value)}>{deps.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}</select>}</Field>
      <Field label="Valor (R$)">{(id) => <input id={id} className="field num" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />}</Field>
      <Field label="Dia do mês">{(id) => <input id={id} className="field num" type="number" min={1} max={31} value={day} onChange={(e) => setDay(e.target.value)} />}</Field>
      <Field label="Conta de origem">{(id) => <select id={id} className="field" value={from} onChange={(e) => setFrom(e.target.value)}>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
      <Field label="Conta de destino">{(id) => <select id={id} className="field" value={to} onChange={(e) => setTo(e.target.value)}>{v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>}</Field>
    </Sheet>
  )
}

function Approvals() {
  const v = useView()
  const list = useApp((s) => s.data.approvalRequests)
  const canDecide = C.can(v.me?.role ?? 'member', 'approveSpending')
  const pending = C.pendingApprovals(list)
  const decided = list.filter((r) => r.status !== 'pending')
  const err = (f: () => void) => { try { f() } catch (e) { if (e instanceof UserError) useApp.getState().toast(e.message, 'danger'); else throw e } }
  return (
    <>
      <Group label="Pendentes">
        {pending.map((r) => <Row key={r.id} icon="alert" title={r.title} sub={`${v.lookup.members.get(r.memberId)?.name ?? '?'} · ${fmtDay(r.date)} · ${monthTitle(C.ymOf(r.date))}`}
          trailing={<span style={{ display: 'flex', gap: 8, alignItems: 'center' }}><Amt value={r.amount} kind="expense" hide={v.hide} />{canDecide && <><Button small onClick={() => err(() => decideApproval(r.id, true))}>Aprovar</Button><Button small variant="secondary" onClick={() => err(() => decideApproval(r.id, false))}>Recusar</Button></>}</span>} />)}
        {pending.length === 0 && <div className="empty"><p>Nenhum pedido pendente.</p></div>}
      </Group>
      {decided.length > 0 && <Group label="Histórico">{decided.map((r) => <Row key={r.id} title={r.title} sub={v.lookup.members.get(r.memberId)?.name} trailing={<Badge tone={r.status === 'approved' ? 'ok' : 'danger'}>{r.status === 'approved' ? 'Aprovado' : 'Recusado'}</Badge>} />)}</Group>}
    </>
  )
}
