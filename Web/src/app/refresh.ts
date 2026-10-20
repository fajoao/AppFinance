import { syncNow } from './syncClient'
import { useApp } from './store'

export interface RefreshResult { ok: boolean; offline: boolean; message: string }

let inflight: Promise<RefreshResult> | null = null
const hhmm = (d: Date) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`

/**
 * Botão "Atualizar": sincronização imediata (push da fila + pull desde o último token) e releitura dos dados.
 * Chamadas simultâneas compartilham a mesma execução (nunca há requisições paralelas).
 */
export function refreshNow(now: () => Date = () => new Date()): Promise<RefreshResult> {
  if (inflight) return inflight
  inflight = (async (): Promise<RefreshResult> => {
    const st = useApp.getState()
    try {
      if (!st.session) {
        await st.reload()
        return { ok: true, offline: false, message: `Dados locais recarregados às ${hhmm(now())}. Entre na sua conta para sincronizar.` }
      }
      await syncNow()
      await useApp.getState().reload()
      const info = useApp.getState().syncInfo
      if (info.status === 'offline') return { ok: false, offline: true, message: 'Sem conexão. Mostrando os dados salvos neste aparelho; as alterações serão enviadas quando a rede voltar.' }
      if (info.status === 'error') return { ok: false, offline: false, message: `Não foi possível atualizar: ${info.error ?? 'erro desconhecido'}` }
      if (!useApp.getState().session) return { ok: false, offline: false, message: 'Sessão expirada. Entre novamente para sincronizar.' }
      return { ok: true, offline: false, message: `Atualizado às ${hhmm(now())}` }
    } catch (e) {
      return { ok: false, offline: false, message: `Não foi possível atualizar: ${e instanceof Error ? e.message : 'erro'}` }
    } finally {
      inflight = null
    }
  })()
  return inflight
}
