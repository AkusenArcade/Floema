# Floema — plan

Status: phases 0, 1 and 2 built, 2026-11-26 (§10, §11); phase 3 next. From the
brainstorm in `docs/questions.md` (Akusen's answers there are the source;
this file only orders them). Pace: prototype first, the organic interface
after.

## 1. What it is

A terminal emulator written on Genoma, opened as a `g.window`
(`app_id = "dev.akusen.floema"`), for the AUR like Sinestesia and Rizoma.
It follows Bioma's theme live through the shared theme file, as every
Genoma app does, and has Bioma's look: no title bar, Bioma's fonts around
the grid, Bioma's buttons and cells.

Not another Alacritty clone. What it keeps from Alacritty is what Akusen
chose it for: **his keyboard layout and dead keys**, and **speed**. What it
adds is how a terminal is used:

- **Each command is a capsule**: its prompt, its line, its output, marked
  discreetly (seen above all under the pointer or while moving through the
  commands). Its exit code is the rim's colour; its output folds and opens.
- **What runs is alive**: the running command moves at the rate its output
  comes; OSC 9;4 progress rises as a level; the bell is a pulse; a command
  over 10 s that ends while the window is not focused is a Bioma
  notification.
- **The cursor travels** with a short trail, as Neovide's.
- **Tabs** on top, as in Rizoma, one shell each, opened in the home folder.
- **The folder's commands**: a small panel, called by a key, growing from
  the cursor, that says what can be run where one stands.
- **The folder is a thread** at the top of the tab, as Rizoma's path; a
  press opens it in Rizoma.

Bioma's principles hold here as in the shell: movement means something (the
trail says where the cursor came from; the running capsule's movement is its
output's rate; nothing moves at a fixed rate); colour says state; at rest
the interface does not speak (the exit code only when not 0, the duration
only past a few seconds, the time under the pointer); what opens grows from
its origin.

## 2. Scope

**v1:**

- A shell per tab; full-screen programs (vim, htop, the alternate screen)
  take the window and give it back; Claude Code, which redraws inline, is a
  living capsule as tall as it needs.
- Runs without defects: vim, tmux, htop, Claude Code, ssh, git, builds with
  a lot of output; vttest passes as far as Alacritty does.
- Dead keys and the layout as in Alacritty: SCTK composes them (as the
  launcher shows); Floema sends the composed character, never the dead key.
- Moving by command: jump to the previous / next, fold, copy one command's
  output, run it again, show only the failed ones.
- Copy and paste: Ctrl+C copies when something is selected (the selection
  then goes, so the next Ctrl+C interrupts), otherwise interrupts; Ctrl+V
  pastes text, and is passed on to the program when the clipboard holds
  only an image (Claude Code takes images so); Ctrl+Shift+C/V still work.
  Several lines pasted ask first, unless the program takes bracketed paste.
