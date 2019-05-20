module UI.UserData exposing (demo, encodedFavourites, encodedSources, encodedTracks, exportEnclosed, gatherSettings, importEnclosed, importHypaethral)

import Authentication exposing (..)
import Base64
import Common exposing (Switch(..))
import Json.Decode as Json
import Json.Decode.Pipeline exposing (..)
import Json.Encode
import List.Extra as List
import Maybe.Extra as Maybe
import Notifications
import Playlists exposing (Playlist)
import Return3 exposing (..)
import Sources exposing (Source)
import Sources.Encoding as Sources
import Tracks exposing (Track, emptyCollection)
import Tracks.Collection as Tracks
import Tracks.Encoding as Tracks
import UI.Backdrop
import UI.Core
import UI.Equalizer as Equalizer
import UI.Notifications
import UI.Playlists as Playlists
import UI.Playlists.Directory
import UI.Ports as Ports
import UI.Reply as UI
import UI.Sources as Sources
import UI.Tracks as Tracks
import UI.Tracks.Core as Tracks



-- HYPAETHRAL


encodedFavourites : UI.Core.Model -> Json.Value
encodedFavourites { tracks } =
    Json.Encode.list Tracks.encodeFavourite tracks.favourites


encodedSources : UI.Core.Model -> Json.Value
encodedSources { sources } =
    Json.Encode.list Sources.encode sources.collection


encodedTracks : UI.Core.Model -> Json.Value
encodedTracks { tracks } =
    Json.Encode.list Tracks.encodeTrack tracks.collection.untouched


gatherSettings : UI.Core.Model -> Settings
gatherSettings { backdrop, tracks } =
    { backgroundImage = backdrop.chosen
    , hideDuplicates = tracks.hideDuplicates
    }


importHypaethral : Json.Value -> UI.Core.Model -> Return UI.Core.Model UI.Core.Msg UI.Reply
importHypaethral value model =
    case decodeHypaethral value of
        Ok data ->
            let
                { backdrop } =
                    model

                backdropModel =
                    data.settings
                        |> Maybe.andThen .backgroundImage
                        |> Maybe.withDefault UI.Backdrop.default
                        |> Just
                        |> (\c -> { backdrop | chosen = c })

                ( sourcesModel, sourcesCmd, sourcesReplies ) =
                    importSources model.sources data

                ( playlistsModel, playlistsCmd, playlistsReplies ) =
                    importPlaylists
                        model.playlists
                        data

                selectedPlaylist =
                    Maybe.andThen
                        (\n -> List.find (.name >> (==) n) playlistsModel.collection)
                        model.playlists.playlistToActivate

                ( tracksModel, tracksCmd, tracksReplies ) =
                    importTracks model.tracks data selectedPlaylist
            in
            ( { model
                | backdrop = backdropModel
                , playlists = playlistsModel
                , sources = sourcesModel
                , tracks = tracksModel
              }
            , Cmd.batch
                [ Cmd.map UI.Core.PlaylistsMsg playlistsCmd
                , Cmd.map UI.Core.SourcesMsg sourcesCmd
                , Cmd.map UI.Core.TracksMsg tracksCmd
                ]
            , playlistsReplies ++ sourcesReplies ++ tracksReplies
            )

        Err err ->
            err
                |> Json.errorToString
                |> Notifications.error
                |> UI.Notifications.showWithModel model
                |> Return3.from2



-- ㊙️


importPlaylists : Playlists.Model -> HypaethralUserData -> Return Playlists.Model Playlists.Msg UI.Reply
importPlaylists model data =
    return
        { model
            | collection = UI.Playlists.Directory.generate data.sources data.tracks
            , playlistToActivate = Nothing
        }


importSources : Sources.Model -> HypaethralUserData -> Return Sources.Model Sources.Msg UI.Reply
importSources model data =
    return { model | collection = data.sources }


