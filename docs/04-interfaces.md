# Interfaces

## What Are Interfaces

Interfaces are similar to Haskell type classes or Rust traits. They define overloadable functions that can be implemented for different types.

```idris
interface Show a where
    show : a -> String
```

Implementation:

```idris
Show Nat where
    show Z     = "Z"
    show (S k) = "s" ++ show k
```

Only **one** implementation per type is allowed. Implementations may have constraints:

```idris
Show a => Show (Vect n a) where
    show xs = "[" ++ show' xs ++ "]"
```

## Default Definitions

Methods can have default implementations:

```idris
interface Eq a where
    (==) : a -> a -> Bool
    (/=) : a -> a -> Bool

    x /= y = not (x == y)   -- default
    x == y = not (x /= y)   -- default
```

Minimal complete implementation requires either `==` or `/=`.

## Extending Interfaces

```idris
data Ordering = LT | EQ | GT

interface Eq a => Ord a where
    compare : a -> a -> Ordering
    (<)     : a -> a -> Bool
    -- ... other methods with defaults
```

Multiple constraints:

```idris
sortAndShow : (Ord a, Show a) => List a -> String
```

Constraints are first-class:

```idris
:t Ord   =>  Ord : Type -> Type
```

## Quantities for Parameters

By default, unnamed parameters have quantity `0` (erased at runtime):

```idris
:t show   =>  {0 a : Type} -> Show a => a -> String
```

Explicit quantities:

```idris
interface Storable (0 a : Type) (size : Nat) | a where
  peekByteOff : HasIO io => ForeignPtr a -> Int -> io a
```

## Functors and Applicatives

```idris
interface Functor (0 f : Type -> Type) where
    map : (m : a -> b) -> f a -> f b

interface Functor f => Applicative (0 f : Type -> Type) where
    pure  : a -> f a
    (<*>) : f (a -> b) -> f a -> f b
```

## Monads and Do-Notation

```idris
interface Applicative m => Monad (m : Type -> Type) where
    (>>=)  : m a -> (a -> m b) -> m b
    -- (>>) defined as: v >> e = v >>= \_ => e
```

`do`-notation desugaring:

| Syntax | Desugars to |
|--------|-------------|
| `x <- v; e` | `v >>= (\x => e)` |
| `v; e` | `v >> e` |
| `let x = v; e` | `let x = v in e` |

Monad Maybe example:

```idris
m_add : Maybe Int -> Maybe Int -> Maybe Int
m_add x y = do x' <- x
               y' <- y
               pure (x' + y')
```

### Pattern Matching Bind

```idris
readNumbers : IO (Maybe (Nat, Nat))
readNumbers =
  do Just x_ok <- readNumber
         | Nothing => pure Nothing
     Just y_ok <- readNumber
         | Nothing => pure Nothing
     pure (Just (x_ok, y_ok))
```

### Bang Notation (`!`)

```idris
m_add : Maybe Int -> Maybe Int -> Maybe Int
m_add x y = pure (!x + !y)
```

`!expr` evaluates and implicitly binds the result.

### Monad Comprehensions

```idris
m_add : Maybe Int -> Maybe Int -> Maybe Int
m_add x y = [ x' + y' | x' <- x, y' <- y ]
```

Requires `Monad` and `Alternative`.

## HasIO Interface

IO operations use `HasIO` for abstraction:

```idris
interface Monad io => HasIO io where
  liftIO : (1 _ : IO a) -> io a
```

## Idiom Brackets

```idris
m_add' : Maybe Int -> Maybe Int -> Maybe Int
m_add' x y = [| x + y |]
```

Desugars to: `pure (+) <*> x <*> y`

## Named Implementations

Multiple implementations for the same type:

```idris
[myord] Ord Nat where
   compare Z (S n)     = GT
   compare (S n) Z     = LT
   compare Z Z         = EQ
   compare (S x) (S y) = compare @{myord} x y

-- Usage:
sort @{myord} [3, 4, 1]  -- [4, 3, 1]
```

Named parent implementations with `using`:

```idris
[PlusNatMonoid] Monoid Nat using PlusNatSemi where
  neutral = 0
```

## Interface Constructors

Interfaces can have user-defined constructors:

```idris
interface A t => B t where
  constructor MkB
  getB : t

-- MkB : A t => t -> B t
getAB : (t : B a) => (a, a)
getAB = (getA, getB)
natAB = getAB { t = MkB (S Z) }
```

## Determining Parameters

Functional dependencies:

```idris
interface Monad m => MonadState s (0 m : Type -> Type) | m where
  get : m s
  put : s -> m ()
```

`| m` means only `m` is needed to find an instance; `s` is determined from it.
