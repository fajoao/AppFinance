import { useMemo } from 'react'
import * as C from '../core'
import { useApp } from '../app/store'
import { useView } from '../app/hooks'
import { billItems, billStatus, billsIn, catColorVar, categoryName, webIcon } from '../app/logic'
import { fmtDayShort, fmtMoney, fmtPercent, monthTitle, cap } from '../app/format'
import { Amt, Bar, Group, Row, SplitAmount, Badge } from '../ui/kit'
import { CompareBars } from '../ui/charts'
import { MonthSwitcher, Page } from '../ui/Shell'
import { navigate } from '../app/router'

export function Dashboard() {
  const v = useView()
  const s = useApp((st) => st.data)
  const summary = useMemo(() => C.monthlySummary(v.month, v.transactions), [v.transactions, v.month])
  const balance = useMemo(() => C.totalBalance(v.activeAccounts, v.transactions), [v.activeAccounts, v.transactions])
  const byId = useMemo(() => new Map(v.categories.map((c) => [c.id, c])), [v.categories])
  const bills = useMemo(() => billItems(v.transactions, v.activeCards, v.invoices, v.today), [v.transactions, v.activeCards, v.invoices, v.today])
  const dues = bills.filter((b) => !b.isPaid && b.direction === 'payable').slice(0, 3)
  const alerts = C.budgetAlerts(v.month, s.budgets, v.transactions, v.categories)
  const c = summary.comparison
  const result = summary.balance
  const empty = v.transactions.length === 0
  void billsIn

  return (
    <Page title="Início" sub={<MonthSwitcher />}>
      <section className="hero" aria-labelledby="saldo-l">
        <p className="hero-label" id="saldo-l">Saldo em contas</p>
        <SplitAmount value={balance} hide={v.hide} />
        <p className="hero-sub">Resultado de {monthTitle(v.month)}: <strong className={result.isNegative() ? 'danger-text' : result.gt(0) ? 'income' : ''}>{fmtMoney(result, { sign: 'plus', hide: v.hide })}</strong></p>
      </section>

      {empty && <div className="empty"><h2>Nenhum lançamento ainda</h2><p>Use o botão “Novo lançamento” para começar.</p></div>}

      {!empty && (
        <>
          <div className="sec">
            <div className="sec-head"><h2 className="sec-title">Receitas × despesas</h2></div>
            <CompareBars desc={`Receitas ${fmtMoney(summary.income)}; despesas ${fmtMoney(summary.expense)}. A marca indica o mês anterior.`}
              rows={[
                { label: 'Receitas', value: summary.income.toNumber(), prev: c.previousIncome.toNumber(), color: 'var(--income)', text: fmtMoney(summary.income, { hide: v.hide }) },
                { label: 'Despesas', value: summary.expense.toNumber(), prev: c.previousExpense.toNumber(), color: 'var(--brand-primary)', text: fmtMoney(summary.expense, { hide: v.hide }) },
              ]} />
            <p className="note">Mês anterior: receitas {fmtMoney(c.previousIncome, { hide: v.hide })}, despesas {fmtMoney(c.previousExpense, { hide: v.hide })}.
              {c.expenseChangePercent && ` Despesas ${c.expenseChangePercent.gt(0) ? 'subiram' : 'caíram'} ${fmtPercent(c.expenseChangePercent.abs())}.`}</p>
          </div>

          {alerts.length > 0 && (
            <div className="sec">
              <div className="sec-head"><h2 className="sec-title">Orçamento em alerta</h2><button type="button" className="link-btn" onClick={() => navigate('/orcamento')}>Ver tudo</button></div>
              <Group>
                {alerts.slice(0, 3).map((a) => (
                  <Row key={a.budget.id} icon={webIcon(byId.get(a.budget.categoryId)?.icon)} color={catColorVar(byId.get(a.budget.categoryId), byId)} title={categoryName(v.lookup, a.budget.categoryId)}
                    sub={a.alert === 'exceeded' ? `Estourou ${fmtMoney(a.spent.minus(a.limit), { hide: v.hide })}` : `${a.percentUsed.toFixed(0)}% usado`}
                    trailing={<Badge tone={a.alert === 'exceeded' ? 'danger' : 'warn'}>{a.alert === 'exceeded' ? 'Estourou' : 'Atenção'}</Badge>} />
                ))}
              </Group>
            </div>
          )}

          <div className="sec">
            <div className="sec-head"><h2 className="sec-title">Para onde foi</h2></div>
            <Group>
              {summary.expensesByCategory.slice(0, 6).map((t) => {
                const cat = t.categoryId ? byId.get(t.categoryId) : undefined
                const color = catColorVar(cat, byId)
                return (
                  <Row key={t.categoryId ?? 'none'} icon={webIcon(cat?.icon)} color={color} title={categoryName(v.lookup, t.categoryId ?? undefined)}
                    sub={<><Bar fraction={t.percentOfTotal.toNumber() / 100} color={color} label={`${categoryName(v.lookup, t.categoryId ?? undefined)} ${t.percentOfTotal}% das despesas`} /></>}
                    trailing={<><Amt value={t.amount} kind="expense" hide={v.hide} /><span className="amt-sub">{fmtPercent(t.percentOfTotal)}</span></>} />
                )
              })}
              {summary.expensesByCategory.length === 0 && <div className="empty"><p>Sem despesas neste mês.</p></div>}
            </Group>
          </div>

          <div className="sec">
            <div className="sec-head"><h2 className="sec-title">Próximos vencimentos</h2><button type="button" className="link-btn" onClick={() => navigate('/contas-a-pagar')}>Ver tudo</button></div>
            <Group>
              {dues.map((b) => {
                const st = billStatus(b, v.today)
                return <Row key={b.id} icon={b.cardId ? 'card' : 'calendar'} title={b.title} sub={`${fmtDayShort(b.dueDate)} · ${cap(st.label.toLowerCase())}`}
                  trailing={<><Amt value={b.amount} kind="expense" hide={v.hide} /><span className={`amt-sub ${st.tone === 'danger' ? 'danger-text' : st.tone === 'warning' ? 'warn-text' : ''}`}>{st.label}</span></>} />
              })}
              {dues.length === 0 && <div className="empty"><p>Nada a vencer nos próximos dias.</p></div>}
            </Group>
          </div>
        </>
      )}
    </Page>
  )
}
