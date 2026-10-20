import { useMemo, useState } from 'react'
import * as C from '../core'
import { Transaction } from '../core'
import { deleteTransaction, markPaid } from '../app/actions'
import { useView } from '../app/hooks'
import {
  TxFilter, PERIOD_TITLES, FilterPeriod, accountLabel, advancedCount, catColorVar, categoryName, draftFrom, emptyFilter, groupByDay, matchesFilter, webIcon,
} from '../app/logic'
import { fmtDayLong, fmtMoney, monthTitle } from '../app/format'
import { Amt, Button, Chip, Empty, Group, Icon, Row, Sheet, useConfirm } from '../ui/kit'
import { MonthSwitcher, Page } from '../ui/Shell'
import { useUi } from '../ui/uiStore'
import { useApp } from '../app/store'

export function TransactionsScreen() {
  const v = useView()
  const [f, setF] = useState<TxFilter>(emptyFilter)
  const [showFilters, setShowFilters] = useState(false)
  const [detail, setDetail] = useState<Transaction | null>(null)
  const openDraft = useUi((s) => s.openDraft)
  const byId = useMemo(() => new Map(v.categories.map((c) => [c.id, c])), [v.categories])
  const list = useMemo(() => v.transactions.filter((t) => matchesFilter(t, f, v.lookup, v.today, v.month)), [v.transactions, f, v.lookup, v.today, v.month])
  const groups = useMemo(() => groupByDay(list), [list])
  const result = useMemo(() => C.sum(list.filter((t) => t.type !== 'transfer' && !t.invoiceId).map(C.signedAmount)), [list])
  const adv = advancedCount(f)
  const setPeriod = (p: FilterPeriod) => setF({ ...f, period: p })

  return (
    <Page title="Lançamentos" sub={<MonthSwitcher />}>
      <div className="search">
        <Icon name="search" />
        <input type="search" aria-label="Buscar lançamentos" placeholder="Buscar por nome, categoria, tag ou conta" value={f.query} onChange={(e) => setF({ ...f, query: e.target.value })} data-testid="tx-search" />
      </div>
      <div className="chips" role="group" aria-label="Filtros rápidos">
        <Chip pressed={adv > 0} onClick={() => setShowFilters(true)}><Icon name="sliders" />Filtros{adv > 0 && <span className="badge brand">{adv}</span>}</Chip>
        <Chip pressed={f.period === 'thisMonth'} onClick={() => setPeriod('thisMonth')}>{monthTitle(v.month).replace(/ de .*/, '')}</Chip>
        <Chip pressed={f.type === 'expense'} onClick={() => setF({ ...f, type: f.type === 'expense' ? 'all' : 'expense' })}>Despesas</Chip>
        <Chip pressed={f.type === 'income'} onClick={() => setF({ ...f, type: f.type === 'income' ? 'all' : 'income' })}>Receitas</Chip>
      </div>
      <p className="list-summary" aria-live="polite">{list.length} {list.length === 1 ? 'lançamento' : 'lançamentos'}, resultado {fmtMoney(result, { sign: 'plus', hide: v.hide })}</p>

      {groups.length === 0 ? (
        <Empty title="Nada por aqui" text="Nenhum lançamento corresponde à busca ou aos filtros." action={<Button small variant="secondary" onClick={() => setF(emptyFilter())}>Limpar busca e filtros</Button>} />
      ) : groups.map((g) => (
        <section key={g.date.toISOString()} aria-label={fmtDayLong(g.date)}>
          <h3 className="group-label"><span>{fmtDayLong(g.date)}</span><span className="amt-sub-inline">{fmtMoney(g.total, { sign: 'plus', hide: v.hide })}</span></h3>
          <div className="group">
            {g.items.map((t) => <TxRow key={t.id} t={t} onOpen={() => setDetail(t)} />)}
          </div>
        </section>
      ))}

      {showFilters && <FiltersSheet f={f} setF={setF} count={list.length} onClose={() => setShowFilters(false)} />}
      {detail && <DetailSheet t={detail} onClose={() => setDetail(null)} onEdit={() => { openDraft(draftFrom(detail)); setDetail(null) }} />}
    </Page>
  )

  function TxRow({ t, onOpen }: { t: Transaction; onOpen: () => void }) {
    const cat = t.categoryId ? byId.get(t.categoryId) : undefined
    const transfer = t.type === 'transfer'
    return (
      <Row icon={transfer ? 'arrows' : webIcon(cat?.icon)} color={transfer ? 'var(--transfer)' : catColorVar(cat, byId)} onClick={onOpen}
        title={t.title} sub={`${transfer ? (t.invoiceId ? 'Pagamento de fatura' : 'Transferência') : categoryName(v.lookup, t.categoryId)} · ${accountLabel(v.lookup, t)}`}
        trailing={<><Amt value={t.amount} kind={t.invoiceId ? 'transfer' : transfer ? 'transfer' : t.type === 'income' ? 'income' : 'expense'} hide={v.hide} />
          {t.status === 'pending' && <span className="amt-sub">Pendente</span>}{t.installment && t.status !== 'pending' && <span className="amt-sub">{C.installmentLabel(t.installment)}</span>}</>} />
    )
  }
}

