# Interactive Editing

## REPL Commands

Idris REPL commands generate program fragments based on types:

| Command | Abbrev | Description |
|---------|--------|-------------|
| `:addclause n f` | `:ac` | Template definition for function `f` on line `n` |
| `:casesplit n c x` | `:cs` | Split variable `x` into constructor patterns |
| `:addmissing n f` | `:am` | Add missing clauses for coverage |
| `:proofsearch n f` | `:ps` | Auto-solve hole `f` by proof search |
| `:makewith n f` | `:mw` | Add `with` clause |
| `:gd n name` | — | Generate full definition from type signature |

Update variant (edits file in-place): `:command!`

### Example

```
-- Given: vzipWith f xs ys = ?rhs
:cs 96 12 xs   -- split xs into [] and (x :: xs)
:cs! 97 12 ys  -- split ys (only [] case valid)
:ps 97 vzipWith_rhs_2  -- auto-solve: f x y :: vzipWith f xs ys
```

### `%name` Directive

Guide name generation:

```idris
%name Vect xs, ys, zs, ws
```

## Editor Integration

### Vim

| Binding | Command | Description |
|---------|---------|-------------|
| `\a` | `:addclause` | Template definition |
| `\c` | `:casesplit` | Case split variable |
| `\m` | `:addmissing` | Add missing cases |
| `\w` | `:makewith` | Add `with` clause |
| `\s` | `:proofsearch` | Solve hole |
| `\t` | `:t` | Show type |
| `\e` | — | Evaluate expression |
| `\r` | — | Reload and re-check |

### Emacs

| Binding | Command | Description |
|---------|---------|-------------|
| `C-c C-s` | `:addclause` | Template definition |
| `C-c C-c` | `:casesplit` | Case split |
| `C-c C-a` | `:proofsearch` | Proof search |
| `C-c C-e` | `:make-lemma` | Make lemma |
| `C-c C-t` | `:t` | Show type |

## Client Mode

Run a REPL command and exit:

```bash
idris2 --client ':t plus'
idris2 --client '2+2'
```

Editors use this for real-time type checking and code generation.

## Key Benefits

- **Correct by construction** — the type system guides implementation
- **Case splitting** — only valid patterns are generated (unification prunes impossible cases)
- **Proof search** — auto-solves simple holes based on precise types
- **Incremental development** — write holes, check types, fill in gradually
