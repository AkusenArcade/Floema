# Floema

A terminal emulator for Linux, built on [Genoma](../Genoma) and part of the
[Bioma](../Bioma) ecosystem.

Phloem is the living tissue that carries what a plant makes to where it is
needed. Bioma, Genoma, Rizoma, Floema.

Not another Alacritty clone: each command a capsule, what runs alive, tabs, a
cursor that travels, the folder's commands a key away — with the keyboard
layouts and dead keys Alacritty handles, and its speed.

Status: usable, not yet packaged. See [`docs/plan.md`](docs/plan.md) and the
brainstorm it comes from, [`docs/questions.md`](docs/questions.md).

```
./install.sh          # ~/.local: floema, its desktop entry and icon
./install.sh --here   # the same, running from this checkout
floema [folder] [-e command …]
```

It needs a Genoma with g.terminal (after 0.1.25). To make it the desktop's
terminal, switch it on in its settings (the corner button); that needs
`xdg-terminal-exec`.