function FiltersSheet({ f, setF, count, onClose }: { f: TxFilter; setF: (f: TxFilter) => void; count: number; onClose: () => void }) {
  const v = useView()
  const toggle = (set: Set<string>, id: string) => { const n = new Set(set); if (n.has(id)) n.delete(id); else n.add(id); return n }
  return (
    <Sheet title="Filtros" onClose={onClose} footer={<Button onClick={onClose}>Mostrar {count} lançamentos</Button>}>
      <div className="field-wrap"><span className="field-label">Período</span></div>
      <div className="chips wrap" role="group" aria-label="Período">
        {(Object.keys(PERIOD_TITLES) as FilterPeriod[]).map((p) => <Chip key={p} pressed={f.period === p} onClick={() => setF({ ...f, period: p })}>{PERIOD_TITLES[p]}</Chip>)}
      </div>
      <div className="field-wrap"><span className="field-label">Tipo</span></div>
      <div className="chips wrap" role="group" aria-label="Tipo">
        {([['all', 'Todos'], ['expense', 'Despesas'], ['income', 'Receitas'], ['transfer', 'Transferências']] as const).map(([k, l]) => <Chip key={k} pressed={f.type === k} onClick={() => setF({ ...f, type: k })}>{l}</Chip>)}
      </div>
      <div className="field-wrap"><span className="field-label">Contas e cartões</span></div>
      <div className="chips wrap" role="group" aria-label="Contas e cartões">
        {[...v.accounts, ...v.cards].map((a) => <Chip key={a.id} pressed={f.sourceIds.has(a.id)} onClick={() => setF({ ...f, sourceIds: toggle(f.sourceIds, a.id) })}>{a.name}</Chip>)}
      </div>
      <div className="field-wrap"><span className="field-label">Categorias</span></div>
      <div className="chips wrap" role="group" aria-label="Categorias">
        {v.categories.filter((c) => !c.parentId).map((c) => <Chip key={c.id} pressed={f.categoryIds.has(c.id)} onClick={() => setF({ ...f, categoryIds: toggle(f.categoryIds, c.id) })}>{c.name}{c.kind === 'income' ? ' (receita)' : ''}</Chip>)}
      </div>
      <div className="field-row" style={{ padding: '0 20px' }}>
        <label className="field-wrap"><span className="field-label">Valor mínimo</span>
          <input className="field num" inputMode="decimal" value={f.min ? f.min.toFixed(2).replace('.', ',') : ''} onChange={(e) => setF({ ...f, min: C.Money.parse(e.target.value) ?? undefined })} /></label>
        <label className="field-wrap"><span className="field-label">Valor máximo</span>
          <input className="field num" inputMode="decimal" value={f.max ? f.max.toFixed(2).replace('.', ',') : ''} onChange={(e) => setF({ ...f, max: C.Money.parse(e.target.value) ?? undefined })} /></label>
      </div>
      <div className="field-wrap"><span className="field-label">Tag</span></div>
      <div className="chips wrap" role="group" aria-label="Tag">
        {v.tags.map((t) => <Chip key={t.id} pressed={f.tagId === t.id} onClick={() => setF({ ...f, tagId: f.tagId === t.id ? undefined : t.id })}>{t.name}</Chip>)}
      </div>
      <div className="btns"><Button variant="secondary" onClick={() => setF(emptyFilter())}>Limpar</Button></div>
    </Sheet>
  )
}

function DetailSheet({ t, onClose, onEdit }: { t: Transaction; onClose: () => void; onEdit: () => void }) {
  const v = useView()
  const all = useApp((s) => s.data.transactions)
  const confirm = useConfirm()
  const members = v.lookup.members
  const group = C.groupMembers(t, all)
  const [scopePick, setScopePick] = useState(false)
  const doDelete = (scope: C.InstallmentScope) => { deleteTransaction(t, scope); onClose() }
  const tags = t.tagIds.map((id) => v.lookup.tags.get(id)?.name).filter(Boolean).join(', ')
  return (
    <Sheet title="Lançamento" onClose={onClose}>
      <div className="panel">
        <h3>{t.title}</h3>
        <p className="meta">{fmtDayLong(t.date)} · {t.status === 'paid' ? 'Pago' : 'Pendente'}</p>
        <div style={{ marginTop: 10, fontSize: 28 }}><Amt value={t.amount} kind={t.type === 'income' ? 'income' : t.type === 'transfer' ? 'transfer' : 'expense'} hide={v.hide} /></div>
        <div className="kv"><span>Categoria</span><span className="num">{t.type === 'transfer' ? '—' : categoryName(v.lookup, t.categoryId)}</span></div>
        <div className="kv"><span>Conta</span><span className="num">{accountLabel(v.lookup, t)}</span></div>
        {tags && <div className="kv"><span>Tags</span><span className="num">{tags}</span></div>}
        {t.memberId && members.get(t.memberId) && <div className="kv"><span>Quem lançou</span><span className="num">{members.get(t.memberId)!.name}</span></div>}
        {t.installment && <div className="kv"><span>Parcela</span><span className="num">{C.installmentLabel(t.installment)}</span></div>}
        {t.note && <div className="kv"><span>Observação</span><span className="num">{t.note}</span></div>}
        <div className="row-actions">
          {t.status === 'pending' && t.type !== 'transfer' && !C.isCardPurchase(t) && <Button variant="secondary" small onClick={() => { markPaid(t.id); onClose() }}>{t.type === 'income' ? 'Recebi' : 'Pagar'}</Button>}
          {!t.invoiceId && <Button variant="secondary" small onClick={onEdit}><Icon name="edit" />Editar</Button>}
          <Button variant="danger" small onClick={() => (group.length > 1 ? setScopePick(true) : confirm.ask('Excluir este lançamento?', () => doDelete('thisOnly')))}><Icon name="trash" />Excluir</Button>
        </div>
      </div>
      {scopePick && (
        <Group label="Excluir parcelas">
          {(['thisOnly', 'thisAndFuture', 'all'] as C.InstallmentScope[]).map((s) => <Row key={s} title={C.installmentScopeName[s]} onClick={() => doDelete(s)} />)}
        </Group>
      )}
      {confirm.node}
    </Sheet>
  )
}
