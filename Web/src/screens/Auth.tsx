import { FormEvent, useState } from 'react'
import { errorText } from '../app/api'
import { login, register } from '../app/actions'
import { useApp } from '../app/store'
import { Button, Field, Segmented } from '../ui/kit'

export function AuthScreen() {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [fieldErr, setFieldErr] = useState<Record<string, string>>({})
  const setSettings = useApp((s) => s.setSettings)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    const fe: Record<string, string> = {}
    if (mode === 'register' && !name.trim()) fe.name = 'Informe seu nome.'
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) fe.email = 'Informe um e-mail válido.'
    if (mode === 'register' ? password.length < 10 : password.length === 0) fe.password = mode === 'register' ? 'Use ao menos 10 caracteres.' : 'Informe a senha.'
    setFieldErr(fe)
    setError('')
    if (Object.keys(fe).length) return
    setBusy(true)
    try {
      if (mode === 'login') await login(email, password)
      else await register(email, password, name)
    } catch (err) {
      setError(errorText(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="auth">
      <form className="auth-card" onSubmit={submit} noValidate aria-labelledby="auth-title">
        <h1 id="auth-title">{mode === 'login' ? 'Entrar' : 'Criar conta'}</h1>
        <p className="lead">Finanças pessoais e da família, com seus dados sempre à mão, mesmo sem internet.</p>
        <Segmented label="Modo" value={mode} onChange={setMode} options={[{ value: 'login', label: 'Entrar' }, { value: 'register', label: 'Criar conta' }]} />
        {mode === 'register' && (
          <Field label="Nome" error={fieldErr.name}>{(id, d) => <input id={id} className="field" autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} aria-invalid={!!fieldErr.name} aria-describedby={d} />}</Field>
        )}
        <Field label="E-mail" error={fieldErr.email}>{(id, d) => <input id={id} className="field" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} aria-invalid={!!fieldErr.email} aria-describedby={d} />}</Field>
        <Field label="Senha" error={fieldErr.password} hint={mode === 'register' ? 'Mínimo de 10 caracteres.' : undefined}>
          {(id, d) => <input id={id} className="field" type="password" autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={(e) => setPassword(e.target.value)} aria-invalid={!!fieldErr.password} aria-describedby={d} />}
        </Field>
        {error && <p className="error" role="alert" style={{ padding: '0 20px' }}>{error}</p>}
        <Button type="submit" disabled={busy}>{busy ? 'Aguarde…' : mode === 'login' ? 'Entrar' : 'Criar conta'}</Button>
        <Button type="button" variant="plain" onClick={() => setSettings({ localMode: true })}>Usar sem conta, só neste aparelho</Button>
      </form>
    </main>
  )
}
