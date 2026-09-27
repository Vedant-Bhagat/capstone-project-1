-- Custom Aggregate Functions in MariaDB: WEIGHTED_AVERAGE
--
-- WEIGHTED_AVERAGE(value, weight) is a two-argument custom aggregate -- this
-- shows CREATE AGGREGATE FUNCTION works with more than one input, which a
-- built-in like AVG() cannot express.
--
-- The question it answers, on MariaDB's OpenFlights dataset
-- (https://github.com/mariadb/openflights, database flightdb2): what is the
-- average route distance for a country's airlines, weighted by how many
-- routes each airline actually flies? Without the weighting, a small airline
-- with three long-haul routes moves a country's figure as much as a major
-- carrier flying two thousand.
--
-- Three ways to get the same number are compared below: the custom
-- aggregate, the formula written out inline, and a window function. A fourth
-- query shows the unweighted average for contrast.
--
-- Prerequisites: load the dataset and run setup_dataset.sql first (see
-- README). It creates the `route_distances` view used here.
--
-- How to run (from the sql directory):
--   Linux/macOS:  mariadb -u root < janhavi_example.sql
--   PowerShell:   Get-Content janhavi_example.sql | mariadb -u root

USE flightdb2;

-- ---------------------------------------------------------------------------
-- The custom aggregate
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS WEIGHTED_AVERAGE;

DELIMITER //

CREATE AGGREGATE FUNCTION WEIGHTED_AVERAGE(val DOUBLE, weight DOUBLE) RETURNS DOUBLE
BEGIN
    DECLARE weighted_sum DOUBLE DEFAULT 0;
    DECLARE weight_total DOUBLE DEFAULT 0;
    DECLARE done INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    main_loop: LOOP
        FETCH GROUP NEXT ROW;
        IF done THEN
            LEAVE main_loop;
        END IF;
        SET weighted_sum = weighted_sum + (val * weight);
        SET weight_total = weight_total + weight;
    END LOOP main_loop;

    IF weight_total = 0 THEN
        RETURN NULL;
    END IF;
    RETURN weighted_sum / weight_total;
END //

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Per-airline figures, shared by every option below
-- ---------------------------------------------------------------------------
-- Two real-data gotchas are handled here:
--
--   * Zero-distance route. One route in route_distances has km = 0 (both
--     endpoint airports share coordinates). WEIGHTED_AVERAGE itself copes
--     with it, but it would break the geometric and harmonic means computed
--     elsewhere in this repository (LN(0) and 1/0), so every query here
--     filters WHERE km > 0 to keep all examples on identical rows.
--
--   * Airline codes are not unique. routes.airline is a 2-letter IATA code,
--     and in the airlines table thousands of rows have an empty code while
--     others share one (e.g. '1I' belongs to 7 airlines). Joining on the
--     code would count one airline's routes several times, sometimes under
--     different countries: it turns 66,770 routes into 76,277 joined rows.
--     We join on the numeric airline id (routes.alid) instead; routes with
--     no airline id are dropped.

CREATE OR REPLACE VIEW airline_route_stats AS
SELECT r.alid,
       AVG(d.km) AS mean_km,
       COUNT(*)  AS route_count
FROM route_distances d
JOIN routes r ON r.rid = d.rid
WHERE d.km > 0
GROUP BY r.alid;

-- ---------------------------------------------------------------------------
-- Option A: custom aggregate function (the feature under test)
-- ---------------------------------------------------------------------------
SELECT '--- Option A: custom aggregate function ---' AS label;
SELECT al.country,
       COUNT(*)                                          AS airlines,
       SUM(x.route_count)                                AS routes,
       ROUND(WEIGHTED_AVERAGE(x.mean_km, x.route_count), 2) AS weighted_mean_km
FROM airline_route_stats x
JOIN airlines al ON al.alid = x.alid
GROUP BY al.country
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Option B: same result, formula repeated inline (the common workaround)
-- ---------------------------------------------------------------------------
SELECT '--- Option B: inline SUM(val*weight)/SUM(weight) at the call site ---' AS label;
SELECT al.country,
       COUNT(*)                                                         AS airlines,
       SUM(x.route_count)                                               AS routes,
       ROUND(SUM(x.mean_km * x.route_count) / SUM(x.route_count), 2)    AS weighted_mean_km
FROM airline_route_stats x
JOIN airlines al ON al.alid = x.alid
GROUP BY al.country
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Option C: window function (OVER, no GROUP BY collapse)
-- ---------------------------------------------------------------------------
-- The window form keeps every airline row, so DISTINCT is needed to get one
-- row per country back. Its strength is the opposite case: showing each
-- airline next to its country's weighted mean, which GROUP BY cannot do.
SELECT '--- Option C: window function SUM(...) OVER (PARTITION BY country) ---' AS label;
SELECT DISTINCT al.country,
       COUNT(*)           OVER w AS airlines,
       SUM(x.route_count) OVER w AS routes,
       ROUND(SUM(x.mean_km * x.route_count) OVER w / SUM(x.route_count) OVER w, 2) AS weighted_mean_km
FROM airline_route_stats x
JOIN airlines al ON al.alid = x.alid
WINDOW w AS (PARTITION BY al.country)
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Contrast: the unweighted average of airline means
-- ---------------------------------------------------------------------------
-- Every airline counts once regardless of size. The gap between this column
-- and the weighted one is the distortion the weighting removes.
SELECT '--- Contrast: unweighted AVG() of airline means ---' AS label;
SELECT al.country,
       COUNT(*)                                             AS airlines,
       SUM(x.route_count)                                   AS routes,
       ROUND(WEIGHTED_AVERAGE(x.mean_km, x.route_count), 2) AS weighted_mean_km,
       ROUND(AVG(x.mean_km), 2)                             AS unweighted_mean_km
FROM airline_route_stats x
JOIN airlines al ON al.alid = x.alid
GROUP BY al.country
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Comparison notes:
--   - Option A (custom aggregate): one call site,
--     WEIGHTED_AVERAGE(mean_km, route_count). The formula lives in one place
--     and the value/weight pairing can't be got wrong at the call site.
--   - Option B (inline formula): same result, but every query that needs a
--     weighted average repeats and correctly pairs up the two SUM()s.
--   - Option C (window function): same result again, but the most verbose
--     for a per-group answer; worth it only when the per-row detail is
--     needed alongside the group figure.
--
-- Limits: weights must be non-negative and not all zero (an all-zero group
-- returns NULL); NULL values or weights are not skipped, so a single NULL
-- makes the whole group's result NULL; results are floating-point, so
-- compare them rounded.
-- Because the weights here are route counts, the weighted mean of airline
-- means equals the plain AVG(km) over all of the country's routes -- a
-- useful independent check on the numbers above.
-- ---------------------------------------------------------------------------
