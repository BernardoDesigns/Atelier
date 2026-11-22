import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Course, CourseFile, Debrief, Flag, Msg } from '../types'

// Co-driver: the person in the passenger seat with the map. It never touches the
// wheel (no tools, never sends a prompt on its own). It reads back where you just
// went (Debrief), checks it against the route you planned (the course files),
// calls out hazards (Watch out), and hands you the next turn written down
// (Ready for Claude Code). Preflight is the glance over before you pull out.

const PANE = 'codriver'
const TITLE = 'Co-driver'

// Aurora palette, same values as the billboard and the HUD.
const C = {
  ok: '#8bc66b',
  warn: '#e5b454',
  hot: '#e0685c',
  mute: '#8b8f98',
  accent: '#c99be8',
}

const MODELS = ['opus', 'sonnet', 'haiku'] as const
const MODEL_LABEL: Record<string, string> = { sonnet: 'Sonnet', opus: 'Opus', haiku: 'Haiku' }
const EFFORT = 'medium' as const

// Preflight runs on every prompt you type, so it is small, fast and bounded.
const PREFLIGHT_MODEL = 'haiku'
const PREFLIGHT_TIMEOUT_MS = 3000

const messages = atom({ plugin: 'codriver', key: 'messages' } as const, [], { shape: 'msgs-1' })
const debrief = atom({ plugin: 'codriver', key: 'debrief' } as const, null, { shape: 'debrief-1' })
const ready = atom({ plugin: 'codriver', key: 'ready' } as const, null)
const busy = atom({ plugin: 'codriver', key: 'busy' } as const, false)
const seesSession = atom({ plugin: 'codriver', key: 'seesSession' } as const, false)
const model = atom({ plugin: 'codriver', key: 'model' } as const, 'opus')
const lastAnswer = atom({ plugin: 'codriver', key: 'lastAnswer' } as const, '')
const source = atom({ plugin: 'codriver', key: 'source' } as const, '')
const flag = atom({ plugin: 'codriver', key: 'flag' } as const, null)
const tightenedFrom = atom({ plugin: 'codriver', key: 'tightenedFrom' } as const, null)
const courseFiles = atom({ plugin: 'codriver', key: 'courseFiles' } as const, [])

// ---------- The course: what Co-driver checks the work against ----------

const COURSE_FIXED = ['CLAUDE.md', 'NEXT.md', 'STATUS.md', 'next-session-starter.md']
const POINTED_NAME = /(plan|status|next|roadmap|progress|todo|spec|handoff)/i
const MAX_POINTED = 4
const MAX_FILE = 12_000
const MAX_COURSE = 40_000
const MAX_SOURCE = 60_000
const MAX_TRANSCRIPT = 30_000

// Plan or status files CLAUDE.md points to: markdown links, `code` paths, @imports.
// Only relative paths inside the project. Never the home folder, never outside.
function pointedFiles(claudeMd: string): string[] {
  const found = new Set<string>()
  const re = /(?:\]\(|`|@|\s|^)((?:\.\/)?[\w][\w\-./]*\.(?:md|markdown|txt))(?=[)`\s,.;:]|$)/gm
  for (const m of claudeMd.matchAll(re)) {
    let p = m[1]!.replace(/^\.\//, '')
    if (p.startsWith('/') || p.startsWith('~') || p.split('/').includes('..')) continue
    const base = p.split('/').pop() ?? p
    if (!POINTED_NAME.test(base)) continue
    if (COURSE_FIXED.includes(p)) continue
    found.add(p)
    if (found.size >= MAX_POINTED) break
  }
  return [...found]
}

type LoadedCourse = { files: CourseFile[]; text: string }

// Every em dash out, en dashes to hyphens. The person asked for none in its writing.
function plain(s: string): string {
  return s.replace(/\s*—\s*/g, ', ').replace(/–/g, '-').trim()
}

const RISKY = /\b(delete|remove|rm\b|drop|truncate|wipe|reset|force|--force|-f\b|rebase|migrat|overwrite|rewrite|purge|prod|production|deploy|secret|credential|\.env|chmod|sudo|everything|all files|whole)/i

