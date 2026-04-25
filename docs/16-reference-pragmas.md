# Reference: Pragmas

Pragmas start with `%` and modify compiler behavior.

## Global Pragmas

### `%default`

Set default totality requirement:

```idris
%default total      -- all functions must be total
%default covering   -- all functions must cover (default)
%default partial    -- relax totality requirement
```

### `%language`

Enable language extensions:

```idris
%language ElabReflection
```

### `%name`

Guide name generation for types:

```idris
%name Vect xs, ys, zs, ws
```

### `%builtin`

Convert recursive naturals to primitives:

```idris
%builtin Natural
```

### `%ambiguity_depth`

Max nested ambiguous names before error (default: 3):

```idris
%ambiguity_depth 10
```

### `%totality_depth`

Constructor matching depth for totality checking (default: 5):

```idris
%totality_depth 10
```

### `%auto_implicit_depth`

Search depth for auto implicits (default: 50):

```idris
%auto_implicit_depth 100
```

### `%logging`

Change logging level:

```idris
%logging 1
%logging "elab" 5
```

### `%prefix_record_projections`

Toggle prefix record projections (default: `on`):

```idris
%prefix_record_projections off
```

### `%transform`

Replace function at runtime with efficient version:

```idris
%transform "plus" plus j k = integerToNat (natToInteger j + natToInteger k)
```

### `%unbound_implicits`

Toggle automatic implicit binding (default: `on`):

```idris
%unbound_implicits off
```

### `%auto_lazy`

Toggle automatic `delay`/`force` insertion (default: `on`).

### `%search_timeout`

Expression search timeout in ms (default: 1000):

```idris
%search_timeout 5000
```

### `%nf_metavar_threshold`

Max stuck applications in unification (default: 25).

### `%cg`

Codegen directives in source:

```idris
%cg chez extraRuntime=mycode.ss
```

## Declaration Pragmas

### `%deprecate`

Mark a definition as deprecated:

```idris
||| Please use altFoo instead.
%deprecate
foo : String -> String
foo x = x ++ "!"
```

### `%inline` / `%noinline`

Force inlining decision:

```idris
%inline
foo : String -> String

%noinline
bar : String -> String
```

### `%tcinline`

Inline during totality checking.

### `%hide` / `%unhide`

Hide/unhide definitions from imports:

```idris
%hide Prelude.Nat
%hide Prelude.S
%hide Prelude.infixl.(+)

%unhide Prelude.Nat
```

### `%unsafe`

Mark a function as unsafe (for visual highlighting).

### `%spec`

Specialize a function:

```idris
%spec a
identity : List a -> List a
```

### `%foreign`

Declare foreign function:

```idris
%foreign "C:puts,libc"
puts : String -> PrimIO Int
```

### `%foreign_impl`

Extend FFI for third-party backends:

```idris
%foreign_impl Prelude.IO.prim__fork "javascript:lambda:(proc) => { throw new Error() }"
```

### `%export`

Export a definition (alternative to `export` modifier):

```idris
%export
foo : Int -> Int
```

### `%nomangle`

Prevent name mangling in generated code.

### `%hint` / `%defaulthint` / `%globalhint`

Mark a function as a hint for auto-implicit search:

```idris
%hint
showBool : MyShow Bool
```

### `%extern`

Declare external definition.

### `%macro`

Define a macro.

### `%start`

Mark entry point.

### `%allow_overloads`

Allow operator overloading.

## Internal Pragmas

| Pragmas | Description |
|---------|-------------|
| `%rewrite` | Internal rewrite |
| `%pair` | Pair handling |
| `%integerLit` | Integer literal handling |
| `%stringLit` | String literal handling |
| `%charLit` | Char literal handling |
| `%doubleLit` | Double literal handling |

## Reflection Literals

| Pragmas | Description |
|---------|-------------|
| `%TTImpLit` | TTImp literal |
| `%declsLit` | Declarations literal |
| `%nameLit` | Name literal |

## Expressions

| Expression | Description |
|------------|-------------|
| `%runElab` | Run elaborator |
| `%search` | Search expression |
| `%World` | World token type |
| `%MkWorld` | World token constructor |
| `%syntactic` | Syntactic annotation |
