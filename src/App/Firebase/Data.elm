port module Firebase.Data exposing (..)

{-| This module is related to the Firebase database.
-}

import Json.Encode as Json


port storeSources : List Json.Value -> Cmd msg


port storeTracks : List Json.Value -> Cmd msg