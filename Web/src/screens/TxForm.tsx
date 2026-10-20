import { useMemo, useState } from 'react'
import * as C from '../core'
import { Money, TransactionType, ZERO, isoDay, parseIsoDay } from '../core'
import { UserError, createTag, saveDraft } from '../app/actions'
import { useView } from '../app/hooks'
import { Draft, DRAFT_MESSAGES, catColorVar, installmentSummary, saveLabel, validateDraft } from '../app/logic'
import { categoryKeywords } from '../app/logic'
import { useApp } from '../app/store'
import { Button, Chip, Field, Segmented, Sheet, SplitAmount } from '../ui/kit'
import { useUi } from '../ui/uiStore'
import { fmtMoney } from '../app/format'

export function TxFormSheet() {
  const draft = useUi((s) => s.draft)
  const close = useUi((s) => s.closeDraft)
  if (!draft) return null
  return <TxForm initial={draft} onClose={close} />
}

function TxForm({ initial, onClose }: { initial: Draft; onClose: () => void }) {
  const v = useView()
  const toast = useApp((s) => s.toast)
  const [d, setD] = useState<Draft>(initial)
  const [amountText, setAmountText] = useState(initial.amount.isZero() ? '' : initial.amount.toFixed(2).replace('.', ','))
  const [amountErr, setAmountErr] = useState('')
  const [err, setErr] = useState('')
  const [newTag, setNewTag] = useState('')
  const [suggested, setSuggested] = useState(false)
  const [chosenByUser, setChosenByUser] = useState(!!initial.categoryId)
  const editing = !!d.editingId
  const kind = d.type === 'income' ? 'income' : 'expense'
  const cats = v.categories.filter((c) => c.kind === kind && !c.parentId)
  const suggester = useMemo(() => new C.CategorySuggester(v.transactions, categoryKeywords(v.categories, kind)), [v.transactions, v.categories, kind])
  const byId = useMemo(() => new Map(v.categories.map((c) => [c.id, c])), [v.categories])

  const upd = (p: Partial<Draft>) => setD((o) => ({ ...o, ...p }))
  const onAmount = (t: string) => {
    setAmountText(t)
    const n = t.trim() === '' ? ZERO : Money.parse(t)
    if (!n || n.isNegative()) { setAmountErr('Valor inválido. Exemplo: 45,90'); return }
    setAmountErr('')
    upd({ amount: n })
  }
  const onTitle = (t: string) => {
    const next: Partial<Draft> = { title: t }
    if (d.type !== 'transfer' && !chosenByUser) {
      const id = suggester.suggest(t, d.type)
      if (id && byId.get(id)?.kind === kind) { next.categoryId = id; setSuggested(true) }
      else if (suggested) { next.categoryId = undefined; setSuggested(false) }
    }
    upd(next)
  }
  const changeType = (t: TransactionType) => {
    if (t === d.type) return
    const p: Partial<Draft> = { type: t, categoryId: undefined }
    if (t !== 'expense' && d.source?.kind === 'card') p.source = undefined
    if (t !== 'expense' && d.repeat === 'installments') p.repeat = 'none'
    if (t !== 'transfer') p.destinationAccountId = undefined
    setSuggested(false); setChosenByUser(false)
    upd(p)
  }
  const sourceValue = d.source ? `${d.source.kind}:${d.source.id}` : ''
  const save = () => {
    setErr('')
    const e = validateDraft(d)
    if (e) { setErr(DRAFT_MESSAGES[e]); return }
    try {
      const r = saveDraft(d)
      toast(r.kind === 'approval' ? 'Gasto acima do limite: enviado para aprovação.' : editing ? 'Lançamento atualizado.' : r.count > 1 ? `${r.count} parcelas lançadas.` : 'Lançamento salvo.')
      onClose()
    } catch (x) {
      if (x instanceof UserError || x instanceof C.FinanceError) setErr(x.message); else throw x
    }
  }
  const summary = installmentSummary(d)
  const dateIso = isoDay(d.date)
  const quick = [['Hoje', 0], ['Ontem', -1], ['Anteontem', -2]] as const

  return (
    <Sheet title={editing ? 'Editar lançamento' : 'Novo lançamento'} onClose={onClose}
      footer={<><Button onClick={save} data-testid="tx-save">{saveLabel(d)}</Button>{err && <p className="error" role="alert" style={{ textAlign: 'center' }}>{err}</p>}</>}>
      {!editing && <Segmented label="Tipo" value={d.type} onChange={changeType} options={[{ value: 'expense', label: 'Despesa' }, { value: 'income', label: 'Receita' }, { value: 'transfer', label: 'Transferência' }]} />}
      <div className="nt-amount"><SplitAmount value={d.amount} /></div>
      <Field label="Valor (R$)" error={amountErr}>
        {(id, desc) => <input id={id} className="field num" inputMode="decimal" autoFocus placeholder="0,00" value={amountText} onChange={(e) => onAmount(e.target.value)} aria-invalid={!!amountErr} aria-describedby={desc} data-testid="tx-amount" />}
      </Field>
      <Field label="Descrição">
        {(id) => <input id={id} className="field" placeholder={d.type === 'transfer' ? 'Transferência' : 'Ex.: Mercado'} value={d.title} onChange={(e) => onTitle(e.target.value)} data-testid="tx-title" />}
      </Field>
      {d.type !== 'transfer' && (
        <>
          <div className="field-wrap"><span className="field-label">Categoria {suggested && <span className="suggest" role="status">· Sugerida</span>}</span></div>
          <div className="chips wrap" role="group" aria-label="Categoria">
            {cats.map((c) => (
              <Chip key={c.id} dot={catColorVar(c, byId)} pressed={d.categoryId === c.id} onClick={() => { upd({ categoryId: d.categoryId === c.id ? undefined : c.id }); setChosenByUser(d.categoryId !== c.id); setSuggested(false) }}>
                {c.name}
              </Chip>
            ))}
          </div>
        </>
      )}
      <Field label={d.type === 'transfer' ? 'Conta de origem' : d.type === 'income' ? 'Conta' : 'Conta ou cartão'}>
        {(id) => (
          <select id={id} className="field" value={sourceValue} data-testid="tx-source" onChange={(e) => {
            const [k, i] = e.target.value.split(':') as ['account' | 'card', string]
            upd({ source: i ? { kind: k, id: i } : undefined })
          }}>
            <option value="">Escolha…</option>
            <optgroup label="Contas">{v.activeAccounts.map((a) => <option key={a.id} value={`account:${a.id}`}>{a.name}</option>)}</optgroup>
            {d.type === 'expense' && <optgroup label="Cartões">{v.activeCards.map((c) => <option key={c.id} value={`card:${c.id}`}>{c.name} · disponível {fmtMoney(C.availableLimit(c, v.transactions), { hide: v.hide })}</option>)}</optgroup>}
          </select>
        )}
      </Field>
      {d.type === 'transfer' && (
        <Field label="Conta de destino">
          {(id) => (
            <select id={id} className="field" value={d.destinationAccountId ?? ''} onChange={(e) => upd({ destinationAccountId: e.target.value || undefined })}>
              <option value="">Escolha…</option>
              {v.activeAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          )}
        </Field>
      )}
      <Field label="Data">
        {(id) => <input id={id} className="field" type="date" value={dateIso} onChange={(e) => { const x = parseIsoDay(e.target.value); if (x) upd({ date: x }) }} />}
      </Field>
      <div className="chips" role="group" aria-label="Atalhos de data">
        {quick.map(([l, off]) => <Chip key={l} pressed={C.isSameDay(d.date, C.addDays(v.today, off))} onClick={() => upd({ date: C.addDays(v.today, off) })}>{l}</Chip>)}
      </div>
      {!editing && (
        <Field label="Repetir" hint={summary ?? undefined}>
          {(id, desc) => (
            <select id={id} className="field" aria-describedby={desc} value={d.repeat} onChange={(e) => upd({ repeat: e.target.value as Draft['repeat'] })}>
              <option value="none">Não repete</option>
              {d.type === 'expense' && <option value="installments">Parcelado</option>}
              <option value="monthly">Todo mês</option>
              <option value="weekly">Toda semana</option>
            </select>
          )}
        </Field>
      )}
      {!editing && d.repeat === 'installments' && (
        <div className="field-wrap">
          <div className="stepper" role="group" aria-label="Número de parcelas">
            <button type="button" aria-label="Menos uma parcela" onClick={() => upd({ installments: Math.max(2, d.installments - 1) })}>−</button>
            <output aria-live="polite">{d.installments}x</output>
            <button type="button" aria-label="Mais uma parcela" onClick={() => upd({ installments: Math.min(24, d.installments + 1) })}>+</button>
          </div>
        </div>
      )}
      <div className="field-wrap"><span className="field-label">Tags</span></div>
      <div className="chips wrap" role="group" aria-label="Tags">
        {v.tags.map((t) => <Chip key={t.id} pressed={d.tagIds.includes(t.id)} onClick={() => upd({ tagIds: d.tagIds.includes(t.id) ? d.tagIds.filter((x) => x !== t.id) : [...d.tagIds, t.id] })}>{t.name}</Chip>)}
      </div>
      <div className="field-row" style={{ padding: '8px 20px 0' }}>
        <input className="field" aria-label="Nova tag" placeholder="Nova tag" value={newTag} onChange={(e) => setNewTag(e.target.value)} />
        <Button variant="secondary" small onClick={() => { if (newTag.trim()) { const t = createTag(newTag); upd({ tagIds: [...new Set([...d.tagIds, t.id])] }); setNewTag('') } }}>Adicionar</Button>
      </div>
      {v.hasFamily && v.me?.role !== 'dependent' && (
        <Field label="Quem">
          {(id) => (
            <select id={id} className="field" value={d.memberId ?? v.me?.id ?? ''} onChange={(e) => upd({ memberId: e.target.value || undefined })}>
              {v.members.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
          )}
        </Field>
      )}
      <Field label="Observação">{(id) => <textarea id={id} className="field" value={d.note} onChange={(e) => upd({ note: e.target.value })} />}</Field>
    </Sheet>
  )
}
