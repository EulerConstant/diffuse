module UI.DnD exposing (Environment, Model, Msg, hasDropped, initialModel, isBeingDraggedOver, isDragging, isDraggingOver, listenToEnterLeave, listenToStart, modelSubject, modelTarget, startDragging, stoppedDragging, update)

import Html exposing (Attribute)
import Html.Attributes as Attributes
import Html.Events.Extra.Mouse as Mouse
import Html.Events.Extra.Pointer as Pointer
import UI.Reply as Reply exposing (Reply)



-- 🌳


type Model context
    = NotDragging
    | Dragging { subject : context }
    | DraggingOver { subject : context, target : context }
    | Dropped { subject : context, target : context }


type Msg context
    = Start context
    | Enter context
    | Leave context
    | Stop


type alias Environment context msg =
    { model : Model context
    , toMsg : Msg context -> msg
    }


initialModel : Model context
initialModel =
    NotDragging



-- 📣


update : Msg context -> Model context -> ( Model context, List Reply )
update msg model =
    ( ------------------------------------
      -- Model
      ------------------------------------
      case msg of
        Start context ->
            Dragging { subject = context }

        Enter context ->
            case model of
                NotDragging ->
                    NotDragging

                Dragging { subject } ->
                    DraggingOver { subject = subject, target = context }

                DraggingOver { subject } ->
                    DraggingOver { subject = subject, target = context }

                Dropped _ ->
                    NotDragging

        Leave context ->
            case model of
                NotDragging ->
                    NotDragging

                Dragging env ->
                    Dragging env

                DraggingOver { subject, target } ->
                    if context == target then
                        Dragging { subject = subject }

                    else
                        model

                Dropped _ ->
                    NotDragging

        Stop ->
            case model of
                DraggingOver { subject, target } ->
                    if subject /= target then
                        Dropped { subject = subject, target = target }

                    else
                        NotDragging

                _ ->
                    NotDragging
      ------------------------------------
      -- Reply
      ------------------------------------
    , case msg of
        Start context ->
            [ Reply.StartedDragging ]

        _ ->
            []
    )



-- 🔱  ░░  EVENTS & MESSAGES


listenToStart : Environment context msg -> context -> Attribute msg
listenToStart { toMsg } context =
    Pointer.onWithOptions
        "pointerdown"
        { stopPropagation = True
        , preventDefault = False
        }
        (\event ->
            case ( event.pointer.button, event.isPrimary ) of
                ( Mouse.MainButton, True ) ->
                    toMsg (Start context)

                _ ->
                    toMsg Stop
        )


listenToEnterLeave : Environment context msg -> context -> List (Attribute msg)
listenToEnterLeave { model, toMsg } context =
    case model of
        NotDragging ->
            []

        _ ->
            [ context
                |> Enter
                |> toMsg
                |> always
                |> Pointer.onEnter
            , context
                |> Leave
                |> toMsg
                |> always
                |> Pointer.onLeave
            ]


startDragging : context -> Msg context
startDragging =
    Start


stoppedDragging : Msg context
stoppedDragging =
    Stop



-- 🔱  ░░  MODEL


isBeingDraggedOver : context -> Model context -> Bool
isBeingDraggedOver context model =
    case model of
        DraggingOver { target } ->
            context == target

        _ ->
            False


hasDropped : Model context -> Bool
hasDropped model =
    case model of
        Dropped _ ->
            True

        _ ->
            False


modelSubject : Model context -> Maybe context
modelSubject model =
    case model of
        NotDragging ->
            Nothing

        Dragging { subject } ->
            Just subject

        DraggingOver { subject } ->
            Just subject

        Dropped { subject } ->
            Just subject


modelTarget : Model context -> Maybe context
modelTarget model =
    case model of
        NotDragging ->
            Nothing

        Dragging _ ->
            Nothing

        DraggingOver { target } ->
            Just target

        Dropped { target } ->
            Just target



-- 🔱  ░░  ENVIRONMENT


isDragging : Environment context msg -> Bool
isDragging { model } =
    case model of
        NotDragging ->
            False

        Dragging _ ->
            True

        DraggingOver _ ->
            True

        Dropped _ ->
            False


isDraggingOver : context -> Environment context msg -> Bool
isDraggingOver context { model } =
    case model of
        NotDragging ->
            False

        Dragging _ ->
            False

        DraggingOver { target } ->
            target == context

        Dropped _ ->
            False
