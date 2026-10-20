import { Dec, dec, rounded, ZERO, sum } from './decimal'

export const CURRENCY_SYMBOL = 'R$'
export const NBSP = ' '

/** Formata em pt-BR: "R$ 1.234,56" (espaço não separável); negativos: "-R$ 1.234,56" (mesmo formato do Core). */
export function format(value: Dec, withSymbol = true): string {
  const r = rounded(value, 2)
  const negative = r.isNegative() && !r.isZero()
  const [intPart, frac] = r.abs().toFixed(2).split('.') as [string, string]
  let grouped = ''
  for (let i = 0; i < intPart.length; i++) {
    if (i > 0 && i % 3 === 0) grouped = '.' + grouped
    grouped = intPart[intPart.length - 1 - i] + grouped
  }
  const number = `${grouped},${frac}`
  const body = withSymbol ? CURRENCY_SYMBOL + NBSP + number : number
  return negative ? '-' + body : body
}

/** Número com 2 casas, sem símbolo nem agrupamento ("-1234,56"). */
export function plain(value: Dec, decimalSeparator = ','): string {
  const f = format(value, false).replace(/\./g, '')
  return f.replace(',', decimalSeparator)
}

export type DecimalStyle = 'auto' | 'comma' | 'dot'

/** Interpreta "R$ 1.234,56", "-1234.56", "(123,45)", "1.234", "12,5". null se inválido. */
export function parse(raw: string, style: DecimalStyle = 'auto'): Dec | null {
  let s = raw.trim().replace(/R\$/g, '').replace(/ /g, '').replace(/ /g, '')
  if (s === '') return null
  let negative = false
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true
    s = s.slice(1, -1)
  }
  if (s.startsWith('-')) {
    negative = !negative
    s = s.slice(1)
  } else if (s.startsWith('+')) s = s.slice(1)
  if (s.endsWith('-')) {
    negative = !negative
    s = s.slice(0, -1)
  }
  if (s === '') return null
  if (!/^[0-9,.]+$/.test(s)) return null
  const commas = (s.match(/,/g) ?? []).length
  const dots = (s.match(/\./g) ?? []).length
  let decimalSep: string | null = null
  if (style === 'comma') decimalSep = ','
  else if (style === 'dot') decimalSep = '.'
  else if (commas > 0 && dots > 0) decimalSep = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.'
  else if (commas > 0) decimalSep = ','
  else if (dots === 1) {
    const after = s.split('.').pop()!.length
    decimalSep = after === 3 ? null : '.'
  }
  let intDigits = '', fracDigits = ''
  let seen = false
  for (const ch of s) {
    if (ch === decimalSep) {
      if (seen) return null
      seen = true
    } else if (ch === ',' || ch === '.') continue
    else if (seen) fracDigits += ch
    else intDigits += ch
  }
  if (intDigits === '') intDigits = '0'
  if (seen && fracDigits === '') return null
  const v = dec(fracDigits === '' ? intDigits : `${intDigits}.${fracDigits}`)
  return negative ? v.neg() : v
}

/** Divide `total` em `count` partes de centavos exatos; a última absorve o resto. */
export function split(total: Dec, count: number): Dec[] {
  if (count < 1) return []
  const t = rounded(total, 2)
  const sign = t.isNegative() ? dec(-1) : dec(1)
  const abs = t.abs()
  const base = rounded(abs.div(count), 2, 'down')
  const parts = Array.from({ length: count }, () => base.times(sign))
  parts[count - 1] = t.minus(base.times(sign).times(count - 1))
  return parts
}

/** Divide proporcionalmente a `weights`. O último absorve o resto. */
export function allocate(total: Dec, weights: Dec[]): Dec[] {
  if (weights.length === 0) return []
  const s = sum(weights)
  if (s.isZero()) return split(total, weights.length)
  const t = rounded(total, 2)
  const parts: Dec[] = []
  let acc = ZERO
  weights.forEach((w, i) => {
    if (i === weights.length - 1) parts.push(t.minus(acc))
    else {
      const p = rounded(t.times(w).div(s), 2, 'plain')
      parts.push(p)
      acc = acc.plus(p)
    }
  })
  return parts
}
