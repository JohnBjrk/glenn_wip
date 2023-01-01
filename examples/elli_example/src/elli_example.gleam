import gleam/io
import gleam/http/response.{Response}
import gleam/bit_builder.{BitBuilder}
import gleam/bit_string
import gleam/list.{find_map}
import gleam/option.{None}
import gleam/json.{object, string}
import gleam/http.{method_to_string}
import gleam/http/request.{Request}
import gleam/http/elli
import glenn.{
  ConfigurationInstance, Next, Trail, add_request_logger, build_service, default,
  get, not_found, request_serializer, route, router, using,
}
import glimt.{Direct, append_instance, new}
import glimt/log_message.{INFO, TRACE, level_value}
import glimt/dispatcher/stdout.{dispatcher}
import glimt/serializer/json.{add_data,
  add_standard_log_message, build, builder} as glimt_json
import glimt/serializer/basic.{basic_serializer}

pub fn main() {
  let logger =
    new("elli_example")
    |> append_instance(Direct(
      None,
      level_value(TRACE),
      dispatcher(
        builder()
        |> add_standard_log_message()
        |> add_data(request_serializer)
        |> build(),
      ),
    ))
  let sub =
    router(default)
    |> get("/run", echo_path_handler)

  let secret =
    router(default)
    |> using(auth)
    |> get("/handshake", echo_path_handler)

  let api =
    router(default)
    |> using(add_request_logger(logger, TRACE))
    |> using(set_header)
    |> route("/gleam", sub)
    |> get("/hello/world", echo_path_handler)
    |> get("/hello/wild/*", echo_path_handler)
    |> get("/users/{user}/details", user_handler)
    |> route("/secret", secret)
    |> using(not_found(fancy_404))

  router(ConfigurationInstance(INFO))
  |> route("/api", api)
  |> build_service()
  |> elli.become(on_port: 3000)
}

fn echo_path_handler(trail: Trail(state), _next) -> Response(BitBuilder) {
  let body = bit_string.from_string(trail.request.path)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

fn user_handler(trail: Trail(state), _next) -> Response(BitBuilder) {
  assert [user] = trail.parameters
  let body = bit_string.from_string("Hello: " <> user)
  let response_body = bit_builder.from_bit_string(body)
  Response(..trail.response, status: 200)
  |> response.set_body(response_body)
}

fn auth(trail: Trail(state), next: Next(state)) {
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

fn set_header(trail: Trail(state), next) {
  io.println("Setting header")
  let new_response =
    trail.response
    |> response.prepend_header("made-with", "glenn")
  next(Trail(..trail, response: new_response))
}

fn fancy_404(trail: Trail(state)) -> Response(BitBuilder) {
  let response_body =
    bit_builder.from_string("Cound not find resource: " <> trail.request.path)
  trail.response
  |> response.set_body(response_body)
}
