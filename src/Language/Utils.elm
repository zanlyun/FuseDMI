module Language.Utils exposing (..)

import Utils exposing (..)
import Language.Syntax exposing (..)
import Language.UtilsFD exposing (eqDelta)
import List exposing (member)
import Array exposing (get)

match : Pattern -> Value -> Maybe (List (String, (Value, Delta)))
match p v =
    case (p, v) of
        (PVar _ s, _) -> Just [(s, (v, value2DId v))]
        
        (PNil _,     VNil) -> Just []
        (PEmpList _, VNil) -> Just []
        (PTrue _,  VTrue)  -> Just []
        (PFalse _, VFalse) -> Just []

        (PCons _ p1 p2, VCons v1 v2) ->
            case (match p1 v1, match p2 v2) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        
        (PList _ p1 p2, VCons v1 v2) ->
            case (match p1 v1, match p2 v2) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        
        (PTuple _ p1 p2, VTuple v1 v2) ->
            case (match p1 v1, match p2 v2) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        
        (PFloat _  f, VFloat g)  -> if f  == g  then Just [] else Nothing
        (PString _ s, VString t) -> if s  == t  then Just [] else Nothing
        (PChar _  c1, VChar c2)  -> if c1 == c2 then Just [] else Nothing
        
        _ -> Nothing


