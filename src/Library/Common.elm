module Common exposing (Switch(..), backToIndex, boolFromString, boolToString, queryString, urlOrigin)

import Tuple.Ext as Tuple
import Url exposing (Protocol(..), Url)
import Url.Builder as Url



-- ⛩


backToIndex : String
backToIndex =
    "Back to tracks"



-- 🌳


type Switch
    = On
    | Off



-- 🔱


boolFromString : String -> Bool
boolFromString string =
    case string of
        "t" ->
            True

        _ ->
            False


boolToString : Bool -> String
boolToString bool =
    if bool then
        "t"

    else
        "f"


queryString : List ( String, String ) -> String
queryString =
    List.map (Tuple.uncurry Url.string) >> Url.toQuery


urlOrigin : Url -> String
urlOrigin { host, port_, path, protocol } =
    let
        scheme =
            case protocol of
                Http ->
                    "http://"

                Https ->
                    "https://"

        thePort =
            port_
                |> Maybe.map (String.fromInt >> (++) ":")
                |> Maybe.withDefault ""
    in
    scheme ++ host ++ thePort ++ path
