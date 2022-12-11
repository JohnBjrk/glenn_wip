import gleam/io
import gleam/string
import gleam/http.{Get, Method, method_to_string, scheme_to_string}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list

pub type RequestResponse =
  Response(BitBuilder)

// #(Request(BitString), Response(BitBuilder))

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

fn chain(
  handler: Handler,
  next: fn(Request(BitString), Response(BitBuilder)) -> RequestResponse,
) -> Next {
  fn(req, res) { handler(req, res, next) }
}

fn end(_request: Request(BitString), response: Response(BitBuilder)) {
  io.println("Reached end")
  response
  // #(request, response)
}

fn continue(router: Router) -> Router {
  router
}

pub fn get(router: Router, path: String, handler: Handler) {
  with_get(path, handler, router, continue)
}

pub fn with_get(
  path: String,
  handler: Handler,
  router: Router,
  continue: Continue,
) {
  let get_route = Route(path, Get, handler)
  continue(Router(..router, routes: [get_route, ..router.routes]))
}

fn mk_handler(path: String, method: Method, handler) {
  io.println("Adding: " <> path)
  fn(req: Request(BitString), res, next) {
    io.println("Trying: " <> path)
    case req.method == method, path == req.path {
      True, True -> handler(req, res, next)
      _, _ -> next(req, res)
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
  with_route(path, sub_router, router, continue)
}

pub fn with_route(
  path: String,
  sub_router: Router,
  router: Router,
  continue: Continue,
) {
  let sub_route = SubRoute(path, sub_router)
  continue(Router(..router, routes: [sub_route, ..router.routes]))
}

pub fn using(router: Router, handler: Handler) {
  with_using(handler, router, continue)
}

pub fn with_using(handler: Handler, router: Router, continue: Continue) {
  let middleware = Middleware(handler)
  continue(Router(..router, routes: [middleware, ..router.routes]))
}

pub fn start_router(base: String) -> Router {
  with_start_router(base, continue)
}

pub fn with_start_router(base: String, continue: Continue) {
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
  with_build_service(router, fn(service) { service })
}

pub fn with_build_service(
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
