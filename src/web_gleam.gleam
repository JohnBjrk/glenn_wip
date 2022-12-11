import gleam/io
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/bit_string
import gleam/http/elli
import glenn/service.{
  Trail, build_service, get, logger, not_found, route, start_router, using,
}

pub fn main() {
  let sub =
    start_router("")
    |> using(auth)
    |> get("/sub", hello_handler)

  start_router("/api")
  |> using(logger)
  |> using(set_header)
  |> route("/ttt", sub)
  |> get("/hello/world", hello_handler)
  |> get("/{user}/details", hello_handler)
  // |> using(auth)
  |> get("/apa/bepa", hello_handler)
  |> using(not_found(fancy_404))
  |> build_service()
  |> elli.become(on_port: 3000)
}

fn hello_handler(trail: Trail, _next) -> Response(BitBuilder) {
  let body = bit_string.from_string(trail.request.path)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

fn auth(trail: Trail, _next) {
  let response_body = bit_builder.from_string("Unauthorized")
  response.new(401)
  |> response.set_body(response_body)
}

fn set_header(trail: Trail, next) {
  io.println("Setting header")
  let new_response =
    trail.response
    |> response.prepend_header("made-with", "Glitch")
  next(Trail(..trail, response: new_response))
}

fn fancy_404(trail: Trail) -> Response(BitBuilder) {
  let response_body =
    bit_builder.from_string("Cound not find resource: " <> trail.request.path)
  trail.response
  |> response.set_body(response_body)
}
