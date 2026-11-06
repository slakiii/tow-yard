-- Content hashing: one canonical dump and one digest. The level format keys a
-- ghost and a best time to a content hash, so these three properties are the
-- ones everything downstream leans on: the digest is a real SHA-256, the dump
-- does not depend on table construction order, and the build stamp moves when a
-- constant that decides whether an input stream parks moves.

local H = require("tests.helper")
local hash = require("lib.hash")

local M = { order = {
    "sha256_matches_a_known_vector",
    "canonical_is_order_independent",
    "build_hash_changes_with_a_constant",
} }

function M.sha256_matches_a_known_vector()
    H.expect(hash.sha256("abc") ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "sha256 of 'abc' must match the standard vector")
end

function M.canonical_is_order_independent()
    H.expect(hash.canonical({ b = 1, a = { 2, x = 3 } }) ==
             hash.canonical({ a = { x = 3, 2 }, b = 1 }),
             "table construction order must not change the canonical dump")
end

function M.build_hash_changes_with_a_constant()
    local base = hash.build_hash()
    H.expect(base == hash.build_hash(), "the build hash must be stable across calls")
    H.expect(base ~= hash.build_hash({ session = { PARK_SPEED = 0.06 } }),
             "changing a parking constant must change the build hash")
end

return M
