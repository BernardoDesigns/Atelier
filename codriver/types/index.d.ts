export type Msg = { role: 'you' | 'claude' | 'note'; text: string }

export type Course = 'on course' | 'drifting' | 'blocked'

export type Debrief = {
  happened: string[]
  course: Course
  why: string
  watch: string[]
}

export type Flag = {
  level: 'amber' | 'red'
  why: string
  text: string
}

export type CourseFile = { path: string; isTrimmed: boolean }

declare module 'claude-code' {
  interface PluginState {
    'codriver': {
      messages: Shaped<Msg[]>
      debrief: Shaped<Debrief | null>
      ready: string | null
      busy: boolean
      seesSession: boolean
      model: string
      lastAnswer: string
      source: string
      flag: Flag | null
      tightenedFrom: string | null
      courseFiles: CourseFile[]
    }
  }
}
