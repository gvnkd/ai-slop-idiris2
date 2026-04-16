module Protocol

public export
record ProcessTask where
  constructor MKProcessTask
  name    : String       -- Краткое имя для логов
  path    : String       -- Полный путь к бинарнику
  args    : List String  -- Список аргументов
  timeout : Int          -- Тайм-аут в секундах

public export
data TaskState = Ready | InProgress | Done | Failed

public export
data Ticket : TaskState -> Nat -> Type where
     MkTicket : (task : ProcessTask) -> Ticket st n

public export
data StepResult : Nat -> Type where
     OK : String -> StepResult n
     Recoverable : Ticket Ready k -> StepResult (S k)
     Abandoned : String -> StepResult n

export
startTask : {n : Nat} -> (1 t : Ticket Ready n) -> Ticket InProgress n
startTask (MkTicket t) = MkTicket t

-- Сама логика "решать, что делать с кодом возврата"
-- Теперь Right — это успех (String, Ticket Done), а Left — ошибка (Ticket Failed)
export
analyzeResult : {n : Nat} -> (1 t : Ticket InProgress n) -> Int -> Either (Ticket Failed n) (String, Ticket Done n)
analyzeResult (MkTicket t) code =
  if code == 0
     then Right ("Success", MkTicket t)
     else Left (MkTicket t)

export
retryTicket : (1 t : Ticket Failed (S n)) -> Ticket Ready n
retryTicket (MkTicket t) = MkTicket t

