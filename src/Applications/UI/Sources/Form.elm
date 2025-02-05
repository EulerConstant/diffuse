module UI.Sources.Form exposing (FormStep(..), Model, Msg(..), defaultContext, edit, initialModel, new, takeStepBackwards, takeStepForwards, update)

import Browser.Navigation as Nav
import Chunky exposing (..)
import Color
import Common exposing (boolFromString, boolToString)
import Conditional exposing (..)
import Dict
import Dict.Ext as Dict
import Html.Styled as Html exposing (Html, strong, text)
import Html.Styled.Attributes exposing (for, name, placeholder, required, selected, style, type_, value)
import Html.Styled.Events exposing (onInput, onSubmit)
import List.Extra as List
import Material.Icons exposing (Coloring(..))
import Material.Icons.Alert as Icons
import Material.Icons.Navigation as Icons
import Return3 as Return exposing (..)
import Sources exposing (..)
import Sources.Services as Services
import Sources.Services.Dropbox
import Sources.Services.Google
import Tachyons.Classes as T
import UI.Kit exposing (ButtonType(..), select)
import UI.Navigation exposing (..)
import UI.Page as Page
import UI.Reply as Reply exposing (Reply(..))
import UI.Sources.Page as Sources



-- 🌳


type alias Model =
    { step : FormStep
    , context : Source
    }


type FormStep
    = Where
    | How
    | By


initialModel : Model
initialModel =
    { step = Where
    , context = defaultContext
    }


defaultContext : Source
defaultContext =
    { id = "CHANGE_ME_PLEASE"
    , data = Services.initialData defaultService
    , directoryPlaylists = True
    , enabled = True
    , service = defaultService
    }


defaultService : Service
defaultService =
    AmazonS3



-- 📣


type Msg
    = AddSource
    | Bypass
    | EditSource
    | ReturnToIndex
    | SelectService String
    | SetData String String
    | TakeStep
    | TakeStepBackwards


update : Msg -> Model -> Return Model Msg Reply
update msg model =
    case msg of
        AddSource ->
            let
                context =
                    model.context

                cleanContext =
                    { context | data = Dict.map (always String.trim) context.data }
            in
            returnRepliesWithModel
                { model | step = Where, context = defaultContext }
                [ GoToPage (Page.Sources Sources.Index)
                , AddSourceToCollection cleanContext
                ]

        Bypass ->
            return model

        EditSource ->
            returnRepliesWithModel
                { model | step = Where, context = defaultContext }
                [ ReplaceSourceInCollection model.context
                , ProcessSources [ model.context ]
                , GoToPage (Page.Sources Sources.Index)
                ]

        ReturnToIndex ->
            returnRepliesWithModel
                model
                [ GoToPage (Page.Sources Sources.Index) ]

        SelectService serviceKey ->
            case Services.keyToType serviceKey of
                Just service ->
                    let
                        ( context, data ) =
                            ( model.context
                            , Services.initialData service
                            )

                        newContext =
                            { context | data = data, service = service }
                    in
                    return { model | context = newContext }

                Nothing ->
                    return model

        SetData key value ->
            let
                context =
                    model.context

                updatedData =
                    Dict.insert key value context.data

                newContext =
                    { context | data = updatedData }
            in
            return { model | context = newContext }

        TakeStep ->
            case ( model.step, model.context.service ) of
                ( How, Dropbox ) ->
                    model.context.data
                        |> Sources.Services.Dropbox.authorizationUrl
                        |> ExternalSourceAuthorization
                        |> returnReplyWithModel model

                ( How, Google ) ->
                    model.context.data
                        |> Sources.Services.Google.authorizationUrl
                        |> ExternalSourceAuthorization
                        |> returnReplyWithModel model

                _ ->
                    return { model | step = takeStepForwards model.step }

        TakeStepBackwards ->
            return { model | step = takeStepBackwards model.step }


takeStepForwards : FormStep -> FormStep
takeStepForwards currentStep =
    case currentStep of
        Where ->
            How

        _ ->
            By


takeStepBackwards : FormStep -> FormStep
takeStepBackwards currentStep =
    case currentStep of
        By ->
            How

        _ ->
            Where



-- NEW