matchC : Pattern -> (Value, BValue) -> Maybe (List (String, (Value, Delta), BValue))
matchC p (v, bv) =
   case (p, v, bv) of
        (PVar _ s,      _, b) -> Just [(s, (v, value2DId v), b)]
        (PNil _,     VNil, _) -> Just []
        (PEmpList _, VNil, _) -> Just []
        (PTrue _,    VTrue, _)  -> Just []
        (PFalse _, VFalse, _) -> Just []

        -- Eval case
        (PCons _ p1 p2, VCons v1 v2, BFalse) ->
            case (matchC p1 (v1, BFalse), matchC p2 (v2, BFalse)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        -- EvalC case
        (PCons _ p1 p2, VCons v1 v2, BTuple b1 b2) ->
            case (matchC p1 (v1, b1), matchC p2 (v2, b2)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        (PCons _ p1 p2, VCons v1 v2, GTuple b1 b2) ->
            case (matchC p1 (v1, b1), matchC p2 (v2, b2)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing                
        -- Eval case
        (PList _ p1 p2, VCons v1 v2, BFalse) ->
            case (matchC p1 (v1, BFalse), matchC p2 (v2, BFalse)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        -- EvalC case
        (PList _ p1 p2, VCons v1 v2, BTuple b1 b2) ->
            case (matchC p1 (v1, b1), matchC p2 (v2, b2)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        (PList _ p1 p2, VCons v1 v2, GTuple b1 b2) ->
            case (matchC p1 (v1, b1), matchC p2 (v2, b2)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing                
        -- Eval case
        (PTuple _ p1 p2, VTuple v1 v2, BFalse) ->
            case (matchC p1 (v1, BFalse), matchC p2 (v2, BFalse)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
         -- EvalC case
        (PTuple _ p1 p2, VTuple v1 v2, BTuple b1 b2) ->
            case (matchC p1 (v1, b1), matchC p2 (v2, b2)) of
                (Just m1, Just m2) -> Just (m1 ++ m2)
                _                  -> Nothing
        
        (PFloat _  f, VFloat g, _)  -> if f  == g  then Just [] else Nothing
        (PString _ s, VString t, _) -> if s  == t  then Just [] else Nothing
        (PChar _  c1, VChar c2, _)  -> if c1 == c2 then Just [] else Nothing
        
        _ -> Nothing


value2DId : Value -> Delta
value2DId v =
    case v of
        VFix env1 e1        -> DFix env1 e1
        VClosure env1 p1 e1 -> DClosure env1 p1 e1
        VCons v1 v2         -> DCons   (value2DId v1) (value2DId v2)
        VTuple v1 v2        -> DTuple (value2DId v1) (value2DId v2)
        _                   -> DId


type alias MatchCaseRes =
    { envm : BEnv
    , choice: Int
    , ei : Exp
    , pi : Pattern
    }


matchBranch : Value -> Branch -> Int -> MatchCaseRes
matchBranch v b cnt =
    case b of
        BSin _ p e ->
            case matchC p (v, BFalse) of
                Nothing ->
                    { envm = []
                    , choice = cnt + 1
                    , ei = EError 2 "match error"
                    , pi = p
                    }
                Just envm ->
                    { envm = envm
                    , choice = cnt + 1
                    , ei = e
                    , pi = p
                    }
        BCom _ b1 b2 ->
            let
                res = matchBranch v b1 cnt
            in
                case res.ei of
                    EError _ _ ->
                        matchBranch v b2 res.choice
                    _ ->
                        res


matchBranchC : (Value, BValue) -> Branch -> Int -> MatchCaseRes
matchBranchC (v, bv) b cnt =
    case b of
        BSin _ p e ->
            case matchC p (v, bv) of
                Nothing ->
                    { envm = []
                    , choice = cnt + 1
                    , ei = EError 2 "match error"
                    , pi = p
                    }
                Just envm ->
                    { envm = envm
                    , choice = cnt + 1
                    , ei = e
                    , pi = p
                    }
        BCom _ b1 b2 ->
            let
                res = matchBranchC (v, bv) b1 cnt
            in
                case res.ei of
                    EError _ _ ->
                       matchBranchC (v,bv) b2 res.choice
                    _ ->
                        res



updateBranch : Branch -> Int -> Int -> Exp -> (Branch, Int)
updateBranch b cnt choice new_ei =
    case b of
        BSin ws p e ->
            if cnt + 1 == choice then
                (BSin ws p new_ei, cnt + 1)
            else
                (BSin ws p e, cnt + 1)
        
        BCom ws b1 b2 ->
            let
                (new_b1, cnt1) = 
                    updateBranch b1 cnt choice new_ei
                
                (new_b2, cnt2) =
                    updateBranch b2 cnt1 choice new_ei
            in
                (BCom ws new_b1 new_b2, cnt2)


-- TODO: BValue in BEnv shall be update or not ?
updateDelta : BEnv -> String -> Delta -> BEnv
updateDelta env s d =
    case env of
        [] -> []
        (s1, (v1, d1), b1) :: env1 ->
            if s == s1 then
                (s1, (v1, d), b1)  :: env1
            else
                (s1, (v1, d1), b1) :: updateDelta env1 s d


substDelta : Pattern -> BEnv -> Delta
substDelta p env =
    case p of
        PVar _ s ->
            case lookup2 s env of
                Nothing          -> DError "substDelta: not found"
                Just ((_, d), _) -> d
        
        PCons _ p1 p2 ->
            DCons (substDelta p1 env) (substDelta p2 env)
        
        PList _ p1 p2 ->
            DCons (substDelta p1 env) (substDelta p2 env)
        
        PTuple _ p1 p2 ->
            DTuple (substDelta p1 env) (substDelta p2 env)

        _ ->
            DId


freeVars : Exp -> List String
freeVars exp =
    case exp of
        EVar _ s -> [s]

        ELam _ p e ->
            freeVars e |> List.filter (\s -> List.member s (varsInPattern p) |> not)
        
        EApp _ e1 e2  -> freeVars e1 ++ freeVars e2   
        
        ECase _ e bs -> freeVars e ++ varsInBranch bs
        
        EBPrim _ _ e1 e2   -> freeVars e1 ++ freeVars e2
        ECons _ e1 e2      -> freeVars e1 ++ freeVars e2     
        EList _ e1 e2      -> freeVars e1 ++ freeVars e2
        EGList _ e1 e2      -> freeVars e1 ++ freeVars e2
        ETuple _ e1 e2     -> freeVars e1 ++ freeVars e2 
        
        EUPrim _ _ e -> freeVars e
        EParens _  e -> freeVars e
        EFix _     e -> freeVars e

        EGraphic _ _ e -> freeVars e
        EMap _ _ e     -> freeVars e
        EUnwrap _ e    -> freeVars e
        EConst _ e     -> freeVars e

        _ -> []


varsInPattern : Pattern -> List String
varsInPattern pattern =
    case pattern of
        PVar _ s -> [s]
        
        PCons _  p1 p2 -> varsInPattern p1 ++ varsInPattern p2    
        PList _  p1 p2 -> varsInPattern p1 ++ varsInPattern p2
        PTuple _ p1 p2 -> varsInPattern p1 ++ varsInPattern p2
        
        _ ->
            []


varsInBranch : Branch -> List String
varsInBranch branch =
    case branch of
        BSin _ p e ->
            freeVars e 
            |> List.filter (\s -> List.member s (varsInPattern p) |> not)
        
        BCom _ b1 b2 ->
            varsInBranch b1 ++ varsInBranch b2


-- Note the arguments order matters, fv1, fv2, env1, env2.
-- fv1 -> env1
-- fv2 -> env2
two_wayMerge : List String -> List String -> BEnv -> BEnv -> (BEnv, List (String, Delta), List (String, Delta))
two_wayMerge fv1 fv2 env1 env2 =
    case (env1, env2) of
        ((s1, (v1, d1), b1) :: env1_, (s2, (_, d2), b2) :: env2_) ->  -- b1 should be equal with b2
            if s1 == s2 then
                    let
                        (env, denv1, denv2) =
                            two_wayMerge fv1 fv2 env1_ env2_
                    in
                    -- if String.startsWith "*" s1 then
                        -- Special Variables
                        if eqDelta d1 DId |> not then
                            ((s1, (v1, d1), b1)::env, denv1, denv2)
                        else
                            ((s1, (v1, d2), b2)::env, denv1, denv2)
                    -- else
                    --     -- Ordinary Variables
                    --     if (eqDelta d1 d2) || (List.member s1 fv2 |> not) then
                    --             (((s1, (v1, d1), b1)::env), denv1, denv2)
                    --     else if List.member s1 fv1 |> not then
                    --             (((s1, (v1, d2), b2)::env), denv1, denv2)
                    --     else ((s1, (v1, DId), b1)::env, (s1, d1)::denv1, (s2, d2)::denv2)
            else ([("Two-way Merge Error", (VError "", DError ""), BError)], [], [])
        ([], []) -> ([], [], [])
        _        -> ([("Two-way Merge Error", (VError "", DError ""), BError)], [], [])


-- If not in fv1, and fv2, but binding to different value, choose which one ? the updated one ? I think so.
-- update v1 by v2
updateBy : List String -> List String -> BEnv -> BEnv -> (BEnv, List (String, Delta), List (String, Delta))
updateBy fv1 fv2 env1 env2 =
    case (env1, env2) of
        ((s1, (v1, d1), b1) :: env1_, (s2, (_, d2), b2) :: env2_) ->  -- b1 should be equal with b2
            if s1 == s2 then
                    let
                        (env, denv1, denv2) =
                            two_wayMerge fv1 fv2 env1_ env2_
                    in
                    -- if String.startsWith "*" s1 then
                        -- Special Variables
                        if eqDelta d1 DId |> not then
                            ((s1, (v1, d1), b1)::env, denv1, denv2)
                        else
                            ((s1, (v1, d2), b2)::env, denv1, denv2)
                    -- else
                    --     -- Ordinary Variables
                    --     if (eqDelta d1 d2) || (List.member s1 fv2 |> not) then
                    --             (((s1, (v1, d1), b1)::env), denv1, denv2)
                    --     else if List.member s1 fv1 |> not then
                    --             (((s1, (v1, d2), b2)::env), denv1, denv2)
                    --     else ((s1, (v1, DId), b1)::env, (s1, d1)::denv1, (s2, d2)::denv2)
            else ([("Two-way Merge Error", (VError "", DError ""), BError)], [], [])
        ([], []) -> ([], [], [])
        _        -> ([("Two-way Merge Error", (VError "", DError ""), BError)], [], [])


bAnd : BValue -> BValue -> BValue
bAnd b1 b2 = 
  case (b1, b2) of 
      (BTrue, BTrue) -> BTrue
      (BFalse, BTrue) -> BFalse
      (BTrue, BFalse) -> BFalse
      (BFalse, BFalse) -> BFalse
      (_, _) -> BFalse

isConstBValue : BValue -> Bool 
isConstBValue b =
    case b of 
      BTrue -> True
      BFalse -> False
      BTuple b1 b2 -> isConstBValue b1 && isConstBValue b2
      _ -> False

getErrorType : Exp -> Int 
getErrorType e = 
    case e of 
        EError i _ -> i
        EParens _ e_ -> getErrorType e_
        EList _ e1 _ -> getErrorType e1
        _          -> -1

isError : Exp -> Bool 
isError e = member (getErrorType e) [0,1,2,3]

isBranchError : Branch -> Bool 
isBranchError b = 
   case b of 
       BSin _ _ (EError _ _ ) -> True 
       BCom _ b1 b2 -> isBranchError b1 || isBranchError b2
       _ -> False

constlizeBranch : Branch -> Branch
constlizeBranch branch =
    case branch of 
        BSin ws p e -> BSin ws p (EConst [] e)
        BCom ws b1 b2 -> BCom ws (constlizeBranch b1) (constlizeBranch b2)

deconstlizeBranch : Branch -> Maybe Branch 
deconstlizeBranch branch =
    case branch of 
        BSin ws p (EConst [] e) -> Just (BSin ws p e)
        BCom ws b1 b2 -> 
            case deconstlizeBranch b1 of 
                Just b1_ -> case deconstlizeBranch b2 of 
                    Just b2_ -> Just (BCom ws b1_ b2_)
                    _ -> Nothing
                _ -> Nothing
        _ -> Nothing

     