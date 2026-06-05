module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import UrlPath exposing (UrlPath)
import View exposing (View)


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Nothing
    }


type Msg
    = SharedMsg SharedMsg
    | MenuClicked


type alias Data =
    ()


type SharedMsg
    = NoOp


type alias Model =
    { showMenu : Bool
    }


init :
    Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : UrlPath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init flags maybePagePath =
    ( { showMenu = False }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg globalMsg ->
            ( model, Effect.none )

        MenuClicked ->
            ( { model | showMenu = not model.showMenu }, Effect.none )


subscriptions : UrlPath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : BackendTask FatalError Data
data =
    BackendTask.succeed ()


view :
    Data
    ->
        { path : UrlPath
        , route : Maybe Route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : List (Html msg), title : String }
view sharedData page model toMsg pageView =
    { body =
        [ Html.nav [ Attrs.class "flex place-items-end mx-auto px-4 py-3 justify-between max-w-xl" ]
            [ Html.h1 [ Attrs.class "text-3xl text-teal-600" ] [ Html.text "Mehdi Hassan" ]
            , Html.div [ Attrs.class "flex gap-x-8 text-xl font-sans *:hover:text-teal-600 text-white" ]
                [ Html.button [] [ Html.text "About" ]
                , Html.button [] [ Html.text "Blog" ]
                ]

            -- Html.button
            --     [ Html.Events.onClick MenuClicked ]
            --     [ Html.text
            --         (if model.showMenu then
            --             "Close Menu"
            --          else
            --             "Open Menu"
            --         )
            --     ]
            -- , if model.showMenu then
            --     Html.ul []
            --         [ Html.li [] [ Html.text "Menu item 1" ]
            --         , Html.li [] [ Html.text "Menu item 2" ]
            --         ]
            --   else
            --     Html.text ""
            ]
            |> Html.map toMsg
        , Html.main_ [] pageView.body
        ]
    , title = pageView.title
    }
