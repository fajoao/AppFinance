// E2E contra o stack real (nginx + API + Postgres). Playwright roda em container (veja e2e/run.sh).
import { chromium } from 'playwright'

const BASE = process.env.BASE_URL ?? 'http://host.docker.internal:8080'
const SHOTS = process.env.SHOTS ?? '/shots'
const stamp = Date.now()
const email = `e2e+${stamp}@example.com`, password = 'senha-forte-123'
const results = []
const check = async (name, fn) => {
  try { await fn(); results.push([true, name]); console.log('PASS', name) } catch (e) { results.push([false, name]); console.log('FAIL', name, '\n   ', String(e.message).split('\n')[0]) }
}
const expect = (c, m) => { if (!c) throw new Error(m) }

const browser = await chromium.launch()
const api = async (path, init = {}, token) => {
  const r = await fetch(BASE + '/api' + path, { ...init, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) } })
  return r.json()
}

// ---------- Fluxo 1: cadastro -> onboarding -> lançamento -> dashboard -> atualizar ----------
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', colorScheme: 'light' })
const page = await ctx.newPage()
page.on('pageerror', (e) => console.log('PAGEERROR', e.message))
await page.goto(BASE + '/')
await check('tela de login carrega e tem CSP', async () => {
  await page.getByRole('heading', { name: 'Entrar' }).waitFor()
  const r = await page.request.get(BASE + '/')
  expect((r.headers()['content-security-policy'] ?? '').includes("default-src 'self'"), 'sem CSP')
})
await page.screenshot({ path: `${SHOTS}/desktop-claro-login.png` })
await check('senha curta é recusada no cadastro (validação)', async () => {
  await page.getByRole('radio', { name: 'Criar conta' }).click()
  await page.getByLabel('Nome', { exact: true }).fill('Teste E2E')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha').fill('curta')
  await page.getByRole('button', { name: 'Criar conta' }).click()
  await page.getByText('Use ao menos 10 caracteres.').waitFor()
})
await check('cadastro na API real e onboarding', async () => {
  await page.getByLabel('Senha').fill(password)
  await page.getByRole('button', { name: 'Criar conta' }).click()
  await page.getByRole('button', { name: 'Começar' }).waitFor({ timeout: 15000 })
  await page.getByRole('button', { name: 'Começar' }).click()
  await page.getByLabel('Nome da conta').fill('Conta E2E')
  await page.getByLabel('Saldo de hoje (R$)').fill('1.000,00')
  await page.getByRole('button', { name: 'Concluir' }).click()
  await page.getByRole('heading', { name: 'Início' }).waitFor()
})
await check('criar lançamento (despesa 45,90 com categoria sugerida)', async () => {
  await page.getByRole('button', { name: 'Novo lançamento' }).first().click()
  await page.getByTestId('tx-amount').fill('45,90')
  await page.getByTestId('tx-title').fill('Padaria E2E')
  await page.getByText('Sugerida').waitFor()
  await page.getByTestId('tx-source').selectOption({ label: 'Conta E2E' })
  await page.screenshot({ path: `${SHOTS}/desktop-claro-novo-lancamento.png` })
  await page.getByTestId('tx-save').click()
  await page.getByText('Lançamento salvo.').waitFor()
})
await check('dashboard mostra a despesa e o saldo 954,10', async () => {
  const t = await page.locator('main').innerText()
  expect(t.includes('Mercado'), 'categoria Mercado ausente no dashboard')
  expect(page.getByLabel(/novecentos e cinquenta e quatro reais e dez centavos/).first() !== null, 'saldo')
  await page.locator('.amt-split').first().waitFor()
  const label = await page.locator('.amt-split').first().getAttribute('aria-label')
  expect(label === 'novecentos e cinquenta e quatro reais e dez centavos', 'saldo errado: ' + label)
})
await check('lançamento aparece em Lançamentos e busca funciona', async () => {
  await page.goto(BASE + '/#/lancamentos')
  await page.getByText('Padaria E2E').first().waitFor()
  await page.getByTestId('tx-search').fill('padaria')
  await page.getByText('1 lançamento,').waitFor()
  await page.getByTestId('tx-search').fill('zzzz')
  await page.getByText('Nada por aqui').waitFor()
  await page.getByTestId('tx-search').fill('')
})
await check('botão Atualizar: sincroniza com a API real e mostra "Atualizado às HH:MM"', async () => {
  const btn = page.getByRole('button', { name: 'Atualizar' })
  await btn.click()
  await page.getByTestId('refresh-status').filter({ hasText: /Atualizado às \d\d:\d\d/ }).waitFor({ timeout: 15000 })
  expect(await btn.isEnabled(), 'botão deveria reabilitar')
})
let token
await check('registro chegou ao servidor (GET /api/sync)', async () => {
  const login = await api('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) })
  token = login.accessToken
  const s = await api('/sync?since=0', {}, token)
  const tx = s.records.find((r) => r.type === 'Transaction' && r.data.title === 'Padaria E2E')
  expect(tx, 'transação ausente no servidor')
  expect(tx.data.amount === 45.9 && tx.data.type === 'expense', 'dados diferentes: ' + JSON.stringify(tx.data))
  expect(typeof tx.data.date === 'number' && tx.data.date > 7e8, 'data não está no formato do Core (segundos desde 2001)')
  expect(/^\d{4}-\d\d-\d\dT/.test(tx.updatedAt), 'updatedAt do envelope não é ISO')
})
await check('botão desabilita durante a execução e atalho R funciona', async () => {
  await page.route('**/api/sync**', async (route) => { await new Promise((r) => setTimeout(r, 700)); await route.continue() })
  await page.keyboard.press('r')
  const btn = page.getByRole('button', { name: 'Atualizar' })
  await page.waitForFunction(() => document.querySelector('[data-testid=refresh]').disabled === true, null, { timeout: 3000 })
  expect(await page.locator('.refresh-btn.spin').count() === 1, 'sem animação de giro')
  await page.getByTestId('refresh-status').filter({ hasText: /Atualizado às/ }).waitFor({ timeout: 15000 })
  expect(await btn.isEnabled(), 'não reabilitou')
  await page.unroute('**/api/sync**')
})
await check('R não dispara dentro de campo de texto', async () => {
  await page.goto(BASE + '/#/lancamentos')
  await page.getByTestId('tx-search').click()
  const before = await page.getByTestId('refresh-status').innerText()
  await page.keyboard.type('r')
  expect((await page.getByTestId('tx-search').inputValue()) === 'r', 'não digitou')
  expect((await page.getByTestId('refresh-status').innerText()) === before, 'disparou atualização')
  await page.getByTestId('tx-search').fill('')
})
await check('offline: aviso claro e dados locais mantidos', async () => {
  await ctx.setOffline(true)
  await page.getByRole('button', { name: 'Atualizar' }).click()
  await page.getByTestId('refresh-status').filter({ hasText: /Sem conexão/ }).waitFor({ timeout: 15000 })
  await page.getByText('Padaria E2E').first().waitFor()
  await ctx.setOffline(false)
})
await check('lançamento criado offline sobe depois de reconectar', async () => {
  await ctx.setOffline(true)
  await page.getByRole('button', { name: 'Novo lançamento' }).first().click()
  await page.getByTestId('tx-amount').fill('10,00')
  await page.getByTestId('tx-title').fill('Criado offline')
  await page.getByTestId('tx-source').selectOption({ label: 'Conta E2E' })
  await page.getByTestId('tx-save').click()
  await page.getByText('Criado offline').first().waitFor()
  await ctx.setOffline(false)
  await page.getByRole('button', { name: 'Atualizar' }).click()
  await page.getByTestId('refresh-status').filter({ hasText: /Atualizado às/ }).waitFor({ timeout: 15000 })
  const s = await api('/sync?since=0', {}, token)
  expect(s.records.some((r) => r.type === 'Transaction' && r.data.title === 'Criado offline'), 'não subiu')
})

// ---------- Fluxo 2: outro dispositivo (contexto limpo) vê os dados ----------
const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' })
const p2 = await ctx2.newPage()
await p2.goto(BASE + '/')
await check('segundo dispositivo: login e dados chegam por sincronização', async () => {
  await p2.getByLabel('E-mail').fill(email)
  await p2.getByLabel('Senha').fill(password)
  await p2.getByRole('button', { name: 'Entrar' }).last().click()
  await p2.getByRole('heading', { name: 'Início' }).waitFor({ timeout: 20000 })
  await p2.goto(BASE + '/#/lancamentos')
  await p2.getByText('Padaria E2E').first().waitFor({ timeout: 15000 })
})
await check('mobile: puxar para atualizar (gesto de toque) chama a sincronização', async () => {
  await p2.goto(BASE + '/#/lancamentos')
  await p2.evaluate(() => scrollTo(0, 0))
  const cdp = await ctx2.newCDPSession(p2)
  const tp = (type, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x: 200, y }] })
  await tp('touchStart', 150)
  for (let y = 160; y <= 290; y += 20) await tp('touchMove', y)
  await tp('touchEnd', 290)
  await p2.getByTestId('refresh-status').filter({ hasText: /Atualizado às/ }).waitFor({ timeout: 15000 })
})
await check('mobile: botão Atualizar visível e com rótulo acessível', async () => {
  const b = p2.getByRole('button', { name: 'Atualizar' })
  expect(await b.isVisible(), 'invisível')
  const box = await b.boundingBox()
  expect(box.width >= 44 && box.height >= 44, 'alvo de toque < 44px')
})
await ctx2.close()

