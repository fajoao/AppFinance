/** Baixa um arquivo de texto. CSV leva BOM UTF-8 para abrir direto no Excel pt-BR. */
export function downloadText(filename: string, text: string, mime = 'text/csv;charset=utf-8', bom = true): void {
  const blob = new Blob([bom ? '﻿' : '', text], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
