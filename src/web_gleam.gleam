import gleam/io
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/bit_string
import gleam/http/elli
import glenn/service.{
  Handler, Next, RequestResponse, build_service, get, logger, route,
  start_router, using, with_build_service, with_get, with_route, with_server,
  with_start_router, with_using,
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
  |> using(auth)
  |> get("/apa/bepa", hello_handler)
  |> build_service()
  |> elli.become(on_port: 3000)
}

fn hello_handler(
  request: Request(BitString),
  response: Response(BitBuilder),
  _next,
) -> RequestResponse {
  let body = bit_string.from_string(request.path)
  let response_body = bit_builder.from_bit_string(body)
  Response(..response, status: 200)
  |> response.set_body(response_body)
}

fn auth(_request: Request(BitString), response: Response(BitBuilder), _next) {
  let response_body = bit_builder.from_string("Unauthorized")
  response.new(401)
  |> response.set_body(response_body)
}

fn set_header(request: Request(BitString), response: Response(BitBuilder), next) {
  io.println("Setting header")
  let new_response =
    response
    |> response.prepend_header("made-with", "Glitch")
  next(request, new_response)
}
