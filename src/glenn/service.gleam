import gleam/io
import gleam/string.{drop_left, drop_right, ends_with, starts_with}
import gleam/http.{
  Connect, Delete, Get, Head, Method, Options, Patch, Post, Put, Trace,
  method_to_string, scheme_to_string,
}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list.{filter_map}
import gleam/uri
import gleam/option.{None, Option, Some}

pub type Configuration {
  Configuration(match_trace: Bool)
}

pub const default = Configuration(False)

pub type Trail {
  Trail(
    request: Request(BitString),
    response: Response(BitBuilder),
    parameters: List(String),
  )
}

pub type Next =
  fn(Trail) -> Response(BitBuilder)

pub type Handler =
  fn(Trail, Next) -> Response(BitBuilder)

pub type Router {
  Router(base: String, routes: List(Route), configuration: Configuration)
}

pub type Route {
  Route(url: String, method: Method, handler: Handler)
  SubRoute(url: String, router: Router)
  Middleware(handler: Handler)
}

type Continue =
  fn(Router) -> Router

type Segment {
  PathParameter(name: String, value: String)
  FixedSegment(name: String)
  Wildcard(rest: List(String))
}

fn chain(handler: Handler, next: fn(Trail) -> Response(BitBuilder)) -> Next {
  fn(trail: Trail) { handler(trail, next) }
}

fn end(trail: Trail) {
  trail.response
}

pub fn get(router: Router, path: String, handler: Handler) {
  use router <- with_method(Get, path, handler, router)
  router
}

pub fn post(router: Router, path: String, handler: Handler) {
  use router <- with_method(Post, path, handler, router)
  router
}

pub fn put(router: Router, path: String, handler: Handler) {
  use router <- with_method(Put, path, handler, router)
  router
}

pub fn patch(router: Router, path: String, handler: Handler) {
  use router <- with_method(Patch, path, handler, router)
  router
}

pub fn options(router: Router, path: String, handler: Handler) {
  use router <- with_method(Options, path, handler, router)
  router
}

pub fn connect(router: Router, path: String, handler: Handler) {
  use router <- with_method(Connect, path, handler, router)
  router
}

pub fn trace(router: Router, path: String, handler: Handler) {
  use router <- with_method(Trace, path, handler, router)
  router
}

pub fn delete(router: Router, path: String, handler: Handler) {
  use router <- with_method(Delete, path, handler, router)
  router
}

pub fn head(router: Router, path: String, handler: Handler) {
  use router <- with_method(Head, path, handler, router)
  router
}

pub fn handler(method: Method, router: Router, path: String, handler: Handler) {
  use router <- with_method(method, path, handler, router)
  router
}

fn with_method(
  method: Method,
  path: String,
  handler: Handler,
  router: Router,
  continue: Continue,
) {
  let get_route = Route(path, method, handler)
  continue(Router(..router, routes: [get_route, ..router.routes]))
}

fn mk_handler(path: String, method: Method, handler) {
  io.println("Adding: " <> path)
  let path_segments = uri.path_segments(path)
  io.debug(path_segments)
  fn(trail: Trail, next) {
    io.println("Trying: " <> path)
    case
      trail.request.method == method,
      match_segments(path_segments, uri.path_segments(trail.request.path))
    {
      True, Some(parsed_segments) -> {
        io.debug(parsed_segments)
        let parameters =
          parsed_segments
          |> filter_map(fn(segment) {
            case segment {
              PathParameter(name, value) -> Ok(value)
              _ -> Error(Nil)
            }
          })
        handler(Trail(..trail, parameters: parameters), next)
      }
      _, _ -> next(trail)
    }
  }
}

