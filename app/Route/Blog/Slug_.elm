module Route.Blog.Slug_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Glob as Glob exposing (Glob)
import Date exposing (Date)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attrs
import Json.Decode as Decode exposing (Decoder)
import Markdown.Parser
import Markdown.Renderer
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    Glob.succeed RouteParams
        |> Glob.match (Glob.literal "content/blog/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toBackendTask


type alias Data =
    { title : String
    , published : Date
    , body : String
    }


type alias ActionData =
    {}


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.File.bodyWithFrontmatter
        (\markdownString ->
            Decode.map3
                (\title published body -> Data title published body)
                (Decode.field "title" Decode.string)
                (Decode.field "published" Decode.string
                    |> Decode.andThen
                        (\isoString ->
                            case Date.fromIsoString isoString of
                                Ok date ->
                                    Decode.succeed date

                                Err err ->
                                    Decode.fail err
                        )
                )
                (Decode.succeed markdownString)
        )
        ("content/blog/" ++ routeParams.slug ++ ".md")
        |> BackendTask.allowFatal



-- BackendTask.succeed {}


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app sharedModel =
    { title = app.data.title
    , body =
        [ View.freeze
            (Html.div []
                [ Html.main_ [ Attrs.class "prose prose-stone md:prose-lg lag:prose-xl lg:max-w-3xl prose-invert mx-auto mt-5" ]
                    (app.data.body
                        |> Markdown.Parser.parse
                        |> Result.mapError
                            (\deadEnds ->
                                deadEnds
                                    |> List.map Markdown.Parser.deadEndToString
                                    |> String.join "\n"
                            )
                        |> Result.andThen
                            (\ast ->
                                Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer ast
                            )
                        |> Result.withDefault []
                    )
                ]
            )
        ]
    }


type alias BlogpostMetadata =
    { title : String
    , published : Date
    }


frontmatterDecoder : Decoder BlogpostMetadata
frontmatterDecoder =
    Decode.map2 BlogpostMetadata
        (Decode.field "title" Decode.string)
        (Decode.field "published"
            Decode.string
            |> Decode.andThen
                (\isoString ->
                    case Date.fromIsoString isoString of
                        Ok date ->
                            Decode.succeed date

                        Err err ->
                            Decode.fail err
                )
        )
