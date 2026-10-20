import { Dec, rounded } from '../core/decimal'
import { NBSP } from '../core/money'
import { YearMonth, components, daysInMonth } from '../core/calendar'

// Formatação para a interface (design/tokens.md: menos tipográfico U+2212 antes do R$, "+" só em receitas,
// máscara "R$ ••••"). O Money.format do Core (hífen ASCII) continua sendo usado em CSV/relatórios.

export const MINUS = '−'
export const MASK = `R$${NBSP}••••`

export interface MoneyParts { sign: string; symbol: string; integer: string; fraction: string }

export function moneyParts(v: Dec, sign: 'auto' | 'plus' = 'auto'): MoneyParts {
  const r = rounded(v, 2)
  const neg = r.isNegative() && !r.isZero()
  const [i, f] = r.abs().toFixed(2).split('.') as [string, string]
  let grouped = ''
  for (let k = 0; k < i.length; k++) {
    if (k > 0 && k % 3 === 0) grouped = '.' + grouped
    grouped = i[i.length - 1 - k] + grouped
  }
  return { sign: neg ? MINUS : sign === 'plus' && !r.isZero() ? '+' : '', symbol: 'R$', integer: grouped, fraction: ',' + f }
}

export function fmtMoney(v: Dec, o: { sign?: 'auto' | 'plus'; hide?: boolean } = {}): string {
  if (o.hide) return MASK
  const p = moneyParts(v, o.sign)
  return `${p.sign}${p.symbol}${NBSP}${p.integer}${p.fraction}`
}

/** Para eixos de gráfico: "R$ 1,2 mil". */
export function fmtShort(v: Dec): string {
  const n = v.toNumber(), a = Math.abs(n)
  const s = (x: number) => x.toLocaleString('pt-BR', { maximumFractionDigits: 1 })
  if (a >= 1e6) return `${n < 0 ? MINUS : ''}R$${NBSP}${s(a / 1e6)} mi`
  if (a >= 1e3) return `${n < 0 ? MINUS : ''}R$${NBSP}${s(a / 1e3)} mil`
  return `${n < 0 ? MINUS : ''}R$${NBSP}${s(a)}`
}

const UN = ['zero', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez', 'onze', 'doze', 'treze', 'quatorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove']
const DZ = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa']
const CT = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos', 'setecentos', 'oitocentos', 'novecentos']
function below1000(n: number): string {
  if (n === 100) return 'cem'
  const parts: string[] = []
  if (n >= 100) parts.push(CT[Math.floor(n / 100)]!)
  const r = n % 100
  if (r > 0) parts.push(r < 20 ? UN[r]! : DZ[Math.floor(r / 10)]! + (r % 10 ? ' e ' + UN[r % 10] : ''))
  return parts.join(' e ')
}
export function numberWords(n: number): string {
  if (n === 0) return 'zero'
  const groups: [number, string, string][] = [[1e9, 'bilhão', 'bilhões'], [1e6, 'milhão', 'milhões'], [1e3, 'mil', 'mil']]
  const parts: string[] = []
  let rest = n
  for (const [size, sing, plur] of groups) {
    const q = Math.floor(rest / size)
    if (q > 0) {
      parts.push(size === 1e3 && q === 1 ? 'mil' : `${below1000(q)} ${q === 1 ? sing : plur}`)
      rest %= size
    }
  }
  if (rest > 0) parts.push(below1000(rest))
  return parts.length > 1 && rest > 0 && (rest < 100 || rest % 100 === 0) ? parts.slice(0, -1).join(', ') + ' e ' + parts[parts.length - 1] : parts.join(', ')
}
/** "menos quarenta e cinco reais e noventa centavos" (VoiceOver/leitores de tela). */
export function spokenMoney(v: Dec, hide = false): string {
  if (hide) return 'valor oculto'
  const r = rounded(v, 2)
  const neg = r.isNegative() && !r.isZero()
  const a = r.abs()
  const reais = a.floor().toNumber()
  const cents = a.minus(a.floor()).times(100).round().toNumber()
  const parts: string[] = []
  if (reais > 0 || cents === 0) parts.push(`${numberWords(reais)} ${reais === 1 ? 'real' : 'reais'}`)
  if (cents > 0) parts.push(`${numberWords(cents)} ${cents === 1 ? 'centavo' : 'centavos'}`)
  return (neg ? 'menos ' : '') + parts.join(' e ')
}

export const MONTHS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']
export const MONTHS_SHORT = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
export const WEEKDAYS = ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado']
export const monthName = (m: YearMonth): string => MONTHS[m.month - 1]!
export const monthTitle = (m: YearMonth): string => `${monthName(m)} de ${m.year}`
export const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1)
export const pad2 = (n: number): string => String(n).padStart(2, '0')
export function fmtDay(d: Date): string {
  const c = components(d)
  return `${pad2(c.day)}/${pad2(c.month)}/${c.year}`
}
export function fmtDayShort(d: Date): string {
  const c = components(d)
  return `${pad2(c.day)} ${MONTHS_SHORT[c.month - 1]}`
}
export function fmtDayLong(d: Date): string {
  const c = components(d)
  return `${cap(WEEKDAYS[d.getUTCDay()]!)}, ${c.day} de ${MONTHS[c.month - 1]}`
}
export const weekday = (d: Date): number => d.getUTCDay()
export { daysInMonth }

/** "12,5" -> usado em campos de percentual/taxa. */
export function fmtPercent(v: Dec | null | undefined): string {
  if (v === null || v === undefined) return '—'
  return v.toDecimalPlaces(2).toFixed().replace('.', ',') + '%'
}
