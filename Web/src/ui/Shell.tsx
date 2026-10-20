import { ReactNode, useRef, useState } from 'react'
import { navigate, useRoute } from '../app/router'
import { useApp } from '../app/store'
import { newDraft } from '../app/logic'
import { useToday, useView } from '../app/hooks'
import { Icon, RefreshButton, Toasts } from './kit'
import { useUi } from './uiStore'
import { TxFormSheet } from '../screens/TxForm'

const NAV: { path: string; label: string; icon: string; match?: string[] }[] = [
  { path: '/', label: 'Início', icon: 'home' },
  { path: '/lancamentos', label: 'Lançamentos', icon: 'list' },
  { path: '/orcamento', label: 'Orçamento', icon: 'target', match: ['/orcamento'] },
  { path: '/contas-a-pagar', label: 'Contas a pagar', icon: 'calendar' },
  { path: '/metas', label: 'Metas', icon: 'flag' },
  { path: '/contas', label: 'Contas', icon: 'wallet' },
  { path: '/cartoes', label: 'Cartões', icon: 'card' },
  { path: '/investimentos', label: 'Investimentos', icon: 'trend' },
  { path: '/dividas', label: 'Dívidas', icon: 'coins' },
  { path: '/fluxo', label: 'Fluxo de caixa', icon: 'arrows' },
  { path: '/relatorios', label: 'Relatórios', icon: 'download' },
  { path: '/importar', label: 'Importar extrato', icon: 'upload' },
  { path: '/familia', label: 'Família', icon: 'house' },
  { path: '/ajustes', label: 'Configurações', icon: 'gear' },
]
const PLAN = ['/orcamento', '/contas-a-pagar', '/metas', '/mais', '/dividas', '/fluxo', '/relatorios', '/ir', '/patrimonio', '/familia', '/categorias', '/importar']
const WALLET = ['/contas', '/cartoes', '/investimentos']

export function Shell({ children }: { children: ReactNode }) {
  const { path } = useRoute()
  const today = useToday()
  const v = useView()
  const open = useUi((s) => s.openDraft)
  const newTx = () => open(newDraft(today, 'expense', v.activeAccounts[0]?.id))
  const cur = (p: string) => (p === '/' ? path === '/' : path === p || path.startsWith(p + '/'))
  return (
    <div className="shell">
      <a className="skip" href="#conteudo">Pular para o conteúdo</a>
      <nav className="side" aria-label="Principal">
        <div className="brand"><i aria-hidden="true">F</i>Finanças</div>
        {NAV.map((n, i) => (
          <span key={n.path} style={{ display: 'contents' }}>
            {(i === 2 || i === 5 || i === 8 || i === 13) && <div className="nav-sep" />}
            <a className="nav-link" href={'#' + n.path} aria-current={cur(n.path) ? 'page' : undefined}><Icon name={n.icon} />{n.label}</a>
          </span>
        ))}
        <SyncBadge />
      </nav>
      <main className="content" id="conteudo" tabIndex={-1}>{children}</main>
      <button type="button" className="fab" onClick={newTx}><Icon name="plus" />Novo lançamento</button>
      <nav className="tabbar" aria-label="Principal">
        <a className="tab" href="#/" aria-current={path === '/' ? 'page' : undefined}><Icon name="home" />Início</a>
        <a className="tab" href="#/lancamentos" aria-current={cur('/lancamentos') ? 'page' : undefined}><Icon name="list" />Lançamentos</a>
        <button type="button" className="tab tab-new" onClick={newTx} aria-label="Novo lançamento"><span className="plus"><Icon name="plus" /></span></button>
        <a className="tab" href="#/orcamento" aria-current={PLAN.some(cur) ? 'page' : undefined}><Icon name="target" />Planejar</a>
        <a className="tab" href="#/contas" aria-current={WALLET.some(cur) ? 'page' : undefined}><Icon name="wallet" />Carteira</a>
      </nav>
      <TxFormSheet />
      <Toasts />
    </div>
  )
}

