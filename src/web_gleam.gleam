import gleam/io
import gleam/map.{Map}
import gleam/http.{Get, Method}
import gleam/http/response.{Response}
import gleam/http/request.{Request}
import gleam/bit_builder.{BitBuilder}
import gleam/list
import gleam/http/elli

type RequestResponse =
  #(Request(BitString), Response(BitBuilder))

type Next =
  fn(Request(BitString), Response(BitBuilder)) -> RequestResponse

type Handler =
  fn(Request(BitString), Response(BitBuilder), Next) -> RequestResponse

type Router(t) {
  Router(base: String, routes: List(Route(t)))
}

type Route(t) {
  Route(url: String, handler: Handler)
}

fn chain(
  handler: Handler,
  next: fn(Request(BitString), Response(BitBuilder)) -> RequestResponse,
) -> Next {
  fn(req, res) { handler(req, res, next) }
}

fn end(request: Request(BitString), response: Response(BitBuilder)) {
  #(request, response)
}

fn get(path: String, handler: Handler, router: Router(t), continue) {
  let get_handler: Handler = fn(req: Request(BitString), res, next) {
    case req.method, path == req.path {
      Get, True -> handler(req, res, next)
      _, _ -> next(req, res)
    }
  }
  let get_route = Route(path, get_handler)
  continue(Router(..router, routes: [get_route, ..router.routes]))
}

fn start_router(base: String, continue) {
  continue(Router(base, []))
}

fn build_service(router: Router(t)) {
  let route_handler =
    router.routes
    |> list.fold(end, fn(next, route) { chain(route.handler, next) })
  fn(request: Request(BitString)) {
    let response =
      response.new(404)
      |> response.set_body(bit_builder.from_string("Not found"))
    assert #(_, res) = route_handler(request, response)
    res
  }
}

pub fn main() {
  use router <- start_router("apa")
  use router <- get("/hello/world", hello_handler, router)
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
  let response_new =
    response.new(200)
    |> response.set_body(response_body)
  next(request, response_new)
  // #(request, response_new)
}
