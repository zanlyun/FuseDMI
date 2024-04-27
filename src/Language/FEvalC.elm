module Language.FEvalC exposing (..)

import Utils exposing (..)
import Language.Utils exposing (..)
import Language.Syntax exposing (..)
import Language.FEvalDelta exposing (fevalDelta)

fevalC : BEnv -> Exp -> (Value, BValue)
fevalC benv exp =
    case exp of
        -- I-Con2
        ETrue _                -> (VTrue, BFalse)
        EFalse _               -> (VFalse, BFalse)
        EFloat _  f            -> (VFloat f, BFalse)
        EChar _   c            -> (VChar  c, BFalse)
        EString _ s            -> (VString s, BFalse)
        -- I-Con1
        EConst _ (ETrue _)     -> (VTrue, BTrue)
        EConst _ (EFalse _)    -> (VFalse, BTrue)
        EConst _ (EFloat _  f) -> (VFloat f, BTrue)
        EConst _ (EChar _   c) -> (VChar  c, BTrue)
        EConst _ (EString _ s) -> (VString s, BTrue)
       
        -- I-Var1
        EConst _ (EVar _ x) -> 
            case lookup2 x benv of 
                Just ((v, _), b) -> 
                    case (v, b) of
                        (VFix benv_ e, _) -> EFix [] e |> fevalC benv_
                        _           -> (v, b)
                Nothing -> 
                    (VError ("Unbound variable: " ++ x), BError)
        -- I-Var2
        EVar _ x ->
            case lookup2 x benv of
                Just ((v, _), b) ->
                    case v of
                        VFix benv_ e -> EFix [] e |> fevalC benv_
                        _           -> case b of 
                            GTuple _ _ -> (v, b)
                            BTrue      -> (v, BFalse)
                            _          -> (v, BFalse)
                Nothing ->
                    (VError ("Unbound variable: " ++ x), BError)
        -- I-Lam
        ELam _ p e   -> (VClosure benv p e, BClosure benv p e)
        -- I-Lam2
        EConst _ (ELam _ p e)   -> (VClosure benv p (EConst [] e), BClosure benv p (EConst [] e))

        -- I-App0
        EConst wsc (EApp wsc2 e1 e2) -> fevalC benv (EApp wsc2 (EConst wsc e1) (EConst wsc e2))
        -- I-App
        EApp _ e1 e2 ->
            case fevalC benv e1 of
                (VClosure benvf p ef, _) ->
                    case e2 of
                        EFix _ e ->
                            case p of
                                PVar _ s -> 
                                    fevalC ((s, (VFix benv e, DFix benv e), BFix benv e)::benvf) ef
                                _        -> (VError "Error 46", BError)
                        _ ->
                            case fevalC benv e2 |> matchC p of
                                Just envm -> fevalC (envm ++ benvf) ef
                                Nothing   -> (VError "Error 10", BError)
                (VError str, b) -> (VError str, b)
                _ ->  (VError "Error 11", BError)
        
        EFix _ e -> EApp [] e (EFix [] e) |> fevalC benv
        -- I-Case
        ECase _ e bs ->
            let (v, bv) = fevalC benv e
            in case v of 
                VError _ -> (v, bv)
                _        ->
                    let res = matchBranchC (v, bv) bs 0
                    in case res.ei of
                        EError _ info -> (VError info, BError)
                        _             -> fevalC (res.envm ++ benv) res.ei
        -- I-Case2
        EConst _ (ECase _ e bs) ->
            let (v, bv) = fevalC benv (EConst [] e)
                res = matchBranchC (v, bv) bs 0
            in case res.ei of
                EError _ info -> (VError info, BError)
                _             -> fevalC (res.envm ++ benv) (EConst [] res.ei)
 
        ENil _     -> (VNil, BFalse)
        EConst _ (ENil _) -> (VNil, BTrue)
        EEmpList _ -> (VNil, BFalse)
        EConst _ (EEmpList _) -> (VNil, BTrue)
        -- I-List2
        ECons _   e1 e2 -> 
            let (v1, bv1) = fevalC benv e1
                (v2, bv2) = fevalC benv e2
            in (VCons v1 v2, BTuple bv1 bv2)
        -- I-List1
        EConst _ (ECons _   e1 e2) -> 
            let (v1, bv1) = fevalC benv (EConst [] e1)
                (v2, bv2) = fevalC benv (EConst [] e2)
            in (VCons v1 v2, BTuple bv1 bv2)
        -- I-List2
        EList _   e1 e2 -> 
            let (v1, bv1) = fevalC benv e1
                (v2, bv2) = fevalC benv e2
            in (VCons v1 v2, BTuple bv1 bv2)
        -- I-GList
        EGList _ e1 e2 -> 
            let (v1, bv1) = fevalC benv e1
                (v2, bv2) = fevalC benv e2
            in (VCons v1 v2, GTuple bv1 bv2)
        EGCons _   e1 e2 -> 
            let (v1, bv1) = fevalC benv e1
                (v2, bv2) = fevalC benv e2
            in (VCons v1 v2, GTuple bv1 bv2)
        -- I-List1
        EConst _ (EList _   e1 e2) -> 
            let (v1, bv1) = fevalC benv (EConst [] e1)
                (v2, bv2) = fevalC benv (EConst [] e2)
            in (VCons v1 v2, BTuple bv1 bv2)
        -- I-Tuple2
        ETuple _ e1 e2  -> 
            let (v1, bv1) = fevalC benv e1
                (v2, bv2) = fevalC benv e2
            in (VTuple v1 v2, BTuple bv1 bv2)
        -- I-Tuple1
        EConst _ (ETuple _   e1 e2) -> 
            let (v1, bv1) = fevalC benv (EConst [] e1)
                (v2, bv2) = fevalC benv (EConst [] e2)
            in (VTuple v1 v2, BTuple bv1 bv2)
        EParens _ e -> fevalC benv e
        -- const (1+2) has parens
        EConst _ (EParens _ e) -> fevalC benv (EConst [] e)
        EError _ info -> (VError info, BError)
        -- I-Oplus
        EBPrim _ bop e1 e2 ->
            case (fevalC benv e1, fevalC benv e2) of
                ((VDelta _ _,_), (VDelta _ _,_)) -> (VError "delta values on both side are not allowed.",BFalse)
                ((VDelta (VFloat v1) d1,_), (VFloat v2,_)) -> 
                    case bop of 
                      Add -> (VDelta (VFloat (v1 + v2)) d1, BFalse)
                      Mul -> (VDelta (VFloat (v1 * v2)) (DMulV (VFloat v2) d1), BFalse)
                      _   -> (VError "wrong bop", BFalse)
                ((VFloat v1,_), (VDelta (VFloat v2) d2,_)) -> 
                    case bop of 
                      Add -> (VDelta (VFloat (v1 + v2)) d2, BFalse)
                      Mul -> (VDelta (VFloat (v1 * v2)) (DMulV (VFloat v1) d2),BFalse)
                      _   -> (VError "wrong bop", BFalse)

                ((VFloat f1, _), (VFloat f2, _)) ->
                    let val = case bop of
                            Add -> VFloat (f1 + f2)
                            Mul -> VFloat (f1 * f2)
                            Sub -> VFloat (f1 - f2)
                            Div -> VFloat (f1 / f2)
                            Mod -> modBy (f2 |> round) (f1 |> round) |> toFloat |> VFloat
                            Lt -> if f1 < f2  then VTrue else VFalse
                            Gt -> if f1 > f2  then VTrue else VFalse
                            Le -> if f1 <= f2 then VTrue else VFalse
                            Ge -> if f1 >= f2 then VTrue else VFalse
                            Eq -> if f1 == f2 then VTrue else VFalse
                            _   -> VError "49"
                    in (val, BFalse)
                ((VString s1, _), (VString s2, _)) ->
                    if bop == Cat 
                    then (VString (s1 ++ s2), BFalse)
                    else (VError "50", BFalse)
                ((v1, _), (v2, _)) ->
                    let _ = Debug.log "v1" v1 
                        _ = Debug.log "v2" v2
                        _ = Debug.log "bop" bop
                        val = case bop of
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
                            _ -> VError "TODO 153"
                    in (val, BFalse)        
        -- I-C-Oplus
        EConst _ (EBPrim _ bop e1 e2) ->
            case (fevalC benv (EConst [] e1), fevalC benv (EConst [] e2)) of
                ((VFloat f1, b1), (VFloat f2, b2)) ->
                    let val = case bop of
                            Add -> VFloat (f1 + f2)
                            Mul -> VFloat (f1 * f2)
                            Sub -> VFloat (f1 - f2)
                            Div -> VFloat (f1 / f2)
                            Mod -> modBy (f2 |> round) (f1 |> round) |> toFloat |> VFloat
                            Lt -> if f1 < f2  then VTrue else VFalse
                            Gt -> if f1 > f2  then VTrue else VFalse
                            Le -> if f1 <= f2 then VTrue else VFalse
                            Ge -> if f1 >= f2 then VTrue else VFalse
                            Eq -> if f1 == f2 then VTrue else VFalse
                            _   -> VError "49"
                        -- _ = Debug.log "b1" b1
                        -- _ = Debug.log "b2" b2
                        b = bAnd b1 b2
                    in (val, b)
                ((VString s1, b1), (VString s2, b2)) ->
                    if bop == Cat 
                    then (VString (s1 ++ s2), bAnd b1 b2)
                    else (VError "50", BFalse)
                ((v1, b1), (v2, b2)) ->
                    let val = case bop of
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
                            _ -> VError "TODO"
                        b = bAnd b1 b2
                    in (val, b)        
        -- I-Unary
        EUPrim _ uop e ->
            case uop of
                Neg ->
                    case fevalC benv e of
                        (VFloat f, _) -> (VFloat (-f), BFalse)
                        _             -> (VError "Error 14", BFalse)
                Not ->
                    case fevalC benv e of
                        (VTrue, _)  -> (VFalse, BFalse)
                        (VFalse, _) -> (VTrue, BFalse)
                        _           -> (VError "Error 15", BFalse)
         -- I-C-Unary
        EConst _ (EUPrim _ uop e) ->
            case uop of
                Neg ->
                    case fevalC benv (EConst [] e) of
                        (VFloat f, b) -> (VFloat (-f), b)
                        _             -> (VError "Error 14", BFalse)
                Not ->
                    case fevalC benv (EConst [] e) of
                        (VTrue, b)  -> (VFalse, b)
                        (VFalse, b) -> (VTrue, b)
                        _           -> (VError "Error 15", BFalse)
        
        EGraphic _ s e -> let (v, b) = fevalC benv e
            in (VGraphic s v, b)

        -- Graphics.map f graphic
        EMap _ e1 e2 ->
            case (fevalC benv e1, fevalC benv e2) of
                ((VClosure envf p ef, _), (VGraphic s pars, b2)) ->
                    case matchC p (pars, b2) of
                        Just envm -> let (v, b) = fevalC (envm ++ envf) ef 
                                     in (VGraphic s v, b)
                        Nothing   -> (VError "Error 52", BError)
                _ -> (VError "Error 55", BError)
        EUnwrap _ e ->
            case fevalC benv e of
                (VGraphic _ v, b) -> (v,b)
                _ -> (VError "Error 56", BError)
        EConst _ (EDelta _ e d) -> 
            case d of 
                DId -> fevalC benv (EConst [] e)     
                _   -> fevalC benv (EDelta [] e d)
        EDelta _ e d ->             
            let v = fevalDelta benv e
            in (VDelta v d, BFalse)
        -- I-Const
        EConst _ e -> fevalC benv e
 