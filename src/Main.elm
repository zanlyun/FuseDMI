port module Main exposing (..)

import View
import Html exposing (..)
import Model exposing (..)
import Browser exposing (..)
import Parser.Exp as ExpParser
import Language.BEval exposing (beval)
import Printer.Exp as ExpPrinter
import Parser.Delta as DeltaParser
import Printer.Value exposing (printGraphics)
import Language.FEvalC exposing (fevalC)
-- import Language.Syntax exposing (Exp(..))
import Language.Syntax exposing (..)
import Language.Preclude exposing (library)
import Language.FEvalDelta exposing (fevalDelta)
import Language.BEvalDelta exposing (bevalDelta)
import Language.FEvalDelta exposing (fevalValue)
import Language.FusionBDelta exposing (fuseDeltaExp)

main : Program () Model Msg
main =
    Browser.element
        { init          = init
        , update        = update
        , view          = view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Cmd Msg )
init _ = (Model.initModel, Cmd.none)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Execute code ->
            -- case ExpParser.parse (library ++ code) of
            case ExpParser.parse code of
                Ok exp ->
                    let
                        -- exp1 = EBPrim [] Add (EFloat [] 2) (EDelta [] (EFloat [] 5) (DAddV (VFloat 2)))
                        -- exp2 = EBPrim [] Mul (EFloat [] 2) (EDelta [] (EFloat [] 5) (DAddV (VFloat 2)))
                        -- exp3 = EApp ["LET"," "," "," \n"] (ELam [] (PVar [" "] "*x") (ETuple [""," ",""] (EVar [""] "*x") (EVar [""] "*x"))) (EDelta [""] (EFloat [" "] 1) (DAddV (VFloat 1)))
                        _ = Debug.log "exp" exp
                        deltaV = fevalDelta [] exp
                        finalV = fevalValue deltaV
                        _ = Debug.log "deltaV" deltaV
                        _ = Debug.log "finalV" finalV
                        (v, b) = fevalC [] exp
                        _ = Debug.log "v" v
                        _ = Debug.log "b" b
                    in
                    ( { model | lastExp = model.exp, exp = exp}
                    , printGraphics v |> genCanvas)

                Err info ->
                    let _ = Debug.log "Parse Exp" (Debug.toString info) in
                    ( model, Cmd.none )
        -- ?x=>([&x,id].[id,rewr x])
        -- ?x=>(([&x,id]::id) . ([id,rewr x]::id))
        -- [?x=>(([&x,id]) . ([id,rewr x]))]
        Change d ->
            case DeltaParser.parse d of
                Ok delta -> 
                    case model.exp of 
                        EError _ _ ->  
                            let _ = Debug.log "Error" "foward evaluation needed, before backward."
                            in (model, Cmd.none)
                        _          ->
                            let 
                                (_, exp1, _) = bevalDelta [] model.exp delta []
                                _ = Debug.log "exp1" exp1
                                _ = Debug.log "exp1 pretty" ""
                                _ = Debug.log (ExpPrinter.print exp1) ""
                                finalExp = fuseDeltaExp exp1
                                _ = Debug.log "finalExp" finalExp
                                _ = Debug.log "finalExp pretty" ""
                                _ = Debug.log (ExpPrinter.print finalExp) ""
 
                                exp_ = case finalExp of 
                                    EError _ _    -> model.exp
                                    _             -> finalExp
                            in ( { model | lastExp = model.exp, exp = exp_ }, retNewCode (exp_ |> ExpPrinter.print))
                            -- in ( { model | lastExp = model.exp, exp = exp_ }, retNewCode (exp_ |> ExpPrinter.print |> String.dropLeft (String.length library)))
                Err info ->
                    let infoStr = Debug.toString info
                        _ = Debug.log "Error" infoStr in
                    ( model, Cmd.none )
        
        SelectFile f -> (model, retCodeFile f)

        Undo _ -> 
          ({model | exp = model.lastExp}, retNewCode (model.lastExp |> ExpPrinter.print ))
          -- ({model | exp = model.lastExp}, retNewCode (model.lastExp |> ExpPrinter.print |> String.dropLeft (String.length library)))
        ParseCode code ->
            -- case ExpParser.parse (library ++ code) of
            case ExpParser.parse code of
                Ok exp ->
                    let
                        _ = Debug.log "Parsed code, exp" exp
                    in
                    ( { model | lastExp = model.exp, exp = exp}
                    , Cmd.none)

                Err info ->
                    let _ = Debug.log "Parse Exp" (Debug.toString info) in
                    ( model, Cmd.none )
 

view : Model -> Html Msg
view = View.view


port exeCode    : (String -> msg) -> Sub msg
port changeCode : (String -> msg) -> Sub msg
port getEdit    : (String -> msg) -> Sub msg

port retNewCode  : String -> Cmd msg
port retCodeFile : String -> Cmd msg
port retEditFile : String -> Cmd msg
port genCanvas   : String -> Cmd msg

port undoCode : (String -> msg) -> Sub msg
port parseCode : (String -> msg) -> Sub msg

subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch 
        [ exeCode Execute
        , changeCode Change
        , getEdit Change
        , undoCode Undo
        , parseCode ParseCode
        ]