# Theorem Proving

## Curry-Howard Correspondence

In Idris, **proofs are programs** and **propositions are types**:

- A proposition is a type
- A proof is a term inhabiting that type
- A true proposition is inhabited (has a constructor)

```idris
-- Proposition: 1 + 1 = 2
:t 1 + 1 = 2   -- (fromInteger 1 + fromInteger 1) === fromInteger 2 : Type

-- Proof:
onePlusOne : 1+1=2
onePlusOne = Refl
```

## Equality

Propositional equality type:

```idris
data Equal : a -> b -> Type where
     Refl : Equal x x

-- Syntactic sugar: x = y
```

Only `Refl` proves equality — both sides must be **definitionally equal** (normalize to the same value):

```idris
four_eq : 4 = 4
four_eq = Refl

twoplustwo : 2 + 2 = 4
twoplustwo = Refl   -- 2+2 reduces to 4

plusReducesZ : (m : Nat) -> plus Z m = m
plusReducesZ m = Refl   -- plus Z m reduces to m
```

`4 = 5` is uninhabited — no proof exists.

### Heterogeneous Equality

Equality between values of different types:

```idris
vect_eq_length : (xs : Vect n a) -> (ys : Vect m a) ->
                 (xs = ys) -> n = m
vect_eq_length xs _ Refl = Refl
```

Explicit heterogeneous equality: `(~=~)`

## The Empty Type (`Void`)

```idris
data Void : Type   -- no constructors

void : Void -> a   -- ex falso quodlibet
```

Prove impossibility by constructing `Void`:

```idris
disjoint : (n : Nat) -> Z = S n -> Void
disjoint n prf = replace {p = disjointTy} prf ()
```

## Proving by Induction

Proofs follow the same structure as recursive functions:

```idris
-- Prove: plus n Z = n
plusReducesR : (n : Nat) -> plus n Z = n
plusReducesR Z = Refl
plusReducesR (S k)
    = let rec = plusReducesR k in
          rewrite rec in Refl
```

### `cong` — Congruence

```idris
cong : (f : t -> u) -> a = b -> f a = f b
```

### `rewrite ... in`

Rewrite a type using an equality proof:

```idris
helpEven : (j : Nat) -> Parity (S j + S j) -> Parity (S (S (plus j j)))
helpEven j p = rewrite plusSuccRightSucc j j in p
```

`rewrite` searches for the left side of the equality in the type and replaces it with the right side.

### `sym` and `trans`

```idris
sym  : x = y -> y = x
trans : a = b -> b = c -> a = c
```

## Replace

```idris
replace : (0 rule : x = y) -> p x -> p y
```

Substitute `y` for `x` in any property `p`. The `0` multiplicity means the proof is erased at runtime.

## Totality Checking

Proofs must be **total** (terminate for all inputs):

```idris
total
plus_commutes : (n, m : Nat) -> n + m = m + n
```

Totality requirements:
- Cover all possible inputs
- Well-founded recursion (arguments decrease)
- No non-strictly-positive types
- No calls to non-total functions

### Hints for Totality

```idris
assert_smaller : a -> a -> a   -- assert y is smaller than x
assert_total   : a -> a        -- mark as always total (use sparingly)
```

## Interactive Proof Building

Use holes and REPL to build proofs incrementally:

```idris
plus_commutes Z m = ?plus_commutes_Z
plus_commutes (S k) m = ?plus_commutes_S

-- :t plus_commutes_Z  =>  m = plus m Z
-- :t plus_commutes_S  =>  S (plus k m) = plus m (S k)
```

## Propositional vs Definitional Equality

| | Definitional | Propositional |
|---|-------------|---------------|
| Proof | `Refl` alone | Requires `rewrite`, `cong`, etc. |
| Condition | Both sides normalize to same value | Provable but not definitionally equal |
| Example | `1+1 = 2` | `n + 0 = n` (for symbolic `n`) |
