-- The transport codec: zlib plus base64, wrapping love.data.
--
-- It is a module so both the shell and the tests build the same one, and it is
-- passed INTO lib/run.lua rather than required by it: the run format stays pure,
-- and a test could hand it an identity codec if it ever needed to inspect the
-- bytes.
--
-- love.data is touched at CALL time, not at load, so this module can be required
-- inside the suite's no-love-at-module-level test.

local M = {}

function M.love_data()
    local data = love.data
    return {
        compress = function(raw) return data.compress("string", "zlib", raw) end,
        decompress = function(blob) return data.decompress("string", "zlib", blob) end,
        encode = function(blob) return data.encode("string", "base64", blob) end,
        decode = function(text) return data.decode("string", "base64", text) end,
    }
end

return M
