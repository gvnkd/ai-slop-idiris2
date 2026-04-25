# Multiplicities

## Quantitative Type Theory (QTT)

Idris 2 is based on QTT. Every variable has a **quantity** (multiplicity):

| Quantity | Meaning |
|----------|---------|
| `0` | Erased at runtime |
| `1` | Used exactly once at runtime |
| *(none)* | Unrestricted (Idris 1 behavior) |

Check multiplicities with holes:

```idris
append : Vect n a -> Vect m a -> Vect (n + m) a
append xs ys = ?rhs

-- :t rhs  =>
--   0 m : Nat
--   0 a : Type
--   0 n : Nat
--      ys : Vect m a
--      xs : Vect n a
```

Explicit multiplicities:

```idris
ignoreN : (0 n : Nat) -> Vect n a -> Nat
duplicate : (1 x : a) -> (a, a)  -- impossible to implement!
```

Unnamed multiplicities use `_`:

```idris
duplicate : (1 _ : a) -> (a, a)
```

## Erasure

The `0` multiplicity makes it precise what is available at runtime.

**Idris 1** (implicit `n` has quantity 0):
```idris
vlen : Vect n a -> Nat
vlen {n} xs = n  -- n is erased, cannot return it
```

**Idris 2** (explicit unrestricted):
```idris
vlen : {n : Nat} -> Vect n a -> Nat
vlen xs = n  -- n is available at runtime
```

Without the annotation, `n` has quantity 0 and cannot be returned:

```idris
sumLengths : Vect m a -> Vect n a -> Nat
sumLengths xs ys = vlen xs + vlen ys
-- Error: m is not accessible (quantity 0)

-- Fix: make m, n unrestricted
sumLengths : {m, n : _} -> Vect m a -> Vect n a -> Nat
sumLengths xs ys = vlen xs + vlen ys
```

**Rule:** It is an error to pattern match on a `0`-multiplicity argument unless its value is inferrable:

```idris
badNot : (0 x : Bool) -> Bool
badNot False = True  -- Error: matching on erased argument

-- OK: value is inferrable from second argument's type
sNot : (0 x : Bool) -> SBool x -> Bool
sNot False SFalse = True
sNot True  STrue  = False
```

## Linearity

The `1` multiplicity means a variable must be used **exactly once**.

"A variable is used" means:
- Data/primitive value: pattern matched (case, function argument)
- Function: applied to an argument

### Resource Protocols

Linearity encodes resource usage at the type level:

```idris
data DoorState = Open | Closed

data Door : DoorState -> Type where
     MkDoor : (doorId : Int) -> Door st

openDoor   : (1 d : Door Closed) -> Door Open
closeDoor  : (1 d : Door Open)   -> Door Closed
deleteDoor : (1 d : Door Closed) -> IO ()

-- Correct protocol:
doorProg : IO ()
doorProg = newDoor $ \d =>
           let d'  = openDoor d
               d'' = closeDoor d'
           in deleteDoor d''
```

If the protocol is violated (e.g., forgetting `deleteDoor`), the program won't type-check.

### IO Implementation

`IO` is implemented internally using linearity with a `%World` type:

```idris
data IORes : Type -> Type where
     MkIORes : (result : a) -> (1 x : %World) -> IORes a

data IO : Type -> Type where
     MkIO : (1 fn : (1 x : %World) -> IORes a) -> IO a
```

## Pattern Matching on Types

With non-erased types, you can pattern match on `Type`:

```idris
showType : Type -> String
showType Int       = "Int"
showType (List a)  = "List of " ++ showType a
showType _         = "something else"
```

Function types: the return type may depend on the input:

```idris
showType (Nat -> a) = "Function from Nat to " ++ showType (a Z)
```

### Relevance Matters

```idris
id    : a -> a                    -- parametric in a (a has quantity 0)
notId : {a : Type} -> a -> a      -- NOT parametric in a (a is unrestricted)
```

`notId` can pattern match on `a`:

```idris
notId {a = Integer} x = x + 1
notId x             = x

notId 93    -- 94
notId "???" -- "???"
```

A function is only parametric in `a` if `a` has multiplicity `0`.
