import { ReactNode, useEffect, useId, useRef, useState } from 'react'
import { Dec } from '../core'
import { fmtMoney, moneyParts, spokenMoney } from '../app/format'
import { ICONS, IconName } from './iconPaths'
import { useApp } from '../app/store'
import { refreshNow } from '../app/refresh'

export function Icon({ name, size, className }: { name: IconName | string; size?: number; className?: string }) {
  const d = (ICONS as Record<string, string>)[name] ?? ICONS.tag
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false"
      width={size} height={size} className={className}><path d={d} /></svg>
  )
}

/** Valor em linhas: sinal, cor por tipo, dígitos tabulares, leitura por extenso. */
export function Amt({ value, kind, hide, sign, className }: { value: Dec; kind?: 'income' | 'expense' | 'transfer' | 'balance'; hide?: boolean; sign?: boolean; className?: string }) {
  const global = useApp((st) => st.settings.hideValues)
  const hideV = hide ?? global
  const cls = kind === 'income' ? 'income' : kind === 'transfer' ? 'transfer' : kind === 'balance' ? (value.isNegative() && !value.isZero() ? 'neg' : value.isZero() ? 'zero' : '') : ''
  const v = kind === 'expense' ? value.abs().neg() : value
  const text = fmtMoney(v, { sign: kind === 'income' || sign ? 'plus' : 'auto', hide: hideV })
  return <span className={`amt ${cls} ${className ?? ''}`} aria-label={spokenMoney(v, hideV)}>{text}</span>
}

/** Numeral dividido (assinatura visual): R$ e centavos pequenos, reais grandes. */
export function SplitAmount({ value, size = 'xl', hide }: { value: Dec; size?: 'xl' | 'large'; hide?: boolean }) {
  const h = hide ?? false
  const p = moneyParts(value)
  const neg = value.isNegative() && !value.isZero()
  return (
    <span className={`amt-split ${size} ${neg ? 'neg' : ''}`} role="text" aria-label={spokenMoney(value, h)}>
      {h ? (<><span className="sym">R$</span><span className="int">••••</span></>) : (
        <><span className="sym">{p.sign}{p.symbol}</span><span className="int">{p.integer}</span><span className="frac">{p.fraction}</span></>)}
    </span>
  )
}

export function Button({ variant = 'primary', small, className, ...p }: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'secondary' | 'plain' | 'danger'; small?: boolean }) {
  return <button type="button" {...p} className={`btn btn-${variant} ${small ? 'btn-small' : ''} ${className ?? ''}`} />
}

export function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label: string }) {
  return (
    <div className="seg" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} type="button" role="radio" aria-checked={value === o.value} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  )
}

export function Chip({ pressed, onClick, children, dot }: { pressed?: boolean; onClick: () => void; children: ReactNode; dot?: string }) {
  return (
    <button type="button" className="chip" aria-pressed={pressed} onClick={onClick}>
      {dot && <i className="dot" style={{ ['--c' as string]: dot }} />}{children}
    </button>
  )
}

export function Field({ label, error, children, hint }: { label: string; error?: string; hint?: string; children: (id: string, describedBy?: string) => ReactNode }) {
  const id = useId()
  const eid = error ? id + '-e' : hint ? id + '-h' : undefined
  return (
    <div className="field-wrap">
      <label className="field-label" htmlFor={id}>{label}</label>
      {children(id, eid)}
      {error ? <p className="error" id={id + '-e'} role="alert">{error}</p> : hint ? <p className="note" id={id + '-h'} style={{ padding: 0 }}>{hint}</p> : null}
    </div>
  )
}

export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return <button type="button" role="switch" className="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} />
}

export function Badge({ tone = 'neutral', children }: { tone?: 'ok' | 'warn' | 'danger' | 'neutral' | 'brand'; children: ReactNode }) {
  return <span className={`badge ${tone}`}>{children}</span>
}

export function Bar({ fraction, color, mark, label }: { fraction: number; color?: string; mark?: number; label?: string }) {
  const f = Math.max(0, Math.min(1, fraction))
  return (
    <div className="bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(f * 100)} aria-label={label}>
      <i style={{ width: `${f * 100}%`, ['--c' as string]: color }} />
      {mark !== undefined && <b style={{ left: `${mark * 100}%` }} />}
    </div>
  )
}

export function Empty({ title, text, action }: { title: string; text?: string; action?: ReactNode }) {
  return <div className="empty"><h2>{title}</h2>{text && <p>{text}</p>}{action}</div>
}

