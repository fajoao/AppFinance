import { useRef, useState } from 'react'
import * as C from '../core'
import { eraseAllData, loadDemo, logout } from '../app/actions'
import { useApp, Theme } from '../app/store'
import { syncNow } from '../app/syncClient'
import { downloadText } from '../app/download'
import { useView } from '../app/hooks'
import { Button, Group, Row, Segmented, Switch, useConfirm } from '../ui/kit'
import { Page } from '../ui/Shell'

export function SettingsScreen() {
  const v = useView()
  const settings = useApp((s) => s.settings)
  const setSettings = useApp((s) => s.setSettings)
  const session = useApp((s) => s.session)
  const info = useApp((s) => s.syncInfo)
  const data = useApp((s) => s.data)
  const confirm = useConfirm()
  const [busy, setBusy] = useState(false)
  const file = useRef<HTMLInputElement>(null)
  const exportAll = () => downloadText('financas-todos-os-lancamentos.csv', C.exportCSV(data.transactions, data.accounts, data.categories, data.tags))
  const backup = () => downloadText('financas-backup.json', JSON.stringify(C.encodeSnapshot(data), null, 1), 'application/json', false)
  const restore = async (f: File | undefined) => {
    if (!f) return
    try {
      const snap = C.decodeSnapshot(JSON.parse(await f.text()))
      for (const t of C.ENTITY_TYPES) {
        const list = snap[C.COLLECTION[t]] as unknown[]
        if (list.length) useApp.getState().commit({ put: list.map((e) => [t, e]) as never })
      }
      useApp.getState().toast('Backup restaurado.')
    } catch { useApp.getState().toast('Arquivo de backup inválido.', 'danger') }
  }
  const status = !session ? 'Somente neste aparelho' : info.status === 'syncing' ? 'Sincronizando…' : info.status === 'offline' ? 'Sem conexão: alterações ficam na fila' : info.status === 'error' ? `Erro: ${info.error}` : info.lastSyncAt ? `Sincronizado às ${new Date(info.lastSyncAt).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}` : 'Conectado'
  return (
    <Page title="Configurações">
      <Group label="Conta e sincronização">
        {session ? <>
          <Row title={session.user.name} sub={session.user.email} />
          <Row title="Sincronização" sub={`${status}${info.pending ? ` · ${info.pending} pendente(s)` : ''}`} trailing={<Button small variant="secondary" disabled={busy} onClick={async () => { setBusy(true); await syncNow(); setBusy(false) }}>Sincronizar</Button>} />
          <Row title="Sair" sub="Os dados continuam neste aparelho" onClick={() => void logout()} />
        </> : <Row title="Sem conta" sub="Entre para sincronizar com o app do iPhone" onClick={() => setSettings({ localMode: false })} />}
      </Group>
      <Group label="Aparência">
        <div className="row"><span className="main"><span className="t1">Tema</span></span></div>
      </Group>
      <Segmented<Theme> label="Tema" value={settings.theme} onChange={(t) => setSettings({ theme: t })} options={[{ value: 'system', label: 'Sistema' }, { value: 'light', label: 'Claro' }, { value: 'dark', label: 'Escuro' }]} />
      <Group>
        <Row title="Ocultar valores" sub="Troca todos os valores por R$ ••••" trailing={<Switch checked={settings.hideValues} onChange={(x) => setSettings({ hideValues: x })} label="Ocultar valores" />} />
      </Group>
      <Group label="Dados">
        <Row icon="download" title="Exportar lançamentos (CSV)" sub="Ponto e vírgula, vírgula decimal, abre no Excel" onClick={exportAll} />
        <Row icon="download" title="Backup completo (JSON)" sub="Mesmo formato do app do iPhone" onClick={backup} />
        <Row icon="upload" title="Restaurar backup" onClick={() => file.current?.click()} />
        <Row icon="upload" title="Importar extrato OFX/CSV" href="#/importar" />
        <Row icon="tag" title="Categorias" href="#/categorias" />
        <Row icon="coins" title="Carregar dados de exemplo" sub="Adiciona contas, cartões e lançamentos de demonstração" onClick={() => confirm.ask('Adicionar os dados de exemplo aos seus dados?', loadDemo)} />
        <Row icon="trash" title="Apagar todos os dados" sub="Remove tudo deste aparelho e da conta" onClick={() => confirm.ask('Apagar TODOS os dados? Esta ação não pode ser desfeita.', () => void eraseAllData())} />
      </Group>
      <input ref={file} type="file" accept="application/json,.json" hidden onChange={(e) => void restore(e.target.files?.[0])} aria-label="Arquivo de backup" />
      <p className="note">Privacidade: os dados ficam neste navegador (IndexedDB). Com conta, também no servidor, apenas para você e seu grupo familiar. Valores em reais (BRL).</p>
      <p className="note">Versão web 1.0 · {v.transactions.length} lançamentos carregados.</p>
      {confirm.node}
    </Page>
  )
}