// ---------- Prompts ----------

const VOICE = `Voice:
- The person is a senior product designer, not an engineer. Talk to them like a sharp friend in the passenger seat.
- Plain language. No jargon. If a technical word is unavoidable, explain it in a few words the first time.
- Short sentences. No filler. Never use em dashes.
- You have no tools. You only know what is in this message: the course files, the output you were given, and the conversation. Never claim you ran, read or changed anything else.`

const DEBRIEF = `You are Co-driver, a second pair of eyes beside a Claude Code session. Claude Code just did some work. Read its output and tell the person what it means, check it against their plan (the course files), and write their next prompt.

${VOICE}

Reply with JSON only, no code fence, in exactly this shape:
{
  "happened": ["line 1", "line 2", "line 3"],
  "course": "on course" | "drifting" | "blocked",
  "why": "one or two plain sentences, naming the course file it was checked against",
  "watch": ["one risk per line, or an empty list"],
  "next": "the next prompt for Claude Code"
}

Rules for each part:
- happened: exactly 3 lines, plain language, what changed and what it means for the person. No file paths unless they matter to the person.
- course: "on course" if the work matches the plan, "drifting" if it went beyond, sideways or skipped a planned step, "blocked" if it stopped, failed or is waiting on the person. If there are no course files, judge against what the output says it set out to do, and say so in why.
- watch: only real risks seen in the output: deleted files or branches, database or data migrations, force-pushes or history rewrites, edits to protected paths (settings, credentials, .env, CI, lockfiles, anything the course files say not to touch), big rewrites, scope creep beyond the plan, quiet assumptions it made without asking. Empty list when there are none. Do not pad it.
- next: a tight prompt the person can send to Claude Code. Shape it:
  First line: the goal in one sentence.
  Files in scope: the files or folders it may change. Everything else is out of scope.
  Steps: short numbered steps.
  Ask first: before deleting anything, migrating data, force-pushing, rewriting history, or touching files outside scope, stop and ask.
  Stop and report if: tests fail, the plan and the code disagree, or the step needs a decision.
  Done when: one checkable line.
  If the work is blocked, the next prompt is about unblocking it. If it drifted, the next prompt steers it back.`

const CHAT = `You are Co-driver, a second pair of eyes beside a Claude Code session. The person can push back on your debrief, or ask what something means.

${VOICE}
- Answer what they asked. Usually 1 to 4 sentences.
- If they ask what something means, explain it with a quick everyday comparison.
- If they push back and they are right, say so and adjust. If they are not, say why, kindly, in one line.
- If they ask you to change the next prompt, reply with the full new prompt after a line that says exactly: NEXT PROMPT:`

const TIGHTEN = `You are Co-driver. The person typed a prompt for Claude Code that looked risky or loose. Rewrite it so it does what they meant, safely.

${VOICE}

Shape it:
First line: the goal in one sentence.
Files in scope: what it may change (guess sensibly from the prompt and course; mark a guess with "(check)").
Steps: short numbered steps. Turn anything destructive into "list what would be removed, then ask me before doing it".
Ask first: before deleting anything, migrating data, force-pushing, rewriting history, or touching files outside scope.
Stop and report if: tests fail, something does not match the plan, or a step needs a decision.
Done when: one checkable line.

Reply with the prompt only, nothing before or after it.`

const PREFLIGHT = `You rate a prompt a person is about to send to Claude Code, an AI that edits their code and runs commands. The person is a designer, not an engineer.

GREEN: clear and safe. Most prompts are green, including short replies like "yes", "go ahead", "looks good", questions, and normal small edits.
AMBER: will probably work but is loose or a bit risky: vague scope ("fix everything", "clean it up"), a big rewrite, touches settings or config, wanders away from the plan.
RED: could lose work or break things: deleting files or branches, force-pushing, rewriting git history, resetting, database or data migrations, touching credentials or .env, deploying to production, running something with sudo.

Answer one line only:
GREEN
or
AMBER: <why, under 12 words, plain language, no em dashes>
or
RED: <why, under 12 words, plain language, no em dashes>`

// ---------- Parsing ----------

