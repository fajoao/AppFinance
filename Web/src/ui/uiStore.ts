import { create } from 'zustand'
import { Draft } from '../app/logic'

interface UiState {
  draft: Draft | null
  openDraft(d: Draft): void
  closeDraft(): void
}
export const useUi = create<UiState>((set) => ({ draft: null, openDraft: (draft) => set({ draft }), closeDraft: () => set({ draft: null }) }))