// ---------- Fluxo 3: telas com dados de exemplo (capturas) ----------
const email3 = `e2e+demo${stamp}@example.com`
async function shots(viewport, scheme, prefix, mobile) {
  const c = await browser.newContext({ viewport, deviceScaleFactor: mobile ? 2 : 1, isMobile: mobile, hasTouch: mobile, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', colorScheme: scheme })
  const p = await c.newPage()
  p.on('pageerror', (e) => console.log('PAGEERROR', e.message))
  await p.goto(BASE + '/')
  await p.getByRole('radio', { name: 'Criar conta' }).click()
  await p.getByLabel('Nome', { exact: true }).fill('Demo')
  await p.getByLabel('E-mail').fill(prefix + email3)
  await p.getByLabel('Senha').fill(password)
  await p.getByRole('button', { name: 'Criar conta' }).click()
  await p.getByRole('button', { name: 'Explorar com dados de exemplo' }).click({ timeout: 15000 })
  await p.getByRole('heading', { name: 'Início' }).waitFor()
  const name = `${mobile ? 'celular-390' : 'desktop-1440'}-${scheme === 'dark' ? 'escuro' : 'claro'}`
  const screens = [['inicio', '/'], ['lancamentos', '/lancamentos'], ['orcamento', '/orcamento'], ['contas-a-pagar', '/contas-a-pagar'], ['metas', '/metas'], ['contas', '/contas'], ['cartoes', '/cartoes'], ['investimentos', '/investimentos'], ['dividas', '/dividas'], ['fluxo-de-caixa', '/fluxo'], ['relatorios', '/relatorios'], ['familia', '/familia'], ['ajustes', '/ajustes']]
  for (const [n, path] of screens) {
    await p.goto(BASE + '/#' + path)
    await p.waitForTimeout(350)
    await p.screenshot({ path: `${SHOTS}/${name}-${n}.png`, fullPage: false })
  }
  await p.goto(BASE + '/#/dividas')
  await p.getByRole('button', { name: 'Simular quitação' }).click()
  await p.getByTestId('sim-avalanche').waitFor()
  await p.screenshot({ path: `${SHOTS}/${name}-simulador-dividas.png` })
  await c.close()
}
await check('capturas desktop 1440 claro/escuro', async () => { await shots({ width: 1440, height: 900 }, 'light', 'a', false); await shots({ width: 1440, height: 900 }, 'dark', 'b', false) })
await check('capturas celular 390 claro/escuro', async () => { await shots({ width: 390, height: 844 }, 'light', 'c', true); await shots({ width: 390, height: 844 }, 'dark', 'd', true) })

await check('dados de exemplo: simulador avalanche × bola de neve e CSV', async () => {
  const c = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true, locale: 'pt-BR' })
  const p = await c.newPage()
  await p.goto(BASE + '/')
  await p.getByRole('button', { name: 'Usar sem conta, só neste aparelho' }).click()
  await p.getByRole('button', { name: 'Explorar com dados de exemplo' }).click()
  await p.goto(BASE + '/#/relatorios')
  const [dl] = await Promise.all([p.waitForEvent('download'), p.getByTestId('export-csv').click()])
  expect(dl.suggestedFilename().endsWith('.csv'), 'sem csv')
  await p.goto(BASE + '/#/dividas')
  await p.getByRole('button', { name: 'Simular quitação' }).click()
  await p.getByTestId('sim-avalanche').waitFor(); await p.getByTestId('sim-snowball').waitFor()
  await c.close()
})

await browser.close()
const failed = results.filter(([ok]) => !ok)
console.log(`\nE2E: ${results.length - failed.length}/${results.length} passaram`)
process.exit(failed.length ? 1 : 0)
