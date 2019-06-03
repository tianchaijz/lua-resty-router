import Router, RouteParser from require "lib.resty.router.router"

build_router = (routes) ->
  handler = (ctx) -> { ctx.params, ctx.route, ctx.name }
  with r = Router!
    for pattern in *routes
      r\add_route pattern, handler
    r\set_default_route -> "failed to find route"
    resolve = r.resolve
    r.resolve = (self, path) ->
      _, ctx, responder = resolve(self, path)
      responder(ctx)

describe "Router", ->
  it "matches a route", ->
    router = Router!
    f = ->
    router\add_route "/hello", f
    assert.same {{}, f, "/hello"}, {router\match "/hello"}

  it "fails to match a route", ->
    router = Router!
    f = ->
    router\add_route "/hello", f
    assert.same {}, {router\match "/zone"}

describe "RouteParser.parse", ->
  for {pattern, test, result} in *{
    {"/:yeah", "ddd", nil}
    {"/:yeah", "/okay", {yeah: "okay"}}
    {"/:yeah", "/okay.com", {yeah: "okay.com"}}

    -- exclude var
    {":thing-:hello", "a-b", {thing: "a", hello: "b"}}

    {":thing(-:hello)", {
      {"a-b", {thing: "a", hello: "b"}}
      {"az", {thing: "az"}}
      {"i/fail", nil}
    }}

    -- exclude splat
    {"/hi/*-:hello", "/hi/a/b/c-okay", {splat: "a/b/c", hello: "okay"}}
    {"*/hello", "whoa/zone/hello", {splat: "whoa/zone"}}
    {":one.*", "sure-thing.com", {splat: "com", one: "sure-thing"}}

    -- splat with optional exclude from format
    {"/browse/*(.:format)", {
      {"/browse/things", {splat: "things"}}
      {"/browse/things.zip", {splat: "things", format: "zip"}}
      {"/browse/things.tar.gz", {splat: "things", format: "tar.gz"}}
    }}

    -- splat doesn't cancel out var
    {":one(*)", "hello_world", { one: "hello_world"}}

    {"/zone(/:game(/:user))", "/zone/drone/leafo",
      { game: "drone", user: "leafo"}}

    {"/:game(/:user)(*)", "/drone/leafo/hi",
      { game: "drone", user: "leafo", splat: "/hi" }}

    -- many optional
    {"/zone(/:game(/:user)(*))",  {
      {"/zone", {}}
      {"/zone/leafo", { game: "leafo"}}
      {"/zone/leafo/beefo", { game: "leafo", user: "beefo"}}
      {"/zone/drone/leafo/here", { game: "drone", user: "leafo", splat: "/here" }}
    }}

    -- many optional with format
    {"/zone(/:game(/:user)(*))(.:format)",  {
      -- same as above, nothing changed
      {"/zone", {}}
      {"/zone/leafo", { game: "leafo"}}
      {"/zone/leafo/beefo", { game: "leafo", user: "beefo"}}
      {"/zone/drone/leafo/here", { game: "drone", user: "leafo", splat: "/here" }}

      -- with formats
      {"/zone.zip", { format: "zip"}}
      {"/zone/leafo.jpeg", { game: "leafo", format: "jpeg"}}
      {"/zone/leafo/beefo.moon", { game: "leafo", user: "beefo", format: "moon"}}
      {"/zone/drone/leafo/here.leaf", {
        game: "drone"
        user: "leafo"
        splat: "/here"
        format: "leaf"
      }}
    }}

    -- adjacent optionals
    {"/manifest(-:version)(.:format)", {
      {"/manifest", {}}
      {"/manifest-first.json", { version: "first", format: "json"}}
      {"/manifest.json", { format: "json"}}
      {"/manifest-first", { version: "first" }}
    }}

    -- moonrocks workaround
    -- TODO: make (-:version)(.:format) work for -5.1.zip
    {"/manifest(-:a.:b)(.:format)", {
      {"/manifest-5.1.json", { a: "5", b: "1", format: "json" }}
      {"/manifest-5.1", { a: "5", b: "1" }}
      {"/manifest.json", { format: "json" }}
    }}

    -- character classes
    {"/:hello[%d]", {
      {"/what", nil}
      {"/", nil}
      {"/1223", { hello: "1223"}}
      {"/1", { hello: "1"}}
    }}

    {"/:world[%a]", {
      {"/what", { world: "what"}}
      {"/1223", nil}
      {"/1"}
    }}

    {"/:lee[%w]", {
      {"/what", {lee: "what"}}
      {"/999", {lee: "999"}}
      {"/aj23", {lee: "aj23"}}
      {"/2lll__", nil}
      {"/", nil}
    }}

    {"/:ben[a-f]", {
      {"/what", nil}
      {"/abf", {ben: "abf"}}
    }}

    {"/:andy[12fg]", {
      {"/what", nil}
      {"/12", {andy: "12"}}
      {"/f2", {andy: "f2"}}
    }}

    {"/:dap[a%dd-g]", {
      {"/what", nil}
      {"/a3", {dap: "a3"}}
      {"/9a99f", {dap: "9a99f"}}
    }}

    {"/:nope[^.]", {
      {"/good", {nope: "good"}}
      {"/", nil}
      {"/one.two", nil}
    }}

    {"/:nope[%%%w]", {
      {"/%20", {nope: "%20"}}
      {"/hi%20", {nope: "hi%20"}}
      {"/", nil}
    }}

    {"/:nope[%-ab]", {
      {"/-", {nope: "-"}}
      {"/--", {nope: "--"}}
      {"/-ab", {nope: "-ab"}}
      {"/ab-", {nope: "ab-"}}
      {"/a-b", {nope: "a-b"}}
      {"/", nil}
      {"/%ab", nil}
      {"/%20", nil}
    }}

    {"/:nope[%%w%-ab]", {
      {"/-", {nope: "-"}}
      {"/%ab", {nope: "%ab"}}
      {"/%ab-", {nope: "%ab-"}}
      {"/%ab-%ab-", {nope: "%ab-%ab-"}}
      {"/w", {nope: "w"}}
      {"/c", nil}
      {"/", nil}
    }}

  }
    do_test = (pattern, test, result) ->
      it "matches `#{pattern}` with `#{test}`", ->
        parser = RouteParser!
        p = assert parser\compile pattern
        assert.same result, (p\match test)

    if type(test) == "table"
      for {_test, result} in *test
        do_test pattern, _test, result
    else
      do_test pattern, test, result