new : Model -> List (Html Msg)
new model =
    case model.step of
        Where ->
            newWhere model

        How ->
            newHow model

        By ->
            newBy model


newWhere : Model -> List (Html Msg)
newWhere { context } =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Back to list" Hidden
          , NavigateToPage (Page.Sources Sources.Index)
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , (\h ->
        form TakeStep
            [ UI.Kit.canisterForm h ]
      )
        [ UI.Kit.h2 "Where is your music stored?"

        -- Dropdown
        -----------
        , let
            contextServiceKey =
                Services.typeToKey context.service
          in
          Services.labels
            |> List.map
                (\( k, l ) ->
                    Html.option
                        [ value k, selected (contextServiceKey == k) ]
                        [ text l ]
                )
            |> select SelectService

        -- Button
        ---------
        , chunk
            [ T.mt4, T.pt2 ]
            [ UI.Kit.button
                IconOnly
                Bypass
                (Html.fromUnstyled <| Icons.arrow_forward 17 Inherit)
            ]
        ]
    ]


newHow : Model -> List (Html Msg)
newHow { context } =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Take a step back" Shown
          , PerformMsg TakeStepBackwards
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , (\h ->
        form TakeStep
            [ chunk
                [ T.tl, T.w_100 ]
                [ UI.Kit.canister h ]
            ]
      )
        [ UI.Kit.h3 "Where exactly?"

        -- Note
        -------
        , note context.service

        -- Fields
        ---------
        , let
            properties =
                Services.properties context.service

            dividingPoint =
                toFloat (List.length properties) / 2

            ( listA, listB ) =
                List.splitAt (ceiling dividingPoint) properties
          in
          chunk
            [ T.flex, T.pt3 ]
            [ chunk
                [ T.flex_grow_1, T.pr3 ]
                (List.map (renderProperty context) listA)
            , chunk
                [ T.flex_grow_1, T.pl3 ]
                (List.map (renderProperty context) listB)
            ]

        -- Button
        ---------
        , chunk
            [ T.mt3, T.tc ]
            [ UI.Kit.button
                IconOnly
                Bypass
                (Html.fromUnstyled <| Icons.arrow_forward 17 Inherit)
            ]
        ]
    ]


howNote : List (Html Msg) -> Html Msg
howNote =
    chunk [ T.f6, T.i, T.lh_copy, T.mb4, T.measure_wide ]


newBy : Model -> List (Html Msg)
newBy { context } =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Take a step back" Shown
          , PerformMsg TakeStepBackwards
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , (\h ->
        form AddSource
            [ UI.Kit.canisterForm h ]
      )
        [ UI.Kit.h2 "One last thing"
        , UI.Kit.label [] "What are we going to call this source?"

        -- Input
        --------
        , let
            nameValue =
                Dict.fetch "name" "" context.data
          in
          chunk
            [ T.flex, T.mt4, T.justify_center, T.w_100 ]
            [ UI.Kit.textField
                [ name "name"
                , onInput (SetData "name")
                , value nameValue
                ]
            ]

        -- Note
        -------
        , chunk
            [ T.mt5 ]
            (case context.service of
                AmazonS3 ->
                    corsWarning "CORS__S3"

                AzureBlob ->
                    corsWarning "CORS__Azure"

                AzureFile ->
                    corsWarning "CORS__Azure"

                Dropbox ->
                    []

                Google ->
                    []

                Ipfs ->
                    corsWarning "CORS__IPFS"

                WebDav ->
                    corsWarning "CORS__WebDAV"
            )

        -- Button
        ---------
        , UI.Kit.button
            Normal
            Bypass
            (text "Add source")
        ]
    ]


corsWarning : String -> List (Html Msg)
corsWarning id =
    [ chunk
        [ T.f6, T.flex, T.items_center, T.justify_center, T.lh_title, T.o_50 ]
        [ UI.Kit.inlineIcon Icons.warning
        , strong
            []
            [ text "Make sure CORS is enabled" ]
        ]
    , chunk
        [ T.f6, T.lh_title, T.mb4, T.mt1, T.o_50 ]
        [ text "You can find the instructions over "
        , UI.Kit.link { label = "here", url = "about#" ++ id }
        ]
    ]



-- EDIT


