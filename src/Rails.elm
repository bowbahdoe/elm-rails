module Rails exposing (Error(..), get, post, send, always, decoder, csrfToken, request, expectRailsJson)

{-|

## Requests
@docs Error, get, post, send, request

## Decoding
@docs decoder, always

## Customizing
@docs csrfToken, expectRailsJson

-}

import Http exposing (Request, Response, Body, Expect, Header)
import Time exposing (Time)
import Json.Decode exposing (Decoder, decodeString)
import Result exposing (Result)
import String
import Native.Rails


-- Http


{-| The kinds of errors a Rails server may return.
-}
type Error error
    = HttpError Http.Error
    | RailsError error


{-| Utility for working with Rails. Wraps Http.send, passing an Authenticity Token along with the type of request. Suitable for use with `fromJson`:
    import Dict
    import Json.Decode (list, string)
    import Json.Encode as Encode
    import Http
    hats : HatStyle -> Task (Error (List String)) (List String)
    hats style =
      let
        payload =
          Encode.object
            [ ( "style", encodeHatStyle style ) ]
        body =
          Http.string (Encode.encode 0 payload)
        success =
          list string
        failure =
          Dict.fromList [ ("style", HatStyle) ]
            |> Rails.Decode.errors
      in
        send "POST" url body
          |> fromJson (decoder success failure)
-}
send : (Result (Error error) success -> msg) -> Request (Result error success) -> Cmd msg
send toMsg req =
    let
        newToMsg result =
            case result of
                Err err ->
                    toMsg (Err (HttpError err))

                Ok (Err railsError) ->
                    toMsg (Err (RailsError railsError))

                Ok (Ok success) ->
                    toMsg (Ok success)
    in
        Http.send newToMsg req


{-| Send a GET request to the given URL. You also specify how to decode the response.

    import Json.Decode (list, string)

    hats : Task (Error (List String)) (List String)
    hats =
      get (decoder (list string) (succeed ())) "http://example.com/hat-categories.json"

-}
get : String -> ResponseDecoder error success -> Request (Result error success)
get url responseDecoder =
    request
        { method = "GET"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , expect = expectRailsJson responseDecoder
        , timeout = Nothing
        , withCredentials = False
        }


{-| Send a POST request to the given URL. You also specify how to decode the response.

    import Json.Decode (list, string)
    import Http

    hats : Task (Error (List String)) (List String)
    hats =
      post (decoder (list string) (succeed ())) "http://example.com/hat-categories.json" Http.empty

-}
post : String -> Http.Body -> ResponseDecoder error success -> Request (Result error success)
post url body responseDecoder =
    request
        { method = "POST"
        , headers = []
        , url = url
        , body = body
        , expect = expectRailsJson responseDecoder
        , timeout = Nothing
        , withCredentials = False
        }


{-| Wraps `Http.request` while adding the following default headers:

* `X-CSRF-Token` - set to `csrfToken` if it's an `Ok` and this request isn't a `GET`
* `Accept` - `"application/json, text/javascript, */*; q=0.01"`
* `X-Requested-With` - `"XMLHttpRequest"`

    import Dict
    import Json.Decode (list, string)
    import Json.Encode as Encode
    import Http

    hats : HatStyle -> Task (Error (List String)) (List String)
    hats style =

      let
        payload =
          Encode.object
            [ ( "style", encodeHatStyle style ) ]

        body =
          Http.string (Encode.encode 0 payload)

        success =
          list string

        failure =
          Dict.fromList [ ("style", HatStyle) ]
            |> Rails.Decode.errors
      in
        send "POST" url body
          |> fromJson (decoder success failure)
-}
request :
    { method : String
    , headers : List Header
    , url : String
    , body : Body
    , expect : Expect a
    , timeout : Maybe Time
    , withCredentials : Bool
    }
    -> Request a
request options =
    let
        csrfTokenHeaders =
            if (String.toUpper options.method) == "GET" then
                []
            else
                case csrfToken of
                    Err _ ->
                        []

                    Ok csrfTokenString ->
                        [ Http.header "X-CSRF-Token" csrfTokenString ]

        headers =
            List.concat
                [ defaultRequestHeaders
                , csrfTokenHeaders
                , options.headers
                ]
    in
        Http.request { options | headers = headers }


defaultRequestHeaders : List Header
defaultRequestHeaders =
    [ Http.header "Accept" "application/json, text/javascript, */*; q=0.01"
    , Http.header "X-Requested-With" "XMLHttpRequest"
    ]


{-| JSON Decoders for parsing an HTTP response body.
-}
type alias ResponseDecoder error success =
    { success : Decoder success
    , failure : Decoder error
    }


{-| Returns a decoder suitable for passing to `fromJson`, which uses the same decoder for both success and failure responses.
-}
always : Decoder success -> ResponseDecoder success success
always decoder =
    ResponseDecoder decoder decoder


{-| Returns a decoder suitable for passing to `fromJson`.
-}
decoder : Decoder success -> Decoder error -> ResponseDecoder error success
decoder successDecoder failureDecoder =
    ResponseDecoder successDecoder failureDecoder


{-| If there was a `<meta name="csrf-token">` tag in the page's `<head>` when
    elm-rails loaded, returns the value its `content` attribute had at that time.

    Rails expects this value in the `X-CSRF-Token` header for non-`GET` requests as
    a [CSRF countermeasure](http://guides.rubyonrails.org/security.html#csrf-countermeasures).
-}
csrfToken : Result String String
csrfToken =
    Native.Rails.csrfToken


{-| Think `Http.fromJson`, but with additional effort to parse a non-20x response as JSON.

  * If the status code is in the 200 range, try to parse with the given `decoder.success`.
  * If that succeeds, the result is `Ok` with the result.
  * If the status code is outside the 200 range, try to parse with the given `decoder.failure`.
  * If that succeeds, the result is `Err` with the result.
  * If either parsing fails, the request as a whole fails.
-}
expectRailsJson : ResponseDecoder error success -> Expect (Result error success)
expectRailsJson responseDecoder =
    let
        fromResponse : Response String -> Result String (Result error success)
        fromResponse { status, body } =
            if status.code >= 200 && status.code < 300 then
                Json.Decode.decodeString responseDecoder.success body
                    |> Result.map Ok
            else
                Json.Decode.decodeString responseDecoder.failure body
                    |> Result.map Err
    in
        Http.expectStringResponse fromResponse
