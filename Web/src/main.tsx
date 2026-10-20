import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'
import { App } from './App'
import { useApp } from './app/store'
import { startSyncLoop } from './app/syncClient'
import { materializeRecurrences, payDueAllowances } from './app/actions'

void useApp.getState().init().then(() => {
  try { materializeRecurrences(); payDueAllowances() } catch { /* dados incompletos: ignorar */ }
  startSyncLoop()
})
createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
