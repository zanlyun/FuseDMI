module Language.BEval exposing (..)

import Utils exposing (lookup, lookup2)
import Language.Utils exposing (..)
import Language.UtilsFD exposing (..)
import Language.FEval exposing (..)
import Language.DEval exposing (..)
import Language.Syntax exposing (..)
import Language.Fusion exposing (..)
import Printer.Exp exposing (..)
import Language.FEvalC exposing (fevalC)

beval : BEnv -> Exp -> Delta -> BST -> (BEnv, Exp, BST)
beval env exp delta st =
    case (exp, delta) of
        (_, DId)     -> (env, exp, st)
        (EConst wsc1 (EConst ws2 e), _) -> 
            let (new_env, new_e2, new_st) = beval env (EConst ws2 e) delta st
            in case new_e2 of 
                EConst _ new_e -> (new_env, EConst wsc1 (EConst ws2 new_e), new_st)
                _              -> (new_env, EError 1 "fuse fail", new_st)
        -- replace exp with p
        (EConst wsc e, DRewr p) ->
            let (v, b) = fevalC env exp in
            if isConstBValue b
            then let pExp = param2EList p
                     (bv, pv) = fevalC [] (EConst [] pExp) in 
                  if v == bv && isConstBValue pv 
                  then let (new_env, new_e, new_st) = beval env e delta st in 
                       (new_env, EConst wsc new_e, new_st)
                  else ([], EError 0 "evaluates to const, not modifiable",[])
            else let (new_env, new_e, new_st) = beval env e delta st in 
            (new_env, EConst wsc new_e, new_st)
        (_, DRewr p) ->
            let lastSP = getLastSpaces exp in
            (env, param2Exp p |> setLastSpaces lastSP, st)
        -- abstract current exp as var s
        (_, DAbst (AVar s)) ->
            case lookup s st of
                Just (env1, _) ->
                    if env1 == env
                    then let lastSP = getLastSpaces exp in
                         (env, EVar [lastSP] s, updateST st s exp)
                    else (env, exp, st)
                Nothing        -> ([], EError 2 "Error 20", [])
        -- P-Constant2
        (EFloat ws f, DAdd (AFloat f1)) -> (env, EFloat ws (f + f1), st)
        (EFloat ws f, DMul (AFloat f1)) -> (env, EFloat ws (f * f1), st)

        (ENil ws,     DInsert 0 p) -> (env, ECons [""] (param2Exp p) (ENil ws)    , st)
        (EEmpList ws, DInsert 0 p) -> (env, EList ws   (param2Exp p) (EEmpList []), st)

        (ENil _,     DGen _ _ _) -> (env, exp, st)
        (EEmpList _, DGen _ _ _) -> (env, exp, st)

        (ENil _,     DMem _ ANil) -> (env, exp, st)
        (EEmpList _, DMem _ ANil) -> (env, exp, st)

        -- P-Constant1
        (EConst _ (EFloat _ _),  _) -> ([], EError 0 "const c, not modifiable.", [])
        (EConst _ (ENil _),     _)  -> ([], EError 0 "const Nil, not modifiable.", [])
        (EConst _ (EEmpList _), _)  -> ([], EError 0 "const [], not modifiable.", [])
        -- TODO: True, False, Char, String

        (EVar _ x, _) ->
            case lookup2 x env of
                Just ((v, od), bv) ->
                    if isConstBValue bv 
                    then (env, fuse delta exp, st) -- P-Var2
                    else case fixCheck v delta of
                          Just d  -> (updateDelta env x (DCom od d), exp, st) -- P-Var4
                          Nothing -> ([], EError 1 "Recursion Conflict", [])
                Nothing -> ([], EError 2 "Error 37", [])

        (EConst _ (EVar _ x), _) ->
            case lookup2 x env of
                Just ((v, od), bv) ->
                    if isConstBValue bv  
                    then ([], EError 0 "x is const, const x, not modifiable.", [])
                    else case fixCheck v delta of
                          Just d  -> (updateDelta env x (DCom od d), exp, st) -- P-Var3
                          Nothing -> ([],  EError 1 "Recursion Conflict", [])
                Nothing ->
                    ([], EError 2 "Error 37", [])
        
        -- P-Lam2
        -- TODO: about env
        (ELam ws _ _, DClosure env1 p1 e1) -> (env1, ELam ws p1 e1, st)
        -- P-Lam1
        (EConst wsc (ELam ws p1 e1), _) -> 
          let (new_env, new_e, new_st) = beval env (ELam ws p1 (EConst [] e1)) delta st
          in case new_e of 
            ELam _ _ (EConst [] new_e1) -> (new_env, EConst wsc (ELam ws p1 new_e1),new_st)
            _ -> ([], EError 1 "fusion failed.",[])

        (EConst wsc (EApp ws e1 e2), _) -> 
            let (new_env, new_app, new_st) = beval env (EApp ws (EConst [] e1) (EConst [] e2)) delta st
            in case new_app of 
                (EApp _ (EConst [] new_e1) (EConst [] new_e2)) -> (new_env, EConst wsc (EApp ws new_e1 new_e2), new_st)
                _ -> ([], EError 1 "fusion failed",[])
        -- P-App
        (EApp ws e1 e2, _) ->
            let (v2, b2) = fevalC env e2
                (v1, _ ) = fevalC env e1
                -- _ = Debug.log "EApp v2" v2
                -- _ = Debug.log "EApp v1" v1
                -- _ = Debug.log "EApp env" env
            in case v1 of
                VClosure envf p ef ->
                    let 
                        -- _ = Debug.log "EApp VClosure p" p
                        -- _ = Debug.log "EApp VClosure ef" ef
                        envm_res = case e2 of
                                       EFix _ e2_ -> 
                                           matchC p (VFix env e2_, BFix env e2_)
                                       _          -> 
                                           (v2, b2) |> matchC p
                        -- _ = Debug.log "EApp envm_res" envm_res
                    in case envm_res of
                        Just envm ->
                            let (_, b) = fevalC (envm ++ envf) ef
                            in if isConstBValue b
                               then ([], EError 0 "evaluates to const, not modifiable.", [])
                               else if isConstBValue b2 
                                    then  -- P-App2
                                       let (env_, ef_, st_) = beval (envm ++ envf) ef delta st
                                           (envm_, envf_) = ( List.take (List.length envm) env_, List.drop (List.length envm) env_)
                                           (env1, new_e1, _) = beval env e1 (DClosure envf_ p ef_) []
                                        in if envm == envm_
                                           then  if isError new_e1
                                                 then (env, fuse delta exp, st) -- back to trivial method
                                                 else (env1, EApp ws new_e1 e2, st_) -- P-App2
                                           else ([], EError 0 "e2 evaluates to const, not modifiable.", [])
                                    else  -- P-App3
                                       -- TODO: check if this is correct for ST
                                       let (env_, ef_, st_) = beval (envm ++ envf) ef delta st
                                          --  _ = Debug.log "envm" envm
                                          --  _ = Debug.log "envf" envf
                                          --  _ = Debug.log "ef" ef
                                          --  _ = Debug.log "env_"  env_
                                          --  _ = Debug.log "ef_" ef_
                                       in if isError ef_
                                       then (env, fuse delta exp, st)
                                       else 
                                       let (envm_, envf_) = (List.take (List.length envm) env_, List.drop (List.length envm) env_)
                                           (env1, new_e1, _) = beval env e1 (DClosure envf_ p ef_) []
                                           (env2, new_e2, _) = beval env e2 (substDelta p envm_) []
                                           (fv1, fv2) = (freeVars e1, freeVars e2)
                                          --  _ = Debug.log "EApp 3, delta" delta
                                          --  _ = Debug.log "EApp 3, envm_" envm_
                                          --  _ = Debug.log "EApp 3, env2" env2
                                          --  _ = Debug.log "EApp 3, e1"   e1
                                          --  _ = Debug.log "EApp 3, e2"   e2
                                          --  _ = Debug.log "EApp 3, new_e1" new_e1
                                          --  _ = Debug.log "EApp 3, p" p
                                          --  _ = Debug.log "EApp 3, new_e2" new_e2
                                          --  _ = Debug.log "EApp 3, substDelta" (substDelta p envm_)
                                          --  _ = Debug.log "EApp 3, fv1" fv1
                                          --  _ = Debug.log "EApp 3, fv2" fv2
                                          --  _ = Debug.log "EApp 3, merge" (two_wayMerge fv1 fv2 env1 env2)
                                          --  _ = Debug.log "EApp 3, env1" env1
                                          --  _ = Debug.log "EApp 3, env2" env2
                                       in
                                       if isError new_e1 || isError new_e2
                                       then case ws of
                                          "EQ" :: _ ->  ([], EError 0 "fusion fail",[])
                                          _         -> (env, fuse delta exp, st) -- back to trivial method
                                       else case ws of
                                          "EQ" :: _ ->  
                                              case two_wayMerge fv1 fv2 env1 env2 of
                                                  (new_env, [], [])       -> (new_env, EApp ws new_e1 new_e2, st_)
                                                  (new_env, denv1, denv2) ->
                                                      let fusedE1 = fuseEnv denv1 new_e1
                                                          fusedE2 = fuseEnv denv2 new_e2
                                                     in
                                                      if  isError fusedE1 || isError fusedE2
                                                      then (env, EError 0 "fuse failed.", st) -- back to trivial method
                                                      else (new_env, EApp ws fusedE1 fusedE2, st_)
                                          _         ->
                                              case two_wayMerge fv1 fv2 env1 env2 of
                                                  (new_env, [], [])       -> (new_env, EApp ws new_e1 new_e2, st_)
                                                  (new_env, denv1, denv2) ->
                                                      let fusedE1 = fuseEnv denv1 new_e1
                                                          fusedE2 = fuseEnv denv2 new_e2
                                                     in
                                                      if  isError fusedE1 || isError fusedE2
                                                      then (env, fuse delta exp, st) -- back to trivial method
                                                      else (new_env, EApp ws fusedE1 fusedE2, st_) -- P-App3
                        Nothing -> ([], EError 2 "Error 30", [])
                _ -> ([], EError 2 "Error 31", [])

        -- P-Fix  TODO:
        (EFix ws1 _, DFix env1 e1) -> (env1, EFix ws1 e1, st)
        (EFix ws1 e, DClosure env1 p1 e1) -> 
            let (new_env, new_e, new_st) = beval env e (DClosure env1 p1 e1) st
            in (new_env, EFix ws1 new_e, new_st)

        -- P-C-Case 
        (EConst wsc (ECase ws e0 bs), _) ->
            let (new_env, new_const_case, new_st) = beval env (ECase ws (EConst [] e0) (constlizeBranch bs)) delta st
            in case new_const_case of 
                 (ECase _ (EConst _ new_e0) new_bs) -> case deconstlizeBranch new_bs of 
                     Just bs_ -> (new_env, EConst wsc (ECase ws new_e0 bs_), new_st)
                     _        -> ([], EError 1 "fusion failed156", [])
                 _ -> ([], EError 1 "fusion failed157", [])
        -- P-Case
        (ECase ws e0 bs, _) ->
            let (v0, b0)  = fevalC env e0        
                res = matchBranchC (v0, b0) bs 0
            in case res.ei of
                EError i info -> ([], EError i info, [])
                _           ->
                    -- TODO: check if this is correct for ST
                    case beval (res.envm ++ env) res.ei delta st of
                        (env_, ei_, st_) ->
                            let (envm_, envi)     = (List.take (List.length res.envm) env_, List.drop (List.length res.envm) env_)
                                -- _ = Debug.log "ECase env_" env_
                                -- _ = Debug.log "ECase ei_" ei_
                                -- _ = Debug.log "ECase envm_" envm_
                                -- _ = Debug.log "ECase envi" envi
                            in if isConstBValue b0 
                               then -- P-Case2
                                    if res.envm == envm_ then  
                                        if isError ei_
                                        then (env, fuse delta exp, st) -- back to trivial method
                                        else (envi, updateBranch bs 0 res.choice ei_ |> Tuple.first |> ECase ws e0, st_) -- P-Case2
                                    else ([], EError 0 "e2 evaluates to const, not modifiable.", [])
                               else 
                                    let (env0, new_e0, _) = beval env e0 (substDelta res.pi envm_) [] -- from pattern to construct delta e0
                                        (fv0, fvi)        = (freeVars e0, freeVars res.ei)
                                        -- _ = Debug.log "ECase substDelta" (substDelta res.pi envm_)
                                        -- _ = Debug.log "ECase env0" env0
                                        -- _ = Debug.log "ECase new_e0" new_e0
                                        -- _ = Debug.log "ECase fv0" fv0
                                        -- _ = Debug.log "ECase fvi" fvi
                                        -- _ = Debug.log "ECase envi" envi
                                        -- _ = Debug.log "ECase twoWaymerge" (two_wayMerge fv0 fvi env0 envi)
                                    in
                                    if isError new_e0 || isError ei_
                                    then (env, fuse delta exp, st)
                                    else
                                        case two_wayMerge fv0 fvi env0 envi of
                                            (new_env, [], [])       -> 
                                                (new_env, updateBranch bs 0 res.choice ei_ |> Tuple.first |> ECase ws new_e0, st_)
                                            (new_env, denv0, denvi) ->
                                                let fusedE0 = fuseEnv denv0 new_e0
                                                    fusedEi = fuseEnv denvi ei_
                                                in
                                                if  isError fusedE0 || isError fusedEi
                                                then
                                                    (env, fuse delta exp, st)
                                                else
                                                    (new_env, updateBranch bs 0 res.choice fusedEi |> Tuple.first |> ECase ws fusedE0, st_) -- P-Case3

        -- P-C-List2
        (EConst wsc (ECons ws e1 e2), DCons _ _) ->
            let
                (_, b1) = fevalC env (EConst [] e1)
                (_, b2) = fevalC env (EConst [] e2)
            in case (b1, b2) of 
                  (BTrue, BTrue) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, e_new, st_new) = beval env (ECons ws (EConst [] e1) (EConst [] e2)) delta st             
                      in  case e_new of 
                          ECons _ (EConst [] e1_new) (EConst [] e2_new) -> (new_env, EConst wsc (ECons ws e1_new e2_new), st_new)
                          _                                             -> ([], EError 1 "Fusion failed.", [])
        -- P-List
        (ECons ws e1 e2, DCons d1 d2) ->
            let
                (env1, new_e1, st1) = beval env e1 d1 st             
                (env2, new_e2, st2) = beval env e2 d2 st
                new_ST = mergeST st1 st2
                -- _ = Debug.log "ECons e1" e1
                -- _ = Debug.log "ECons d1" d1
                -- _ = Debug.log "ECons new_e1" new_e1
                -- _ = Debug.log "ECons env1" env1
            in
            if isError new_e1 || isError new_e2
            then (env, fuse delta exp, st)
            else
            case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                (new_env, [], [])       -> (new_env, ECons ws new_e1 new_e2, new_ST)
                (new_env, denv1, denv2) ->
                    let
                        fusedE1 = fuseEnv denv1 new_e1
                        fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE1 || isError fusedE2
                    then
                        (env, fuse delta exp, st)
                    else
                        (new_env, ECons ws fusedE1 fusedE2, new_ST)

        (ECons ws e1 e2, DInsert n p) ->
            if n == 0 
            then (env, ECons ws (param2Exp p) exp, st)
            else let (env2, new_e2, st_) = beval env e2 (DInsert (n - 1) p) st
                in
                if isError new_e2
                then (env, fuse delta exp, st) -- back to trivial method
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                (new_env, [], [])   -> (new_env, ECons ws e1 new_e2, st_)
                (new_env, _, denv2) ->
                    let fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE2
                    then (env, fuse delta exp, st)
                    else (new_env, ECons ws e1 fusedE2, st_)

        (ECons ws e1 e2, DDelete n) ->
            if n == 0 then (env, e2, st)
            else
                let (env2, new_e2, st_) = beval env e2 (DDelete (n - 1)) st
                in
                if isError new_e2
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                (new_env, [], [])   -> (new_env, ECons ws e1 new_e2, st_)
                (new_env, _, denv2) ->
                    let fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE2
                    then (env, fuse delta exp, st)
                    else (new_env, ECons ws e1 fusedE2, st_)
        
        -- Put it close to the copied one.
        (ECons ws e1 e2, DCopy n) ->
            if n == 0 
            then (env, ECons ws e1 (ECons ws e1 e2), st)
            else
                let (env2, new_e2, st_) = beval env e2 (DCopy (n - 1)) st
                in
                if isError new_e2
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, ECons ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then (env, fuse delta exp, st)
                        else (new_env, ECons ws e1 fusedE2, st_)
        
        (ECons ws e1 e2, DModify n d) ->
            if n == 0 
            then
                let (env1, new_e1, st_) = beval env e1 d st
                in
                if isError new_e1
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env1 env of
                    (new_env, [], [])   -> (new_env, ECons ws new_e1 e2, st_)
                    (new_env, denv1, _) ->
                        let fusedE1 = fuseEnv denv1 new_e1
                        in if isError fusedE1
                        then (env, fuse delta exp, st)
                        else (new_env, ECons ws fusedE1 e2, st_)
            else
                let (env2, new_e2, st_) = beval env e2 (DModify (n - 1) d) st
                in
                if isError new_e2
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, ECons ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then (env, fuse delta exp, st)
                        else (new_env, ECons ws e1 fusedE2, st_)
        
        (ECons ws e1 e2, DGen next df p) -> -- EAPP, next is e1, p is e2, should get a tuple. I guess dfoldl
            case feval env (EApp [] next (p |> param2Exp)) of
                VTuple v1 v2 ->
                    let
                        d1 = v1 |> value2Param |> DApp df |> deval [] 
                        d2 = v2 |> value2Param |> DGen next df  -- recursively
                        (env1, new_e1, st1) = beval env e1 d1 st
                        (env2, new_e2, st2) = beval env e2 d2 st
                        new_ST = mergeST st1 st2
                    in
                    if isError new_e1 || isError new_e2
                    then(env, fuse delta exp, st)
                    else
                    case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                        (new_env, [], [])       -> (new_env, ECons ws e1 new_e2, new_ST)
                        (new_env, denv1, denv2) ->
                            let
                                fusedE1 = fuseEnv denv1 new_e1
                                fusedE2 = fuseEnv denv2 new_e2
                            in
                            if isError fusedE1 || isError fusedE2
                            then (env, fuse delta exp, st)
                            else (new_env, ECons ws fusedE1 fusedE2, new_ST)
                _ -> ([], EError 2 "Error 32", [])

        (ECons ws e1 e2, DMem s (ACons a1 a2)) ->
            let (env_, e2_, st_) = beval env e2 (DMem s a2) st  -- using a2 to update e2, Mem means cache in state.
            in
            case a1 of
                ATrue -> case lookup s st_ of
                            Just (_, ls) -> (env_, e2_, updateST st_ s (EList [""] e1 ls)) -- only return e2
                            _            -> ([], EError 2 "Error 01", [])
                AFalse -> (env_, ECons ws e1 e2_, st_) -- return total
                _      -> ([], EError 2 "Error 02", [])

        -- Start EGCons
        (EConst wsc (EGCons ws e1 e2), DCons _ _) ->
            let
                (_, b1) = fevalC env (EConst [] e1)
                (_, b2) = fevalC env (EConst [] e2)
            in case (b1, b2) of 
                  (BTrue, BTrue) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, e_new, st_new) = beval env (EGCons ws (EConst [] e1) (EConst [] e2)) delta st             
                      in  case e_new of 
                          EGCons _ (EConst [] e1_new) (EConst [] e2_new) -> (new_env, EConst wsc (EGCons ws e1_new e2_new), st_new)
                          _                                             -> ([], EError 1 "Fusion failed.", [])
        -- P-List
        (EGCons ws e1 e2, DCons d1 d2) ->
            let
                (env1, new_e1, st1) = beval env e1 d1 st             
                (env2, new_e2, st2) = beval env e2 d2 st
                new_ST = mergeST st1 st2
            in
            if isError new_e1 || isError new_e2
            then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
            else
            case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                (new_env, [], [])       -> (new_env, EGCons ws new_e1 new_e2, new_ST)
                (new_env, denv1, denv2) ->
                    let
                        fusedE1 = fuseEnv denv1 new_e1
                        fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE1 || isError fusedE2
                    then
                        ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                    else
                        (new_env, EGCons ws fusedE1 fusedE2, new_ST)

        (EGCons ws e1 e2, DInsert n p) ->
            if n == 0 
            then (env, EGCons ws (param2Exp p) exp, st)
            else let (env2, new_e2, st_) = beval env e2 (DInsert (n - 1) p) st
                in
                if isError new_e2
                then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                (new_env, [], [])   -> (new_env, EGCons ws e1 new_e2, st_)
                (new_env, _, denv2) ->
                    let fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE2
                    then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                    else (new_env, EGCons ws e1 fusedE2, st_)

        (EGCons ws e1 e2, DDelete n) ->
            if n == 0 then (env, e2, st)
            else
                let (env2, new_e2, st_) = beval env e2 (DDelete (n - 1)) st
                in
                if isError new_e2
                then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                (new_env, [], [])   -> (new_env, EGCons ws e1 new_e2, st_)
                (new_env, _, denv2) ->
                    let fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE2
                    then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                    else (new_env, EGCons ws e1 fusedE2, st_)
        
        -- Put it close to the copied one.
        (EGCons ws e1 e2, DCopy n) ->
            if n == 0 
            then (env, EGCons ws e1 (EGCons ws e1 e2), st)
            else
                let (env2, new_e2, st_) = beval env e2 (DCopy (n - 1)) st
                in
                if isError new_e2
                then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGCons ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                        else (new_env, EGCons ws e1 fusedE2, st_)
        
        (EGCons ws e1 e2, DModify n d) ->
            if n == 0 
            then
                let (env1, new_e1, st_) = beval env e1 d st
                in
                if isError new_e1
                then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env1 env of
                    (new_env, [], [])   -> (new_env, EGCons ws new_e1 e2, st_)
                    (new_env, denv1, _) ->
                        let fusedE1 = fuseEnv denv1 new_e1
                        in if isError fusedE1
                        then (env, fuse delta exp, st)
                        else (new_env, EGCons ws fusedE1 e2, st_)
            else
                let (env2, new_e2, st_) = beval env e2 (DModify (n - 1) d) st
                in
                if isError new_e2
                then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGCons ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                        else (new_env, EGCons ws e1 fusedE2, st_)
        
        (EGCons ws e1 e2, DGen next df p) -> -- EAPP, next is e1, p is e2, should get a tuple. I guess dfoldl
            case feval env (EApp [] next (p |> param2Exp)) of
                VTuple v1 v2 ->
                    let
                        d1 = v1 |> value2Param |> DApp df |> deval [] 
                        d2 = v2 |> value2Param |> DGen next df  -- recursively
                        (env1, new_e1, st1) = beval env e1 d1 st
                        (env2, new_e2, st2) = beval env e2 d2 st
                        new_ST = mergeST st1 st2
                    in
                    if isError new_e1 || isError new_e2
                    then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                    else
                    case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                        (new_env, [], [])       -> (new_env, EGCons ws e1 new_e2, new_ST)
                        (new_env, denv1, denv2) ->
                            let
                                fusedE1 = fuseEnv denv1 new_e1
                                fusedE2 = fuseEnv denv2 new_e2
                            in
                            if isError fusedE1 || isError fusedE2
                            then ([], EError 1 "fuse failed, EGCons not modifiable.", [])
                            else (new_env, EGCons ws fusedE1 fusedE2, new_ST)
                _ -> ([], EError 2 "Error 32", [])

        (EGCons ws e1 e2, DMem s (ACons a1 a2)) ->
            let (env_, e2_, st_) = beval env e2 (DMem s a2) st  -- using a2 to update e2, Mem means cache in state.
            in
            case a1 of
                ATrue -> case lookup s st_ of
                            Just (_, ls) -> (env_, e2_, updateST st_ s (EList [""] e1 ls)) -- only return e2
                            _            -> ([], EError 2 "Error 01", [])
                AFalse -> (env_, EGCons ws e1 e2_, st_) -- return total
                _      -> ([], EError 2 "Error 02", [])
        -- End EGCons

        -- P-C-List2
        (EConst wsc (EList ws e1 e2), DCons _ _) ->
            let (_, b1) = fevalC env (EConst [] e1)
                (_, b2) = fevalC env (EConst [] e2)
            in case (b1, b2) of 
                  (BTrue, BTrue) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, e_new, st_new) = beval env (EList ws (EConst [] e1) (EConst [] e2)) delta st             
                      in  case e_new of 
                          EList _ (EConst [] e1_new) (EConst [] e2_new) -> (new_env, EConst wsc (EList ws e1_new e2_new), st_new)
                          _                                             -> ([], EError 1 "Fusion failed.", [])
        (EList ws e1 e2, DCons d1 d2) ->
            let (env1, new_e1, st1) = beval env e1 d1 st
                (env2, new_e2, st2) = beval env e2 d2 st
                new_ST = mergeST st1 st2
            in
            if isError new_e1 || isError new_e2
            then (env, fuse delta exp, st)
            else
            case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                (new_env, [], [])       -> (new_env, EList ws new_e1 new_e2, new_ST)
                (new_env, denv1, denv2) ->
                    let fusedE1 = fuseEnv denv1 new_e1
                        fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError new_e1 || isError new_e2
                    then (env, fuse delta exp, st)
                    else (new_env, EList ws fusedE1 fusedE2, new_ST)

        (EList ws e1 e2, DInsert n p) ->
            if n == 0 
            then
                (env, EList ws (param2Exp p) exp, st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DInsert (n - 1) p) st
                in
                if isError new_e2
                then
                    (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2 
                        then
                            (env, fuse delta exp, st)
                        else
                            (new_env, EList ws e1 fusedE2, st_)

        (EList ws e1 e2, DDelete n) ->
            if n == 0 
            then
                case ws of
                    _::[] -> (env, e2, st)
                    _     ->
                        case e2 of
                            EList _ e21 e22 -> (env, EList ws e21 e22 , st)
                            EEmpList _      -> (env, EEmpList ["", ""], st)
                            _               -> (env, EError 2 "Error 03", st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DDelete (n - 1)) st
                in
                if isError new_e2 
                then
                    (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then
                            (env, fuse delta exp, st)
                        else
                            (new_env, EList ws e1 fusedE2, st_)

        (EList ws e1 e2, DCopy n) ->
            if n == 0 
            then
                case ws of
                    _::[] -> (env, EList ws e1 (EList ws e1 e2)   , st)
                    _     -> (env, EList ws e1 (EList [" "] e1 e2), st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DCopy (n - 1)) st
                in
                if isError new_e2
                then
                    (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then
                            (env, fuse delta exp, st)
                        else
                            (new_env, EList ws e1 fusedE2, st_)

        (EList ws e1 e2, DModify n d) ->
            if n == 0 
            then
                let
                    (env1, new_e1, st_) = beval env e1 d st
                in
                if isError new_e1 
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env1 env of
                    (new_env, [], [])   -> (new_env, EList ws new_e1 e2, st_)
                    (new_env, denv1, _) ->
                        let fusedE1 = fuseEnv denv1 new_e1
                        in if isError fusedE1 
                        then (env, fuse delta exp, st)
                        else (new_env, EList ws fusedE1 e2, st_)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DModify (n - 1) d) st
                in
                if isError new_e2 
                then (env, fuse delta exp, st)
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let fusedE2 = fuseEnv denv2 new_e2
                        in if isError fusedE2
                        then (env, fuse delta exp, st)
                        else (new_env, EList ws e1 fusedE2, st_)
        
        (EList ws e1 e2, DGen next df p) ->
            case feval env (EApp [] next (p |> param2Exp)) of
                VTuple v1 v2 ->
                    let
                        d1 =  v1 |> value2Param |> DApp df |> deval []
                        d2 =  v2 |> value2Param |> DGen next df
                        
                        (env1, new_e1, st1) = beval env e1 d1 st               
                        (env2, new_e2, st2) = beval env e2 d2 st

                        new_ST = mergeST st1 st2
                    in
                    if isError new_e1 || isError new_e2
                    then (env, fuse delta exp, st)
                    else
                    case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                        (new_env, [], [])       -> (new_env, EList ws new_e1 new_e2, new_ST)
                        (new_env, denv1, denv2) ->
                            let
                                fusedE1 = fuseEnv denv1 new_e1
                                fusedE2 = fuseEnv denv2 new_e2
                            in
                            if isError fusedE1 || isError fusedE2
                            then (env, fuse delta exp, st)
                            else (new_env, EList ws fusedE1 fusedE2, new_ST)

                _ -> ([], EError 2 "Error 33", [])

        (EList ws e1 e2, DMem s (ACons a1 a2)) ->
            let
                (env_, e2_, st_) =
                    beval env e2 (DMem s a2) st
            in
            case a1 of
                ATrue -> case lookup s st_ of
                            Just (_, ls) -> (env_, e2_, updateST st_ s (EList [""] e1 ls))
                            _            -> ([], EError 2 "Error 04", [])

                AFalse -> (env_, EList ws e1 e2_, st_)
                _      -> ([], EError 2 "Error 34", [])
        

        -- Start GList
        -- P-C-GList2
        (EConst wsc (EGList ws e1 e2), DCons _ _) ->
            let (_, b1) = fevalC env (EConst [] e1)
                (_, b2) = fevalC env (EConst [] e2)
            in case (b1, b2) of 
                  (BTrue, BTrue) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, e_new, st_new) = beval env (EGList ws (EConst [] e1) (EConst [] e2)) delta st             
                      in  case e_new of 
                          EGList _ (EConst [] e1_new) (EConst [] e2_new) -> (new_env, EConst wsc (EGList ws e1_new e2_new), st_new)
                          _                                             -> ([], EError 1 "Fusion failed.", [])

        (EGList ws e1 e2, DCons d1 d2) ->
            let (env1, new_e1, st1) = beval env e1 d1 st
                (env2, new_e2, st2) = beval env e2 d2 st
                new_ST = mergeST st1 st2
                -- _ = Debug.log "EGList e1" e1
                -- _ = Debug.log "EGList e2" e2
                -- _ = Debug.log "EGList new_e1" new_e1
                -- _ = Debug.log "EGList env1" env1
                -- _ = Debug.log "EGList env2" env2
            in
            if isError new_e1 || isError new_e2 
            then ([], EError 1 "fuse failed",[])
            else
            -- let _ = Debug.log "EGList merge result:" (two_wayMerge (freeVars e1) (freeVars e2) env1 env2)
            --     _ = Debug.log "EGList fv1" (freeVars e1)
            --     _ = Debug.log "EGList fv2" (freeVars e2)
            --     _ = Debug.log "EGList env1" env1
            --     _ = Debug.log "EGList env2" env2
            -- in
            case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                (new_env, [], [])       -> (new_env, EGList ws new_e1 new_e2, new_ST)
                (new_env, denv1, denv2) ->
                    let fusedE1 = fuseEnv denv1 new_e1
                        fusedE2 = fuseEnv denv2 new_e2
                        -- _ = Debug.log "EGList fusedE1" fusedE1
                        -- _ = Debug.log "EGList fusedE2" fusedE2
                        -- _ = Debug.log "EGList env1" env1
                        -- _ = Debug.log "EGList env2" env2
                        -- _ = Debug.log "EGList new_env" new_env
                        -- _ = Debug.log "EGList denv1" denv1
                        -- _ = Debug.log "EGList denv2" denv2
                    in
                    if isError fusedE1 || isError fusedE2
                    then ([], EError 1 "fuse failed",[])
                    else (new_env, EGList ws fusedE1 fusedE2, new_ST)

        (EGList ws e1 e2, DInsert n p) ->
            if n == 0 
            then
                (env, EGList ws (param2Exp p) exp, st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DInsert (n - 1) p) st
                in
                if isError new_e2
                then ([], EError 1 "fuse failed",[])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then
                            ([], EError 1 "fuse failed",[])
                        else
                            (new_env, EGList ws e1 fusedE2, st_)

        (EGList ws e1 e2, DDelete n) ->
            if n == 0 
            then
                case ws of
                    _::[] -> (env, e2, st)
                    _     ->
                        case e2 of
                            EList _ e21 e22 -> (env, EList ws e21 e22 , st)
                            EGList _ e21 e22 -> (env, EGList ws e21 e22 , st)
                            EEmpList _      -> (env, EEmpList ["", ""], st)
                            _               -> (env, EError 2 "Error 03", st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DDelete (n - 1)) st
                in
                if isError new_e2
                then
                    ([], EError 1 "fuse failed",[])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then
                            ([], EError 1 "fuse failed",[])
                        else
                            (new_env, EGList ws e1 fusedE2, st_)

        (EGList ws e1 e2, DCopy n) ->
            if n == 0 
            then
                case ws of
                    _::[] -> (env, EGList ws e1 (EGList ws e1 e2)   , st)
                    _     -> (env, EGList ws e1 (EGList [" "] e1 e2), st)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DCopy (n - 1)) st
                in
                if isError new_e2
                then
                    ([], EError 1 "fuse failed",[])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                        in
                        if isError fusedE2
                        then
                            (env, fuse delta exp, st)
                        else
                            (new_env, EGList ws e1 fusedE2, st_)

        (EGList ws e1 e2, DModify n d) ->
            if n == 0 
            then
                let
                    (env1, new_e1, st_) = beval env e1 d st
                    -- _ = Debug.log "EGList new_e1"  (print new_e1)
                in
                if isError new_e1 
                then ([], new_e1 ,[])
                else
                -- let
                --     _ = Debug.log "886 freeVars e1" (freeVars e1)
                --     _ = Debug.log "886 freeVars e2" (freeVars e2)
                --     _ = Debug.log "886" (updateBy (freeVars e1) (freeVars e2) env1 env)
                -- in
                
                case updateBy (freeVars e1) (freeVars e2) env1 env of
                    (new_env, [], [])   -> (new_env, EGList ws new_e1 e2, st_)
                    (new_env, denv1, _) ->
                        let
                            fusedE1 = fuseEnv denv1 new_e1
                        in
                        if isError fusedE1 
                        then
                            (env, fuse delta exp, st)
                        else
                            (new_env, EGList ws fusedE1 e2, st_)
            else
                let
                    (env2, new_e2, st_) = beval env e2 (DModify (n - 1) d) st
                    -- _ = Debug.log "904 EGList new_e2" new_e2
                    -- _ = Debug.log "904 EGList env2" env2
                    -- _ = Debug.log "904 EGList env" env
                    -- _ = Debug.log "904 fv1" (freeVars e1)
                    -- _ = Debug.log "904 fv2" (freeVars e2)
                    -- _ = Debug.log "904 two_wayMerge" (two_wayMerge (freeVars e1) (freeVars e2) env env2)
                in
                if isError new_e2 
                then ([], new_e2 ,[])
                else
                case two_wayMerge (freeVars e1) (freeVars e2) env env2 of
                    (new_env, [], [])   -> (new_env, EGList ws e1 new_e2, st_)
                    (new_env, _, denv2) ->
                        let
                            fusedE2 = fuseEnv denv2 new_e2
                            _ = Debug.log "919 fusedE2" fusedE2
                            _ = Debug.log "919 denv2" denv2
                        in
                        if isError fusedE2 then
                            ([], fusedE2 ,[])
                        else
                            (new_env, EGList ws e1 fusedE2, st_)
        
        (EGList ws e1 e2, DGen next df p) ->
            case feval env (EApp [] next (p |> param2Exp)) of
                VTuple v1 v2 ->
                    let
                        d1 =  v1 |> value2Param |> DApp df |> deval []
                        d2 =  v2 |> value2Param |> DGen next df
                        
                        (env1, new_e1, st1) = beval env e1 d1 st               
                        (env2, new_e2, st2) = beval env e2 d2 st

                        new_ST = mergeST st1 st2
                    in
                    if isError new_e1
                    || isError new_e2
                    then
                        ([], EError 1 "fuse failed",[])
                    else
                    case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                        (new_env, [], [])       -> (new_env, EGList ws new_e1 new_e2, new_ST)
                        (new_env, denv1, denv2) ->
                            let
                                fusedE1 = fuseEnv denv1 new_e1
                                fusedE2 = fuseEnv denv2 new_e2
                            in
                            if isError fusedE1 || isError fusedE2
                            then
                                ([], EError 1 "fuse failed",[])
                            else
                                (new_env, EGList ws fusedE1 fusedE2, new_ST)

                _ -> ([], EError 2 "Error 33", [])

        (EGList ws e1 e2, DMem s (ACons a1 a2)) ->
            let
                (env_, e2_, st_) =
                    beval env e2 (DMem s a2) st
            in
            case a1 of
                ATrue -> case lookup s st_ of
                            Just (_, ls) -> (env_, e2_, updateST st_ s (EGList [""] e1 ls))
                            _            -> ([], EError 2 "Error 04", [])

                AFalse -> (env_, EGList ws e1 e2_, st_)
                _      -> ([], EError 2 "Error 34", [])

        -- End GList

        -- P-C-Tuple2
        (EConst wsc (ETuple ws e1 e2), DTuple _ _) ->
            let (_, b1) = fevalC env (EConst [] e1)
                (_, b2) = fevalC env (EConst [] e2)
            in case (b1, b2) of 
                  (BTrue, BTrue) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, e_new, st_new) = beval env (ETuple ws (EConst [] e1) (EConst [] e2)) delta st             
                      in case e_new of 
                          ETuple _ (EConst [] e1_new) (EConst [] e2_new) -> (new_env, EConst wsc (ETuple ws e1_new e2_new), st_new)
                          _ -> ([], EError 2 "Failed", [])
        -- P-Tuple
        (ETuple ws e1 e2, DTuple d1 d2) ->
            let (env1, new_e1, st1) = beval env e1 d1 st
                (env2, new_e2, st2) = beval env e2 d2 st
                new_ST = mergeST st1 st2
            in
            if isError new_e1 || isError new_e2 
            then (env, fuse delta exp, st)
            else
            case two_wayMerge (freeVars e1) (freeVars e2) env1 env2 of
                (new_env, [], [])       -> (new_env, ETuple ws new_e1 new_e2, new_ST)
                (new_env, denv1, denv2) ->
                    let fusedE1 = fuseEnv denv1 new_e1
                        fusedE2 = fuseEnv denv2 new_e2
                    in
                    if isError fusedE1 || isError fusedE2 
                    then (env, fuse delta exp, st)
                    else (new_env, ETuple ws fusedE1 fusedE2, new_ST)

        -- P-C-Paren
        (EConst wsc (EParens ws e1), _) ->
            let (env1, new_e1, st_) = beval env (EConst [] e1) delta st
            in
            if isError new_e1
            then (env, EError 1 "Fusion Failed", st_)
            else case new_e1 of 
              EConst _ e1_ -> (env1, (EConst wsc (EParens ws e1_)), st_)
              _            -> (env, EError 1 "Fusion Failed", st_)

        -- P-Paren
        (EParens ws e1, _) ->
            let
                (env1, new_e1, st_) = beval env e1 delta st
            in
            if isError new_e1
            then (env,  EError 1 "Fusion Failed", st_)
            else (env1, EParens ws new_e1, st_)

        -- P-C-Oplus-Add
        (EConst wsc (EBPrim ws Add e1 e2), _) ->
             case (fevalC env (EConst [] e1), fevalC env (EConst [] e2)) of 
                  ((VFloat _, BTrue), (VFloat _, BTrue)) -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                  _              -> 
                      let (new_env, new_e, new_st) = beval env (EBPrim ws Add (EConst [] e1) (EConst [] e2)) delta st
                      in case new_e of 
                          (EBPrim _ Add (EConst [] new_e1) (EConst [] new_e2)) -> 
                              (new_env, (EConst wsc (EBPrim ws Add new_e1 new_e2)),new_st)
                          _                                                     -> 
                              (new_env,  EError 1 "Fusion Failed", new_st)
        -- P-Oplus-DAdd
        (EBPrim ws Add e1 e2, DAdd _) ->
            let (_, b1) = fevalC env e1
                (_, b2) = fevalC env e2
                -- _ = Debug.log "EBPrim env" env
                -- _ = Debug.log "EBPrim e1" e1
                -- _ = Debug.log "EBPrim e2" e2
                -- _ = Debug.log "EBPrim b1" b1
                -- _ = Debug.log "EBPrim b2" b2
            in case (b1, b2) of 
                (BTrue, BTrue)  -> (env, fuse delta exp, st) -- P-Oplus1
                (BTrue, BFalse) ->  -- P-Oplus2
                   let (env2, new_e2, _) = beval env e2 delta []
                       (fv1, fv2) = (freeVars e1, freeVars e2)
                      --  _ = Debug.log "1031 EBPrim env1" env2
                      --  _ = Debug.log "1031 EBPrim new_e2" new_e2
                      --  _ = Debug.log "1031 EBPrim fv1" fv1
                      --  _ = Debug.log "1031 EBPrim fv2" fv2
                      --  _ = Debug.log "1031 EBPrim two_wayMerge" (two_wayMerge fv1 fv2 env env2)
                   in case two_wayMerge fv1 fv2 env env2 of
                      (new_env, [], [])   -> (new_env, EBPrim ws Add e1 new_e2, st)
                      (new_env, denv2, _) ->
                          let fusedE2 = fuseEnv denv2 new_e2
                          in if isError fusedE2
                          then (env, fuse delta exp, st)
                          else (new_env, EBPrim ws Add e1 fusedE2, st)
                _               -> -- P-Oplus3
                   let (env1, new_e1, _) = beval env e1 delta []
                       (fv1, fv2) = (freeVars e1, freeVars e2)
                      --  _ = Debug.log "EBPrim env1" env1
                      --  _ = Debug.log "EBPrim new_e1" new_e1
                      --  _ = Debug.log "EBPrim two_wayMerge"  (two_wayMerge fv1 fv2 env1 env)
                   in case two_wayMerge fv1 fv2 env1 env of
                      (new_env, [], [])   -> (new_env, EBPrim ws Add new_e1 e2, st)
                      (new_env, denv1, _) ->
                          let fusedE1 = fuseEnv denv1 new_e1
                          in if isError fusedE1
                          then (env, fuse delta exp, st)
                          else (new_env, EBPrim ws Add fusedE1 e2, st)
        -- P-Oplus-DMul
        (EBPrim ws Add e1 e2, DMul (AFloat f)) ->
            case (fevalC env e1, fevalC env e2) of
                ((VFloat f1, b1), (VFloat f2, b2)) ->
                    case (b1, b2) of 
                        (BTrue, BTrue)  -> (env, fuse delta exp, st)
                        (BTrue, BFalse) ->  -- P-Oplus-2
                            let delta2 = ((f1 + f2) * f - f1) / f2 |> AFloat |> DMul
                                (env2, new_e2, _) = beval env e2 delta2 []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env env2 of
                                (new_env, [], [])    -> (new_env, EBPrim ws Add e1 new_e2, st)
                                (new_env, denv2, _)  ->
                                    let fusedE2 = fuseEnv denv2 new_e2
                                    in
                                    if isError fusedE2 
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Add e1 fusedE2, st)
                        _ -> -- P-Oplus3
                            let delta1 = ((f1 + f2) * f - f2) / f1 |> AFloat |> DMul
                                (env1, new_e1, _) = beval env e1 delta1 []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env1 env of
                                (new_env, [], [])    -> (new_env, EBPrim ws Add new_e1 e2, st)
                                (new_env, denv1, _)  ->
                                    let fusedE1 = fuseEnv denv1 new_e1
                                    in
                                    if isError fusedE1 
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Add fusedE1 e2, st)
                _ -> ([], EError 2 "Error 36", st)

        -- P-C-Oplus-Sub-Delta
        (EConst wsc (EBPrim ws Sub e1 e2), _) ->
            case (fevalC env (EConst [] e1), fevalC env (EConst [] e2)) of
                ((VFloat _, b1), (VFloat _, b2)) ->
                    case (b1, b2) of 
                        (BTrue, BTrue)  -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                        _               ->
                          let (new_env, new_e, new_st) = beval env (EBPrim ws Sub (EConst [] e1) (EConst [] e2)) delta st
                          in case new_e of 
                              (EBPrim _ Sub (EConst [] new_e1) (EConst [] new_e2)) -> 
                                  (new_env, EConst wsc (EBPrim ws Sub new_e1 new_e2), new_st)
                              _                                                     -> 
                                  (new_env, EError 1 "Fusion Failed", new_st)
                _ -> ([], EError 2 "Error 36", st)
 
        -- P-Oplus-Sub-DAdd
        (EBPrim ws Sub e1 e2, DAdd _) ->
            let (_, b1) = fevalC env e1
                (_, b2) = fevalC env e2
            in case (b1, b2) of 
                (BTrue, BTrue)  -> (env, fuse delta exp, st) -- P-Oplus1
                (BTrue, BFalse) ->  -- P-Oplus2
                    let (env2, new_e2, _) = beval env e2 delta []
                        (fv1, fv2) =  (freeVars e1, freeVars e2)
                    in
                    case two_wayMerge fv1 fv2 env env2 of
                            (new_env, [], [])   -> (new_env, EBPrim ws Sub e1 new_e2, st)
                            (new_env, denv2, _) ->
                                let fusedE2 = fuseEnv denv2 new_e2
                                in
                                if isError fusedE2
                                then (env, fuse delta exp, st)
                                else (new_env, EBPrim ws Sub e1 fusedE2, st)
                _               ->
                    let (env1, new_e1, _) = beval env e1 delta []
                        (fv1, fv2) =  (freeVars e1, freeVars e2)
                    in
                    case two_wayMerge fv1 fv2 env1 env of
                            (new_env, [], [])   -> (new_env, EBPrim ws Sub new_e1 e2, st)
                            (new_env, denv1, _) ->
                                let fusedE1 = fuseEnv denv1 new_e1
                                in
                                if isError fusedE1
                                then (env, fuse delta exp, st)
                                else (new_env, EBPrim ws Sub fusedE1 e2, st)
 
        -- P-Oplus-Sub-DMul
        (EBPrim ws Sub e1 e2, DMul (AFloat f)) ->  
            case (fevalC env e1, fevalC env e2) of
                ((VFloat f1, b1), (VFloat f2, b2)) ->
                    case (b1, b2) of 
                        (BTrue, BTrue)  -> (env, fuse delta exp, st)
                        (BTrue, BFalse) ->  -- P-Oplus-2
                            let delta2 = ((1 - f) * f1 + (f - 1)* f2) |> AFloat |> DMul
                                (env2, new_e2, _) = beval env e2 delta2 []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env env2 of
                                (new_env, [], [])    -> (new_env, EBPrim ws Sub e1 new_e2, st)
                                (new_env, denv2, _)  ->
                                    let fusedE2 = fuseEnv denv2 new_e2
                                    in
                                    if isError fusedE2 
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Sub e1 fusedE2, st)
                        _ -> -- P-Oplus3
                            let delta1 = ((f - 1) * f1 + (1 - f) * f2) |> AFloat |> DMul
                                (env1, new_e1, _) = beval env e1 delta1 []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env1 env of
                                (new_env, [], [])    -> (new_env, EBPrim ws Sub new_e1 e2, st)
                                (new_env, denv1, _)  ->
                                    let fusedE1 = fuseEnv denv1 new_e1
                                    in
                                    if isError fusedE1 
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Sub fusedE1 e2, st)
                _ -> ([], EError 2 "Error 36", st)


        -- P-C-Oplus-Mul
        (EConst wsc (EBPrim ws Mul e1 e2), _) ->
            case (fevalC env (EConst [] e1), fevalC env (EConst [] e2)) of
                ((VFloat _, b1), (VFloat _, b2)) ->
                    case (b1, b2) of 
                        (BTrue, BTrue)  -> ([], EError 0 "e1, e2 evaluates to const, not modifiable.", [])
                        _               ->
                          let (new_env, new_e, new_st) = beval env (EBPrim ws Mul (EConst [] e1) (EConst [] e2)) delta st
                          in case new_e of 
                              (EBPrim _ Mul (EConst [] new_e1) (EConst [] new_e2)) -> 
                                  (new_env, EConst wsc (EBPrim ws Mul new_e1 new_e2), new_st)
                              _                                                     -> 
                                  (new_env, EError 1 "Fusion Failed", new_st)
                _ -> ([], EError 2 "Error 36", st)
 
        -- P-Oplus-Mul-DAdd
        (EBPrim ws Mul e1 e2, DAdd (AFloat f)) ->
            let (v1, b1) = fevalC env e1
                (v2, b2) = fevalC env e2
            in case (b1, b2) of 
                (BTrue, BTrue)  -> (env, fuse delta exp, st) -- P-Oplus1
                (BTrue, BFalse)  -> -- P-Oplus2
                    case v1 of
                        VFloat f1 ->
                            let (env2, new_e2, _) = beval env e2 ((f / f1 |> AFloat) |> DAdd) []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env env2 of
                                (new_env, [], [])   -> (new_env, EBPrim ws Mul e1 new_e2, st)
                                (new_env, denv2, _) ->
                                    let fusedE2 = fuseEnv denv2 new_e2
                                    in
                                    if isError fusedE2
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Mul e1 fusedE2, st)
                        _ -> ([], EError 2 "Error 35", [])
                _                ->  -- P-Oplus3
                    case v2 of
                        VFloat f2 ->
                            let (env1, new_e1, _) = beval env e1 ((f / f2 |> AFloat) |> DAdd) []
                                (fv1, fv2) = (freeVars e1, freeVars e2)
                            in
                            case two_wayMerge fv1 fv2 env1 env of
                                (new_env, [], [])   -> (new_env, EBPrim ws Mul new_e1 e2, st)
                                (new_env, denv1, _) ->
                                    let fusedE1 = fuseEnv denv1 new_e1
                                    in
                                    if isError fusedE1
                                    then (env, fuse delta exp, st)
                                    else (new_env, EBPrim ws Mul fusedE1 e2, st)
                        _ -> ([], EError 2 "Error 35", [])

        -- P-Oplus-Mul-DMul                       
        (EBPrim ws Mul e1 e2, DMul _) ->
            let (_, b1) = fevalC env e1
                (_, b2) = fevalC env e2
            in case (b1, b2) of 
                (BTrue, BTrue)  -> (env, fuse delta exp, st) -- P-Oplus1
                (BTrue, BFalse) -> -- P-Oplus2
                    let (env2, new_e2, _) = beval env e2 delta []
                        (fv1, fv2) = (freeVars e1, freeVars e2)
                    in
                    case two_wayMerge fv1 fv2 env env2 of
                        (new_env, [], [])   -> (new_env, EBPrim ws Mul e1 new_e2, st)
                        (new_env, denv2, _) ->
                            let fusedE2 = fuseEnv denv2 new_e2
                            in
                            if isError fusedE2 
                            then (env, fuse delta exp, st)
                            else (new_env, EBPrim ws Mul e1 fusedE2, st)
                _               -> -- P-Oplus3
                    let (env1, new_e1, _) = beval env e1 delta []
                        (fv1, fv2) = (freeVars e1, freeVars e2)
                    in
                    case two_wayMerge fv1 fv2 env1 env of
                        (new_env, [], [])   -> (new_env, EBPrim ws Mul new_e1 e2, st)
                        (new_env, denv1, _) ->
                            let fusedE1 = fuseEnv denv1 new_e1
                            in
                            if isError fusedE1 
                            then (env, fuse delta exp, st)
                            else (new_env, EBPrim ws Mul fusedE1 e2, st)


        -- P-C-Neg
        (EConst wsc (EUPrim ws Neg e1), _) -> 
           let (new_env, new_e, _) = beval env (EUPrim ws Neg (EConst [] e1)) delta st
           in case new_e of 
               EUPrim _ Neg (EConst _ new_e1) -> (new_env, EConst wsc (EUPrim ws Neg new_e1), st)
               _                              -> ([], EError 2 "Fail", [])
 
        -- P-Neg-DAdd
        (EUPrim ws Neg e1, DAdd (AFloat f)) ->
            let (_, b1) = fevalC env e1
            in case b1 of 
                BTrue -> ([], EError 0 "e1 evaluates to const, not modifiable.", [])
                _ -> let (env1, new_e1, _) = beval env e1 (AFloat -f |> DAdd) []
                     in (env1, EUPrim ws Neg new_e1, st)
        
        -- P-Neg-DMul
        (EUPrim ws Neg e1, DMul _) ->
            let (_, b1) = fevalC env e1
            in case b1 of 
                BTrue -> ([], EError 0 "e1 evaluates to const, not modifiable.", [])
                _     -> let (env1, new_e1, _) = beval env e1 delta []
                         in (env1, EUPrim ws Neg new_e1, st)

        -- P-C-Unwrap
        (EConst wsc (EUnwrap ws e), _) -> 
            let (env1, new_const_e, st_) = beval env (EConst [] e) (DMap delta) st
            in case new_const_e of 
                EConst _ new_e -> (env1, EConst wsc (EUnwrap ws new_e), st_)
                _              -> ([], EError 1 "Fusion fail", [])

        -- P-Unwrap
        (EUnwrap ws e,  _) ->
            let (env1, new_e, st_) = beval env e (DMap delta) st
            in (env1, EUnwrap ws new_e, st_)
        
        -- P-EMap  --TODO: usecase, example needed.
        (EMap ws e1 e2, DMap d) ->
            case fevalC env e1 of
                (VClosure envf p ef, _) ->
                    case fevalC env e2 of
                        (VGraphic _ v, bv) ->
                            case matchC p (v, bv) of
                            Just envm ->
                                let (env_, ef_, st_) = beval (envm ++ envf) ef d st
                                    (envm_, envf_) = (List.take (List.length envm) env_, List.drop (List.length envm) env_)
                                    (env1, new_e1, _) = beval env e1 (DClosure envf_ p ef_) []
                                    (env2, new_e2, _) = beval env e2 (substDelta p envm_ |> DMap) []
                                    (fv1, fv2) = (freeVars e1, freeVars e2)
                                in
                                if isError new_e1 || isError new_e2
                                then (env, fuse delta exp, st)
                                else
                                case two_wayMerge fv1 fv2 env1 env2 of
                                    (new_env, [], [])       -> (new_env, EMap ws new_e1 new_e2, st_)
                                    (new_env, denv1, denv2) ->
                                        let fusedE1 = fuseEnv denv1 new_e1
                                            fusedE2 = fuseEnv denv2 new_e2
                                        in
                                        if isError fusedE1 || isError fusedE2
                                        then (env, fuse delta exp, st)
                                        else (new_env, EMap ws fusedE1 fusedE2, st_)
                            Nothing -> ([], EError 2 "Error 50", [])
                        _ -> ([], EError 2 "", [])
                _ -> ([], EError 2 "Error 51", [])


        -- P-C-EGraphic
        (EConst wsc (EGraphic ws s e), _) -> 
            let (new_env, new_g_e, new_st) = beval env (EGraphic ws s  (EConst [] e)) delta st
            in case new_g_e of 
                (EGraphic _ _  (EConst _ new_e)) -> (new_env, EConst wsc (EGraphic ws s new_e), new_st)
                _                              -> ([], EError 1 "Fusion fail", [])
        -- P-EGraphic
        (EGraphic ws s e, DMap d) ->
            let (_, b) = fevalC env e
            in if isConstBValue b  
               then ([], EError 0 "e evaluates to const, not modifiable.", [])
               else let (env1, new_e, st_) = beval env e d st
                        -- _ = Debug.log "1329 new_e" new_e
                        -- _ = Debug.log "1329 env1" env1
                    in case new_e of 
                        EError _ _ -> ([], new_e, [])
                        _          ->(env1, EGraphic ws s new_e, st_)

        (e, DCtt (PVar _ s) d) ->
            let (env_, e_, st1) = beval env e d ((s, (env, EError 2 "IIIegal Constraint"))::st)
            in
            if isError e_ 
            then (env, fuse delta exp, st)
            else
            case st1 of
                (_, (_, EError _ _)) :: st_ -> (env, fuse delta exp, st_) -- update st fail.
                (_, (_, sub)) :: st_ ->
                    let fun = ELam [] (PVar [""] s) e_
                    in (env_, EApp ["LET", " ", " ", "\n"] fun (pars " " sub), st_)
                _ -> ([], EError 2 "Error 21", [])

        (e, DGroup s d) ->
            let (env_, e_, st1) = beval env e d ((s, ([], EEmpList []))::st)
            in case e_ of 
                EError _ _ -> ([], e_, [])
                _        ->
                    case st1 of
                        (_, (_, ls)) :: st_ ->
                            let group = EGraphic [" "] "g" (EGList ["", ""] (EFloat [""] 0) (EGList [""] ls (EEmpList [])))
                            in
                            (env_,  EApp ["LET", " ", " ", "\n"] (ELam [] (PVar [""] s) (ECons [""] (EVar [""] s) e_)) (group |> setLastSpaces " "), st_)
                        _ -> ([], EError 2 "Error 05", [])

        (e, DCom d1 d2) ->
            let (env1, e1, st1) = beval env e d1 st
            in if isError e1
            then (env, fuse delta exp, st)
            else let (env2, e2, st2) = beval env1 e1 d2 st
            in if isError e2
            then (env, fuse delta exp, st)
            else (env2, e2, mergeST st1 st2)
        (_, DError info) -> ([], EError 2 info, [])
        (_, _)           -> let _ = Debug.log "1353 delta" delta
                                _ = Debug.log "1353 exp" exp
                            in ([], EError 2 "Cannot handle this delta", [])