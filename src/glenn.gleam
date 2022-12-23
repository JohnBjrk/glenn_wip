//// Glenn is a module for building http routes. The routes are constructed with a fluent (builder) api which maps
//// [handler](#Handler) functions to specific paths/methods. Routes can be constructed in a modular fashion which
//// makes it easy to construct different subroutes separately.
//// The final router can then be converted into a standard [Gleam HTTP](https://github.com/gleam-lang/http) service
//// which can be used together with a server adapter of choice.

import gleam/io
import gleam/string.{drop_left, drop_right, ends_with, join, starts_with}
import gleam/http.{
  Connect, Delete, Get, Head, Method, Options, Patch, Post, Put, Trace,
  method_to_string, scheme_to_string,
}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list.{filter_map, fold, map}
import gleam/uri
import glogg.{Logger, anonymous_direct_logger, info, trace as tracing, warning}

/// Configuration type
pub type Configuration {
  ConfigurationInstance(logger: Logger)
  Inherit
}

pub const default = ConfigurationInstance(anonymous_direct_logger)

/// A type holding the state of a request as it is being handled by the router.
/// This state holds the incoming request and the current response (which might 
/// have been manipulated by any handler/middleware). Futhermore it also holds any
/// path-parameters that was found when matching the current route as well as a
/// list of failed routes that can be used for more granular reporting.
pub type Trail(state) {
  Trail(
    request: Request(BitString),
    response: Response(BitBuilder),
    parameters: List(String),
    failed_routes: List(List(Segment)),
    state: state,
  )
}

/// The next function which should be called by a handler in order to continue processing the current [Trail](#Trail)
pub type Next(state) =
  fn(Trail(state)) -> Response(BitBuilder)

/// The function signature of a handler. Handlers are attached to a router either as handlers for a specific path/method or
/// as a middleware (see [using](#using)).
/// The handler can process both the request and the response and then either return a response or call the [next](#Next) function
/// with the updated [trail](#Trail).
/// Usually a handler for a path/method will want to terminate the route by returning an updated whereas a middleware will call
/// the [next](#Next) function in order to continue processing the current [trail](#Trail). This is however not a firm rule.
pub type Handler(state) =
  fn(Trail(state), Next(state)) -> Response(BitBuilder)

/// The Router type holds all routes, subroutes and middlewares when constructing a service.
pub opaque type Router(state) {
  Router(
    base: String,
    routes: List(Route(state)),
    configuration: Configuration,
    initial_state: state,
  )
}

type Route(state) {
  Route(url: String, method: Method, handler: Handler(state))
  SubRoute(url: String, router: Router(state))
  Middleware(handler: Handler(state))
}

type Continue(state) =
  fn(Router(state)) -> Router(state)

pub type Segment {
  PathParameter(name: String, value: String)
  FixedSegment(name: String)
  Wildcard(rest: List(String))
  Mismatch(expected: String, got: String)
}

fn chain(
  handler: Handler(state),
  next: fn(Trail(state)) -> Response(BitBuilder),
) -> Next(state) {
  fn(trail: Trail(state)) { handler(trail, next) }
}

fn end(trail: Trail(state)) {
  trail.response
}

pub fn get(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Get, path, handler, router)
  router
}

pub fn post(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Post, path, handler, router)
  router
}

pub fn put(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Put, path, handler, router)
  router
}

pub fn patch(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Patch, path, handler, router)
  router
}

pub fn options(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Options, path, handler, router)
  router
}

pub fn connect(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Connect, path, handler, router)
  router
}

pub fn trace(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Trace, path, handler, router)
  router
}

pub fn delete(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Delete, path, handler, router)
  router
}

pub fn head(router: Router(state), path: String, handler: Handler(state)) {
  use router <- with_method(Head, path, handler, router)
  router
}

pub fn handler(
  method: Method,
  router: Router(state),
  path: String,
  handler: Handler(state),
) {
  use router <- with_method(method, path, handler, router)
  router
}

fn with_method(
  method: Method,
  path: String,
  handler: Handler(state),
  router: Router(state),
  continue: Continue(state),
) {
  let get_route = Route(path, method, handler)
  continue(Router(..router, routes: [get_route, ..router.routes]))
}

fn mk_handler(
  configuration: Configuration,
  path: String,
  method: Method,
  handler,
) {
  assert ConfigurationInstance(logger) = configuration
  let path_segments = uri.path_segments(path)
  logger
  |> tracing("Adding: " <> join(path_segments, "/"))
  fn(trail: Trail(state), next) {
    logger
    |> info("Trying: " <> join(path_segments, "/"))
    case
      trail.request.method == method,
      match_segments(path_segments, uri.path_segments(trail.request.path))
    {
      True, Ok(parsed_segments) -> {
        io.debug(parsed_segments)
        let parameters =
          parsed_segments
          |> filter_map(fn(segment) {
            case segment {
              PathParameter(_name, value) -> Ok(value)
              _ -> Error(Nil)
            }
          })
        handler(Trail(..trail, parameters: parameters), next)
      }
      _, Error(segments) -> {
        segments
        let new_trail =
          Trail(..trail, failed_routes: [segments, ..trail.failed_routes])
        next(new_trail)
      }
    }
  }
}

