import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import * as C from '../src/core'

// Entidades codificadas pelo Core Swift real (golden) devem sobreviver a decode -> encode sem alteração.
describe('codec (formato Codable do Swift)', () => {
  const suite = JSON.parse(readFileSync(join(__dirname, 'golden', 'report.json'), 'utf8')) as { cases: { input: Record<string, unknown[]> }[] }
  const input = suite.cases[0]!.input
  it('transações: decode/encode idempotente', () => {
    for (const w of input.transactions as Record<string, unknown>[]) {
      const back = JSON.parse(JSON.stringify(C.encodeEntity('Transaction', C.decodeEntity('Transaction', w))))
      expect(back).toEqual(w)
    }
  })
  it('categorias: decode/encode idempotente', () => {
    for (const w of input.categories as Record<string, unknown>[]) {
      expect(JSON.parse(JSON.stringify(C.encodeEntity('Category', C.decodeEntity('Category', w))))).toEqual(w)
    }
  })
  it('datas: segundos desde 2001 viram o dia civil correto', () => {
    // 815140800 = 2026-10-31 12:00 UTC (valor produzido pelo Swift no teste de exploração)
    expect(C.isoDay(C.dateFromWire(815140800))).toBe('2026-10-31')
    expect(C.dateToWire(C.civil(2026, 10, 31))).toBe(815140800)
  })
  it('dados antigos (sem campos novos) recebem padrões', () => {
    const a = C.decodeEntity('Account', { id: 'A', name: 'x', type: 'checking', initialBalance: 10.5, currency: 'BRL', isArchived: false, createdAt: 0, updatedAt: 0 })
    expect(a.visibility).toBe('shared')
    expect(a.initialBalance.toString()).toBe('10.5')
  })
  it('dinheiro nunca passa por float: 100,01 em 10x soma exatamente', () => {
    const parts = C.Money.split(C.dec('100.01'), 10)
    expect(C.sum(parts).toString()).toBe('100.01')
  })
})

describe('newId', () => {
  it('gera UUID v4 maiúsculo, inclusive sem crypto.randomUUID (http fora de localhost)', () => {
    const orig = globalThis.crypto.randomUUID
    Object.defineProperty(globalThis.crypto, 'randomUUID', { value: undefined, configurable: true })
    try {
      const id = C.newId()
      expect(id).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/)
      expect(C.newId()).not.toBe(id)
    } finally {
      Object.defineProperty(globalThis.crypto, 'randomUUID', { value: orig, configurable: true })
    }
  })
})
