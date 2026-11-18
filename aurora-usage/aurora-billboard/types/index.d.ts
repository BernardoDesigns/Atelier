export type Limit = { percent: number; resetsAt?: string }

export type Snapshot = {
  fiveHour: Limit | null
  sevenDay: Limit | null
  contextTokens?: number
  contextWindow: number
  contextPercent?: number
  costUsd?: number
}

export type LimitKey = '5h' | '7d'

// The lines, pause points, notes and snoozes, as they sit in the shared file. A
// missing line means the default, a missing pause point means none, a missing
// snooze means not snoozed. A note rides along with a limit's heads-up.
export type Gate = {
  showAt: Partial<Record<LimitKey, number>>
  pauseAt?: Partial<Record<LimitKey, number>>
  note?: Partial<Record<LimitKey, string>>
  snooze: Partial<Record<LimitKey, number>>
}

// ~/.claude/aurora-usage.json, shared with the floating HUD (main.swift reads
// and writes the same keys).
export type Shared = {
  v?: 1
  updatedAt?: number
  fiveHour?: Limit | null
  sevenDay?: Limit | null
  theme?: string
  glyph?: 'thin' | 'block'
  showAt?: Gate['showAt']
  pauseAt?: Gate['pauseAt']
  note?: Gate['note']
  snooze?: Gate['snooze']
  // Set by `aurora profile <name>`. Informational: the lines above are what count.
  profile?: string
}

declare module 'claude-code' {
  interface PluginState {
    'aurora-billboard': {
      snapshot: Shaped<Snapshot | null>
      model: string | null
      theme: string
      glyph: 'thin' | 'block'
      now: number
      gate: Gate
    }
  }
}
