# Reference: Operators

## Fixity Declarations

Operators are **separate** from function definitions. A fixity declaration controls parsing:

```idris
infixl 8 +
infixr 9 *
infix  0 ==
prefix ~
```

| Keyword | Associativity | Example |
|---------|--------------|---------|
| `infixl` | Left | `n + m + 3 = ((n + m) + 3)` |
| `infixr` | Right | `f . g . h = f . (g . h)` |
| `infix` | Non-associative | `(a == b) == c` requires brackets |
| `prefix` | — | `~x` |

Precedence: higher number binds tighter. `*` (9) binds tighter than `+` (8).

## Using Operators

Any function can be used infix with parentheses:

```idris
n + 3    -- same as
(+) n 3
```

## Fixity Namespacing

Conflicting fixities from different modules:

```idris
module A
export infixl 8 -

module B
export infixr 5 -

module C
import A
import B

%hide A.infixl.(-)   -- hide conflicting fixity

-- Now: 1 - 3 - 10 parses as 1 - (3 - 10)
```

Hide fixities with `%hide ModuleName.fixityKind.(operator)`.

## Private Fixities

```idris
module A
private infixl &&& 8
export (&&&) : ...

module B
import A

main = do print (a &&& b)  -- Error: private fixity
          print ((&&&) a b) -- OK: prefix form
```

## Typebind Operators

Bind a **type** on the left side of an operator:

```idris
typebind infixr 0 =@
(=@) : (x : Type) -> (x -> Type) -> Type

-- Usage:
(x : Nat) =@ Singleton x

-- Desugars to:
(=@) Nat (\x => Singleton x)
```

Only `infixr` with precedence 0 allowed.

## Autobind Operators

Bind a **term** on the left side:

```idris
autobind infixr 0 =>>
(=>>) : Value -> (Value -> Value) -> Value

-- Usage:
(fstTy <- VStar) =>> (sndTy <- fstTy) =>> body

-- Desugars to:
(=>>) VStar (\fstTy => (=>>) fstTy (\sndTy => body))
```

Full syntax with explicit type: `(name : Type <- expr) op body`.

## Rules

- Operators are part of file namespacing
- A single operator can have multiple fixity declarations
- Fixities and operators are **separate** from function definitions
- Use with caution — operators can reduce legibility
