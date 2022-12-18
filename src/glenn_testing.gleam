import gleam/bit_builder.{BitBuilder, from_bit_string, to_bit_string}
import gleam/bit_string.{from_string, to_string}
import gleam/string.{join}
import gleam/http/response.{Response}
import gleam/http/request.{from_uri, set_body}
import gleam/uri
import glenn.{Trail}

pub fn path_echo(trail: Trail, _next) -> Response(BitBuilder) {
  let body = bit_string.from_string(trail.request.path)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

pub fn body_echo(trail: Trail, _next) -> Response(BitBuilder) {
  let body =
    trail.request.body
    |> from_bit_string()
  Response(..trail.response, status: 200)
  |> response.set_body(body)
}

pub fn parameters_echo(trail: Trail, _next) -> Response(BitBuilder) {
  let body =
    trail.parameters
    |> join(":")
    |> from_string()
    |> from_bit_string()
  Response(..trail.response, status: 200)
  |> response.set_body(body)
}

pub fn never(trail: Trail, _next) -> Response(BitBuilder) {
  assert 0 = 1
  let body = bit_string.from_string("never")
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

pub fn fixed_body_response(body: String) {
  fn(trail: Trail, _next) {
    let body = bit_string.from_string(body)
    let response_body = bit_builder.from_bit_string(body)
    Response(..trail.response, status: 200)
    |> response.set_body(response_body)
  }
}

pub fn mk_request(url: String, body: String) {
  assert Ok(uri) =
    url
    |> uri.parse()
  assert Ok(request) =
    uri
    |> from_uri()
  request
  |> set_body(from_string(body))
}

pub fn get_body(response: Response(BitBuilder)) -> String {
  assert Ok(body) =
    response.body
    |> to_bit_string()
    |> to_string()
  body
}
