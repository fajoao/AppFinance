import { useState } from 'react'
import { ACCOUNT_TYPES, AccountType, Money, ZERO, accountTypeName } from '../core'
import { completeOnboarding, loadDemo, UserError } from '../app/actions'
import { Button, Field, Icon, Segmented } from '../ui/kit'
import { useApp } from '../app/store'
import { SplitAmount } from '../ui/kit'
import { dec } from '../core'

export function Onboarding() {
  const [step, setStep] = useState(1)
  const [name, setName] = useState('')
  const [type, setType] = useState<AccountType>('checking')
  const [balance, setBalance] = useState('')
  const [err, setErr] = useState('')
  const [berr, setBerr] = useState('')
  const session = useApp((s) => s.session)
  const synced = useApp((s) => s.data.accounts.length)

  const finish = () => {
    setErr(''); setBerr('')
    const parsed = balance.trim() === '' ? ZERO : Money.parse(balance)
    if (!parsed) { setBerr('Valor inválido. Exemplo: 1.234,56'); return }
    try { completeOnboarding({ accountName: name, type, balance: parsed }) } catch (e) {
      if (e instanceof UserError) setErr(e.message); else throw e
    }
  }
  return (
    <main className="auth">
      <div className="auth-card">
        <div className="ob-progress" aria-hidden="true">{[1, 2].map((n) => <i key={n} className={n <= step ? 'on' : ''} />)}</div>
        {step === 1 ? (
          <>
            <h1>Bem-vindo{session ? `, ${session.user.name.split(' ')[0]}` : ''}</h1>
            <p className="lead">Organize contas, cartões, orçamento e metas em poucos minutos.</p>
            <div style={{ margin: '20px' }}><SplitAmount value={dec('1234.56')} size="large" /></div>
            <ul className="ob-points">
              <li><span className="ico"><Icon name="lock" /></span><span>Seus dados ficam neste aparelho e, se você entrar, sincronizam com o app do iPhone.</span></li>
              <li><span className="ico"><Icon name="upload" /></span><span>Importe extratos OFX e CSV; lançamentos repetidos são ignorados.</span></li>
            </ul>
            <Button onClick={() => setStep(2)}>Começar</Button>
            {synced > 0 && <Button variant="plain" onClick={() => useApp.getState().setSettings({ onboarded: true })}>Já tenho dados, continuar</Button>}
            <Button variant="plain" onClick={() => loadDemo()}>Explorar com dados de exemplo</Button>
          </>
        ) : (
          <form onSubmit={(e) => { e.preventDefault(); finish() }} noValidate>
            <h1>Sua primeira conta</h1>
            <p className="lead">Você pode adicionar outras depois.</p>
            <Field label="Nome da conta" error={err}>{(id, d) => <input id={id} className="field" value={name} placeholder="Ex.: Nubank" onChange={(e) => setName(e.target.value)} aria-invalid={!!err} aria-describedby={d} />}</Field>
            <div className="field-wrap"><span className="field-label">Tipo</span></div>
            <Segmented label="Tipo de conta" value={type} onChange={setType} options={ACCOUNT_TYPES.slice(0, 3).map((t) => ({ value: t, label: accountTypeName[t] }))} />
            <Field label="Saldo de hoje (R$)" error={berr}>{(id, d) => <input id={id} className="field num" inputMode="decimal" value={balance} placeholder="0,00" onChange={(e) => setBalance(e.target.value)} aria-invalid={!!berr} aria-describedby={d} />}</Field>
            <Button type="submit">Concluir</Button>
            <Button type="button" variant="plain" onClick={() => setStep(1)}>Voltar</Button>
          </form>
        )}
      </div>
    </main>
  )
}