describe "with router", ->
  local r

  describe "basic router", ->
    before_each ->
      r = build_router {
        "/hello"
        "/hello/:name[%d]"
        "/hello/:name"
        "/hello/:name/world"
        "/static/*"
        "/x/:color/:height/*"
        "/please/"
      }

    it "should match static route", ->
      out = r\resolve "/hello"
      assert.same { {}, "/hello" }, out

    it "should match character class route", ->
      out = r\resolve "/hello/234"
      assert.same { { name: "234" }, "/hello/:name[%d]" }, out

    it "should match param route", ->
      out = r\resolve "/hello/world2323"
      assert.same {
        { name: "world2323" },
        "/hello/:name"
      }, out

    it "should match param route", ->
      out = r\resolve "/hello/the-parameter/world"
      assert.same {
        { name: "the-parameter" },
        "/hello/:name/world"
      }, out

    it "should match splat", ->
      out = r\resolve "/static/hello/world/343434/foo%20bar.png"
      assert.same {
        { splat: 'hello/world/343434/foo%20bar.png' }
        "/static/*"
      }, out

    it "should match all", ->
      out = r\resolve "/x/greenthing/123px/ahhhhwwwhwhh.txt"
      assert.same {
        {
          splat: 'ahhhhwwwhwhh.txt'
          height: '123px'
          color: 'greenthing'
        }
        "/x/:color/:height/*"
      }, out

    it "should match nothing", ->
      assert.same "failed to find route", r\resolve("/what-the-heck")

    it "should match nothing", ->
      assert.same "failed to find route", r\resolve("/hello//world")

    it "should match trailing exactly", ->
      assert.same {
        {}
        "/please/"
      }, r\resolve("/please/")

      assert.same "failed to find route", r\resolve("/please")

  it "should match the catchall", ->
    r = build_router {"*"}

    assert.same {
      { splat: "hello_world" }
      "*"
    }, r\resolve "hello_world"

