module Language.Syntax exposing (..)

type alias ID = Int
type alias Info = String
-- WS : Whitespace
type alias WS = List String
type alias Env = List (String, (Value, Delta))
type alias Bnv = List (String, BValue)
type alias BEnv = List (String, (Value, Delta), BValue)

type Exp
    -- Constants
    = ETrue    WS
    | EFalse   WS
    | ENil     WS
    | EEmpList WS
    | EFloat   WS Float
    | EChar    WS Char
    | EString  WS String
    -- Lambda Calculus
    | EVar     WS String
    | ELam     WS Pattern Exp
    | EApp     WS Exp Exp
    | EFix     WS Exp
    | ECase    WS Exp Branch
    -- Primitive Functions
    | EUPrim   WS Uop Exp
    | EBPrim   WS Bop Exp Exp
    -- Constructors
    | ECons    WS Exp Exp
    | EList    WS Exp Exp
    | ETuple   WS Exp Exp
    -- Others
    | EParens  WS Exp
    | EError   Int Info  -- Int: 0 - Const; 1 - Fusion Fail; 2 - Other; 3: Recursion Conflict
    -- Graphics
    | EGraphic WS String Exp
    -- List Handlers
    | EMap     WS Exp Exp
    | EUnwrap  WS Exp
    -- Rect: [rAngle, color, x, y, w, h]
    -- Circle: [rAngle, color, cx, cy, r]
    -- Ellipse: [rAngle, color, cx, cy, rx, ry]
    -- Line: [rAngle, color, x1, y1, x2, y2]
    -- Polygon: [rAngle, color, [(x1, y1), (x2, y2), (x3, y3) ...]]
    -- Group: [rAngle, [graphic1, graphic2, ...]]
    | EConst WS Exp
    | EGList WS Exp Exp
    | EGCons WS Exp Exp
    | EDelta WS Exp Delta

type Bop = Add | Sub | Mul | Div | Mod | Cat
        |  Eq  | Lt  | Gt  | Le  | Ge 
        |  And | Or

type Uop = Not | Neg

type Value
    -- Constants
    = VNil
    | VTrue
    | VFalse
    | VFloat Float
    | VChar Char
    | VString String
    -- Constructors
    | VCons Value Value
    | VTuple Value Value
    -- Closures
    | VFix BEnv Exp
    | VClosure BEnv Pattern Exp
    -- Graphics
    | VGraphic String Value
    -- Others
    | VError Info
    | VDelta Value Delta

type Pattern
    -- Constants
    = PTrue    WS
    | PFalse   WS
    | PFloat   WS Float
    | PChar    WS Char
    | PString  WS String
    | PNil     WS
    | PEmpList WS
    -- Variables
    | PVar     WS String
    -- Constructors
    | PCons    WS Pattern Pattern
    | PList    WS Pattern Pattern
    | PTuple   WS Pattern Pattern
    -- Others
    | PError

type Branch
    = BSin WS Pattern Exp
    | BCom WS Branch Branch

-- Edit
type alias Ctx =
    List (String, Param)

type alias ST =
    List (String, (Env, Exp))

-- Env including inferred const result
type alias BST =
    List (String, (BEnv, Exp))


type Delta
    -- Atomic
    = DId
    -- Delta Value
    | DReplV Value
    | DAddV Value
    | DDeleteV
    | DInsertV
    | DMulV Value Delta
    --
    | DAdd Param
    | DMul Param
    -- Propagation
    | DFix BEnv Exp
    | DClosure BEnv Pattern Exp
    -- Constructors
    | DCons   Delta Delta
    | DTuple  Delta Delta
    -- List Handler
    | DCopy   Int
    | DDelete Int
    | DModify Int Delta
    | DInsert Int Param
    | DMap Delta
    | DGen Exp Delta Param
    -- Constraint
    | DRewr Param
    | DAbst Param
    | DCtt Pattern Delta
    | DMem   String Param
    | DGroup String Delta
    -- Extentions
    | DCom  Delta Delta
    | DApp  Delta Param
    | DFun Pattern Delta
    -- Others
    | DError String


type Param
    -- Constants
    = ANil
    | ATrue
    | AFalse
    | AFloat Float
    -- Varaibles
    | AVar String
    -- Construactors
    | ACons   Param Param
    | AGCons  Param Param
    | ATuple  Param Param
    -- Primitive Functions
    | AAdd Param Param
    | ASub Param Param
    | AMul Param Param
    | ADiv Param Param
    | ALt  Param Param
    | ALe  Param Param
    | AEq  Param Param
    -- Graphics
    | AGraphic String Param
    -- Others
    | AParens Param
    | AError String

type BValue
    = BTrue
    | BFalse
    | BTuple BValue BValue
    | GTuple BValue BValue
    | BFix BEnv Exp
    | BClosure BEnv Pattern Exp
    | BError