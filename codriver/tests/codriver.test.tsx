import { expect, mock, test } from 'claude-code/testing'

const PANE = {
  plugin: 'codriver',
  component: 'Pane',
  requestId: 'codriver',
  props: {
    title: 'Co-driver',
    isFocused: true,
    bodyColumns: 70,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'codriver',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

const usage = { input_tokens: 10, output_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }

const SAMPLE_OUTPUT = `I updated the pricing page. Changes:
- src/app/pricing/page.tsx: rebuilt the tier cards with the new Card component
- Deleted src/components/OldPricingTable.tsx (no longer used)
- Also refactored src/lib/format.ts to use Intl.NumberFormat everywhere
All 42 tests pass.`

const DEBRIEF_JSON = JSON.stringify({
  happened: [
    'The pricing page now uses the new card design for each plan.',
    'An old pricing table file was deleted because nothing used it anymore.',
    'It also reworked how prices are formatted across the whole app.',
  ],
  course: 'drifting',
  why: 'NEXT.md asks for the pricing cards only — the price formatting change was not in the plan.',
  watch: ['It deleted a file without asking.', 'Price formatting changed everywhere, not just on pricing.'],
  next: 'Review the price formatting change and undo it if it was not needed.\n\nFiles in scope: src/lib/format.ts\n\nDone when: prices look the same as before outside the pricing page.',
})

const FILES: Record<string, string> = {
  'CLAUDE.md': '# Project\nThe plan lives in `docs/plan.md`. See [status](STATUS-old.txt) too.\nNever touch .env.',
  'NEXT.md': 'Next: rebuild the pricing cards. Nothing else.',
  'docs/plan.md': 'Phase 2: pricing page.',
}

type Opts = { promptBox?: string; files?: Record<string, string>; preflight?: string | 'timeout' | 'error'; debrief?: string }

// Stand in for the engine. Returns what the mod sent so tests can check it.
function engine(on: any, opts: Opts = {}) {
  const files = opts.files ?? FILES
  const sent = {
    complete: [] as any[],
    preflights: [] as any[],
    forks: 0,
    fills: [] as any[],
    toasts: [] as string[],
    submits: [] as any[],
    commands: [] as string[],
    opens: 0,
    clock: null as any,
  }
  on('command.register', (_: unknown, e: any) => {
    sent.commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('ui.open', () => {
    sent.opens++
    return { value: { isPlaced: true } }
  })
  const clock = mock.clock(on)
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  const rel = (p: string) => p.replace(/^\/(w|work\/banner-cms)\//, '')
  on('fs.exists', (_: unknown, e: any) => ({ value: rel(e.path) in files }))
  on('fs.read', (_: unknown, e: any) => ({ value: files[rel(e.path)] ?? '' }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('turn.complete', (_: unknown, e: any) => ({ text: e.answer }))
  on('ui.toast', (_: unknown, e: any) => {
    sent.toasts.push(String(e.text ?? e))
    return { value: undefined }
  })
  on('prompt.read', () => ({ value: { text: opts.promptBox ?? '', cursor: 0 } }))
  on('prompt.fill', (_: unknown, e: any) => {
    sent.fills.push(e)
    return { isFilled: true, text: e.text }
  })
  on('prompt.submit', (_: unknown, e: any) => {
    sent.submits.push(e)
    return { text: e.text }
  })
  on('model.fork', () => {
    sent.forks++
    return { value: { isAnswered: false, reason: 'nothing-to-fork' } }
  })
  on('model.complete', (_: unknown, e: any) => {
    const all = JSON.stringify(e)
    if (all.includes('You rate a prompt')) {
      sent.preflights.push(e)
      if (opts.preflight === 'timeout') return { value: { isAnswered: false, reason: 'aborted', usage } }
      if (opts.preflight === 'error') return { value: { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage } }
      const p = JSON.stringify(e.prompt)
      const text =
        opts.preflight ??
        (/force push|delete/i.test(p) ? 'RED: Deletes branches and rewrites shared history.' : 'GREEN')
      return { value: { isAnswered: true, text, usage } }
    }
    sent.complete.push(e)
    let text = 'Sure. A migration is like moving furniture to a new house: the stuff stays, the layout changes.'
    if (all.includes('Reply with JSON only')) text = opts.debrief ?? DEBRIEF_JSON
    else if (all.includes('looked risky or loose'))
      text = 'List the merged branches older than 30 days.\n\nAsk first: before deleting any branch.\n\nDone when: I have a list to approve.'
    return { value: { isAnswered: true, text, usage } }
  })
  sent.clock = clock
  return sent
}

const typed = (text: string) => ({ text, origin: { kind: 'composer' }, wait: false }) as any

test('/codriver opens the pane and names the course files it loaded; /sketch is gone', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/work/banner-cms', surface: 'desktop', isInteractive: true })
  expect(sent.commands).toEqual(['codriver'])
  const opened = await $.command.run({ command: 'codriver', args: '' } as any)
  expect(opened.text).toContain('Co-driver open')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    const course = await ui.find({ type: 'Text', text: /^Course:/ })
    expect(course?.text).toBe('Course: CLAUDE.md, NEXT.md, docs/plan.md')
    await ui.unmount()
  }
})

test('a course file that is too long says so', async ($, on) => {
  engine(on, { files: { 'CLAUDE.md': 'x'.repeat(20_000) } })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^Course:/ }))?.text).toBe('Course: CLAUDE.md (trimmed)')
  await ui.unmount()
})

test('no course files says so plainly', async ($, on) => {
  engine(on, { files: {} })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^Course:/ }))?.text).toContain('no CLAUDE.md or plan files found')
  await ui.unmount()
})

