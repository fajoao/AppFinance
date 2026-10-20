import { dec } from '../core'
import { fmtShort } from '../app/format'

// Gráficos SVG próprios (sem dependências). Sempre com <title>/<desc> e rótulos de texto: a cor nunca é a única pista.

interface Series { name: string; color: string; points: (number | null)[]; dashed?: boolean }

export function LineChart({ series, labels, desc, height = 180, yFormat = (n: number) => fmtShort(dec(n)), step = false }: {
  series: Series[]; labels: string[]; desc: string; height?: number; yFormat?: (n: number) => string; step?: boolean
}) {
  const W = 600, H = height, L = 56, R = 12, T = 12, B = 24
  const all = series.flatMap((s) => s.points).filter((p): p is number => p !== null)
  if (all.length === 0) return null
  let min = Math.min(0, ...all), max = Math.max(0, ...all)
  if (min === max) max = min + 1
  const x = (i: number) => L + (labels.length <= 1 ? 0 : (i * (W - L - R)) / (labels.length - 1))
  const y = (v: number) => T + ((max - v) * (H - T - B)) / (max - min)
  const ticks = [max, (max + min) / 2, min]
  const path = (pts: (number | null)[]) => {
    let d = '', prev: number | null = null, started = false
    pts.forEach((p, i) => {
      if (p === null) { started = false; return }
      if (!started) d += `M${x(i)},${y(p)}`
      else d += step ? `L${x(i)},${y(prev!)}L${x(i)},${y(p)}` : `L${x(i)},${y(p)}`
      prev = p; started = true
    })
    return d
  }
  const every = Math.max(1, Math.ceil(labels.length / 6))
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={desc}>
      <title>{desc}</title>
      {ticks.map((t, i) => (
        <g key={i}><line x1={L} x2={W - R} y1={y(t)} y2={y(t)} stroke="var(--separator)" /><text x={L - 6} y={y(t) + 4} textAnchor="end">{yFormat(t)}</text></g>
      ))}
      {min < 0 && <line x1={L} x2={W - R} y1={y(0)} y2={y(0)} stroke="var(--border)" strokeWidth="1.5" />}
      {series.map((s) => <path key={s.name} d={path(s.points)} fill="none" stroke={s.color} strokeWidth="2.5" strokeLinejoin="round" strokeDasharray={s.dashed ? '6 5' : undefined} />)}
      {labels.map((l, i) => (i % every === 0 ? <text key={i} x={x(i)} y={H - 6} textAnchor="middle">{l}</text> : null))}
    </svg>
  )
}

export function Donut({ slices, desc }: { slices: { label: string; value: number; color: string }[]; desc: string }) {
  const total = slices.reduce((a, s) => a + s.value, 0)
  if (total <= 0) return null
  const R = 56, r = 36, c = 70
  let acc = 0
  return (
    <svg className="chart" viewBox="0 0 140 140" role="img" aria-label={desc} style={{ maxWidth: 180 }}>
      <title>{desc}</title>
      {slices.map((s) => {
        const a0 = (acc / total) * 2 * Math.PI - Math.PI / 2
        acc += s.value
        const a1 = (acc / total) * 2 * Math.PI - Math.PI / 2
        const large = a1 - a0 > Math.PI ? 1 : 0
        const p = (rad: number, a: number) => `${c + rad * Math.cos(a)},${c + rad * Math.sin(a)}`
        if (slices.length === 1) return <circle key={s.label} cx={c} cy={c} r={(R + r) / 2} fill="none" stroke={s.color} strokeWidth={R - r} />
        return <path key={s.label} d={`M${p(R, a0)}A${R},${R} 0 ${large} 1 ${p(R, a1)}L${p(r, a1)}A${r},${r} 0 ${large} 0 ${p(r, a0)}Z`} fill={s.color} stroke="var(--surface)" strokeWidth="1.5" />
      })}
    </svg>
  )
}

/** Duas barras horizontais (receitas × despesas) com a marca do mês anterior. */
export function CompareBars({ rows, desc }: { rows: { label: string; value: number; prev: number; color: string; text: string }[]; desc: string }) {
  const max = Math.max(1, ...rows.flatMap((r) => [r.value, r.prev]))
  return (
    <div role="img" aria-label={desc}>
      {rows.map((r) => (
        <div key={r.label} style={{ padding: '8px 20px 0' }}>
          <div className="kv" style={{ marginTop: 0 }}><span>{r.label}</span><span className="num">{r.text}</span></div>
          <div className="bar" style={{ marginTop: 6 }}>
            <i style={{ width: `${(r.value / max) * 100}%`, ['--c' as string]: r.color }} />
            <b style={{ left: `${(r.prev / max) * 100}%` }} title="Mês anterior" />
          </div>
        </div>
      ))}
    </div>
  )
}
