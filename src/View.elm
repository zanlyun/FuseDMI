module View exposing (..)

import Html exposing (..)
import Html.Events as Events
import Html.Attributes as Attr
import Svg exposing (svg)
import Model exposing (Model, Msg(..))


view : Model -> Html Msg
view model =
    div [ Attr.id "body" ]
        [ div [Attr.id "menu-bar"] 

            [ div   [ Attr.class "title"
                    , Attr.style "width" "75px"]
                    [ Html.text "FuseDMI"]
            
            , select    [ Events.onInput SelectFile
                        , Attr.class "btn"]
                        <| List.map (\s-> option [Attr.value s] [text s]) 
                        <| model.fileList
            ]

        , button [ Attr.id "execute-button"
                ,  Attr.class "bx-btn"][]

        , button [ Attr.id "back-button"
                ,  Attr.class "bx-btn"][]

        , button [ Attr.id "delta-back-button"
                ,  Attr.class "bx-btn"][]

        , button [ Attr.id "delta-undo-button"
                ,  Attr.class "undo-btn"][]

        , button [ Attr.id "delta-redo-button"
                ,  Attr.class "redo-btn"][]


        , div [Attr.id "output-div"]
            [ svg [Attr.id "output-svg"] []]
        ]