const COURSES: Course[] = ['on course', 'drifting', 'blocked']

function parseDebrief(raw: string): { debrief: Debrief; next: string } | null {
  const start = raw.indexOf('{')
  const end = raw.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  let j: any
  try {
    j = JSON.parse(raw.slice(start, end + 1))
  } catch {
    return null
  }
  const lines = (v: unknown) =>
    Array.isArray(v) ? v.filter(x => typeof x === 'string' && x.trim()).map(x => plain(x as string)) : []
  const course = String(j.course ?? '').toLowerCase().trim()
  const happened = lines(j.happened).slice(0, 3)
  if (happened.length === 0) return null
  return {
    debrief: {
      happened,
      course: (COURSES.includes(course as Course) ? course : 'drifting') as Course,
      why: plain(String(j.why ?? '')),
      watch: lines(j.watch),
    },
    next: plain(String(j.next ?? '')),
  }
}

function parseRating(raw: string): { level: 'green' | 'amber' | 'red'; why: string } | null {
  const line = raw.trim().split('\n')[0]!.trim()
  const m = /^\**\s*(GREEN|AMBER|RED)\b\**\s*[:\-]?\s*(.*)$/i.exec(line)
  if (!m) return null
  const level = m[1]!.toLowerCase() as 'green' | 'amber' | 'red'
  return { level, why: plain(m[2] ?? '').replace(/\.$/, '') }
}

function transcript(list: readonly Msg[]): string {
  const lines = list
    .filter(m => m.role !== 'note')
    .map(m => `${m.role === 'you' ? 'Person' : 'Co-driver'}: ${m.text}`)
  let text = lines.join('\n\n')
  while (text.length > MAX_TRANSCRIPT && lines.length > 1) {
    lines.shift()
    text = '(earlier messages trimmed)\n\n' + lines.join('\n\n')
  }
  return text
}

function clip(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '\n(trimmed)' : s
}

// Per-process scratch, rebuilt on reload: what is being typed, the course text,
// the call in flight. Values that must survive a reload live in atoms instead.
type ModelResult =
  | Awaited<ReturnType<EngineInterface['model']['complete']>>
  | Awaited<ReturnType<EngineInterface['model']['fork']>>

type Scratch = {
  cwd: string
  projectName: string
  typedSource: string
  typedChat: string
  courseText: string
  stop: AbortController | null
  lastSentReady: string
}

// Reads the course files fresh each time, so a NEXT.md edited mid-session counts.
async function loadCourse($: EngineInterface, s: Scratch): Promise<LoadedCourse> {
  const files: CourseFile[] = []
  const parts: string[] = []
  let total = 0
  // Always the session's own folder, spelled out, never wherever a relative path lands.
  const at = (path: string) => (s.cwd ? `${s.cwd}/${path}` : path)
  const claudeMd = (await $.fs.exists(at('CLAUDE.md')).catch(() => false))
    ? String(await $.fs.read(at('CLAUDE.md')).catch(() => ''))
    : ''
  for (const path of [...COURSE_FIXED, ...pointedFiles(claudeMd)]) {
    if (total >= MAX_COURSE) break
    try {
      if (!(await $.fs.exists(at(path)))) continue
      const body = String(await $.fs.read(at(path)))
      const room = Math.min(MAX_FILE, MAX_COURSE - total)
      const isTrimmed = body.length > room
      const kept = body.slice(0, room)
      total += kept.length
      files.push({ path, isTrimmed })
      parts.push(`=== ${path}${isTrimmed ? ' (trimmed)' : ''} ===\n${kept}`)
    } catch {
      // unreadable: leave it out, the header shows what did load
    }
  }
  s.courseText = parts.join('\n\n')
  await update($, courseFiles, () => files)
  return { files, text: s.courseText }
}

function courseBlock(text: string): string {
  return text
    ? `The course (the person's plan and rules):\n\n${text}`
    : 'The course: no course files were found in this project.'
}

