module Protocol

public export
data TaskState = Ready | InProgress | Done | Failed

public export
data Ticket : TaskState -> Nat -> Type where
     MkTicket : (val : Int) -> Ticket st n

public export
data StepResult : Nat -> Type where
     OK : Int -> StepResult n
     Recoverable : Ticket Ready k -> StepResult (S k)
     Abandoned : Int -> StepResult n

-- Чистые переходы состояний
export
startTask : {n : Nat} -> (1 t : Ticket Ready n) -> Ticket InProgress n
startTask (MkTicket v) = MkTicket v

export
completeTask : {n : Nat} -> (1 t : Ticket InProgress n) -> Either (Int, Ticket Done n) (Ticket Failed n)
completeTask (MkTicket v) = 
  if (mod v 10) == 0 
     then Right (MkTicket v)
     else Left (v * v, MkTicket v)

export
retryTicket : (1 t : Ticket Failed (S n)) -> Ticket Ready n
retryTicket (MkTicket v) = MkTicket v

-- Логика протокола
export
processProtocol : {n : Nat} -> (1 t : Ticket Ready (S n)) -> StepResult (S n)
processProtocol t = 
  let t2 = startTask t in
  case completeTask t2 of
    Left (val, _) => OK val  -- Мы упростили, так как Ticket Done тут потребляется неявно
    Right t_err => 
      let (MkTicket v) = t_err in
      if v > 100 || n == 0
         then Abandoned v
         else Recoverable (retryTicket t_err)
