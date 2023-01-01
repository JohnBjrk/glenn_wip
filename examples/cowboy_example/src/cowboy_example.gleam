import gleam/io
import gleam/http/response.{Response}
import gleam/bit_builder.{BitBuilder}
import gleam/bit_string
import gleam/list.{find_map}
import gleam/http/cowboy
import gleam/erlang/process
import glenn.{
  Trail, build_service, default, get, logger, not_found, route, router, using,
}

pub fn main() {
  let sub =
    router(default)
    |> get("/run", echo_path_handler)

  let secret =
    router(default)
    |> using(auth)
    |> get("/handshake", echo_path_handler)

  let api =
    router(default)
    |> using(logger)
    |> using(set_header)
    |> route("/gleam", sub)
    |> get("/hello/world", echo_path_handler)
    |> get("/hello/wild/*", echo_path_handler)
    |> get("/users/{user}/details", user_handler)
    |> route("/secret", secret)
    |> using(not_found(fancy_404))

  router(default)
  |> route("/api", api)
  |> build_service()
  |> cowboy.start(on_port: 3000)
  process.sleep_forever()
}

fn echo_path_handler(trail: Trail, _next) -> Response(BitBuilder) {
  let body = bit_string.from_string(trail.request.path)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

fn user_handler(trail: Trail, _next) -> Response(BitBuilder) {
  assert [user] = trail.parameters
  let body = bit_string.from_string("Hello: " <> user)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

fn auth(trail: Trail, next) {
  let password =
    trail.request.headers
    |> find_map(fn(header) {
      case header {
        #("x-supersecret-header", password) -> Ok(password)
        _ -> Error(Nil)
      }
    })
  case password {
    Ok("neverimplementauthlikethis") -> next(trail)
    _ -> {
      let response_body = bit_builder.from_string("Unauthorized")
      Response(..trail.response, status: 401)
      |> response.set_body(response_body)
    }
  }
}

fn set_header(trail: Trail, next) {
  io.println("Setting header")
  let new_response =
    trail.response
    |> response.prepend_header("made-with", "glenn")
  next(Trail(..trail, response: new_response))
}

fn fancy_404(trail: Trail) -> Response(BitBuilder) {
  let response_body =
    bit_builder.from_string("Cound not find resource: " <> trail.request.path)
  trail.response
  |> response.set_body(response_body)
}
