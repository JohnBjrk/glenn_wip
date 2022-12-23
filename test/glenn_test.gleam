import gleeunit
import gleeunit/should
import gleam/bit_builder.{BitBuilder, from_string}
import gleam/string.{join}
import gleam/http/request
import gleam/http/response.{Response}
import gleam/http.{Patch}
import glenn.{
  Trail, build_service, default, get, logger, not_found, not_found_trace, patch,
  route, router, router_with_state, using,
}
import glenn_testing.{
  fixed_body_response, get_body, mk_request, never, parameters_echo, path_echo,
}

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn one_wildcard_test() {
  let sut =
    router(default)
    |> get("a/b/*", path_echo)
    |> build_service()
  let response = sut(mk_request("https://base.test/a/b/c/d", ""))
  response
  |> get_body()
  |> should.equal("/a/b/c/d")
}

pub fn wildcard_before_test() {
  let sut =
    router(default)
    |> get("a/b/*", path_echo)
    |> get("a/b/c/d", never)
    |> build_service()
  let response = sut(mk_request("https://base.test/a/b/c/d", ""))
  response
  |> get_body()
  |> should.equal("/a/b/c/d")
}

pub fn wildcard_after_test() {
  let sut =
    router(default)
    |> get("a/b", path_echo)
    |> get("a/b/*", never)
    |> build_service()
  let response = sut(mk_request("https://base.test/a/b", ""))
  response
  |> get_body()
  |> should.equal("/a/b")
}

pub fn subroute_test() {
  let sub_router =
    router(default)
    |> get("sub1", path_echo)
  let sut =
    router(default)
    |> route("sub", sub_router)
    |> build_service()
  let response = sut(mk_request("https://base.test/sub/sub1", ""))
  response
  |> get_body()
  |> should.equal("/sub/sub1")
}

pub fn parameters_test() {
  let sut =
    router(default)
    |> get("api/users/{userid}/details/{name}", parameters_echo)
    |> build_service()
  let response =
    sut(mk_request("https://base.test/api/users/123/details/glenn", ""))
  response
  |> get_body()
  |> should.equal("123:glenn")
}

pub fn not_found_trace_test() {
  let sub_router =
    router(default)
    |> get("sub1", path_echo)
    |> get("sub3", path_echo)
  let sut =
    router(default)
    |> route("sub", sub_router)
    |> using(not_found_trace)
    |> build_service()
  let response = sut(mk_request("https://base.test/sub/sub2", ""))
  response
  |> get_body()
  |> should.equal(
    "sub/sub2<-- Expected 'sub3' here\nsub/sub2<-- Expected 'sub1' here",
  )
}

pub fn different_methods_test() {
  let sut =
    router(default)
    |> patch("a/b", path_echo)
    |> get("a/b", never)
    |> build_service()

  let patch_request =
    mk_request("https://base.test/a/b", "")
    |> request.set_method(Patch)

  let response = sut(patch_request)
  response
  |> get_body()
  |> should.equal("/a/b")
}

pub fn state_test() {
  let state_appender = fn(trail: Trail(List(String)), next) -> Response(
    BitBuilder,
  ) {
    let new_trail = Trail(..trail, state: ["gleam", ..trail.state])
    next(new_trail)
  }

  let state_echo = fn(trail: Trail(List(String)), _next) -> Response(BitBuilder) {
    let body =
      trail.state
      |> join("/")
      |> from_string()
    Response(..trail.response, status: 200)
    |> response.set_body(body)
  }
  let sut =
    router_with_state(default, [])
    |> using(state_appender)
    |> get("state/of", state_echo)
    |> build_service()

  let response = sut(mk_request("https://base.test/state/of", ""))

  response
  |> get_body()
  |> should.equal("gleam")
}
