-- Copyright (C) Leaf Corcoran
-- Copyright (C) Jinzheng Zhang (tianchaijz)

-- XXX: port from https://github.com/leafo/lapis/blob/master/lapis/router.moon

local lpeg = require "lpeg"

local R, S, V, P = lpeg.R, lpeg.S, lpeg.V, lpeg.P
local C, Ct, Cg = lpeg.C, lpeg.Ct, lpeg.Cg

local next = next
local error = error
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local unpack = unpack or table.unpack
local tbl_sort = table.sort
local tbl_concat = table.concat
local tbl_remove = table.remove
local tbl_insert = table.insert


local RouteGrammar, RouteCompiler

do
    local function mark(name)
        return function(...) return { name, ... } end
    end

    local alpha = R("az", "AZ", "__")
    local alpha_num = alpha + R"09"
    local splat = P"*"
    local char_class = P"[" * C((1 - P"]") ^ 1) * P"]"
    local char_range = C(1) * P"-" * C(1) / function(a, b) return a .. b end
    local char_set = C(P"%" * S"adw%-" + char_range + 1)
    local char_class_inner = Ct(C"^" ^ -1 * char_set ^ 1)
    local var = P":" * C(alpha * alpha_num ^ 0) * char_class ^ -1

    local grammar = P({
        "route",
        optional_literal = (1 - P")" - V"chunk") ^ 1 / mark("literal"),
        optional_route = Ct((V"chunk" + V"optional_literal") ^ 1),
        optional = P"(" * V"optional_route" * P")" / mark("optional"),
        literal = (1 - V"chunk") ^ 1 / mark("literal"),
        chunk = var / mark("var") + splat / mark("splat") + V"optional",
        route = Ct((V"chunk" + V"literal") ^ 1)
    })

    local function compile_char_class(chars)
        local negate = false
        local patterns = {}
        local plain_chars = {}
        local list = char_class_inner:match(chars)

        if list[1] == "^" then
            negate = true
            tbl_remove(list, 1)
        end

        for _, item in ipairs(list) do
            if item == "%a" then
                patterns[#patterns + 1] = R("az", "AZ")
            elseif item == "%d" then
                patterns[#patterns + 1] = R("09")
            elseif item == "%w" then
                patterns[#patterns + 1] = R("09", "az", "AZ")
            elseif item == "%%" then
                patterns[#patterns + 1] = P"%"
            elseif item == "%-" then
                patterns[#patterns + 1] = P"-"
            elseif #item == 2 then
                patterns[#patterns + 1] = R(item)
            else
                plain_chars[#plain_chars + 1] = item
            end
        end

        if next(plain_chars) then
            patterns[#patterns + 1] = S(tbl_concat(plain_chars))
        end

        local out
        for _, p in ipairs(patterns) do
            out = out and out + p or p
        end

        if negate then
            out = 1 - out
        end

        return out or P(-1)
    end

    local function compile_chunks(chunks, exclude)
        local pattern
        local flags = {}
        local visitor = {}

        function visitor.visit_splat()
            local inside = P(1)
            if exclude then
                inside = inside - exclude
            end
            exclude = nil
            return Cg(inside ^ 1, "splat")
        end

        function visitor.visit_var(ctx)
            local char = ctx.chars and compile_char_class(ctx.chars) or P(1)
            local inside = char - "/"
            if exclude then
                inside = inside - exclude
            end
            exclude = nil
            return Cg(inside ^ 1, ctx.value)
        end

        function visitor.visit_literal(ctx)
            exclude = P(ctx.value)
            return P(ctx.value)
        end

        function visitor.visit_optional(ctx)
            local inner, inner_flags, inner_exclude = compile_chunks(ctx.value,
                                                                     exclude)
            for k, v in pairs(inner_flags) do
                flags[k] = flags[k] or v
            end

            if inner_exclude then
                if exclude then
                    exclude = inner_exclude + exclude
                else
                    exclude = inner_exclude
                end
            end

            return inner ^ -1
        end

        -- XXX: from back to front
        for i = #chunks, 1, -1 do
            local chunk_pattern
            local chunk = chunks[i]
            local kind, value, chars = unpack(chunk)
            local ctx = { value = value, chars = chars }

            flags[kind] = (flags[kind] or 0) +
                          (kind == "literal" and #value or 1)
            chunk_pattern = visitor["visit_" .. kind](ctx)

            if pattern then
                pattern = chunk_pattern * pattern
            else
                pattern = chunk_pattern
            end
        end

        return pattern, flags, exclude
    end

    RouteGrammar = grammar
    RouteCompiler = grammar / function(...)
        return compile_chunks(...)
    end / function(p, f) return Ct(p) * -1, f end
end


local RouteParser = {}
local route_parser_mt = { __index = RouteParser }

RouteParser.__index = RouteParser


function RouteParser.new()
    return setmetatable({}, route_parser_mt)
end


function RouteParser.parse(self, route)
    return RouteGrammar:match(route)
end


function RouteParser.compile(self, route)
    return RouteCompiler:match(route)
end


local _RouteParser = setmetatable({}, {
    __index = RouteParser,
    __call = function(cls, ...) return cls.new(...) end
})


local Router = {}
local router_mt = { __index = Router }

Router.__index = Router


function Router.new()
    local self = {
        routes = {},
        named_routes = {},
        parser = _RouteParser(),
    }

    return setmetatable(self, router_mt)
end


function Router.add_route(self, route, responder)
    local name
    if type(route) == "table" then
        name, route = next(route)
        if not self.named_routes[name] then
            self.named_routes[name] = route
        end
    end

    self.routes[#self.routes + 1] = { route, responder, name }
end


function Router.route_precedence(self, flags)
    local p = 0

    if flags.var then
        p = p + flags.var
    end

    if flags.literal then
        p = p + 1 / flags.literal
    end

    if flags.splat then
        p = p + (10 + (1 / flags.splat) * 10)
    end

    return p
end


function Router.build_route(self, route, responder, name)
    local pattern, flags = self.parser:compile(route)
    pattern = pattern / function(params)
        return params, responder, route, name
    end

    return pattern, flags
end


function Router.build(self)
    local precedences = {}
    local by_precedence = {}

    for _, r in ipairs(self.routes) do
        local pattern, flags = self:build_route(unpack(r))
        local p = self:route_precedence(flags)
        by_precedence[p] = by_precedence[p] or {}
        tbl_insert(by_precedence[p], pattern)
    end

    for k in pairs(by_precedence) do
        precedences[#precedences + 1] = k
    end

    tbl_sort(precedences)

    for _, p in ipairs(precedences) do
        local list = by_precedence[p]
        for _, patt in ipairs(list) do
            if self.pattern then
                self.pattern = self.pattern + patt
            else
                self.pattern = patt
            end
        end
    end

    self.pattern = self.pattern or P(-1)
end


function Router.match(self, path)
    if not self.pattern then
        self:build()
    end

    return self.pattern:match(path)
end


function Router.default_route()
    return error("failed to find route")
end


function Router.set_default_route(self, responder)
    self.default_route = responder
end


function Router.resolve(self, path)
    local params, responder, route, name = self:match(path)
    local ctx = { params = params, route = route, name = name, path = path }
    if params then
        return true, ctx, responder
    end

    return false, ctx, self.default_route
end


local _Router = setmetatable({}, {
    __index = Router,
    __call = function(cls, ...) return cls.new(...) end
})


return {
    Router = _Router,
    RouteParser = _RouteParser,
}
