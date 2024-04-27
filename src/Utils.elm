module Utils exposing (..)

lookup : String -> List (String, a) -> Maybe a
lookup key list =
    case List.filter (\(k, _) -> k == key) list of
        []          -> Nothing
        (_, v) :: _ -> Just v

lookup2 : String -> List (String, a, b) -> Maybe (a, b)
lookup2 key list =
    case List.filter (\(k, _, _) -> k == key) list of
        []          -> Nothing
        (_, v, b) :: _ -> Just (v, b)



setLast : a -> List a -> List a
setLast item list =
    case List.reverse list of
        [] ->
            [item]

        _ :: rest ->
            List.reverse (item :: rest)