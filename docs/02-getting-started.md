# Getting Started

## Installation

### From Source

Idris 2 is implemented in Idris 2, so bootstrapping requires a Scheme implementation:

- **Chez Scheme** (default, recommended — fastest)
- **Racket**
- **Gambit**

```bash
make bootstrap SCHEME=chez
make install   # installs to $HOME/.idris2 by default
```

### From Package Managers

```bash
# Homebrew (macOS)
brew install idris2

# Arch Linux
yay -S idris2

# Fedora
sudo dnf install idris2
```

## Your First Program

Create `hello.idr`:

```idris
module Main

main : IO ()
main = putStrLn "Hello world"
```

Compile and run:

```bash
idris2 hello.idr -o hello
./build/exec/hello
```

## The Interactive REPL

```bash
idris2 hello.idr
```

Key REPL commands:

| Command | Description |
|---------|-------------|
| `:t expr` | Check the type of an expression |
| `:exec expr` | Execute an `IO ()` expression |
| `:c name expr` | Compile to executable |
| `:q` | Quit |
| `:?` | Show help |

The REPL supports `rlwrap` for command history:

```bash
rlwrap idris2
```

## Build Artefacts

- Checked modules: `build/ttc/` (TTC bytecode, regenerated on source change)
- Executables: `build/exec/`

## Useful Compiler Flags

| Flag | Description |
|------|-------------|
| `-o prog` | Compile to executable `prog` |
| `--check` | Type-check without starting REPL |
| `-p pkg` / `--package pkg` | Add package dependency |