// One completion, through the session when "Session: on", else standalone.
async function ask($: EngineInterface, s: Scratch, system: string, prompt: string, maxTokens: number) {
  s.stop = new AbortController()
  let r: ModelResult | undefined
  let fellBack = false
  if (await read($, seesSession)) {
    r = await $.model.fork({
      prompt:
        `[Side request from the Co-driver pane. Don't continue the build work above; use it only as context.]\n\n` +
        `${system}\n\n${prompt}`,
      effort: EFFORT,
    })
    if (!r.isAnswered && r.reason === 'nothing-to-fork') fellBack = true
  }
  if (!r || fellBack) {
    r = await $.model.complete(
      { model: await read($, model), effort: EFFORT, system: [{ text: system, cache: true }], prompt, maxTokens },
      { signal: s.stop.signal },
    )
  }
  s.stop = null
  if (fellBack) {
    await update($, messages, (l): Msg[] => [
      ...l,
      { role: 'note', text: 'The session had nothing to share yet, so that came from the pane alone.' },
    ])
  }
  return r
}

async function failNote($: EngineInterface, r: ModelResult) {
  if (r.isAnswered || r.reason === 'aborted') return
  const why = r.reason === 'api-error' ? `API error ${r.status}` : r.reason
  await update($, messages, (l): Msg[] => [...l, { role: 'note', text: `No reply (${why}). Try again.` }])
}

async function keepWords($: EngineInterface, text: string) {
  await $.clock.sleep(400)
  const box = await $.prompt.read()
  if (!box.text.trim()) await $.prompt.fill({ text, mode: 'replace' })
}

async function runDebrief($: EngineInterface, s: Scratch) {
  if (await read($, busy)) return
  const text = s.typedSource.trim()
  if (!text) {
    $.ui.toast('Paste some Claude Code output first, or use the last answer.')
    return
  }
  await update($, busy, () => true)
  await update($, messages, () => [])
  const course = await loadCourse($, s)
  const r = await ask(
    $,
    s,
    DEBRIEF,
    `${courseBlock(course.text)}\n\nClaude Code's output:\n\n${clip(text, MAX_SOURCE)}`,
    4000,
  )
  if (r.isAnswered) {
    const parsed = parseDebrief(r.text)
    if (parsed) {
      await update($, debrief, () => parsed.debrief)
      await update($, ready, () => parsed.next || null)
      await update($, tightenedFrom, () => null)
    } else {
      await update($, messages, (l): Msg[] => [
        ...l,
        { role: 'note', text: 'The debrief came back in the wrong shape. Here it is as-is:' },
        { role: 'claude', text: plain(r.text) },
      ])
    }
  } else {
    await failNote($, r)
  }
  await update($, busy, () => false)
}

async function runChat($: EngineInterface, s: Scratch, value: string) {
  const text = value.trim()
  if (!text || (await read($, busy))) return
  s.typedChat = ''
  await update($, messages, (l): Msg[] => [...l, { role: 'you', text }])
  await update($, busy, () => true)
  const d = await read($, debrief)
  const nextPrompt = await read($, ready)
  const context = [
    courseBlock(s.courseText),
    s.typedSource.trim() ? `Claude Code's output:\n\n${clip(s.typedSource, MAX_SOURCE)}` : '',
    d
      ? `Your debrief:\nWhat happened: ${d.happened.join(' ')}\nOn course? ${d.course}. ${d.why}\nWatch out: ${d.watch.join('; ') || 'nothing'}`
      : '',
    nextPrompt ? `The next prompt you wrote:\n${nextPrompt}` : '',
    `The conversation:\n\n${transcript(await read($, messages))}`,
    'Reply to the last message from the person.',
  ]
    .filter(Boolean)
    .join('\n\n')
  const r = await ask($, s, CHAT, context, 2000)
  if (r.isAnswered) {
    const reply = plain(r.text)
    const cut = reply.indexOf('NEXT PROMPT:')
    if (cut >= 0) {
      const newPrompt = reply.slice(cut + 'NEXT PROMPT:'.length).trim()
      if (newPrompt) await update($, ready, () => newPrompt)
      const said = reply.slice(0, cut).trim() || 'Updated the prompt below.'
      await update($, messages, (l): Msg[] => [...l, { role: 'claude', text: said }])
    } else {
      await update($, messages, (l): Msg[] => [...l, { role: 'claude', text: reply }])
    }
  } else {
    await failNote($, r)
  }
  await update($, busy, () => false)
}