fn match_segments(
  route_segments: List(String),
  request_segments: List(String),
) -> Option(List(Segment)) {
  io.println("Matching")
  io.debug(route_segments)
  io.debug(request_segments)
  case route_segments, request_segments {
    ["*"], remaining_request_segments ->
      Some([Wildcard(remaining_request_segments)])
    [first_router_segment, ..router_segments], [
      first_request_segment,
      ..request_segments
    ] ->
      case
        match_segment(first_router_segment, first_request_segment),
        match_segments(router_segments, request_segments)
      {
        Some(segment), Some(segments) -> Some([segment, ..segments])
        _, _ -> None
      }
    [last_router_segment], [last_request_segment] ->
      case match_segment(last_router_segment, last_request_segment) {
        Some(segment) -> Some([segment])
        None -> None
      }
    [], [] -> Some([])
    _, _ -> None
  }
  |> io.debug()
}

fn match_segment(router_segment, request_segment) -> Option(Segment) {
  case starts_with(router_segment, "{") && ends_with(router_segment, "}") {
    True -> {
      let name =
        router_segment
        |> drop_left(1)
        |> drop_right(1)
      Some(PathParameter(name, request_segment))
      |> io.debug()
    }
    False ->
      case router_segment == request_segment {
        True ->
          Some(FixedSegment(router_segment))
          |> io.debug()
        False -> None
      }
  }
}

fn mk_middleware(path: String, handler: Handler) {
  fn(trail: Trail, next) {
    case string.starts_with(trail.request.path, path) {
      True -> handler(trail, next)
      False -> next(trail)
    }
  }
}

pub fn route(router: Router, path: String, sub_router: Router) {
  use router <- with_route(path, sub_router, router)
  router
}

fn with_route(
  path: String,
  sub_router: Router,
  router: Router,
  continue: Continue,
) {
  let sub_route = SubRoute(path, sub_router)
  continue(Router(..router, routes: [sub_route, ..router.routes]))
}

pub fn using(router: Router, handler: Handler) {
  use router <- with_using(handler, router)
  router
}

fn with_using(handler: Handler, router: Router, continue: Continue) {
  let middleware = Middleware(handler)
  continue(Router(..router, routes: [middleware, ..router.routes]))
}

pub fn router(configuration: Configuration) -> Router {
  start_router_base(configuration)
}

pub fn start_router_config(configuration: Configuration) -> Router {
  router(configuration)
}

pub fn start_router_base(configuration: Configuration) -> Router {
  use router <- with_start_router("", configuration)
  router
}

fn with_start_router(
  base: String,
  configuration: Configuration,
  continue: Continue,
) {
  continue(Router(base, [], configuration))
}

fn build_route_handler(next: Next, context: String, routes: List(Route)) {
  routes
  |> list.fold(
    next,
    fn(next, route) {
      case route {
        Route(path, method, handler) ->
          mk_handler("/" <> context <> "/" <> path, method, handler)
          |> chain(next)
        SubRoute(path, router) ->
          build_route_handler(
            next,
            "/" <> context <> "/" <> path,
            router.routes,
          )
        Middleware(handler) ->
          mk_middleware(context, handler)
          |> chain(next)
      }
    },
  )
}

pub fn build_service(router: Router) {
  use service <- with_build_service(router)
  service
}

fn with_build_service(
  router: Router,
  continue,
) -> fn(Request(BitString)) -> Response(BitBuilder) {
  let route_handler = build_route_handler(end, router.base, router.routes)
  continue(fn(request: Request(BitString)) {
    let response =
      response.new(404)
      |> response.set_body(bit_builder.from_string("Not found"))
    route_handler(Trail(request, response, []))
  })
}

pub fn with_server(server, service, continue) {
  server(service)
  continue()
}

pub fn logger(trail: Trail, next) {
  io.println(
    string.uppercase(method_to_string(trail.request.method)) <> ": " <> scheme_to_string(
      trail.request.scheme,
    ) <> ":" <> trail.request.host <> trail.request.path,
  )
  next(trail)
}

pub fn not_found(handler: fn(Trail) -> Response(BitBuilder)) {
  error_handler(404, handler)
}

pub fn error_handler(status: Int, handler: fn(Trail) -> Response(BitBuilder)) {
  fn(trail: Trail, next) {
    let new_response = case trail.response.status == status {
      True -> handler(trail)
      _ -> trail.response
    }
    next(Trail(..trail, response: new_response))
  }
}