edit : Model -> List (Html Msg)
edit { context } =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Go Back" Shown
          , PerformMsg ReturnToIndex
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , (\h ->
        form EditSource
            [ chunk
                [ T.tl, T.w_100 ]
                [ UI.Kit.canister h ]
            ]
      )
        [ UI.Kit.h3 "Edit source"

        -- Note
        -------
        , note context.service

        -- Fields
        ---------
        , let
            properties =
                Services.properties context.service

            dividingPoint =
                toFloat (List.length properties) / 2

            ( listA, listB ) =
                List.splitAt (ceiling dividingPoint) properties
          in
          chunk
            [ T.flex, T.pt3 ]
            [ chunk
                [ T.flex_grow_1, T.pr3 ]
                (List.map (renderProperty context) listA)
            , chunk
                [ T.flex_grow_1, T.pl3 ]
                (List.map (renderProperty context) listB)
            ]

        -- Button
        ---------
        , chunk
            [ T.mt3, T.tc ]
            [ UI.Kit.button
                Normal
                Bypass
                (text "Save")
            ]
        ]
    ]



-- PROPERTIES


renderProperty : Source -> Property -> Html Msg
renderProperty context property =
    chunk
        [ T.mb4 ]
        [ UI.Kit.label
            [ for property.key ]
            property.label

        --
        , if
            (property.placeholder == boolToString True)
                || (property.placeholder == boolToString False)
          then
            let
                bool =
                    context.data
                        |> Dict.fetch property.key property.placeholder
                        |> boolFromString
            in
            chunk
                [ T.mt2, T.pt1 ]
                [ UI.Kit.checkbox
                    { checked = bool
                    , toggleMsg =
                        bool
                            |> not
                            |> boolToString
                            |> SetData property.key
                    }
                ]

          else
            UI.Kit.textField
                [ name property.key
                , onInput (SetData property.key)
                , placeholder property.placeholder
                , required (property.label |> String.toLower |> String.contains "optional" |> not)
                , type_ (ifThenElse property.password "password" "text")
                , value (Dict.fetch property.key "" context.data)
                ]
        ]



-- ⚗️


form : Msg -> List (Html Msg) -> Html Msg
form msg html =
    slab
        Html.form
        [ onSubmit msg ]
        [ T.flex
        , T.flex_grow_1
        , T.flex_shrink_0
        , T.tc
        ]
        [ UI.Kit.centeredContent html ]


note : Service -> Html Msg
note service =
    case service of
        AmazonS3 ->
            nothing

        AzureBlob ->
            nothing

        AzureFile ->
            nothing

        Dropbox ->
            howNote
                [ inline
                    [ T.fw6 ]
                    [ text "If you don't know what any of this is, "
                    , text "continue to the next screen."
                    ]
                , text " Changing the app key allows you to use your own Dropbox app."
                , text " Also, make sure you verified your email address on Dropbox,"
                , text " or this might not work."
                ]

        Google ->
            howNote
                [ inline
                    [ T.fw6 ]
                    [ text "If you don't know what any of this is, "
                    , text "continue to the next screen."
                    ]
                , text " Changing the client stuff allows you to use your own Google OAuth client."
                ]

        Ipfs ->
            howNote
                [ inline [ T.fw6 ] [ text "This is using the default gateway address." ]
                , lineBreak
                , text " If you use a different gateway, please change it here."
                , lineBreak
                , text " You can find your gateway address on the IPFS Web UI."
                , lineBreak
                , text "DNSLinks are resolved through Cloudflare."
                ]

        WebDav ->
            howNote
                [ inline
                    [ T.fw6 ]
                    [ UI.Kit.inlineIcon Icons.warning
                    , text "This app requires a proper implementation of "
                    , UI.Kit.link
                        { label = "CORS"
                        , url = "https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS"
                        }
                    , text " on the server side."
                    ]
                , lineBreak
                , text " WebDAV servers usually don't implement"
                , text " CORS properly, if at all."
                , lineBreak
                , text " Some servers, like "
                , UI.Kit.link
                    { label = "this one"
                    , url = "https://github.com/hacdias/webdav"
                    }
                , text ", do. You can find the configuration for that server "
                , UI.Kit.link
                    { label = "here"
                    , url = "about#CORS__WebDAV"
                    }
                , text "."
                ]
