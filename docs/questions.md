# Floema — questions before a plan

Floema is a terminal emulator on Genoma (`g.window`, Luau over Rust
primitives), in Bioma's look. Not another Alacritty clone: new in how it is
used and how it looks, with an organic feel. The concept comes from these
answers, round by round; no plan is written before them.

Fixed already (Akusen, 2026-11-20): vim, tmux, htop and Claude Code run
without defects; dead keys as in Alacritty (Genoma composes them through
SCTK; Floema sends the composed character); a minimal prototype first, the
organic interface after. Genoma prerequisites (vault, "App in Genoma"):
`g.pty`, emulation through the `alacritty_terminal` crate, a grid render
node, key encoding (Ctrl/Alt/function keys, bracketed paste, mouse, OSC 52,
IME).

Facts checked 2026-11-25: he uses Alacritty (Mod+T) and Ghostty
(Mod+Return), no tmux configuration, the compositor tiles; fish 4.9 (it
emits OSC 133 prompt marks by itself); Alacritty has no font set, so
fontconfig's monospace, Noto Sans Mono; Bioma writes the palette
(`alacritty/themes/bioma.toml`); Shift+Return sends ESC CR (Claude Code's
new line).

## Round 1 — why, for whom, what "organic" means

1. What bothers you in Alacritty and Ghostty today, and what do you miss?
2. What must stay exactly as in Alacritty (besides dead keys)?
3. For you only, or for the AUR like Sinestesia and Rizoma (then config,
   defaults and first run matter)?
4. "Organic": which of the seeds below goes the right way, which not?
5. Where do you use a terminal most: Claude Code, git, builds, ssh, editors?

### Answers (Akusen, 2026-11-25)

1. He prefers Alacritty because it handles his keyboard layout. He wants
   from Floema: a cursor that moves with a smooth animation; tabs, several
   instances in one window; a small panel called up by a keybinding that
   says which commands are available in the folder he is in; Bioma's fonts.
2. Besides layouts (dead keys) and speed, nothing must stay as in Alacritty.
3. For the AUR.
4. Every seed is worth trying; shells that survive the window maybe as an
   option.
5. Everything but editors: Claude Code, git, builds, ssh and the rest.

## Round 2 — the unit of the interface

6. One capsule per command (prompt, command, output; exit code as the rim's
   colour; output folded and opened again), or a classic grid with
   discreet marks?
7. Full-screen programs (vim, htop: the alternate screen) take the whole
   window; and Claude Code, which redraws inline on the main screen?
8. Moving through history by command (jump, fold, copy one command's
   output, run again, show only the failed ones)?

### Answers (Akusen, 2026-11-25)

- Fonts: Bioma's around the grid (Orbitron technical, Spectral names); in
  the grid a monospace **as close to Spectral as possible**; a third font,
  `mono`, added to the shared theme file so every Genoma app follows it.
  Specimen of serif monospaces: `docs/drafts/fonts.png` (missing glyphs
  there are drawn by Floema itself: box drawing and blocks built in, the
  rest from fallback fonts).
- The folder's commands panel as proposed: the project's own commands
  (make, npm scripts, just, cargo, executables, makepkg), the git actions
  that make sense now, the commands already run in that folder; it grows
  from the cursor and writes the command at the prompt.
6. Discreet marks, seen above all under the pointer or while moving through
   the commands.
7. Yes: full-screen programs take the window; Claude Code stays a living
   capsule as tall as it needs.
8. Yes: jump between commands, fold, copy one output, run again, only the
   failed ones.
9. Each tab is one shell; tabs on top as in Rizoma.
- Copy and paste with the traditional keys, without Shift.

## Round 3 — living signals

9. OSC 9;4 progress as a level; output rate as the running capsule's
   movement; the bell as a pulse; a long command ending while unfocused as
   a Bioma notification. Which, and which not?
10. What is said at rest (duration, exit code, time)?

### Answers (Akusen, 2026-11-25)

- The serif monospaces of the first specimen do not convince him: a face
  that recalls analog typewriters instead. Second specimen:
  `docs/drafts/fonts-typewriter.png` (Special Elite there is not a
  monospace: out).
- Copy and paste as proposed: Ctrl+C copies with a selection, otherwise
  interrupts; Ctrl+V pastes text, and passes the key on when the clipboard
  holds only an image (Claude Code); Ctrl+Shift+C/V still work.
10. All four living signals; the notification for a long command (over 10 s)
    always when the window is not focused.
11. At rest: the exit code only when not 0, the duration only past a few
    seconds, the time under the pointer.
12. The cursor with a short trail (as Neovide).

## Round 4 — space and sessions

11. Tabs and splits in Floema, or the compositor's columns only?
12. Shells that survive closing the window or restarting Floema (a small
    daemon holding the ptys, the window only a view), as tmux does?
13. A quick terminal that drops from a membrane, as a Bioma cell?

### Answers (Akusen, 2026-11-26)

- Font of the grid: Courier Prime, at first; in the grid it was hard to
  read. Lekton (the Olivetti one) and Sometype Mono did not convince either,
  nor Geist Mono and Monaspace Neon: **Space Mono at 15** (2026-11-26).
  `docs/drafts/fonts-live.png`, `fonts-live-2.png`.
- **The size of the letters must be adjustable** (2026-11-26), and kept.
13. A new tab opens in the home folder.
14. Shells that survive the window: after v1.
15. The quick terminal dropping from a membrane: he likes it a lot; after v1.

## Rounds 5 to 9, closed together (Akusen, 2026-11-26: "va bene tutto")

16. The shell keeps line editing (fish's completions and suggestions).
17. Pasting several lines asks first, unless the program takes bracketed
    paste.
18. Ctrl+click on paths and URLs: browser, Rizoma, the default app.
19. Shift+Return sends ESC CR; Ctrl+= / Ctrl+- / Ctrl+0 for the font size.
20. Padding 12; opacity is the compositor's.
21. Block cursor with its trail; it blinks only after a while idle.
22. Courier Prime (now Space Mono at 15) the default `mono` in the theme file, changeable in Bioma's
    Appearance for every app.
23. ANSI colours from Bioma's palette, live.
24. The cwd as a thread at the top of the tab, a press opens it in Rizoma.
25. Floema the terminal Rizoma's F4, the launcher and Mod+T open, when he
    switches it on.
26. Images in the terminal: after v1.
27. Prototype targets: latency no worse than Alacritty, 0 CPU at rest, a
    test set of vttest, vim, htop, tmux, Claude Code, a build with a lot of
    output.

The questions as first asked follow.

## Round 5 — input

14. The shell keeps the line editing (fish's completions and
    suggestions), or an editor of Floema's own?
15. Selection, copy and paste: as Alacritty (Ctrl+Shift+C/V) or otherwise?
    Paste protection for multi-line text?
16. Mouse: clickable paths and URLs (open in Rizoma / the browser)?

## Round 6 — look

17. Font: Noto Sans Mono as now, or another (JetBrains Mono, Iosevka,
    Commit Mono, IBM Plex Mono)? Ligatures?
18. Bioma's fonts around the grid (Orbitron for labels, Spectral for
    names), the grid itself monospace only?
19. Padding, opacity (the compositor's), cursor shape and blink.

## Round 7 — the suite

20. cwd shown as a thread, a press opens Rizoma there?
21. Images in the terminal (kitty graphics protocol, sixel)?
22. Floema as the terminal Rizoma's F4 and the launcher open?

## Round 8 — measures

23. Latency and frame targets; vttest and which TUIs as the test set.

## Round 9 — v1

24. What v1 is, what waits.
