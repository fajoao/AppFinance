import Decimal from 'decimal.js'

// Precisão alta para imitar o Decimal do Swift (38 dígitos). Arredondamento padrão: meio para cima (longe de zero).
Decimal.set({ precision: 40, rounding: Decimal.ROUND_HALF_UP, toExpNeg: -40, toExpPos: 40 })

export type Dec = Decimal
export { Decimal }

/** Cria um Decimal exato a partir de texto ("100.01") ou inteiro. Nunca passe números fracionários de float. */
export function dec(v: string | number | Decimal): Dec {
  return new Decimal(v)
}
export const ZERO = new Decimal(0)

export type RoundMode = 'plain' | 'down' | 'up'
const MODES: Record<RoundMode, Decimal.Rounding> = {
  plain: Decimal.ROUND_HALF_UP,
  down: Decimal.ROUND_DOWN,
  up: Decimal.ROUND_UP,
}

/** Arredonda para `scale` casas (padrão 2); `plain` = meio para cima (como o varejo BR). */
export function rounded(d: Dec, scale = 2, mode: RoundMode = 'plain'): Dec {
  return d.toDecimalPlaces(scale, MODES[mode])
}
export function truncated(d: Dec, scale = 2): Dec {
  return d.toDecimalPlaces(scale, Decimal.ROUND_DOWN)
}
export const sum = (list: Dec[]): Dec => list.reduce((a, b) => a.plus(b), ZERO)
export const dmax = (a: Dec, b: Dec): Dec => (a.gte(b) ? a : b)
export const dmin = (a: Dec, b: Dec): Dec => (a.lte(b) ? a : b)
