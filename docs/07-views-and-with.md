# Views and the "with" Rule

## Dependent Pattern Matching

In dependent types, the form of one argument can be determined by the value of another:

```idris
(++) : Vect n a -> Vect m a -> Vect (n + m) a
(++) {n=Z}   []        ys = ys
(++) {n=S k} (x :: xs) ys = x :: xs ++ ys
```

The length `n` is constrained by the vector shape.

## The `with` Rule

The `with` construct matches on intermediate computation results, accounting for dependent types:

```idris
filter : (a -> Bool) -> Vect n a -> (p ** Vect p a)
filter p [] = (_ ** [])
filter p (x :: xs) with (filter p xs)
  filter p (x :: xs) | (_ ** xs') =
    if p x then (_ ** x :: xs') else (_ ** xs')
```

If the pattern is unchanged, use `_`:

```idris
filter p (x :: xs) with (filter p xs)
  _ | (_ ** xs') = if p x then (_ ** x :: xs') else (_ ** xs')
```

### Nested `with` Clauses

```idris
foo : Int -> Int -> Bool
foo n m with (n + 1)
  _ | 2 with (m + 1)
    _ | 3 = True
    _ | _ = False
  _ | _ = False
```

Multiple expressions in one `with`:

```idris
foo n m with (n + 1) | (m + 1)
  _ | 2 | 3 = True
  _ | _ | _ = False
```

## Views

A **view** transforms a value into a form suitable for pattern matching.

```idris
data Parity : Nat -> Type where
   Even : {n : _} -> Parity (n + n)
   Odd  : {n : _} -> Parity (S (n + n))

parity : (n : Nat) -> Parity n
```

Using the `Parity` view:

```idris
natToBin : Nat -> List Bool
natToBin Z = Nil
natToBin k with (parity k)
   natToBin (j + j)     | Even = False :: natToBin j
   natToBin (S (j + j)) | Odd  = True  :: natToBin j
```

The `with` refines the original argument pattern based on the view constructor:
- `Even` refines `k` to `(j + j)` (from `Parity (n + n)`)
- `Odd` refines `k` to `S (j + j)` (from `Parity (S (n + n))`)

## Defining Views

```idris
parity : (n : Nat) -> Parity n
parity Z = Even {n = Z}
parity (S Z) = Odd {n = Z}
parity (S (S k)) with (parity k)
  parity (S (S (j + j)))     | Even
      = rewrite plusSuccRightSucc j j in Even {n = S j}
  parity (S (S (S (j + j)))) | Odd
      = rewrite plusSuccRightSucc j j in Odd {n = S j}
```

Views require proofs (theorem proving) for correctness.
