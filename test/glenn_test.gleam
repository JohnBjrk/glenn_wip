import gleeunit
import gleeunit/should
import gleam/bit_builder.{BitBuilder, to_bit_string}
import gleam/bit_string.{from_string, to_string}
import gleam/http/response.{Response}
import gleam/http/request.{Request, from_uri, set_body}
import gleam/http.{Patch}
import gleam/uri
import glenn/service.{
  Trail, build_service, default, get, logger, not_found, not_found_trace, patch,
  route, router, using,
}
import glenn/testing.{
  fixed_body_response, get_body, mk_request, never, parameters_echo, path_echo,
}
import gleam/io

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