function SyncBadge() {
  const info = useApp((s) => s.syncInfo)
  const session = useApp((s) => s.session)
  const label = !session ? 'Somente neste aparelho' : info.status === 'syncing' ? 'Sincronizando…' : info.status === 'offline' ? 'Offline' : info.status === 'error' ? 'Erro ao sincronizar' : info.pending ? `${info.pending} pendente(s)` : 'Sincronizado'
  return <div className="syncdot" style={{ marginTop: 'auto' }}><span aria-hidden="true">●</span>{label}</div>
}

/** Cabeçalho de página com o botão Atualizar, ocultar valores e (no celular) puxar para atualizar. */
export function Page({ title, children, actions, sub }: { title: string; children: ReactNode; actions?: ReactNode; sub?: ReactNode }) {
  const hide = useApp((s) => s.settings.hideValues)
  const setSettings = useApp((s) => s.setSettings)
  const [pull, setPull] = useState(0)
  const startY = useRef<number | null>(null)
  const onStart = (e: React.TouchEvent) => { startY.current = window.scrollY <= 0 ? e.touches[0]!.clientY : null }
  const onMove = (e: React.TouchEvent) => { if (startY.current !== null) setPull(Math.max(0, Math.min(90, e.touches[0]!.clientY - startY.current))) }
  const onEnd = () => {
    if (pull >= 70) window.__refreshPull?.()
    startY.current = null
    setPull(0)
  }
  return (
    <div className="page" onTouchStart={onStart} onTouchMove={onMove} onTouchEnd={onEnd}>
      <div className="topbar">
        <h1 className="large-title">{title}</h1>
        <div className="actions">
          {actions}
          <RefreshButton />
          <button type="button" className="icon-btn" aria-pressed={hide} aria-label={hide ? 'Mostrar valores' : 'Ocultar valores'} onClick={() => setSettings({ hideValues: !hide })}>
            <Icon name={hide ? 'eyeOff' : 'eye'} />
          </button>
          <button type="button" className="icon-btn" aria-label="Configurações" onClick={() => navigate('/ajustes')}><Icon name="gear" /></button>
        </div>
      </div>
      <div className={`ptr ${pull > 0 ? 'on' : ''}`} aria-hidden="true">{pull >= 70 ? 'Solte para atualizar' : 'Puxe para atualizar'}</div>
      {sub}
      {children}
    </div>
  )
}

export function SubNav({ items, current }: { items: { path: string; label: string }[]; current: string }) {
  return (
    <div className="seg" role="tablist" aria-label="Seções">
      {items.map((i) => (
        <button key={i.path} type="button" role="tab" aria-selected={current === i.path} aria-checked={current === i.path} onClick={() => navigate(i.path)}>{i.label}</button>
      ))}
    </div>
  )
}
export const PLAN_TABS = [{ path: '/orcamento', label: 'Orçamento' }, { path: '/contas-a-pagar', label: 'A pagar' }, { path: '/metas', label: 'Metas' }, { path: '/mais', label: 'Mais' }]
export const WALLET_TABS = [{ path: '/contas', label: 'Contas' }, { path: '/cartoes', label: 'Cartões' }, { path: '/investimentos', label: 'Investimentos' }]

export function MonthSwitcher() {
  const month = useApp((s) => s.month)
  const setMonth = useApp((s) => s.setMonth)
  return <MonthSwitch month={month} onChange={setMonth} />
}
import { YearMonth, ymAdd } from '../core'
import { cap, monthTitle } from '../app/format'
export function MonthSwitch({ month, onChange }: { month: YearMonth; onChange: (m: YearMonth) => void }) {
  return (
    <div className="monthsw">
      <button type="button" className="icon-btn" aria-label="Mês anterior" onClick={() => onChange(ymAdd(month, -1))}><Icon name="chevL" /></button>
      <h2 aria-live="polite">{cap(monthTitle(month))}</h2>
      <button type="button" className="icon-btn" aria-label="Próximo mês" onClick={() => onChange(ymAdd(month, 1))}><Icon name="chevR" /></button>
    </div>
  )
}