fn match_segments(
  route_segments: List(String),
  request_segments: List(String),
) -> Result(List(Segment), List(Segment)) {
  case route_segments, request_segments {
    ["*"], remaining_request_segments ->
      Ok([Wildcard(remaining_request_segments)])
    [first_router_segment, ..router_segments], [
      first_request_segment,
      ..request_segments
    ] ->
      case
        match_segment(first_router_segment, first_request_segment),
        match_segments(router_segments, request_segments)
      {
        Ok(segment), Ok(segments) -> Ok([segment, ..segments])
        Ok(segment), Error(segments) -> Error([segment, ..segments])
        Error(segment), Ok(segments) -> Error([segment, ..segments])
        Error(segment), Error(segments) -> Error([segment, ..segments])
      }
    [last_router_segment], [last_request_segment] ->
      case match_segment(last_router_segment, last_request_segment) {
        Ok(segment) -> Ok([segment])
        Error(segment) -> Error([segment])
      }
    [], [] -> Ok([])
    _, _ -> Error([])
  }
}

fn match_segment(router_segment, request_segment) -> Result(Segment, Segment) {
  case starts_with(router_segment, "{") && ends_with(router_segment, "}") {
    True -> {
      let name =
        router_segment
        |> drop_left(1)
        |> drop_right(1)
      Ok(PathParameter(name, request_segment))
    }
    False ->
      case router_segment == request_segment {
        True -> Ok(FixedSegment(router_segment))
        False -> Error(Mismatch(router_segment, request_segment))
      }
  }
}

fn mk_middleware(
  configuration: Configuration,
  path: String,
  handler: Handler(state),
) {
  assert ConfigurationInstance(logger) = configuration
  let path_segments = uri.path_segments(path)
  fn(trail: Trail(state), next) {
    logger
    |> info("Trying " <> path)
    case
      match_segments(path_segments, uri.path_segments(trail.request.path))
      |> io.debug()
    {
      Ok(_) -> handler(trail, next)
      _ -> next(trail)
    }
  }
}

pub fn route(router: Router(state), path: String, sub_router: Router(state)) {
  use router <- with_route(path, sub_router, router)
  router
}

fn with_route(
  path: String,
  sub_router: Router(state),
  router: Router(state),
  continue: Continue(state),
) {
  let sub_route = SubRoute(path, sub_router)
  continue(Router(..router, routes: [sub_route, ..router.routes]))
}

pub fn using(router: Router(state), handler: Handler(state)) {
  use router <- with_using(handler, router)
  router
}

fn with_using(
  handler: Handler(state),
  router: Router(state),
  continue: Continue(state),
) {
  let middleware = Middleware(handler)
  continue(Router(..router, routes: [middleware, ..router.routes]))
}

pub fn router(configuration: Configuration) -> Router(Nil) {
  Router("", [], configuration, Nil)
}

pub fn router_with_state(
  configuration: Configuration,
  state: state,
) -> Router(state) {
  Router("", [], configuration, state)
}

fn build_route_handler(
  next: Next(state),
  configuration: Configuration,
  context: String,
  routes: List(Route(state)),
) {
  routes
  |> list.fold(
    next,
    fn(next, route) {
      case route {
        Route(path, method, handler) ->
          mk_handler(
            configuration,
            "/" <> context <> "/" <> path,
            method,
            handler,
          )
          |> chain(next)
        SubRoute(path, router) -> {
          let sub_configuration = case router.configuration {
            ConfigurationInstance(_) -> router.configuration
            Inherit -> configuration
          }
          build_route_handler(
            next,
            sub_configuration,
            "/" <> context <> "/" <> path,
            router.routes,
          )
        }
        Middleware(handler) ->
          mk_middleware(configuration, context <> "/*", handler)
          |> chain(next)
      }
    },
  )
}

pub fn build_service(router: Router(state)) {
  assert ConfigurationInstance(logger) = router.configuration
  logger
  |> info("Building Service")
  let route_handler =
    build_route_handler(end, router.configuration, router.base, router.routes)
  fn(request: Request(BitString)) {
    let response =
      response.new(404)
      |> response.set_body(bit_builder.from_string("Not found"))
    route_handler(Trail(request, response, [], [], router.initial_state))
  }
}

pub fn with_server(server, service, continue) {
  server(service)
  continue()
}

pub fn logger(trail: Trail(state), next) {
  io.println(
    string.uppercase(method_to_string(trail.request.method)) <> ": " <> scheme_to_string(
      trail.request.scheme,
    ) <> ":" <> trail.request.host <> trail.request.path,
  )
  next(trail)
}

pub fn not_found(handler: fn(Trail(state)) -> Response(BitBuilder)) {
  error_handler(404, handler)
}

pub fn not_found_trace(trail: Trail(state), next: Next(state)) {
  let new_response = case trail.response.status == 404 {
    True -> {
      let response_str =
        trail.failed_routes
        |> map(fn(failed_route) {
          failed_route
          |> fold(
            "",
            fn(resp, segment) {
              case segment {
                FixedSegment(name) -> {
                  resp <> "/"
                  name
                }
                PathParameter(name, value) -> {
                  resp <> "/"
                  name <> ":"
                  value
                }
                Wildcard(_) -> resp <> "/*"
                Mismatch(expected, got) ->
                  resp <> "/" <> got <> "<-- Expected '" <> expected <> "' here"
              }
            },
          )
        })
        |> string.join("\n")
      trail.response
      |> response.set_body(bit_builder.from_string(response_str))
    }
    _ -> trail.response
  }
  next(Trail(..trail, response: new_response))
}

pub fn error_handler(
  status: Int,
  handler: fn(Trail(state)) -> Response(BitBuilder),
) {
  fn(trail: Trail(state), next) {
    let new_response = case trail.response.status == status {
      True -> handler(trail)
      _ -> trail.response
    }
    next(Trail(..trail, response: new_response))
  }
}