importTracks : Tracks.Model -> HypaethralUserData -> Maybe Playlist -> Return Tracks.Model Tracks.Msg UI.Reply
importTracks model data selectedPlaylist =
    let
        adjustedModel =
            { model
                | collection = { emptyCollection | untouched = data.tracks }
                , enabledSourceIds = Sources.enabledSourceIds data.sources
                , favourites = data.favourites
                , hideDuplicates = Maybe.unwrap False .hideDuplicates data.settings
                , selectedPlaylist = selectedPlaylist
            }

        addReplyIfNecessary =
            case model.searchTerm of
                Just _ ->
                    identity

                Nothing ->
                    addReply (UI.ToggleLoadingScreen Off)
    in
    adjustedModel
        |> Tracks.makeParcel
        |> Tracks.identify
        |> Tracks.resolveParcel adjustedModel
        |> andThen (Tracks.update Tracks.Search)
        |> addReplyIfNecessary



-- ENCLOSED


exportEnclosed : UI.Core.Model -> Json.Value
exportEnclosed model =
    let
        equalizerSettings =
            { low = model.equalizer.low
            , mid = model.equalizer.mid
            , high = model.equalizer.high
            , volume = model.equalizer.volume
            }
    in
    encodeEnclosed
        { equalizerSettings = equalizerSettings
        , grouping = model.tracks.grouping
        , onlyShowFavourites = model.tracks.favouritesOnly
        , repeat = model.queue.repeat
        , searchTerm = model.tracks.searchTerm
        , selectedPlaylist = Maybe.map .name model.tracks.selectedPlaylist
        , shuffle = model.queue.shuffle
        , sortBy = model.tracks.sortBy
        , sortDirection = model.tracks.sortDirection
        }


importEnclosed : Json.Value -> UI.Core.Model -> Return UI.Core.Model UI.Core.Msg UI.Reply
importEnclosed value model =
    let
        { equalizer, playlists, queue, tracks } =
            model
    in
    case decodeEnclosed value of
        Ok data ->
            let
                newEqualizer =
                    { equalizer
                        | low = data.equalizerSettings.low
                        , mid = data.equalizerSettings.mid
                        , high = data.equalizerSettings.high
                        , volume = data.equalizerSettings.volume
                    }

                newPlaylists =
                    { playlists
                        | playlistToActivate = data.selectedPlaylist
                    }

                newQueue =
                    { queue
                        | repeat = data.repeat
                        , shuffle = data.shuffle
                    }

                newTracks =
                    { tracks
                        | favouritesOnly = data.onlyShowFavourites
                        , grouping = data.grouping
                        , searchTerm = data.searchTerm
                        , sortBy = data.sortBy
                        , sortDirection = data.sortDirection
                    }
            in
            ( { model
                | equalizer = newEqualizer
                , playlists = newPlaylists
                , queue = newQueue
                , tracks = newTracks
              }
            , Cmd.batch
                [ Cmd.map UI.Core.EqualizerMsg (Equalizer.adjustAllKnobs newEqualizer)
                , Ports.setRepeat data.repeat
                ]
            , []
            )

        Err err ->
            return model



-- DEMO (TODO: Update this to the new structure)


