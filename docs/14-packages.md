# Packages

## Package Description Files

Idris uses `.ipkg` files to manage packages:

```ipkg
package maths
version = 0.0.1

modules = Maths
        , Maths.NumOps
        , Maths.BinOps
```

### Header

```ipkg
package my-lib
```

Package names use kebab-case (`my-lib`), including hyphens (allowed despite not being valid in ordinary identifiers).

### Metadata Fields

| Field | Description |
|-------|-------------|
| `brief = "<text>"` | Brief description |
| `version = <num>` | Semantic version (e.g., `1.0.0`) |
| `langversion <constraints>` | Idris version constraints |
| `readme = "<file>"` | README file location |
| `license = "<text>"` | License information |
| `authors = "<text>"` | Author info |
| `maintainers = "<text>"` | Maintainer info |
| `homepage = "<url>"` | Project website |
| `sourceloc = "<url>"` | Source repository URL |
| `bugtracker = "<url>"` | Bug tracker URL |

### Directory Fields

| Field | Description |
|-------|-------------|
| `sourcedir = "<dir>"` | Directory for `.idr` source files |
| `builddir = "<dir>"` | Directory for checked modules |
| `outputdir = "<dir>"` | Directory for executable output |

### Common Fields

| Field | Description |
|-------|-------------|
| `executable = <name>` | Name of executable to generate |
| `main = <module>` | Main module (required if `executable` present) |
| `opts = "<flags>"` | Options passed to Idris |
| `depends = <pkg>` | Dependencies (with optional version constraints) |

### Dependencies

```ipkg
depends = contrib, lightyear >= 0.3.0 && < 1.0.0
```

Version constraints: `<`, `<=`, `>`, `>=`, `==`, combined with `&&`.

## Using Packages

```bash
idris2 --build maths.ipkg    # Build all modules
idris2 --install maths.ipkg  # Install globally
idris2 --clean maths.ipkg    # Clean build files
idris2 --mkdoc maths.ipkg    # Generate HTML docs
```

Load installed package:

```bash
idris2 -p maths Main.idr
```

## Package Resolution Order

1. `depends/pkgname-<version>/` (local)
2. `$IDRIS2_PREFIX/idris-<version>/pkgname-<version>/` (global)

Highest version satisfying constraints is chosen.

## Support File Directories

### `lib/` — Shared Libraries

Files needed at runtime (e.g., `.so` files for C FFI). Copied to the executable's build folder.

### `data/` — Data Files

Support files bundled into the executable (e.g., `.js` files for JavaScript FFI).

For JavaScript FFI: look for `data/js/my_lib.js`.

## Comments

Standard Idris comments: `--` (single line) and `{- -}` (multiline).
