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
  Router(base: String, routes: Map(Method, List(Route(t))))
}

type Route(t) {
  Route(url: String, handler: fn(Request(t)) -> Response(BitBuilder))
}

fn chain_handlers(
  req: Request(BitString),
  resp: Response(BitBuilder),
  a: Handler,
  b: Handler,
) {
  let first = chain(a, end)
  let second = chain(b, first)
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

fn start_router(base: String, continue) {
  continue(Router(base, map.new()))
}

fn route(route: Route(t), router: Router(t), continue) {
  let routes = case map.get(router.routes, Get) {
    Ok(routes) -> routes
    _ -> []
  }
  continue(
    Router(..router, routes: map.insert(router.routes, Get, [route, ..routes])),
  )
}

fn service(router: Router(t)) {
  router
  |> io.debug()
  fn(req: Request(t)) -> Response(BitBuilder) {
    let routes =
      router.routes
      |> map.get(req.method)
    case routes {
      Ok(route_list) -> match_route(req, route_list)
      _ ->
        response.new(404)
        |> response.set_body(bit_builder.from_string(""))
    }
  }
}

fn match_route(
  req: Request(t),
  route_list: List(Route(t)),
) -> Response(BitBuilder) {
  let route =
    route_list
    |> list.find(fn(route) { route.url == req.path })
  case route {
    Ok(route) -> route.handler(req)
    _ ->
      response.new(404)
      |> response.set_body(bit_builder.from_string(""))
  }
}

pub fn main() {
  use router <- start_router("testj")
  use router <- route(Route("/hello/world", hello_handler), router)
  use router <- route(Route("/apa/bepa", hello_handler), router)
  elli.become(service(router), on_port: 3000)
}

fn hello_handler(request: Request(BitString)) -> Response(BitBuilder) {
  let body: BitString = request.body
  let response_body = bit_builder.from_bit_string(body)
  response.new(200)
  |> response.set_body(response_body)
}

fn bepa_handler(request: Request(Int)) -> Response(BitBuilder) {
  let body: Int = request.body
  let response_body = bit_builder.from_string("Bepa")
  response.new(200)
  |> response.set_body(response_body)
}
