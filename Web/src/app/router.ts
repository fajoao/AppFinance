import { useEffect, useState } from 'react'

// Roteador por hash (#/caminho?x=1): funciona em qualquer hospedagem estática, sem configuração de servidor.
export interface Route { path: string; query: URLSearchParams }

function parse(): Route {
  const raw = location.hash.replace(/^#/, '') || '/'
  const [p, q] = raw.split('?')
  return { path: p || '/', query: new URLSearchParams(q ?? '') }
}

export function useRoute(): Route {
  const [r, setR] = useState(parse)
  useEffect(() => {
    const h = () => setR(parse())
    window.addEventListener('hashchange', h)
    return () => window.removeEventListener('hashchange', h)
  }, [])
  return r
}
export function navigate(path: string, replace = false): void {
  if (replace) location.replace('#' + path)
  else location.hash = path
}
export const back = (fallback = '/'): void => {
  if (history.length > 1) history.back()
  else navigate(fallback)
}