test('Debrief on pasted output: three parts, next prompt ready, opus at medium effort, no em dashes', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/work/banner-cms', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'clear' })
    await ui.input({ key: 'source', text: SAMPLE_OUTPUT })
    expect(sent.complete.length).toBe(surface === 'terminal' ? 0 : 1) // pasting alone never runs it
    await ui.press({ key: 'debrief' })

    const req = sent.complete.at(-1)
    expect(req.model).toBe('opus')
    expect(req.effort).toBe('medium')
    expect(JSON.stringify(req.prompt)).toContain('OldPricingTable')
    expect(JSON.stringify(req.prompt)).toContain('rebuild the pricing cards. Nothing else.')

    expect(await ui.find({ type: 'Text', text: 'What happened' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /old pricing table file was deleted/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'Drifting' })).toBeTruthy()
    const why = await ui.find({ type: 'Text', text: /NEXT.md asks/ })
    expect(why?.text).not.toContain('—')
    expect(await ui.find({ type: 'Text', text: 'Watch out' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /deleted a file without asking/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /Ready for Claude Code/ })).toBeTruthy()

    await ui.press({ key: 'send' })
    expect(sent.fills.at(-1).text).toContain('Review the price formatting change')
    expect(sent.fills.at(-1).mode).toBe('replace')
    expect(sent.submits.length).toBe(0) // never auto-sends
    await ui.unmount()
  }
})

test('Watch out is left out when there are no risks', async ($, on) => {
  engine(on, {
    debrief: JSON.stringify({ happened: ['a', 'b', 'c'], course: 'on course', why: 'Matches NEXT.md.', watch: [], next: 'Next step.' }),
  })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.input({ key: 'source', text: 'Added a button.' })
  await ui.press({ key: 'debrief' })
  expect(await ui.find({ type: 'Text', text: 'On course' })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: 'Watch out' })).toBeFalsy()
  await ui.unmount()
})

test('Debrief with nothing pasted only nudges', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'debrief' })
  expect(sent.complete.length).toBe(0)
  expect(sent.toasts.join(' ')).toContain('Paste some Claude Code output first')
  await ui.unmount()
})

test('a finished turn is remembered, never debriefed on its own; Use last answer grabs it', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.turn.complete({ answer: 'I migrated the users table.', durationMs: 10, isAborted: false, turnId: 't1', reason: 'answer' } as any)
  await $.turn.complete({ answer: 'subagent noise', durationMs: 10, isAborted: false, turnId: 't2', reason: 'answer', agentId: 'a1' } as any)
  expect(sent.complete.length).toBe(0)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'last' })
  await ui.press({ key: 'debrief' })
  expect(JSON.stringify(sent.complete.at(-1).prompt)).toContain('I migrated the users table.')
  expect(JSON.stringify(sent.complete.at(-1).prompt)).not.toContain('subagent noise')
  await ui.unmount()
})

test('chat below the debrief answers in plain language', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.input({ key: 'source', text: SAMPLE_OUTPUT })
  await ui.press({ key: 'debrief' })
  await ui.input({ key: 'chat', text: 'what does migration mean?' })
  const req = sent.complete.at(-1)
  expect(JSON.stringify(req.prompt)).toContain('what does migration mean?')
  expect(JSON.stringify(req.prompt)).toContain('Your debrief')
  expect(await ui.find({ type: 'Markdown', text: /moving furniture/ })).toBeTruthy()
  await ui.unmount()
})

test('Send to prompt goes under an existing draft instead of replacing it', async ($, on) => {
  const sent = engine(on, { promptBox: 'my half-typed thought' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.input({ key: 'source', text: SAMPLE_OUTPUT })
  await ui.press({ key: 'debrief' })
  await ui.press({ key: 'send' })
  expect(sent.fills.at(-1).mode).toBe('append')
  expect(sent.fills.at(-1).text.startsWith('\n\nReview the price formatting change')).toBe(true)
  await ui.unmount()
})

test('model button cycles from opus, and session mode falls back with a note', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'model' })
  await ui.press({ key: 'session' })
  expect(await ui.find({ type: 'Text', text: /sees the session/ })).toBeTruthy()
  await ui.input({ key: 'source', text: SAMPLE_OUTPUT })
  await ui.press({ key: 'debrief' })
  expect(sent.forks).toBe(1)
  expect(sent.complete.at(-1).model).toBe('sonnet')
  expect(await ui.find({ type: 'Text', text: /nothing to share yet/ })).toBeTruthy()
  await ui.unmount()
})