async function runTighten($: EngineInterface, s: Scratch) {
  const f = await read($, flag)
  if (!f) return
  await update($, flag, () => null)
  await $.ui.open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true })
  if (await read($, busy)) return
  await update($, busy, () => true)
  await update($, messages, (l): Msg[] => [
    ...l,
    { role: 'note', text: `Tightening your prompt (${f.level}: ${f.why}).` },
  ])
  const course = await loadCourse($, s)
  const r = await ask($, s, TIGHTEN, `${courseBlock(course.text)}\n\nThe prompt they typed:\n\n${f.text}`, 2000)
  if (r.isAnswered) {
    await update($, ready, () => plain(r.text))
    await update($, tightenedFrom, () => f.text)
  } else {
    await failNote($, r)
  }
  await update($, busy, () => false)
}

async function sendAnyway($: EngineInterface, s: Scratch) {
  const f = await read($, flag)
  if (!f) return
  await update($, flag, () => null)
  const box = await $.prompt.read()
  const text = box.text.trim() || f.text
  await $.prompt.fill({ text: '', mode: 'replace' })
  await $.prompt.submit({ text, asUser: true })
}


export const register: Register = on => {
  const s: Scratch = { cwd: '', projectName: '', typedSource: '', typedChat: '', courseText: '', stop: null, lastSentReady: '' }

  // ---------- Session, command, last answer ----------

  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    await $.command.register({
      name: 'codriver',
      description: 'Co-driver: debrief Claude Code output, check it against your plan, get a guarded next prompt. /codriver, /codriver clear, /codriver model opus',
    })
    s.cwd = e.cwd.replace(/\/+$/, '')
    s.projectName = e.cwd.split('/').filter(Boolean).pop() ?? ''
    await loadCourse($, s)
    const savedModel = await $.store.get('model')
    if (typeof savedModel === 'string' && MODELS.includes(savedModel as (typeof MODELS)[number])) {
      await update($, model, () => savedModel)
    }
    return ran
  })

  on('command.run', { command: 'codriver' }, async ($, e) => {
    const [sub, value] = e.args.trim().split(/\s+/)
    if (sub === 'clear') {
      s.stop?.abort()
      s.typedSource = ''
      s.typedChat = ''
      await update($, messages, () => [])
      await update($, debrief, () => null)
      await update($, ready, () => null)
      await update($, source, () => '')
      return { text: 'Co-driver cleared.' }
    }
    if (sub === 'model') {
      if (!value || !MODELS.includes(value as (typeof MODELS)[number])) {
        return { text: `Co-driver models: ${MODELS.join(', ')}` }
      }
      await update($, model, () => value)
      await $.store.set('model', value)
      return { text: `Co-driver model: ${MODEL_LABEL[value]}` }
    }
    const opened = await $.ui.open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true })
    return { text: opened.isPlaced ? 'Co-driver open. Esc closes it.' : 'Co-driver is waiting for room to open.' }
  })

  // Remember the latest main-loop answer. Never acts on it: Debrief only runs on a press.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && e.reason === 'answer' && e.answer.trim()) {
      await update($, lastAnswer, () => e.answer)
    }
    return next(e)
  })

  // ---------- Preflight ----------

  on('prompt.submit', async ($, e, next) => {
    // Only what the person typed themselves. Slash commands, plugin prompts
    // (Send anyway included), notifications and hidden prompts go straight through.
    if (e.origin.kind !== 'composer' || e.isMeta) return next(e)
    const text = e.text.trim()

    // Any new send retires the last flag. Enter again on the same flagged words
    // means "send anyway".
    const f = await read($, flag)
    if (f) await update($, flag, () => null)
    if (f && f.text.trim() === text) return next(e)
    if (e.command || !text) return next(e)

    // A prompt Co-driver wrote and handed over is already guarded.
    if (s.lastSentReady && text === s.lastSentReady.trim()) return next(e)

    // Short, harmless replies ("yes", "go ahead") skip the model.
    if (text.split(/\s+/).length <= 4 && !RISKY.test(text)) return next(e)

    let rating: ReturnType<typeof parseRating> = null
    try {
      const r = await $.model.complete({
        model: PREFLIGHT_MODEL,
        effort: 'low',
        system: [{ text: PREFLIGHT, cache: true }],
        prompt: `${s.courseText ? `The project's plan, for scope:\n${s.courseText.slice(0, 6000)}\n\n` : ''}The prompt:\n${clip(text, 8000)}`,
        maxTokens: 60,
        timeoutMs: PREFLIGHT_TIMEOUT_MS,
      })
      if (r.isAnswered) rating = parseRating(r.text)
    } catch {
      rating = null
    }

    // Green, a timeout, an error or an answer it can't read: send as typed.
    if (!rating || rating.level === 'green') return next(e)

    const why = rating.why || (rating.level === 'red' ? 'this could lose work' : 'this is a bit loose')
    await update($, flag, () => ({ level: rating!.level as Flag['level'], why, text: e.text }))
    // The engine puts a dropped prompt back in the box itself. Only if it didn't,
    // put the words back, so nothing is lost. Enter again sends it as-is.
    void keepWords($, e.text).catch(() => undefined)
    return { drop: `Co-driver, ${rating.level}: ${why}. Enter sends it as-is.` }
  })

  // The one-line flag above the prompt, with the choice.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const f = await read($, flag)
    if (!f || e.props.hasSurvey) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const color = f.level === 'red' ? C.hot : C.warn
    return (
      <Box flexDirection="row" gap={1} flexWrap="wrap">
        <Text color={color} bold>
          {f.level === 'red' ? '● Red' : '● Amber'}
        </Text>
        <Text>{f.why}</Text>
        <Button key="cd-anyway" label="Send anyway" onPress={() => sendAnyway($, s)} />
        <Button key="cd-tighten" variant="primary" label="Let Co-driver tighten it" onPress={() => runTighten($, s)} />
        <Button key="cd-dismiss" label="Dismiss" onPress={() => update($, flag, () => null)} />
      </Box>
    )
  })

  // ---------- The pane ----------

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input, Markdown } = $.ui.resolve(e)
    const list = await read($, messages)
    const d = await read($, debrief)
    const prompt = await read($, ready)
    const isBusy = await read($, busy)
    const withSession = await read($, seesSession)
    const modelName = await read($, model)
    const files = await read($, courseFiles)
    const last = await read($, lastAnswer)
    await read($, source) // redraw when "Use last answer" fills the box

    const useLast = async () => {
      const a = await read($, lastAnswer)
      if (!a.trim()) {
        $.ui.toast('No answer yet this session. Paste one instead.')
        return
      }
      s.typedSource = a
      await update($, source, () => a)
    }

    const toPrompt = async () => {
      const text = await read($, ready)
      if (!text) {
        $.ui.toast('Nothing ready yet. Run a Debrief first.')
        return
      }
      const box = await $.prompt.read()
      const draft = box.text.trim()
      const from = await read($, tightenedFrom)
      // Replacing is only for the exact risky prompt Co-driver put back for tightening.
      const replacesFlagged = !!from && draft === from.trim()
      const hasDraft = draft.length > 0 && !replacesFlagged
      await $.prompt.fill({ text: hasDraft ? `\n\n${text}` : text, mode: hasDraft ? 'append' : 'replace' })
      s.lastSentReady = text
      $.ui.toast(
        replacesFlagged
          ? 'Swapped in the tightened version. Give it a read, then send.'
          : hasDraft
            ? 'Added under your draft. Give it a read, then send.'
            : 'In the prompt box. Give it a read, then send.',
      )
    }

    const clear = async () => {
      s.stop?.abort()
      s.typedSource = ''
      s.typedChat = ''
      await update($, messages, () => [])
      await update($, debrief, () => null)
      await update($, ready, () => null)
      await update($, source, () => '')
      await update($, tightenedFrom, () => null)
      await update($, busy, () => false)
    }

    const cycleModel = async () => {
      const i = MODELS.indexOf(modelName as (typeof MODELS)[number])
      const nextModel = MODELS[(i + 1) % MODELS.length]!
      await update($, model, () => nextModel)
      await $.store.set('model', nextModel)
    }

    const courseLine = files.length
      ? `Course: ${files.map(f => (f.isTrimmed ? `${f.path} (trimmed)` : f.path)).join(', ')}`
      : 'Course: no CLAUDE.md or plan files found, so I can only judge the output on its own'
    const statusColor = d?.course === 'on course' ? C.ok : d?.course === 'blocked' ? C.hot : C.warn

    return (
      <Box flexDirection="column" gap={1} paddingX={1}>
        <Box flexDirection="column">
          <Text color={C.mute}>
            {s.projectName ? `${s.projectName} · ` : ''}
            {withSession ? 'sees the session' : 'pane only'} · {withSession ? 'session model' : MODEL_LABEL[modelName] ?? modelName}
          </Text>
          <Text color={C.mute}>{courseLine}</Text>
        </Box>

        <Input
          key="source"
          rows={5}
          label="Claude Code output"
          placeholder="Paste what Claude Code said here…"
          submitLabel="keep"
          value={s.typedSource}
          autoFocus
          onInput={value => {
            s.typedSource = value
          }}
          onSubmit={value => {
            s.typedSource = value
          }}
        />

        <Box flexDirection="row" gap={1} flexWrap="wrap">
          <Button key="debrief" variant="primary" onPress={() => runDebrief($, s)}>
            Debrief
          </Button>
          <Button key="last" onPress={() => useLast()}>
            {last.trim() ? 'Use last answer' : 'Use last answer (none yet)'}
          </Button>
        </Box>

        {isBusy && <Text color={C.mute}>reading…</Text>}

        {d && (
          <Box flexDirection="column" gap={1}>
            <Box flexDirection="column">
              <Text color={C.accent} bold>
                What happened
              </Text>
              {d.happened.map(line => (
                <Text>{line}</Text>
              ))}
            </Box>
            <Box flexDirection="column">
              <Text color={C.accent} bold>
                On course?
              </Text>
              <Text color={statusColor} bold>
                {d.course === 'on course' ? 'On course' : d.course === 'blocked' ? 'Blocked' : 'Drifting'}
              </Text>
              {d.why ? <Text>{d.why}</Text> : null}
            </Box>
            {d.watch.length > 0 && (
              <Box flexDirection="column">
                <Text color={C.hot} bold>
                  Watch out
                </Text>
                {d.watch.map(w => (
                  <Text>· {w}</Text>
                ))}
              </Box>
            )}
          </Box>
        )}

        {prompt && (
          <Box flexDirection="column" borderStyle="round" borderColor={C.warn} paddingX={1}>
            <Text color={C.warn} bold>
              Ready for Claude Code
            </Text>
            <Markdown text={prompt} />
          </Box>
        )}

        {list.slice(-30).map(m =>
          m.role === 'note' ? (
            <Text color={C.mute} italic>
              {m.text}
            </Text>
          ) : (
            <Box flexDirection="column">
              <Text color={m.role === 'you' ? C.accent : C.ok} bold>
                {m.role === 'you' ? 'You' : 'Co-driver'}
              </Text>
              <Markdown text={m.text} />
            </Box>
          ),
        )}

        <Input
          key="chat"
          rows={2}
          placeholder="Push back, or ask what something means…"
          submitLabel="ask"
          value={s.typedChat}
          onInput={value => {
            s.typedChat = value
          }}
          onSubmit={value => runChat($, s, value)}
        />

        <Box flexDirection="row" gap={1} flexWrap="wrap">
          <Button key="send" onPress={() => toPrompt()}>Send to prompt</Button>
          <Button key="model" onPress={() => cycleModel()}>{MODEL_LABEL[modelName] ?? modelName}</Button>
          <Button key="session" onPress={() => update($, seesSession, v => !v)}>
            {withSession ? 'Session: on' : 'Session: off'}
          </Button>
          <Button key="clear" onPress={() => clear()}>Clear</Button>
        </Box>
      </Box>
    )
  })
}