demo : Json.Value
demo =
    "eyJmYXZvdXJpdGVzIjpbeyJhcnRpc3QiOiJKYW1lcyBCbGFrZSIsInRpdGxlIjoiRXNzZW50aWFsIE1peCAoMDktMTctMjAxMSkifV0sInNldHRpbmdzIjp7ImFwcGxpY2F0aW9uIjp7ImJhY2tncm91bmRJbWFnZSI6IjcuanBnIn0sImVxdWFsaXplciI6eyJsb3ciOjAsIm1pZCI6MCwiaGlnaCI6MCwidm9sdW1lIjoxfSwicXVldWUiOnsicmVwZWF0IjpmYWxzZSwic2h1ZmZsZSI6ZmFsc2V9LCJ0cmFja3MiOnsiZmF2b3VyaXRlc09ubHkiOmZhbHNlLCJzZWFyY2hUZXJtIjpudWxsLCJzZWxlY3RlZFBsYXlsaXN0IjpudWxsfX0sInNvdXJjZXMiOlt7ImlkIjoiMTUwNzY0MDIxODczNDIiLCJkYXRhIjp7ImFjY2Vzc0tleSI6IkFLSUFKUUNINTdZRkozVUVSWElBIiwiYnVja2V0TmFtZSI6Im9uZ2FrdS1yeW9oby1kZW1vIiwiZGlyZWN0b3J5UGF0aCI6Ii8iLCJuYW1lIjoiRGVtbyIsInJlZ2lvbiI6InVzLWVhc3QtMSIsInNlY3JldEtleSI6Ii9qSUM2REE5a2MyRFpTdzNLR3NGN1ZmdC94VEFSVHB0R2I5NmtrUDIifSwiZGlyZWN0b3J5UGxheWxpc3RzIjp0cnVlLCJlbmFibGVkIjp0cnVlLCJzZXJ2aWNlIjoiQW1hem9uUzMifV0sInRyYWNrcyI6W3siaWQiOiJNVFV3TnpZME1ESXhPRGN6TkRJdkwwWnlaV1VnYlhWemFXTXZLRk5YVERBeE15a3RiM0pwU21GdWRYTXRWMFZDTFRJd01UUXRSbEpGUlM4d01TMWliMjVwZEdFdWJYQXoiLCJwYXRoIjoiRnJlZSBtdXNpYy8oU1dMMDEzKS1vcmlKYW51cy1XRUItMjAxNC1GUkVFLzAxLWJvbml0YS5tcDMiLCJzb3VyY2VJZCI6IjE1MDc2NDAyMTg3MzQyIiwidGFncyI6eyJkaXNjIjoxLCJuciI6MSwiYWxidW0iOiJTb3VsZWN0aW9uIFdoaXRlIExhYmVsOiAwMTMiLCJhcnRpc3QiOiJvcmlKYW51cyIsInRpdGxlIjoiQm9uaXRhIiwiZ2VucmUiOiJTb3VsZWN0aW9uIiwicGljdHVyZSI6bnVsbCwieWVhciI6bnVsbH19LHsiaWQiOiJNVFV3TnpZME1ESXhPRGN6TkRJdkwwWnlaV1VnYlhWemFXTXZLRk5YVERBeE15a3RiM0pwU21GdWRYTXRWMFZDTFRJd01UUXRSbEpGUlM4d01pMDJMbTF3TXciLCJwYXRoIjoiRnJlZSBtdXNpYy8oU1dMMDEzKS1vcmlKYW51cy1XRUItMjAxNC1GUkVFLzAyLTYubXAzIiwic291cmNlSWQiOiIxNTA3NjQwMjE4NzM0MiIsInRhZ3MiOnsiZGlzYyI6MSwibnIiOjIsImFsYnVtIjoiU291bGVjdGlvbiBXaGl0ZSBMYWJlbDogMDEzIiwiYXJ0aXN0Ijoib3JpSmFudXMiLCJ0aXRsZSI6IjYiLCJnZW5yZSI6IlNvdWxlY3Rpb24iLCJwaWN0dXJlIjpudWxsLCJ5ZWFyIjpudWxsfX0seyJpZCI6Ik1UVXdOelkwTURJeE9EY3pOREl2TDBaeVpXVWdiWFZ6YVdNdktGTlhUREF4TXlrdGIzSnBTbUZ1ZFhNdFYwVkNMVEl3TVRRdFJsSkZSUzh3TXkxb2IzUmZjbVZ0YVhoZlpuUXVYM1JsYXk1c2RXNWZKbDk2YVd0dmJXOHViWEF6IiwicGF0aCI6IkZyZWUgbXVzaWMvKFNXTDAxMyktb3JpSmFudXMtV0VCLTIwMTQtRlJFRS8wMy1ob3RfcmVtaXhfZnQuX3Rlay5sdW5fJl96aWtvbW8ubXAzIiwic291cmNlSWQiOiIxNTA3NjQwMjE4NzM0MiIsInRhZ3MiOnsiZGlzYyI6MSwibnIiOjMsImFsYnVtIjoiU291bGVjdGlvbiBXaGl0ZSBMYWJlbDogMDEzIiwiYXJ0aXN0Ijoib3JpSmFudXMiLCJ0aXRsZSI6IkhvdCBSZW1peCBmdC4gVGVrLkx1biAmIFppa29tbyIsImdlbnJlIjoiU291bGVjdGlvbiIsInBpY3R1cmUiOm51bGwsInllYXIiOm51bGx9fSx7ImlkIjoiTVRVd056WTBNREl4T0Rjek5ESXZMMFp5WldVZ2JYVnphV012UTI5dFgxUnlkV2x6WlMxRGFHVnRhV05oYkY5TVpXZHpMVEl3TVRJdFJsSkZSUzh3TVMxamIyMWZkSEoxYVhObExXTm9aVzFwWTJGc1gyeGxaM011YlhBeiIsInBhdGgiOiJGcmVlIG11c2ljL0NvbV9UcnVpc2UtQ2hlbWljYWxfTGVncy0yMDEyLUZSRUUvMDEtY29tX3RydWlzZS1jaGVtaWNhbF9sZWdzLm1wMyIsInNvdXJjZUlkIjoiMTUwNzY0MDIxODczNDIiLCJ0YWdzIjp7ImRpc2MiOjEsIm5yIjo5LCJhbGJ1bSI6IkFkdWx0IFN3aW0gU2luZ2xlcyBQcm9qZWN0IDIwMTIiLCJhcnRpc3QiOiJDb20gVHJ1aXNlIiwidGl0bGUiOiJDaGVtaWNhbCBMZWdzIiwiZ2VucmUiOm51bGwsInBpY3R1cmUiOm51bGwsInllYXIiOjIwMTJ9fSx7ImlkIjoiTVRVd056WTBNREl4T0Rjek5ESXZMMFp5WldVZ2JYVnphV012VFdGdWRXVnNaVjlCZEhwbGJtbGZMVjh3TkY4dFgweHBkSFJzWlY5VGRHRnlMbTF3TXciLCJwYXRoIjoiRnJlZSBtdXNpYy9NYW51ZWxlX0F0emVuaV8tXzA0Xy1fTGl0dGxlX1N0YXIubXAzIiwic291cmNlSWQiOiIxNTA3NjQwMjE4NzM0MiIsInRhZ3MiOnsiZGlzYyI6MSwibnIiOjQsImFsYnVtIjoiVGhlIE1peWF6YWtpIFRvdXIgRVAiLCJhcnRpc3QiOiJNYW51ZWxlIEF0emVuaSIsInRpdGxlIjoiTGl0dGxlIFN0YXIiLCJnZW5yZSI6IkZ1bmsiLCJwaWN0dXJlIjpudWxsLCJ5ZWFyIjpudWxsfX0seyJpZCI6Ik1UVXdOelkwTURJeE9EY3pOREl2TDBaeVpXVWdiWFZ6YVdNdlVHRjBjbWxqYTE5TVpXVmZMVjh3TWw4dFgxRjFhWFIwYVc1ZlZHbHRaUzV0Y0RNIiwicGF0aCI6IkZyZWUgbXVzaWMvUGF0cmlja19MZWVfLV8wMl8tX1F1aXR0aW5fVGltZS5tcDMiLCJzb3VyY2VJZCI6IjE1MDc2NDAyMTg3MzQyIiwidGFncyI6eyJkaXNjIjoxLCJuciI6MiwiYWxidW0iOiJUaGUgTGFzdCBUaGluZyIsImFydGlzdCI6IlBhdHJpY2sgTGVlIiwidGl0bGUiOiJRdWl0dGluJyBUaW1lIiwiZ2VucmUiOiJFbGVjdHJvbmljIiwicGljdHVyZSI6bnVsbCwieWVhciI6bnVsbH19LHsiaWQiOiJNVFV3TnpZME1ESXhPRGN6TkRJdkwxSmhaR2x2TDJwaGJXVnpYMkpzWVd0bExXVnpjMlZ1ZEdsaGJGOXRhWGd0YzJGMExUQTVMVEUzTFRJd01URXViWEF6IiwicGF0aCI6IlJhZGlvL2phbWVzX2JsYWtlLWVzc2VudGlhbF9taXgtc2F0LTA5LTE3LTIwMTEubXAzIiwic291cmNlSWQiOiIxNTA3NjQwMjE4NzM0MiIsInRhZ3MiOnsiZGlzYyI6MSwibnIiOjEsImFsYnVtIjoiRXNzZW50aWFsIE1peC1TQVQtMDktMTciLCJhcnRpc3QiOiJKYW1lcyBCbGFrZSIsInRpdGxlIjoiRXNzZW50aWFsIE1peCAoMDktMTctMjAxMSkiLCJnZW5yZSI6IkVsZWN0cm9uaWMiLCJwaWN0dXJlIjpudWxsLCJ5ZWFyIjpudWxsfX1dfQ=="
        |> Base64.decode
        |> Result.mapError (\err -> Json.Failure err Json.Encode.null)
        |> Result.andThen (Json.decodeString Json.value)
        |> Result.withDefault (Json.Encode.object [])
