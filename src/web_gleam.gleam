import gleam/io
import gleam/string
import gleam/map.{Map}
import gleam/http.{Get, Method}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list
import gleam/http/elli

type RequestResponse =
  Response(BitBuilder)

// #(Request(BitString), Response(BitBuilder))

type Next =
  fn(Request(BitString), Response(BitBuilder)) -> RequestResponse

type Handler =
  fn(Request(BitString), Response(BitBuilder), Next) -> RequestResponse

type Router {
  Router(base: String, routes: List(Route))
}

type Route {
  Route(url: String, method: Method, handler: Handler)
  SubRoute(url: String, router: Router)
  Middleware(handler: Handler)
}

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

fn get(path: String, handler: Handler, router: Router, continue) {
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

fn subr(path: String, sub_router: Router, router: Router, continue) {
  let sub_route = SubRoute(path, sub_router)
  continue(Router(..router, routes: [sub_route, ..router.routes]))
}

fn using(handler: Handler, router: Router, continue) {
  let middleware = Middleware(handler)
  continue(Router(..router, routes: [middleware, ..router.routes]))
}

fn start_router(base: String, continue) {
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

fn build_service(router: Router) {
  let route_handler = build_route_handler(end, router.base, router.routes)
  fn(request: Request(BitString)) {
    let response =
      response.new(404)
      |> response.set_body(bit_builder.from_string("Not found"))
    // assert #(_, res) = route_handler(request, response)
    // res
    route_handler(request, response)
  }
}

pub fn main() {
  use sub <- start_router("")
  use sub <- using(auth, sub)
  use sub <- get("/sub", hello_handler, sub)

  use router <- start_router("/api")
  use router <- using(log, router)
  use router <- using(set_header, router)
  use router <- subr("/ttt", sub, router)
  use router <- get("/hello/world", hello_handler, router)
  use router <- using(auth, router)
  use router <- get("/apa/bepa", hello_handler, router)
  elli.become(build_service(router), on_port: 3000)
}

fn hello_handler(
  request: Request(BitString),
  response: Response(BitBuilder),
  next,
) -> RequestResponse {
  let body: BitString = request.body
  let response_body = bit_builder.from_bit_string(body)
  Response(..response, status: 200)
  |> response.set_body(response_body)
  // next(request, response_new)
}

fn auth(request: Request(BitString), response: Response(BitBuilder), next) {
  let response_body = bit_builder.from_string("Unauthorized")
  let response_new =
    response.new(401)
    |> response.set_body(response_body)
}

fn log(request: Request(BitString), response: Response(BitBuilder), next) {
  io.println(request.path)
  next(request, response)
}

fn set_header(request: Request(BitString), response: Response(BitBuilder), next) {
  io.println("Setting header")
  let new_response =
    response
    |> response.prepend_header("made-with", "Glitch")
  next(request, new_response)
}
// fn start() {
//   fn(request: Request(BitString), response: Response(BitBuilder)) { response }
// }

// fn get2(next: Next, path: String, handler: Handler) {
//   let h = fn(req: Request(BitString), res, next) {
//     case req.method, path == req.path {
//       Get, True -> handler(req, res, next)
//       _, _ -> next(req, res)
//     }
//   }
//   chain(h, next)
// }

// fn stop(next: Next) {
//   fn(req, res, next) { next(req, res) }
// }

// fn service(handler: Next) {
//   fn(request: Request(BitString)) {
//     let response =
//       response.new(404)
//       |> response.set_body(bit_builder.from_string("Not found"))
//     handler(request, response)
//   }
// }

// fn test() {
//   let sub_route =
//     start()
//     |> get2("/hej/hej", hello_handler)
//     |> get2("/test/hej", hello_handler)
//     |> stop()

//   let route =
//     start()
//     |> get2("/api", sub_route)
// }
