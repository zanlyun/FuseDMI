module Model exposing(..)

import Language.Syntax exposing (Exp(..))

type alias Model =
    { exp      : Exp
    , lastExp  : Exp
    , fileList : List String
    }


type Msg
    = Execute String
    | Change String
    | SelectFile String
    | Undo String
    | ParseCode String


initModel : Model
initModel = 
    { exp      = EError 2 "No code yet"
    , lastExp  = EError 2 "No code yet"
    , fileList = [ "New File", "Bench-Arrows", "Bench-BalanceScale"
                , "Bench-Battery", "Bench-BoxVolume", "Bench-FerrisWheel", "Bench-Ladder", "Bench-Logo"
                , "Bench-MondrianArch", "Bench-NBoxes", "Bench-PencilTip", "Bench-PrecisionFloorPlan"
                , "const-Bench-PrecisionFloorPlan", "Bench-Rails", "Bench-Target", "Bench-TreeBranch","SVG-1", "SVG-2"
                , "SVG-3", "SVG-4", "SVG-5", "SVG-6", "SVG-7"
                , "Test-1-Tuple", "Test-2-List", "Test-3-Recursion", "Test-4-Nested-List"]
    }