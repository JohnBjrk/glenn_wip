import gleam/io
import gleam/string.{drop_left, drop_right, ends_with, starts_with}
import gleam/http.{Get, Method, method_to_string, scheme_to_string}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list
import gleam/uri
import gleam/option.{None, Option, Some}

pub type RequestResponse =
  Response(BitBuilder)

pub type Next =
  fn(Request(BitString), Response(BitBuilder)) -> RequestResponse

pub type Handler =
  fn(Request(BitString), Response(BitBuilder), Next) -> RequestResponse

pub type Router {
  Router(base: String, routes: List(Route))
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
}

fn chain(
  handler: Handler,
  next: fn(Request(BitString), Response(BitBuilder)) -> RequestResponse,
) -> Next {
  fn(req, res) { handler(req, res, next) }
}

fn end(_request: Request(BitString), response: Response(BitBuilder)) {
  response
}

pub fn get(router: Router, path: String, handler: Handler) {
  use router <- with_get(path, handler, router)
  router
}

fn with_get(path: String, handler: Handler, router: Router, continue: Continue) {
  let get_route = Route(path, Get, handler)
  continue(Router(..router, routes: [get_route, ..router.routes]))
}

fn mk_handler(path: String, method: Method, handler) {
  io.println("Adding: " <> path)
  let path_segments = uri.path_segments(path)
  io.debug(path_segments)
  fn(req: Request(BitString), res, next) {
    io.println("Trying: " <> path)
    case
      req.method == method,
      match_segments(path_segments, uri.path_segments(req.path))
    {
      True, Some(parsed_segments) -> {
        io.debug(parsed_segments)
        handler(req, res, next)
      }
      _, _ -> next(req, res)
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
  fn(req: Request(BitString), res, next) {
    case string.starts_with(req.path, path) {
      True -> handler(req, res, next)
      False -> next(req, res)
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

pub fn start_router(base: String) -> Router {
  use router <- with_start_router(base)
  router
}

fn with_start_router(base: String, continue: Continue) {
  continue(Router(base, []))
}

fn build_route_handler(next: Next, context: String, routes: List(Route)) {
  routes
  |> list.fold(
    next,
    fn(next, route) {
      case route {
        Route(path, method, handler) ->
          mk_handler(context <> path, method, handler)
          |> chain(next)
        SubRoute(path, router) ->
          build_route_handler(next, context <> path, router.routes)
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
    route_handler(request, response)
  })
}

pub fn with_server(server, service, continue) {
  server(service)
  continue()
}

pub fn logger(request: Request(BitString), response: Response(BitBuilder), next) {
  io.println(
    string.uppercase(method_to_string(request.method)) <> ": " <> scheme_to_string(
      request.scheme,
    ) <> ":" <> request.host <> request.path,
  )
  next(request, response)
}

pub fn not_found(
  handler: fn(Request(BitString), Response(BitBuilder)) -> Response(BitBuilder),
) {
  error_handler(404, handler)
}

pub fn error_handler(
  status: Int,
  handler: fn(Request(BitString), Response(BitBuilder)) -> Response(BitBuilder),
) {
  fn(request: Request(BitString), response: Response(BitBuilder), next) {
    let new_response = case response.status == status {
      True -> handler(request, response)
      _ -> response
    }
    next(request, new_response)
  }
}