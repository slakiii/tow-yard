-- Shared assertion helpers for the headless test suite.

local H = {}

function H.expect(cond, msg)
    if not cond then
        error(msg or "expectation failed", 2)
    end
end

function H.near(a, b, eps, label)
    eps = eps or 1e-6
    if math.abs(a - b) > eps then
        error(string.format("%s: %.6f ~= %.6f (eps %.6f)", label or "value", a, b, eps), 2)
    end
end

function H.between(v, lo, hi, label)
    if v < lo or v > hi then
        error(string.format("%s: %.4f not in [%.4f, %.4f]", label or "value", v, lo, hi), 2)
    end
end

H.deg = math.deg
H.rad = math.rad

return H
