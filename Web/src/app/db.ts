// IndexedDB: entidades (JSON Codable do Core), fila de sincronização e metadados. Sem dependências.
export interface StoredEntity { key: string; type: string; id: string; data: Record<string, unknown> }
export interface QueueItem { key: string; type: string; id: string; deleted: boolean; updatedAt: string }

const DB_NAME = 'financas-web'
const VERSION = 1
let dbPromise: Promise<IDBDatabase> | null = null

function open(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      db.createObjectStore('entities', { keyPath: 'key' })
      db.createObjectStore('queue', { keyPath: 'key' })
      db.createObjectStore('meta', { keyPath: 'k' })
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
  return dbPromise
}

/** Só para testes: descarta a conexão em cache. */
export function resetDbConnection(): void {
  dbPromise = null
}

function tx<T>(stores: string[], mode: IDBTransactionMode, fn: (t: IDBTransaction) => Promise<T> | T): Promise<T> {
  return open().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const t = db.transaction(stores, mode)
        let result: T
        Promise.resolve(fn(t)).then((r) => (result = r), reject)
        t.oncomplete = () => resolve(result)
        t.onerror = () => reject(t.error)
        t.onabort = () => reject(t.error)
      }),
  )
}
const reqP = <T>(r: IDBRequest<T>): Promise<T> => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error) })

export const entityKey = (type: string, id: string): string => `${type}:${id}`

export const db = {
  allEntities: () => tx(['entities'], 'readonly', (t) => reqP(t.objectStore('entities').getAll() as IDBRequest<StoredEntity[]>)),
  putEntities: (list: StoredEntity[]) => tx(['entities'], 'readwrite', (t) => { const s = t.objectStore('entities'); list.forEach((e) => s.put(e)) }),
  deleteEntities: (keys: string[]) => tx(['entities'], 'readwrite', (t) => { const s = t.objectStore('entities'); keys.forEach((k) => s.delete(k)) }),
  allQueue: () => tx(['queue'], 'readonly', (t) => reqP(t.objectStore('queue').getAll() as IDBRequest<QueueItem[]>)),
  putQueue: (list: QueueItem[]) => tx(['queue'], 'readwrite', (t) => { const s = t.objectStore('queue'); list.forEach((e) => s.put(e)) }),
  deleteQueue: (keys: string[]) => tx(['queue'], 'readwrite', (t) => { const s = t.objectStore('queue'); keys.forEach((k) => s.delete(k)) }),
  getMeta: <T>(k: string) => tx(['meta'], 'readonly', async (t) => (await reqP(t.objectStore('meta').get(k)) as { k: string; v: T } | undefined)?.v),
  setMeta: (k: string, v: unknown) => tx(['meta'], 'readwrite', (t) => { t.objectStore('meta').put({ k, v }) }),
  delMeta: (k: string) => tx(['meta'], 'readwrite', (t) => { t.objectStore('meta').delete(k) }),
  clearData: () => tx(['entities', 'queue'], 'readwrite', (t) => { t.objectStore('entities').clear(); t.objectStore('queue').clear() }),
}
