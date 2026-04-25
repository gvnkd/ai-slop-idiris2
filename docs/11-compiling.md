# Compiling to Executables

## Compilation

### From REPL

```idris
Main> :c execname expr    -- compile to executable
Main> :exec expr          -- execute directly (IO () required)
```

### From Command Line

```bash
idris2 hello.idr -o hello   -- compiles Main.main to build/exec/hello
```

## Code Generators (Backends)

| Backend | Command | Description |
|---------|---------|-------------|
| Chez Scheme | `:set cg chez` | Default, fastest |
| Racket | `:set cg racket` | Alternative Scheme target |
| Gambit | `:set cg gambit` | Another Scheme target |
| JavaScript | `--cg javascript` | Browser target |
| Node.js | `--cg node` | Node.js target |
| C (RefC) | `--codegen refc` | C with reference counting |

Set via REPL: `:set cg <backend>`
Set via env: `IDRIS2_CG=<backend>`
Set via pragma: `%cg chez extraRuntime=path`

## Whole Program Compilation

Idris 2 is a **whole program compiler** — it finds all needed definitions and compiles them together. This enables optimization but can be slow for rebuilds.

### Incremental Code Generation

Supported by some backends for faster rebuilds.

## Profiling

```bash
idris2 --profile myprog.idr -o myprog
# or in REPL: :set profile
```

Profile data depends on the backend (Chez and Racket supported).

## Build Artefacts

| Path | Description |
|------|-------------|
| `build/ttc/` | Checked module bytecode (TTC files) |
| `build/exec/` | Generated executables |

## Custom Backends

Idris 2 supports plug-in code generation. See `backends/custom.html` for details on building new backends.

External backends are listed on the [Idris2 wiki](https://github.com/idris-lang/Idris2/wiki/External-backends).

## Libraries

Work is in progress for generating libraries for other languages from Idris 2 code.