- Shift+Return sends ESC CR (Claude Code's new line).
- Ctrl+click on a path or a URL: the browser, Rizoma, the default app.
- The folder's commands panel (§6).
- Look: padding 12; block cursor with its trail, blinking only after a
  while idle; opacity is the compositor's; ANSI colours from Bioma's
  palette, live; the grid in the theme's `mono` font, **Space Mono at 15**
  by default; Bioma's fonts everywhere else.
- **The size of the letters is the person's**: Ctrl+= / Ctrl+- / Ctrl+0
  and the settings cell, kept between runs (`~/.config/floema/config.json`).
- Floema as the terminal Rizoma's F4, Bioma's launcher and Mod+T open,
  when switched on (as Rizoma's DEFAULT).

**After v1:** shells that survive the window (a small process holding the
ptys, the window only a view; an option); the quick terminal dropping from
a membrane of Bioma with a key; images (kitty graphics protocol, sixel).

**Not planned:** an editor of its own for the command line (the shell keeps
it: fish's completions and suggestions work as today); splits inside a tab
(the compositor tiles windows).

## 3. Architecture

Luau for the interface, Rust for what a terminal must do per byte and per
frame. Three Genoma services, general enough for any terminal-shaped need
(Bioma could show a command's live output in a cell with them):

```
 shell ⇄ pty (g.pty)  →  emulation (alacritty_terminal, Rust)  →  g.terminal node (GPU)
                              │ events: title, bell, cwd, marks,        ↑ what lines, folds,
                              │ progress, clipboard, mode changes        │ selection, cursor
                              ↓                                          │
                         Luau: tabs, capsules, panel, signals, keys ─────┘
```

- **The emulation lives in Rust**, owned by the node that draws it: the
  grid never crosses into Luau as text, only what Luau asks for (a command's
  output when copied, the line under the pointer, the marks). Bytes go from
  the pty to the parser on the loop, never through Luau.
- **Marks.** `alacritty_terminal` drops OSCs it does not know. Floema needs
  133 (prompt, command, output, exit code), 7 (cwd), 9;4 (progress), 777
  and 9 (notifications). A small scanner in front of the parser splits the
  byte stream at those sequences, feeds the parts, and at each mark records
  where the cursor is in the grid (absolute line, through the history
  offset). Those lines are the capsules' edges; they move with the
  scrollback and are dropped when it drops them.
- **Shell integration.** fish 4 emits OSC 133 itself (which marks fish 4.9
  sends, and whether 133;D carries the exit code, to be checked first);
  bash and zsh get a small script Floema ships and sources through the
  shell's environment, as Ghostty does. Without marks Floema is a plain
  terminal: no capsules, everything else works.
- **Keys.** Legacy encoding plus the kitty keyboard protocol (fish 4 and
  Claude Code ask for it), ported from Alacritty's `input/keyboard.rs`
  (Apache-2.0, compatible with Genoma's GPL). The composed text of a dead
  key is what is sent.
- **Folds are the view's**: the node is given the spans of lines to show,
  so a folded output takes one line and the grid underneath is untouched.
  Scrolling, selection and the pointer are measured through the same spans.

## 4. What Genoma needs

The four lines already in the vault ("App in Genoma"), in this order, each
verified without Floema before the next:

| Need | What | How it is verified |
|---|---|---|
| `g.pty` | open a pseudo-terminal (rustix `openpty`), spawn the shell with `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=Floema`, resize (`TIOCSWINSZ`), read off the loop, the child's exit code and its cwd (`/proc/<pid>/cwd`, when there is no OSC 7) | a scratch interface runs `fish -c`, `stty size`, a resize, a killed child; 0 wake-ups at rest |
| emulation | `alacritty_terminal` in genoma-script: parser, grid, history, selection, modes (alternate screen, bracketed paste, mouse reporting, kitty keyboard), OSC 52; the mark scanner (§3) | Rust tests feeding recorded sessions (vim, htop, Claude Code, fish with marks); vttest by hand against Alacritty |
| `g.terminal` node | a grid drawn on the GPU: a glyph atlas of the mono font (glyphon / cosmic-text, as Genoma's text), cell backgrounds, only changed rows drawn again, wide characters and emoji, underline styles, box drawing and blocks drawn by the node itself (no font has them right), selection, spans (folds), the cursor's place given to Luau so Luau draws it | snapshot of a recorded session against Alacritty's screenshot; a 50 MB `cat` measured against Alacritty; GPU time per frame at rest 0 |
| keys and the rest | key encoding (legacy + kitty protocol), bracketed paste, mouse reporting, IME preedit drawn at the cursor, clipboard by OSC 52 (write only, read asked) | the test set (§7) |

Plus two small changes:

- **Genoma's kit / theme file**: a third font, `fonts.mono`, beside
  `technical` and `expressive`; `theme.desktop().fonts.mono`.
- **Bioma**: Appearance gets the mono font (Space Mono by default, for
  every Genoma app); `services/desktop_theme.luau` writes it, and the 16
  terminal colours derived as the Alacritty template derives them
  (`config/templates/alacritty`), so Floema has one source and follows
  palette changes live. Without Bioma, Floema derives them from the roles.

## 5. Interface

```
 (~)─(Development)─(Floema)                                     ← the cwd thread
 [ fish  ~/Development/Floema ] [ claude ] ( + )                ← tabs, Rizoma's
 ┊ ❯ cargo build --release                                  41s ┊
 ┊   Compiling floema …                                         ┊ ← a command: discreet
 ┊ ❯ git push                                              ✕ 1  ┊ ← failed: rim in alert
 ┊ ❯ ▌                                                          ┊ ← the prompt, the cursor
```

- **The capsule's marks** are a rim drawn over the grid's line range, not a
  box around it: discreet at rest, lit under the pointer and on the one
  moved to. Folded, a command is its line and a count of the lines hidden.
- **Running** (from 133;C to 133;D): its edge's movement follows the output's
  bytes a second, still when nothing comes; a progress (9;4) is a level
  rising in it, the alert colour when 9;4 says error.
- **Moving by command**: Ctrl+Up / Ctrl+Down jump; on the one stood on,
  keys fold it, copy its output, run it again (written at the prompt, as
  the panel does); a filter shows only the failed ones.
- **The cursor**: the block in the primary; moving, a trail as long as the
  distance, shorter as it settles; the blink only after a pause.
- **Tabs**: Rizoma's tab row (budding capsules, a dashed "+"), each named
  by its running program or its folder; Ctrl+Shift+T new (home),
  Ctrl+Shift+W close (asks if something runs), Ctrl+Tab / Ctrl+PgUp/PgDn
  move, drag to order. (Shift because Ctrl+W deletes a word in the shell and
  Ctrl+T is fish's file search; §12.)
- **The cwd thread**: Rizoma's path bar, read only, budding as the folder
  changes; a press on a step opens it in Rizoma.
- **Full screen** (alternate screen): the capsule grows to the window and
  the thread and tabs step back; out of it, everything comes back.
- No title bar; settings behind a corner button that opens a cell, as the
  other apps (font size, cursor, notifications threshold, the default
  terminal switch).

## 6. The folder's commands

Called by a key (to be chosen; Ctrl+Space proposed), a panel grows from the
cursor with what makes sense where the shell stands, read when it opens:

- the project's own: `Makefile` targets, `package.json` scripts, `just`
  recipes, `cargo` build / test / run where there is a `Cargo.toml`,
  `makepkg` where there is a `PKGBUILD`, the folder's executables
  (`./install.sh`);
- git, as it is now: commit with changes, push when ahead, pull when
  behind, the branch;
- the commands already run in this folder, the most used first: Floema
  keeps them itself, since every command reaches it with its folder
  (`$XDG_STATE_HOME/floema/history.json`).

Choosing one writes it at the prompt; Return runs it. Typing filters.

## 7. Phases

Each ends with something usable, verified before the next.

0. **Genoma** (§4): `g.pty`, emulation and marks, the `g.terminal` node,
   keys; `fonts.mono` in the theme file.
1. **Prototype**: one window, one shell. Keys, dead keys, paste, Ctrl+C /
   Ctrl+V as decided, selection, scrollback, resize, the bell, the
   alternate screen, font size. **Verified against the test set**: vttest,
   vim, htop, tmux, Claude Code, ssh, a build with a lot of output, a 50 MB
   `cat`. Measured: latency from key to screen no worse than Alacritty
   (same probe on both), 0 CPU at rest, memory. The size of the letters
   set by keys and kept.
2. **Capsules**: shell integration, marks, the discreet rims, exit code and
   duration, moving by command, fold, copy one output, run again, only the
   failed ones.
3. **Tabs and the thread**: Rizoma's tab row, the cwd thread, Rizoma opened
   from it.
4. **Living**: the cursor's trail, the running capsule's movement, progress,
   the bell's pulse, notifications.
5. **The folder's commands** panel.
6. **The rest of v1**: links, paste confirmation, the settings cell; Bioma's
   mono font and terminal colours; the default terminal switch (Rizoma F4,
   the launcher, Mod+T).
7. **Packaging**: AUR (`depends=('genoma>=…' 'ttf-space-mono-nerd')`, in
   extra; or Space Mono shipped with Floema, OFL), the
   app icon chosen with Akusen, install.sh as Rizoma's.

## 8. Risks

- **The node is the large part**: glyph atlas, damage, wide characters,
  box drawing; a terminal that is slower than Alacritty has failed. Measure
  from the first frame of phase 0.
- **Marks and folds** are Floema's invention on top of a grid that does not
  know them: a program that clears the screen or rewrites lines above its
  start (Claude Code, progress bars) moves under the marks. The scanner
  records lines, and a capsule whose lines were rewritten keeps its rim
  only where they still stand.
- **Kitty keyboard protocol** edge cases (Claude Code, fish): the encoder is
  tested key by key against Alacritty's output.
- **Hot reload**: Genoma reloads an interface when its files change; the
  ptys must survive a reload of the Luau, or the shells die with it
  (held by the Rust side, keyed by tab).

## 9. Decisions

All Akusen's, 2026-11-25/26 (`docs/questions.md`): keyboard layout and dead
keys as Alacritty; smooth cursor with a trail; tabs on top, one shell each,
new ones in home; the folder's commands panel; Bioma's fonts around the
grid, Space Mono at 15 in it (after Courier Prime, Lekton, Sometype Mono,
Geist Mono and Monaspace Neon were tried in the grid, 2026-11-26), its size
adjustable and kept; AUR; every seed of the brainstorm, surviving
shells optional and after v1; discreet capsules; full-screen programs take
the window, Claude Code a living capsule; moving by command; Ctrl+C / Ctrl+V
without Shift; notifications only when unfocused, over 10 s; at rest only a
non-zero exit code and a long duration; the quick terminal after v1.

Mine, to be confirmed while building: Ctrl+Space for the panel; Ctrl+Up /
Ctrl+Down for moving by command; the emulation in Rust owned by the node;
Bioma writing the terminal colours into the theme file.

## 10. Phases 0 and 1, as built (2026-11-26)

Genoma (e80a36c and after): `g.pty`, `g.terminal`, `g.terminal_view`, key
encoding. Differences from §3–4, learned while building:

- **The terminal is read and parsed on a thread of its own**, not on the
  loop: the grid sits behind a lock, taken a 64 KB piece at a time by the
  parser and for a snapshot of the rows in view by the drawing. The changes
  reach Luau once a turn of the loop.
- **Letters are spaced to fill their cells** (cosmic-text's monospace width
  scales glyphs instead), and characters outside the grid's font (emoji,
  CJK, arrows, the prompt's ❯) are pieces of their own at their column.
- `alacritty_terminal` is vendored with one addition, the count of lines
  that leave for the history, so marks keep their line.

Floema (`genoma/shell.luau`): one window, one shell; keys as the program
asked (fish 4 turns the kitty keyboard protocol on); dead keys composed;
Ctrl+C copies with a selection, else interrupts; Ctrl+V pastes text and
leaves an image to the program; selection by character, word, line; the
middle button pastes; the pointer and the wheel to programs that ask (Shift
keeps them); Shift+Return; the size of the letters by keys, kept.

The test set, in a headless Umbriel against Alacritty there:

| | Floema | Alacritty |
|---|---|---|
| key to screen (median of 40) | 12.3 ms | 12.8 ms |
| 50 MB of coloured text | 0.50 s | 0.42 s |
| `seq 1 2000000` | 0.56 s | 0.46 s |
| at rest | 0 CPU, 76 MB | |

Claude Code works inside it as it should (Akusen, 2026-11-26).

vttest's screens are Alacritty's, defects included (both keep their width
when a program asks for 80 or 132 columns); btop, vim, top and tmux 3.8
with split panes and a status bar draw as they should.

Left for later, on purpose:

- **Speed**: the 20 % behind Alacritty on a flood of output is the hand-off
  between the two threads; the parser itself costs what Alacritty's does.
- **Input methods** (Chinese, Japanese): Genoma takes text-input-v3 only
  in its fields; dead keys, which Akusen uses, work.
- Columns asked by a program (DECCOLM) are not obeyed, as in Alacritty.

## 11. Phase 2, as built (2026-11-26)

- **The marks are the terminal's**, followed by id (`t:mark`): when the
  window's width changes and the lines rewrap, each mark is counted in
  whole lines from the cursor (which a rewrap keeps) and found again, so a
  capsule stays on its text through niri's and Umbriel's resizes.
- **Folds are the view's** (`t:hide`): the rows above take the place of the
  lines left out; the cursor, the selection and the capsules read where
  lines are drawn from the same map (`t:row`, `t:span`, `t:line_at`).
- `core/commands.luau` builds the commands from the marks: a prompt drawn
  again where nothing ran replaces the last; one drawn over older commands
  (a cleared screen) takes them away. `ui/capsules.luau` draws them.
- **At rest**: a 2-unit thread down the margin beside each command's lines,
  faint for one that ended well, the alert colour for one that failed, the
  primary while it runs; on its line, only when there is something to say,
  "exit N", how long it took past 3 seconds, how many lines are folded.
- **Under the pointer or stood on**: its outline (the primary when stood
  on) and three Bioma buttons in the middle of its line (Akusen,
  2026-11-26), "exit N" and the rest staying at its end: FOLD/UNFOLD, COPY (its output,
  wrapped lines joined), AGAIN (written at the prompt, bracketed, not run).
  A press on the thread folds it.
- **Keys**: Ctrl+Up / Ctrl+Down stand on the commands, the view following;
  then Up/Down move, F folds, C copies the output, R writes it again, E
  shows only the failed ones; Escape leaves, anything else typed leaves and
  goes on to the shell.
- **bash and zsh** get the marks from `shell/` (as Ghostty does): bash
  started with `--rcfile shell/floema.bash`, which reads `~/.bashrc` first;
  zsh through `ZDOTDIR=shell/zsh`, whose `.zshenv` gives the person's
  ZDOTDIR back, reads their `.zshenv` and adds precmd/preexec hooks. fish
  marks by itself. Verified on all three.

Not yet: the time a command ran shown under the pointer (no wall clock in
Genoma's Luau yet; the plan's §1 asks for it).

## 12. Phase 3, as built (2026-11-26)

- **A tab is a shell** (`core/tabs.luau`): its pty, its terminal, its
  commands (`core/commands.luau` is now one per terminal), the folder it
  stands in and what runs in it. The folder is OSC 7 where the shell says it
  (fish does) and the shell's own folder at each prompt otherwise (bash,
  zsh). What runs is the terminal's foreground program, read when a command
  starts (a moment after, so it is the program and not the shell) and ends,
  and when the title changes.
- **The tabs** (`ui/tabs.luau`), after three tries with Akusen: a line
  rising round the seen tab, first across the whole window, then only round
  it with fading tails, read as out of Bioma's style. What stays is Bioma's
  segmented control at the size of a name: the names in a row on a track
  (`TRACK`, or bare) a little darker than the window and with no outline
  (an outline makes it the segmented choice of the settings), the seen one
  a pill in the secondary (the primary is the interactive components'),
  with an edge of its own hue, darker, its name dark.
  Choosing another, the pill goes as a drop would: the edge it moves
  towards leads on a quick spring a little past (`pill_lead`, Bioma's `hop`
  damped for the length it travels), the other follows softer
  (`pill_trail`), so it stretches on the way and gathers where it arrives;
  it never leaves the track, and a name turns dark the moment the pill is
  under it. Always there, one tab too, with the dashed "+" after the track.
  The cross shows under the pointer. A tab where something runs asks before
  it closes: "sleep runs: close?", the pill in the alert colour; a second
  close closes it, Escape or four seconds forget it. Middle click closes,
  drag orders. A shell that exits takes its tab with it; the last tab
  closes the window.
- **No path above the grid for now** (Akusen, 2026-11-26: not convinced of
  its use). It was Rizoma's path, read only, budding at each `cd`, a press
  on a step opening it in Rizoma; `ui/thread.luau` keeps it, unused, to be
  thought about again. Drawn on the prompt's own line instead (pure leaving
  the room for it) it was too small and too near the cursor.
- Genoma: a `g.path` with a long straight run after a curve draws a second,
  brighter line along part of it (the stroke's fringe; reproduced alone).
- **Keys**: Ctrl+Shift+T a new tab in the home folder, Ctrl+Shift+W close,
  Ctrl+Tab / Ctrl+Shift+Tab and Ctrl+PgUp/PgDn move, Ctrl+Shift+PgUp/PgDn
  move the tab itself.
- **Only the seen tab's grid is built**; the others' terminals go on
  without a view. A box per tab hidden by a reactive `present` stalled every
  transition in the window (Genoma; not looked into yet).

Seen in headless Umbriel, not yet on a desktop: a Genoma window resized
while it has not the keys presents no new frame until it has them again
(phase 2's Floema too: its cursor stays filled).