export function Group({ children, label, aside }: { children: ReactNode; label?: string; aside?: ReactNode }) {
  return (
    <>
      {label && <h3 className="group-label"><span>{label}</span>{aside && <span className="amt-sub-inline">{aside}</span>}</h3>}
      <div className="group">{children}</div>
    </>
  )
}

export function Row({ icon, color, title, sub, trailing, onClick, href, children }: {
  icon?: string; color?: string; title: ReactNode; sub?: ReactNode; trailing?: ReactNode; onClick?: () => void; href?: string; children?: ReactNode
}) {
  const inner = (
    <>
      {icon && <span className="ico" style={{ ['--c' as string]: color }}><Icon name={icon} /></span>}
      <span className="main"><span className="t1">{title}</span>{sub && <span className="t2" style={{ display: 'block' }}>{sub}</span>}{children}</span>
      {trailing && <span className="trail">{trailing}</span>}
      {(onClick || href) && !trailing && <Icon name="chevR" className="chev" />}
    </>
  )
  if (href) return <a className="row" href={href}>{inner}</a>
  if (onClick) return <button type="button" className="row" onClick={onClick}>{inner}</button>
  return <div className="row">{inner}</div>
}

/** Sheet modal acessível (<dialog> nativo: foco preso, Esc fecha). */
export function Sheet({ title, onClose, children, footer, short }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; short?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null)
  const prev = useRef<Element | null>(null)
  useEffect(() => {
    prev.current = document.activeElement
    const d = ref.current
    if (d && !d.open) d.showModal()
    return () => { (prev.current as HTMLElement | null)?.focus?.() }
  }, [])
  return (
    <dialog ref={ref} className={`sheet ${short ? 'short' : ''}`} aria-labelledby="sheet-title" onCancel={(e) => { e.preventDefault(); onClose() }}
      onClick={(e) => { if (e.target === ref.current) onClose() }}>
      <div className="sheet-inner">
        <div className="sheet-head">
          <button type="button" className="link-btn" onClick={onClose}>Cancelar</button>
          <h2 id="sheet-title">{title}</h2>
          <span />
        </div>
        <div className="sheet-body">{children}</div>
        {footer && <div className="sheet-foot">{footer}</div>}
      </div>
    </dialog>
  )
}

export function Toasts() {
  const toasts = useApp((s) => s.toasts)
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map((t) => <div key={t.id} className={`toast show ${t.tone === 'info' ? '' : t.tone}`}>{t.text}</div>)}
    </div>
  )
}

export function useConfirm() {
  const [state, setState] = useState<{ text: string; ok: () => void } | null>(null)
  const node = state && (
    <Sheet title="Confirmar" short onClose={() => setState(null)} footer={<Button variant="danger" onClick={() => { state.ok(); setState(null) }}>Confirmar</Button>}>
      <p style={{ padding: '8px 20px' }}>{state.text}</p>
    </Sheet>
  )
  return { ask: (text: string, ok: () => void) => setState({ text, ok }), node }
}

/** Botão "Atualizar": sincroniza agora (push da fila + pull) e recarrega os dados. Gira ao executar e anuncia o resultado. */
export function RefreshButton() {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const [bad, setBad] = useState(false)
  const run = async () => {
    if (busy) return
    setBusy(true)
    setMsg('Atualizando…')
    const r = await refreshNow()
    setBad(!r.ok)
    setMsg(r.message)
    // celular: a mensagem visual vem como aviso (o texto acima continua anunciado por leitores de tela)
    if (window.matchMedia('(max-width: 899px)').matches) useApp.getState().toast(r.message, r.ok ? 'info' : 'warn')
    setBusy(false)
  }
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null
      if ((e.key === 'r' || e.key === 'R') && !e.ctrlKey && !e.metaKey && !e.altKey && !(t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) && !document.querySelector('dialog[open]')) {
        e.preventDefault()
        void run()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })
  useEffect(() => { window.__refreshPull = run })
  return (
    <span className="refresh">
      <button type="button" className={`icon-btn refresh-btn ${busy ? 'spin' : ''}`} onClick={run} disabled={busy} aria-label="Atualizar" title="Atualizar (R)" data-testid="refresh">
        <Icon name="refresh" />
      </button>
      <span className={`refresh-msg ${bad ? 'danger-text' : ''}`} role="status" aria-live="polite" data-testid="refresh-status">{msg}</span>
    </span>
  )
}
declare global { interface Window { __refreshPull?: () => void } }
