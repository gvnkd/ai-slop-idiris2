# Introduction to Idris 2

## What is Idris 2?

Idris 2 is a general-purpose functional programming language with **dependent types**. It is compiled, aims to generate efficient executable code, and has a lightweight FFI for interacting with external libraries.

Idris 2 is implemented in Idris 2 itself (bootstrapping), and targets Chez Scheme by default.

## Dependent Types

The key distinction from conventional languages (Haskell, OCaml) is that **types can depend on values**. Types are a first-class language construct:

```idris
app : Vect n a -> Vect m a -> Vect (n + m) a
```

The type of `app` describes its own properties: the result length equals the sum of input lengths.

## Core Concepts

- **Dependent types** — types can contain values and describe properties
- **First-class types** — types can be computed, passed to functions, and returned
- **Curry-Howard correspondence** — proofs are programs, propositions are types
- **Totality** — functions must terminate for all inputs (by default, `covering`)
- **Pattern matching** — functions are defined by case analysis on inputs
- **Quantitative Type Theory (QTT)** — every variable has a multiplicity (0, 1, or unrestricted)

## Intended Audience

This documentation assumes familiarity with a functional language (Haskell or OCaml). It is aimed at readers interested in using dependent types for writing and verifying software.

## Key Design Philosophy

Idris **allows** (but does not require) programmers to express invariants and prove properties. Programs that do not use dependent typing features work exactly as in a conventional functional language.
