import { useRoute } from './app/router'
import { useApp } from './app/store'
import { Shell } from './ui/Shell'
import { Toasts } from './ui/kit'
import { AuthScreen } from './screens/Auth'
import { Onboarding } from './screens/Onboarding'
import { Dashboard } from './screens/Dashboard'
import { TransactionsScreen } from './screens/Transactions'
import { AccountsScreen, CardsScreen, CardDetail } from './screens/Wallet'
import { BudgetScreen, BillsScreen, GoalsScreen, MoreScreen } from './screens/Plan'
import { DebtsScreen, CashFlowScreen, NetWorthScreen, InvestmentsScreen } from './screens/Money'
import { ReportsScreen, TaxScreen, ImportScreen, CategoriesScreen } from './screens/Reports'
import { FamilyScreen } from './screens/Family'
import { SettingsScreen } from './screens/Settings'

function Routes() {
  const { path } = useRoute()
  if (path.startsWith('/cartoes/')) return <CardDetail id={path.split('/')[2]!} />
  switch (path) {
    case '/lancamentos': return <TransactionsScreen />
    case '/orcamento': return <BudgetScreen />
    case '/contas-a-pagar': return <BillsScreen />
    case '/metas': return <GoalsScreen />
    case '/mais': return <MoreScreen />
    case '/contas': return <AccountsScreen />
    case '/cartoes': return <CardsScreen />
    case '/investimentos': return <InvestmentsScreen />
    case '/patrimonio': return <NetWorthScreen />
    case '/dividas': return <DebtsScreen />
    case '/fluxo': return <CashFlowScreen />
    case '/relatorios': return <ReportsScreen />
    case '/ir': return <TaxScreen />
    case '/importar': return <ImportScreen />
    case '/categorias': return <CategoriesScreen />
    case '/familia': return <FamilyScreen />
    case '/ajustes': return <SettingsScreen />
    default: return <Dashboard />
  }
}

export function App() {
  const ready = useApp((s) => s.ready)
  const session = useApp((s) => s.session)
  const settings = useApp((s) => s.settings)
  if (!ready) return <div className="auth" role="status">Carregando…</div>
  if (!session && !settings.localMode) return <><AuthScreen /><Toasts /></>
  if (!settings.onboarded) return <><Onboarding /><Toasts /></>
  return <Shell><Routes /></Shell>
}
