// Dia civil = Date em UTC ao meio-dia (mesma convenção do Core Swift: FinanceCalendar).
const DAY = 86_400_000

export interface YearMonth {
  year: number
  month: number // 1...12
}

export function ym(year: number, month: number): YearMonth {
  const total = year * 12 + (month - 1)
  const y = Math.floor(total / 12)
  return { year: y, month: total - y * 12 + 1 }
}
export const ymOf = (d: Date): YearMonth => ym(d.getUTCFullYear(), d.getUTCMonth() + 1)
export const ymAdd = (m: YearMonth, n: number): YearMonth => ym(m.year, m.month + n)
export const ymPrev = (m: YearMonth): YearMonth => ymAdd(m, -1)
export const ymNext = (m: YearMonth): YearMonth => ymAdd(m, 1)
export const ymEq = (a: YearMonth, b: YearMonth): boolean => a.year === b.year && a.month === b.month
export const ymCmp = (a: YearMonth, b: YearMonth): number => a.year - b.year || a.month - b.month
export const ymMonthsTo = (a: YearMonth, b: YearMonth): number => (b.year - a.year) * 12 + (b.month - a.month)
export const ymLabel = (m: YearMonth): string => `${String(m.month).padStart(2, '0')}/${m.year}`
export const ymKey = (m: YearMonth): string => `${m.year}-${String(m.month).padStart(2, '0')}`
export const ymContains = (m: YearMonth, d: Date): boolean => ymEq(ymOf(d), m)

export function isLeapYear(y: number): boolean {
  return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0
}
export function daysInMonth(m: YearMonth): number {
  switch (m.month) {
    case 2:
      return isLeapYear(m.year) ? 29 : 28
    case 4:
    case 6:
    case 9:
    case 11:
      return 30
    default:
      return 31
  }
}
/** Data civil do dia `day`, limitado a 1...último dia do mês. */
export function ymDate(m: YearMonth, day: number): Date {
  const d = Math.min(Math.max(day, 1), daysInMonth(m))
  return new Date(Date.UTC(m.year, m.month - 1, d, 12))
}
export const ymFirst = (m: YearMonth): Date => ymDate(m, 1)
export const ymLast = (m: YearMonth): Date => ymDate(m, daysInMonth(m))

export const civil = (y: number, m: number, d: number): Date => ymDate(ym(y, m), d)

/** Converte um instante para o dia civil local (fuso do navegador). */
export function normalizeLocal(d: Date): Date {
  return civil(d.getFullYear(), d.getMonth() + 1, d.getDate())
}
export const todayCivil = (): Date => normalizeLocal(new Date())

export function components(d: Date): { year: number; month: number; day: number } {
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() }
}
export function startOfDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
}
export const dayNum = (d: Date): number => Math.floor(startOfDay(d).getTime() / DAY)
export const isSameDay = (a: Date, b: Date): boolean => dayNum(a) === dayNum(b)
export const isBeforeDay = (a: Date, b: Date): boolean => dayNum(a) < dayNum(b)
export const addDays = (d: Date, n: number): Date => new Date(d.getTime() + n * DAY)

/** Soma meses preservando a hora e limitando o dia (31/jan + 1 mês = 28 ou 29/fev). */
export function addMonths(d: Date, n: number): Date {
  const target = ym(d.getUTCFullYear(), d.getUTCMonth() + 1 + n)
  const day = Math.min(d.getUTCDate(), daysInMonth(target))
  return new Date(
    Date.UTC(target.year, target.month - 1, day, d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds()),
  )
}
export const addYears = (d: Date, n: number): Date => addMonths(d, 12 * n)
export const daysBetween = (a: Date, b: Date): number => dayNum(b) - dayNum(a)

/** "2026-10-31" */
export function isoDay(d: Date): string {
  const c = components(d)
  return `${c.year}-${String(c.month).padStart(2, '0')}-${String(c.day).padStart(2, '0')}`
}
export function parseIsoDay(s: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  if (!m) return null
  const y = +m[1]!, mo = +m[2]!, d = +m[3]!
  if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(ym(y, mo))) return null
  return civil(y, mo, d)
}
