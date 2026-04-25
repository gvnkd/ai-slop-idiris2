# Miscellany

## Implicit Arguments

### Auto Implicit Arguments

Idris searches the context for values of the required type:

```idris
head : (xs : List a) -> {auto p : isCons xs = True} -> a
head (x :: xs) = x
```

Search order:
1. Local variables with exact right type
2. Constructors (recursive, depth ≤ 100)
3. Local function variables (recursive)
4. Functions marked `%hint`

Explicit provision: `head xs {p = proof}`

### Default Implicit Arguments

Provide a default value for implicit arguments:

```idris
fibonacci : {default 0 lag : Nat} -> {default 1 lead : Nat} -> (n : Nat) -> Nat
fibonacci {lag} Z = lag
fibonacci {lag} {lead} (S n) = fibonacci {lag=lead} {lead=lag+lead} n

fibonacci 5   -- equivalent to fibonacci {lag=0} {lead=1} 5
```

Primarily intended for custom proof search scripts.

## Literate Programming

Files with `.lidr` extension:

```idris
> module Literate

This is a comment.

> main : IO ()
> main = putStrLn "Hello literate world!"
```

- Lines starting with `>` are code
- All other lines are comments
- Blank line required between code and comment lines

## Universes and Cumulativity

Types have types, forming a hierarchy:

```idris
:t Type   -- Type : Type 1
```

The hierarchy prevents Girard's paradox:

```
Type : Type 1 : Type 2 : Type 3 : ...
```

Universes are **cumulative**: if `x : Type n` and `n ≤ m`, then `x : Type m`.

### Universe Polymorphism

Self-application cycles are prevented:

```idris
myid : (a : Type) -> a -> a
myid _ x = x

idid : (a : Type) -> a -> a
idid = myid _ myid   -- Error: universe cycle
```

## `%default` Directive

Control totality requirements for the entire file:

```idris
%default total     -- all functions must be total
%default covering  -- all functions must cover (default for new files)
%default partial   -- relax totality requirement
```

After `%default total`, individual functions can be marked `partial`.

## `assert_total`

Mark a subexpression as total (use sparingly):

```idris
assert_total : a -> a
assert_total x = x
```

Useful for reasoning about primitives or external functions.