// ---------- Preflight ----------

test('preflight: a green prompt goes through untouched and silently, checked by haiku', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const r = await $.prompt.submit(typed('make the pricing card titles a bit larger'))
  expect(r.text).toBe('make the pricing card titles a bit larger')
  expect(sent.preflights.length).toBe(1)
  expect(sent.preflights[0].model).toBe('haiku')
  expect(sent.preflights[0].timeoutMs).toBeLessThanOrEqual(3000)
  expect(sent.fills.length).toBe(0)
  expect(sent.toasts.length).toBe(0)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Button', key: 'cd-anyway' })).toBeFalsy()
  await band.unmount()
})

test('preflight: "delete the old branches and force push" is flagged red, words kept, choice offered', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const r = await $.prompt.submit(typed('delete the old branches and force push'))
  expect(r.drop).toContain('red')
  await sent.clock.advance(500)
  // The box came back empty here, so Co-driver put the words back itself.
  expect(sent.fills.at(-1)).toMatchObject({ text: 'delete the old branches and force push', mode: 'replace' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: '● Red' })).toBeTruthy()
    expect(await band.find({ type: 'Text', text: /rewrites shared history/ })).toBeTruthy()
    expect(await band.find({ type: 'Button', key: 'cd-anyway' })).toBeTruthy()
    expect(await band.find({ type: 'Button', key: 'cd-tighten' })).toBeTruthy()
    await band.unmount()
  }
})

test('preflight: when the engine already restored the draft, the words are not doubled', async ($, on) => {
  const sent = engine(on, { promptBox: 'delete the old branches and force push' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(typed('delete the old branches and force push'))
  await sent.clock.advance(500)
  expect(sent.fills.length).toBe(0)
})

test('preflight: Send anyway sends the words as typed, unchecked', async ($, on) => {
  const sent = engine(on, { promptBox: 'delete the old branches and force push' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(typed('delete the old branches and force push'))
  const band = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await band.press({ key: 'cd-anyway' })
  expect(sent.submits.at(-1).text).toBe('delete the old branches and force push')
  expect(sent.preflights.length).toBe(1)
  expect(await band.find({ type: 'Button', key: 'cd-anyway' })).toBeFalsy()
  await band.unmount()
})

test('preflight: Enter again on the same flagged words sends them', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(typed('delete the old branches and force push'))
  const r = await $.prompt.submit(typed('delete the old branches and force push'))
  expect(r.text).toBe('delete the old branches and force push')
  expect(sent.preflights.length).toBe(1)
})

test('preflight: Let Co-driver tighten it opens the pane with a guarded rewrite that swaps in', async ($, on) => {
  const sent = engine(on, { promptBox: 'delete the old branches and force push' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(typed('delete the old branches and force push'))
  const band = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await band.press({ key: 'cd-tighten' })
  expect(await band.find({ type: 'Button', key: 'cd-tighten' })).toBeFalsy()
  expect(sent.complete.at(-1).model).toBe('opus')
  await band.unmount()

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Markdown', text: /Ask first: before deleting any branch/ })).toBeTruthy()
  await ui.press({ key: 'send' })
  expect(sent.fills.at(-1).mode).toBe('replace')
  expect(sent.toasts.at(-1)).toContain('Swapped in the tightened version')
  expect(sent.submits.length).toBe(0) // the flagged one was held back, and nothing is auto-sent
  await ui.unmount()
})

test('preflight: amber shows one line too', async ($, on) => {
  engine(on, { preflight: 'AMBER: Vague scope, it may change more than you want.' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const r = await $.prompt.submit(typed('clean up the whole codebase please'))
  expect(r.drop).toContain('amber')
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: '● Amber' })).toBeTruthy()
  await band.unmount()
})

test('preflight never blocks: a timeout or an API error lets the prompt through', async ($, on) => {
  engine(on, { preflight: 'timeout' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  expect((await $.prompt.submit(typed('delete the old branches and force push'))).text).toBe('delete the old branches and force push')
})

test('preflight never blocks: an API error lets the prompt through', async ($, on) => {
  engine(on, { preflight: 'error' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  expect((await $.prompt.submit(typed('delete the old branches and force push'))).text).toBe('delete the old branches and force push')
})

test('preflight skips short replies, slash commands and prompts it did not see typed', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(typed('yes go ahead'))
  await $.prompt.submit({ ...typed('/review the diff'), command: { name: 'review', args: 'the diff' } })
  await $.prompt.submit({ text: 'delete stuff', origin: { kind: 'sdk' }, wait: false } as any)
  expect(sent.preflights.length).toBe(0)
  expect(sent.submits.length).toBe(3)
})
