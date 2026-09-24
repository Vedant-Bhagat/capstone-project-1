-- Custom Aggregate Functions in MariaDB: GEOMETRIC_MEAN
--
-- MariaDB lets you define your own SQL-level aggregate with
-- CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW. MySQL cannot do this at
-- the SQL level at all -- there you would write a UDF in C, or give up and do
-- the work in application code.
--
-- This script answers a real question about real data: what is the typical
-- length of an airline's routes? Route lengths span three orders of magnitude
-- (a 30 km hop and a 16,000 km long-haul are both "a route"), and for data
-- spread that widely the arithmetic mean is pulled upward by the long tail.
-- The geometric mean -- the nth root of the product, computed here in log
-- space -- is the appropriate summary.
--
-- Three ways to get the same number are compared below: the custom aggregate,
-- the formula written out inline, and a window function.
--
-- Prerequisites: run setup_dataset.sql first (see README).
--
-- How to run:
--   Linux/macOS:  mariadb -u root < vedant_example.sql
--   PowerShell:   Get-Content vedant_example.sql | mariadb -u root

USE flightdb2;

-- ---------------------------------------------------------------------------
-- The custom aggregate
-- ---------------------------------------------------------------------------
-- Computed as EXP(AVG(LN(x))) rather than by multiplying the values: the
-- product of 66,000 route lengths overflows a DOUBLE long before you get to
-- take its root. Summing logarithms is the standard way round that.

DROP FUNCTION IF EXISTS GEOMETRIC_MEAN;

DELIMITER //

CREATE AGGREGATE FUNCTION GEOMETRIC_MEAN(x DOUBLE) RETURNS DOUBLE
BEGIN
    DECLARE log_sum DOUBLE DEFAULT 0;
    DECLARE cnt INT DEFAULT 0;
    DECLARE done INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    main_loop: LOOP
        FETCH GROUP NEXT ROW;
        IF done THEN
            LEAVE main_loop;
        END IF;

        -- LN() is undefined at zero and negative, where MariaDB returns NULL
        -- rather than raising. Guarding explicitly means the skip is a stated
        -- decision rather than a side effect; see the limits section below.
        IF x > 0 THEN
            SET log_sum = log_sum + LN(x);
            SET cnt = cnt + 1;
        END IF;
    END LOOP main_loop;

    IF cnt = 0 THEN
        RETURN NULL;
    END IF;
    RETURN EXP(log_sum / cnt);
END //

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Option A: the custom aggregate
-- ---------------------------------------------------------------------------
SELECT '--- Option A: custom aggregate function ---' AS label;

SELECT airline,
       COUNT(*)                          AS routes,
       ROUND(GEOMETRIC_MEAN(km), 1)      AS geometric_km,
       ROUND(AVG(km), 1)                 AS arithmetic_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 500
ORDER BY routes DESC;

-- ---------------------------------------------------------------------------
-- Option B: the formula written out inline
-- ---------------------------------------------------------------------------
-- Same answer, but every caller has to know that the geometric mean is
-- EXP(AVG(LN(x))), and has to remember the km > 0 guard. Get either wrong and
-- the query still runs -- it just returns something that isn't a geometric
-- mean.
SELECT '--- Option B: inline EXP(AVG(LN(x))) ---' AS label;

SELECT airline,
       COUNT(*)                              AS routes,
       ROUND(EXP(AVG(LN(km))), 1)            AS geometric_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 500
ORDER BY routes DESC;

-- ---------------------------------------------------------------------------
-- Option C: a window function
-- ---------------------------------------------------------------------------
-- Window functions are the usual answer when someone asks how to do this
-- without a custom aggregate. They work, but they solve a different problem:
-- a window function computes a value for every row rather than collapsing the
-- group. Getting one row per airline therefore needs a DISTINCT, and filtering
-- on the result needs the whole thing wrapped in a derived table, because a
-- window function cannot be referenced from HAVING and MariaDB has no QUALIFY
-- clause. Three extra lines of scaffolding to reach the same number that
-- Option A gets from a plain GROUP BY.
SELECT '--- Option C: window function over a partition ---' AS label;

SELECT DISTINCT airline, routes, geometric_km
FROM (SELECT airline,
             COUNT(*)      OVER (PARTITION BY airline)              AS routes,
             ROUND(EXP(AVG(LN(km)) OVER (PARTITION BY airline)), 1) AS geometric_km
      FROM route_distances
      WHERE km > 0) windowed
WHERE routes >= 500
ORDER BY routes DESC;

-- ---------------------------------------------------------------------------
-- Why the three means disagree
-- ---------------------------------------------------------------------------
-- Shown together so the difference is impossible to miss. For a large carrier
-- the arithmetic and geometric means differ by hundreds of kilometres: the
-- arithmetic mean is reporting the pull of a handful of intercontinental
-- routes, the geometric mean is reporting what a typical route looks like.
SELECT '--- Arithmetic vs geometric, side by side ---' AS label;

SELECT airline,
       COUNT(*)                     AS routes,
       ROUND(AVG(km), 1)            AS arithmetic_km,
       ROUND(GEOMETRIC_MEAN(km), 1) AS geometric_km,
       ROUND(AVG(km) - GEOMETRIC_MEAN(km), 1) AS difference_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 500
ORDER BY difference_km DESC;

-- ---------------------------------------------------------------------------
-- Limits and failure modes
-- ---------------------------------------------------------------------------
-- 1. Domain, and a silent trap. LN(x) is undefined for x <= 0, and MariaDB
--    returns NULL there rather than raising an error. AVG() then skips those
--    NULLs. So neither this function nor the inline form of Option B fails on
--    the dataset's one zero-length route -- both quietly compute the mean
--    without it, and agree to the last decimal.
--
--    The trap is what happens to the row count reported alongside it. COUNT(*)
--    still counts the row that contributed nothing, so an unguarded query
--    reports a mean over N routes that was actually computed from N-1.
--    Demonstrated below on airline IL: 23 routes counted, 22 used. Nothing
--    warns you. This is why every query here filters WHERE km > 0 rather than
--    relying on NULL propagation to do it quietly.
--
-- 2. Empty groups. The function returns NULL rather than raising, matching how
--    built-in aggregates treat an empty input.
--
-- 3. FETCH GROUP NEXT ROW is single-pass. The loop sees each row of the group
--    exactly once and cannot rewind, so anything needing two passes (a median,
--    say) has to buffer rows itself.
--
-- 4. Custom aggregates cannot currently be used as window functions -- there
--    is no GEOMETRIC_MEAN(km) OVER (PARTITION BY airline). That is why
--    Option C has to spell the formula out rather than reuse the function.

SELECT '--- Limit 1: the zero-length route, and the count that lies ---' AS label;

SELECT airline,
       COUNT(*)                     AS count_star,
       SUM(km > 0)                  AS rows_actually_used,
       ROUND(GEOMETRIC_MEAN(km), 2) AS custom_aggregate,
       ROUND(EXP(AVG(LN(km))), 2)   AS inline_form
FROM route_distances
WHERE airline = (SELECT airline FROM route_distances WHERE km = 0 LIMIT 1)
GROUP BY airline;

SELECT '--- Limit 2: an empty group ---' AS label;

SELECT GEOMETRIC_MEAN(km) AS returns_null
FROM route_distances
WHERE km > 0 AND airline = '--no-such-airline--';
