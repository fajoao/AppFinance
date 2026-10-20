// Cliente da API (mesma origem, /api; em produção o nginx faz proxy para a API). Contrato: Backend/openapi.yaml.

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public retryAfter?: number) {
    super(message)
    this.name = 'ApiError'
  }
}

export interface TokenPair { accessToken: string; refreshToken: string; expiresIn?: number }
export interface UserRef { id: string; email: string; name: string }
export interface HouseholdRef { id: string; name: string; role: 'admin' | 'member' | 'dependent' }
export interface Session { accessToken: string; refreshToken: string; expiresAt: number; user: UserRef; household: HouseholdRef }
export interface Me { user: UserRef; household: HouseholdRef; members: { userId: string; name: string; email: string; role: string }[] }
export interface SyncRecordWire { type: string; id: string; data?: Record<string, unknown>; updatedAt: string; deleted?: boolean }
export interface PullResponse { records: SyncRecordWire[]; token: number; hasMore?: boolean }
export interface PushResponse {
  accepted: string[]
  rejected: { id: string; reason: 'stale' | 'tie_lost' | 'forbidden_role'; serverRecord?: SyncRecordWire | null }[]
  token: number
}

const BASE = '/api'

export async function rawRequest<T>(path: string, init: { method?: string; body?: unknown; token?: string; signal?: AbortSignal } = {}): Promise<T> {
  let res: Response
  try {
    res = await fetch(BASE + path, {
      method: init.method ?? (init.body !== undefined ? 'POST' : 'GET'),
      headers: {
        ...(init.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      signal: init.signal,
    })
  } catch {
    throw new ApiError(0, 'network', 'Sem conexão com o servidor. Seus dados continuam salvos neste aparelho.')
  }
  if (res.status === 204) return undefined as T
  let json: unknown = null
  try { json = await res.json() } catch { /* corpo vazio ou HTML (erro do proxy) */ }
  if (!res.ok) {
    const j = (json ?? {}) as { error?: string; message?: string; retryAfter?: number }
    throw new ApiError(res.status, j.error ?? `http_${res.status}`, j.message ?? friendly(res.status), j.retryAfter ?? (Number(res.headers.get('Retry-After')) || undefined))
  }
  return json as T
}

function friendly(status: number): string {
  if (status === 401) return 'Sessão expirada. Entre novamente.'
  if (status === 429) return 'Muitas tentativas. Aguarde um pouco e tente de novo.'
  if (status >= 500) return 'O servidor está indisponível no momento.'
  return 'Não foi possível concluir a operação.'
}

/** Mensagens em pt-BR para códigos conhecidos da API. */
export function errorText(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.code === 'invalid_credentials') return 'E-mail ou senha incorretos.'
    if (e.code === 'email_in_use') return 'Este e-mail já está cadastrado.'
    if (e.status === 429 && e.retryAfter) return `Muitas tentativas. Tente de novo em ${e.retryAfter} s.`
    return e.message
  }
  return e instanceof Error ? e.message : 'Algo deu errado.'
}

export const authApi = {
  register: (p: { email: string; password: string; name: string }) =>
    rawRequest<TokenPair & { user: UserRef; household: HouseholdRef }>('/auth/register', { method: 'POST', body: p }),
  login: (p: { email: string; password: string }) => rawRequest<TokenPair>('/auth/login', { method: 'POST', body: p }),
  refresh: (refreshToken: string) => rawRequest<TokenPair>('/auth/refresh', { method: 'POST', body: { refreshToken } }),
  logout: (refreshToken: string) => rawRequest<void>('/auth/logout', { method: 'POST', body: { refreshToken } }),
  me: (token: string) => rawRequest<Me>('/me', { token }),
}
export const householdApi = {
  invite: (token: string, role: 'member' | 'dependent') => rawRequest<{ code: string; role: string; expiresAt: string }>('/households/invite', { method: 'POST', body: { role }, token }),
  join: (token: string, code: string) => rawRequest<{ household: HouseholdRef }>('/households/join', { method: 'POST', body: { code }, token }),
}
export const syncApi = {
  pull: (token: string, since: number, limit = 1000) => rawRequest<PullResponse>(`/sync?since=${since}&limit=${limit}`, { token }),
  push: (token: string, records: SyncRecordWire[]) => rawRequest<PushResponse>('/sync', { method: 'POST', body: { records }, token }),
}
