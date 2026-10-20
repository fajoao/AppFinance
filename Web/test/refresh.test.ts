import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as C from '../src/core'

// Ambiente mínimo de navegador para o store
Object.assign(globalThis, { document: { documentElement: { dataset: {} }, querySelector: () => null, addEventListener: () => {} }, window: { addEventListener: () => {} } })

const { useApp } = await import('../src/app/store')
const { refreshNow } = await import('../src/app/refresh')
const { db } = await import('../src/app/db')
const { syncNow } = await import('../src/app/syncClient')

interface Call { url: string; method: string; body?: { records?: { id: string; type: string; deleted?: boolean }[] } }
let calls: Call[]
let responder: (c: Call) => Response | Promise<Response>
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json' } })

const session = { accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 600_000, user: { id: 'u', email: 'a@b.c', name: 'Ana' }, household: { id: 'h', name: 'Casa', role: 'admin' as const } }

beforeEach(async () => {
  calls = []
  responder = (c) => (c.url.includes('since') ? json({ records: [], token: 5, hasMore: false }) : json({ accepted: c.body?.records?.map((r) => r.id.toLowerCase()) ?? [], rejected: [], token: 5 }))
  vi.stubGlobal('fetch', async (url: string, init?: RequestInit) => {
    const c: Call = { url, method: init?.method ?? 'GET', body: init?.body ? JSON.parse(init.body as string) : undefined }
    calls.push(c)
    return responder(c)
  })
  await db.clearData()
  await db.delMeta('syncToken')
  await useApp.getState().init()
  useApp.setState({ session: null, data: C.emptySnapshot(), syncInfo: { status: 'off', pending: 0 } })
})

const clock = () => new Date(2026, 9, 20, 14, 5)

describe('botão Atualizar (refreshNow)', () => {
  it('sem conta: recarrega os dados locais', async () => {
    const r = await refreshNow(clock)
    expect(r.ok).toBe(true)
    expect(r.message).toContain('Dados locais recarregados às 14:05')
    expect(calls).toHaveLength(0)
  })

  it('com conta: envia a fila (push) e depois busca desde o último token (pull); mostra a hora', async () => {
    useApp.setState({ session })
    const acc = C.mkAccount({ name: 'Nubank', type: 'checking' })
    useApp.getState().put('Account', acc)
    await new Promise((r) => setTimeout(r, 50))
    calls.length = 0
    await db.setMeta('syncToken', 7)
    const r = await refreshNow(clock)
    expect(r).toEqual({ ok: true, offline: false, message: 'Atualizado às 14:05' })
    const post = calls.find((c) => c.method === 'POST')!
    expect(post.body!.records![0]!.type).toBe('Account')
    const get = calls.find((c) => c.method === 'GET')!
    expect(get.url).toContain('since=7')
    expect(await db.getMeta('syncToken')).toBe(5)
    expect((await db.allQueue()).length).toBe(0)
  })

  it('não dispara requisições paralelas: cliques repetidos compartilham a execução', async () => {
    useApp.setState({ session })
    let release!: () => void
    const gate = new Promise<void>((res) => { release = res })
    responder = async () => { await gate; return json({ records: [], token: 1, hasMore: false }) }
    const a = refreshNow(clock), b = refreshNow(clock)
    expect(a).toBe(b)
    release()
    await a
    expect(calls.filter((c) => c.method === 'GET')).toHaveLength(1)
  })

  it('aplica registros do servidor e recarrega os dados exibidos', async () => {
    useApp.setState({ session })
    const remote = C.mkAccount({ name: 'Vinda do iPhone', type: 'savings' })
    responder = (c) => (c.url.includes('since')
      ? json({ records: [{ type: 'Account', id: remote.id.toLowerCase(), data: C.encodeEntity('Account', remote), updatedAt: remote.updatedAt.toISOString() }], token: 9, hasMore: false })
      : json({ accepted: [], rejected: [], token: 9 }))
    await refreshNow(clock)
    expect(useApp.getState().data.accounts.map((a) => a.name)).toEqual(['Vinda do iPhone'])
    expect((await db.allQueue()).length).toBe(0)
  })

  it('offline: mensagem clara e os dados locais continuam', async () => {
    useApp.setState({ session })
    useApp.getState().put('Tag', C.mkTag({ name: 'x' }))
    await new Promise((r) => setTimeout(r, 50))
    vi.stubGlobal('fetch', async () => { throw new TypeError('Failed to fetch') })
    const r = await refreshNow(clock)
    expect(r.ok).toBe(false)
    expect(r.offline).toBe(true)
    expect(r.message).toMatch(/Sem conexão/)
    expect(useApp.getState().data.tags).toHaveLength(1)
    expect((await db.allQueue()).length).toBeGreaterThan(0)
  })

  it('erro do servidor: mensagem em português', async () => {
    useApp.setState({ session })
    responder = () => json({ error: 'internal', message: 'O servidor está indisponível no momento.' }, 500)
    const r = await refreshNow(clock)
    expect(r.ok).toBe(false)
    expect(r.message).toContain('Não foi possível atualizar')
  })

  it('conflito: vence o maior updatedAt (servidor rejeita como stale e devolve o vencedor)', async () => {
    useApp.setState({ session })
    const local = C.mkAccount({ name: 'Local antigo', type: 'checking' })
    local.updatedAt = new Date('2026-10-01T10:00:00Z')
    useApp.getState().commit({ put: [['Account', local]] })
    await new Promise((r) => setTimeout(r, 50))
    const winner = { ...local, name: 'Servidor novo', updatedAt: new Date('2026-10-02T10:00:00Z') }
    responder = (c) => (c.method === 'POST'
      ? json({ accepted: [], rejected: [{ id: local.id.toLowerCase(), reason: 'stale', serverRecord: { type: 'Account', id: local.id.toLowerCase(), data: C.encodeEntity('Account', winner), updatedAt: winner.updatedAt.toISOString() } }], token: 3 })
      : json({ records: [], token: 3, hasMore: false }))
    await syncNow()
    expect(useApp.getState().data.accounts[0]!.name).toBe('Servidor novo')
    expect((await db.allQueue()).length).toBe(0)
  })

  it('exclusão local vira deleted:true + Tombstone no envelope', async () => {
    useApp.setState({ session })
    const t = C.mkTag({ name: 'apagar' })
    useApp.getState().put('Tag', t)
    await new Promise((r) => setTimeout(r, 50))
    await syncNow()
    calls.length = 0
    useApp.getState().del('Tag', t.id)
    await new Promise((r) => setTimeout(r, 50))
    await syncNow()
    const recs = calls.find((c) => c.method === 'POST')!.body!.records!
    expect(recs.some((r) => r.type === 'Tag' && r.deleted)).toBe(true)
    expect(recs.some((r) => r.type === 'Tombstone')).toBe(true)
  })
})
