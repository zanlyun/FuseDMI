module Language.FusionBDelta exposing (..)
import Language.Syntax exposing (Exp)
import Language.Syntax exposing (Exp(..))
import Language.Syntax exposing (Delta(..))
import Language.Syntax exposing (Value(..))
import Language.Syntax exposing (Bop(..))
import Language.Syntax exposing (Branch)

fuseDeltaExp : Exp -> Exp 
fuseDeltaExp exp = 
    case exp of 
        EDelta ws exp1 delta -> 
            case delta of 
                DId -> exp1
                DReplV v -> 
                    case v of 
                        VTrue -> ETrue ws
                        VFalse -> EFalse ws
                        VNil -> ENil ws
                        VFloat f -> EFloat ws f 
                        VChar c -> EChar ws  c 
                        VString str -> EString ws str
                        _ -> EError 1 "fuse DeltaExp fail"
                DAddV v -> 
                    case v of 
                        VFloat f -> 
                          case exp1 of 
                              EFloat wsf ef -> EFloat wsf (ef+f)
                              _ -> EBPrim [" "] Add exp1 (EFloat [] f)
                        _ -> EError 1 "fuse DeltaExp fail"
                DMulV (VFloat f1) (DAddV (VFloat f2)) -> EBPrim [] Add exp1 (EFloat [] (f1*f2))
                DCom delta1 delta2 -> 
                    let newExp1 = fuseDeltaExp (EDelta ws exp1 delta1) in 
                    fuseDeltaExp (EDelta [] newExp1 delta2)
                DDeleteV -> case exp1 of 
                    EList _ _ t -> t
                    ECons _ _ t -> t
                    _ -> EError 1 "fuse DDeleteV fail."
                DInsertV -> exp1
                _ -> EError 1 "fuse DeltaExp fail"
        ELam ws p e1 -> ELam ws p (fuseDeltaExp e1)
        EApp ws e1 e2 -> EApp ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        EFix ws e1 -> EFix ws (fuseDeltaExp e1)
        ECase ws e1 branch -> ECase ws (fuseDeltaExp e1) (fuseDeltaBranch branch)
        EUPrim ws uop e1 -> EUPrim ws uop (fuseDeltaExp e1)
        EBPrim ws bop e1 e2 -> EBPrim ws bop (fuseDeltaExp e1) (fuseDeltaExp e2)
        ECons ws e1 e2 -> ECons ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        EList ws e1 e2 -> EList ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        ETuple ws e1 e2 -> ETuple ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        EParens ws e1 -> EParens ws (fuseDeltaExp e1)
        EGraphic ws str e1 -> EGraphic ws str (fuseDeltaExp e1)
        EMap ws e1 e2 -> EMap ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        EUnwrap ws e1 -> EUnwrap ws (fuseDeltaExp e1)
        EConst ws e1 -> EConst ws (fuseDeltaExp e1)
        EGList ws e1 e2 -> EGList ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        EGCons ws e1 e2 -> EGCons ws (fuseDeltaExp e1) (fuseDeltaExp e2)
        _ -> exp

fuseDeltaBranch : Branch -> Branch 
fuseDeltaBranch b = b