module Language.FEvalDelta exposing (..)

import Utils exposing (..)
import Language.Utils exposing (..)
import Language.Syntax exposing (..)



fevalDelta : BEnv -> Exp -> Value
fevalDelta env exp =
    case exp of
        ETrue _     -> VTrue
        EFalse _    -> VFalse
        EFloat _  f -> VFloat  f
        EChar _   c -> VChar   c
        EString _ s -> VString s
        
        EVar _ x ->
            case lookup2 x env of
                Just ((v, _),_) ->
                    case v of
                        VFix env_ e -> EFix [] e |> fevalDelta env_
                        _           -> v
                Nothing ->
                    VError ("Unbound variable: " ++ x)
        ELam _ p e -> VClosure env p e
        EConst _ e -> fevalDelta env e
        EApp _ e1 e2 ->
            case fevalDelta env e1 of
                VClosure envf p ef ->
                    case e2 of
                        EFix _ e ->
                            case p of
                                PVar _ s -> fevalDelta ((s, (VFix env e, DFix env e), BTrue)::envf) ef
                                _        -> VError "Error 46"
                        _ ->
                            case (fevalDelta env e2, BTrue) |> matchC p of
                                Just envm -> fevalDelta (envm ++ envf) ef
                                Nothing   -> VError "Error 10"
                _ -> let _ = Debug.log "Result:" (fevalDelta env e1) in VError "Error 11"
        EFix _ e -> EApp [] e (EFix [] e) |> fevalDelta env
        ECase _ e bs ->
            let v = fevalDelta env e
                res = matchBranch v bs 0
            in case res.ei of
                    EError _ _ -> VError "Error 12"
                    _ -> fevalDelta (res.envm ++ env) res.ei
        ENil _     -> VNil
        EEmpList _ -> VNil
        ECons _   e1 e2 -> VCons  (fevalDelta env e1) (fevalDelta env e2)
        EGCons _  e1 e2 -> VCons  (fevalDelta env e1) (fevalDelta env e2)
        EList _   e1 e2 -> VCons  (fevalDelta env e1) (fevalDelta env e2)
        EGList _  e1 e2 -> VCons  (fevalDelta env e1) (fevalDelta env e2)
        ETuple _ e1 e2  -> VTuple (fevalDelta env e1) (fevalDelta env e2)
        EParens _ e -> fevalDelta env e
        EError _ info -> VError ("Error 13: " ++ info)
        EBPrim _ bop e1 e2 ->
            case (fevalDelta env e1, fevalDelta env e2) of
                (VDelta v1 d1, VDelta v2 d2) -> VError "Error: delta values on both side are not allowed."
                (VDelta (VFloat v1) d1, VFloat v2) -> 
                    case bop of 
                      Add -> VDelta (VFloat (v1 + v2)) d1
                      Mul -> VDelta (VFloat (v1 * v2)) (DMulV (VFloat v2) d1)
                      _   -> VError "wrong bop"
                (VFloat v1, VDelta (VFloat v2) d2) -> 
                    case bop of 
                      Add -> VDelta (VFloat (v1 + v2)) d2
                      Mul -> VDelta (VFloat (v1 * v2)) (DMulV (VFloat v1) d2)
                      _   -> VError "wrong bop"
                (VFloat f1, VFloat f2) ->
                    case bop of
                        Add -> VFloat (f1 + f2)
                        Mul -> VFloat (f1 * f2)
                        Sub -> VFloat (f1 - f2)
                        Div -> VFloat (f1 / f2)
                        Mod -> modBy (f2 |> round) (f1 |> round) 
                                    |> toFloat 
                                    |> VFloat
                        
                        Lt -> if f1 < f2  then VTrue else VFalse
                        Gt -> if f1 > f2  then VTrue else VFalse
                        Le -> if f1 <= f2 then VTrue else VFalse
                        Ge -> if f1 >= f2 then VTrue else VFalse
                        Eq -> if f1 == f2 then VTrue else VFalse
                        _   -> VError "49"

                (VString s1, VString s2) ->
                    if bop == Cat 
                    then VString (s1 ++ s2)
                    else VError "50"
                
                (v1, v2) ->
                    case bop of
                        Eq -> if v1 == v2 then VTrue else VFalse
                        
                        And ->
                            case (v1, v2) of
                                (VTrue, VTrue)   -> VTrue
                                (VTrue, VFalse)  -> VFalse
                                (VFalse, VTrue)  -> VFalse
                                (VFalse, VFalse) -> VFalse
                                _                -> VError "Error 47"
                        
                        Or ->
                            case (v1, v2) of
                                (VTrue,  VTrue)  -> VTrue
                                (VTrue,  VFalse) -> VTrue
                                (VFalse, VTrue)  -> VTrue
                                (VFalse, VFalse) -> VFalse
                                _                -> VError "Error 48"
                        
                        _ ->
                            VError "TODO"
        
        EUPrim _ uop e ->
            case uop of
                Neg ->
                    case fevalDelta env e of
                        VFloat f -> VFloat (-f)
                        _        -> VError "Error 14"

                Not ->
                    case fevalDelta env e of
                        VTrue  -> VFalse
                        VFalse -> VTrue
                        _      -> VError "Error 15"
        
        EGraphic _ s e -> VGraphic s (fevalDelta env e)

        EMap _ e1 e2 ->
            case (fevalDelta env e1, fevalDelta env e2) of
                (VClosure envf p ef, VGraphic s pars) ->
                    case matchC p (pars,BTrue) of
                        Just envm -> fevalDelta (envm ++ envf) ef |> VGraphic s
                        Nothing   -> VError "Error 52"
                
                _ -> VError "Error 55"

        EUnwrap _ e ->
            case fevalDelta env e of
                VGraphic _ v -> v
                
                _ -> VError "Error 56"

        EDelta _ e delta ->
            let v = fevalDelta env e
            in VDelta v delta


fevalValue : Value -> Value
fevalValue v = 
    case v of  
        VTuple vf vs -> VTuple (fevalValue vf) (fevalValue vs)
        VCons vh vt -> case vh of 
            VDelta _ DDeleteV -> fevalValue vt
            _                 -> VCons (fevalValue vh) (fevalValue vt)
        VDelta (VFloat f) delta -> 
            case delta of 
                DReplV newV -> newV
                DInsertV    -> (VFloat f)
                _           ->
                    case delta of 
                            DReplV newV -> newV
                            DAddV (VFloat df) -> VFloat (f+df)
                            DMulV (VFloat scalar) (DAddV (VFloat df)) -> VFloat (f+scalar*df) 
                            _ -> VError "not supported"
        _ -> v