describe "named routes", ->
  local r

  before_each ->
    r = build_router {
      { homepage: "/home" }
      { profile: "/profile/:name" }
      { profile_settings: "/profile/:name/settings" }
      { game: "/game/:user_slug/:game_slug" }
      { splatted: "/page/:slug/*" }
      { optional: "/page(.:format)" }
    }

  it "should match", ->
    out = r\resolve "/home"
    assert.same {
      {}, "/home", "homepage"
    }, out


describe "optional parts", ->
  local r

  describe "basic router", ->
    before_each ->
      r = build_router {
        "/test(/:game)"
        "/zone(/:game(/:user)(*))"
        "/test/me"
      }

    it "matches without optional", ->
      out = r\resolve "/test/yeah"
      assert.same { {game: "yeah"}, "/test(/:game)" }, out

    it "matches with optional part", ->
      out = r\resolve "/test/ozone"
      assert.same { {game: "ozone"}, "/test(/:game)" }, out

    it "fails to find", ->
      out = r\resolve "/test/ozone/"
      assert.same "failed to find route", out

    it "lets literal route take precedence", ->
      out = r\resolve "/test/me"
      assert.same { {}, "/test/me" }, out

describe "route precedence", ->
  local r

  before_each ->
    r = build_router {
      "/*"
      "/:slug"
      "/hello"
    }

  it "matches literal route first", ->
    out = r\resolve "/hello"
    assert.same { {}, "/hello" }, out

  it "matches var route second", ->
    out = r\resolve "/world"
    assert.same { {slug: "world"}, "/:slug" }, out

  it "matches slug last", ->
    out = r\resolve "/whoa/zone"
    assert.same { { splat: "whoa/zone" }, "/*" }, out

  it "preserves declare order among routes with same precedence", ->
    r = build_router {
      "/*"
      "/:slug1"
      "/:slug2"
      "/:slug3"
      "/:slug4"
      "/:slug5"
      "/hello"
    }

    out = r\resolve "/hey"
    assert.same { { slug1: "hey" }, "/:slug1" }, out

  it "more specific takes precedence", ->
    pending "todo"
    r = build_router {
      "/test/:game"
      "/test/:game-world"
    }

    out = r\resolve "/test/hello-world"
    assert.same { { game: "hello" }, "/test/:game-world" }, out

  it "non-optional takes precedence", ->
    pending "todo"
    r = build_router {
      "/test(/:game)"
      "/test/:game"
    }

    out = r\resolve "/test/thing"
    assert.same { { game: "thing" }, "/test/:game" }, out

  it "precedence with unnamed routes", ->
    r = build_router {
      { something: "/*" }
      "/foo"
      "/bar/*"
    }

    out = r\resolve "/bar/baz/1"
    assert.same { { splat: "baz/1" }, "/bar/*" }, out

    out = r\resolve "/qux/foo"
    assert.same { { splat: "qux/foo" }, "/*", "something" }, out

describe "sort routes", ->
  sort_routes = (rs) ->
    router = build_router rs

    tuples = for r in *router.routes
      pattern, flags = router\build_route unpack r
      p = router\route_precedence flags
      -- print r[1], p
      {r[1], p}

    table.sort tuples, (a,b) ->
      a[2] < b[2]

    [t[1] for t in *tuples]

  it "basic set", ->
    assert.same {
      "/hello"
      "/:slug1/two"
      "/*"
    }, sort_routes {
      "/*"
      "/:slug1/two"
      "/hello"
    }

  it "number of slugs affects match", ->
    assert.same {
      "/hello"
      "/:slug1/two"
      "/:slug1/:slug2"

      "/*/hi/*"
      "/*"
    }, sort_routes {
      "/*"
      "/*/hi/*"
      "/:slug1/:slug2"
      "/:slug1/two"
      "/hello"
    }
