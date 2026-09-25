-- Starter: Custom Aggregate Functions (MariaDB-only feature)
-- HARMONIC_MEAN on real data: MariaDB Foundation's OpenFlights dataset
-- (https://github.com/mariadb/openflights), database flightdb2.
--
-- Harmonic mean is the correct average for RATES (see the earlier speed
-- example this replaces). Route distance is not a rate -- we compute it
-- here anyway so a reader can see, on identical real data, how far apart
-- the harmonic mean, the inline formula, a window-function equivalent,
-- and a plain AVG() land. Harmonic mean is not claimed to be the "right"
-- answer for distances; it is shown for comparison only.
--
-- Prerequisite (run once, outside this script) -- see the Setup section of
-- the repository README for the exact commands on each platform:
--   1. git clone https://github.com/mariadb/openflights
--   2. From inside that folder, load sql/create.sql then sql/load-data.sql
--      (the latter needs --local-infile=1, or it silently loads nothing)
--   3. Run setup_dataset.sql from this directory, which creates the shared
--      `route_distances` view that every example here builds on
--
-- Gotcha: exactly one route in route_distances has km = 0 (its two
-- endpoint airports share coordinates). 1/km is undefined at 0, so every
-- query below filters WHERE km > 0.
--
-- How to run (from the sql directory): Get-Content pranesh_example.sql | mariadb -u root

USE flightdb2;

DROP FUNCTION IF EXISTS HARMONIC_MEAN;

DELIMITER //

CREATE AGGREGATE FUNCTION HARMONIC_MEAN(x DOUBLE) RETURNS DOUBLE
BEGIN
    DECLARE inv_sum DOUBLE DEFAULT 0;
    DECLARE cnt INT DEFAULT 0;
    DECLARE done INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    main_loop: LOOP
        FETCH GROUP NEXT ROW;
        IF done THEN
            LEAVE main_loop;
        END IF;
        SET inv_sum = inv_sum + (1 / x);
        SET cnt = cnt + 1;
    END LOOP main_loop;

    IF cnt = 0 THEN
        RETURN NULL;
    END IF;
    RETURN cnt / inv_sum;
END //

DELIMITER ;

SELECT '--- Option A: custom aggregate function (HARMONIC_MEAN) ---' AS label;
SELECT airline, COUNT(*) AS routes, HARMONIC_MEAN(km) AS harmonic_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 100
ORDER BY routes DESC
LIMIT 15;

SELECT '--- Option B: inline COUNT(*) / SUM(1/x) at the call site ---' AS label;
SELECT airline, COUNT(*) AS routes, COUNT(*) / SUM(1 / km) AS harmonic_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 100
ORDER BY routes DESC
LIMIT 15;

SELECT '--- Option C: window-function equivalent (OVER(), no GROUP BY collapse) ---' AS label;
SELECT DISTINCT airline,
       COUNT(*) OVER (PARTITION BY airline) AS routes,
       COUNT(*) OVER (PARTITION BY airline) / SUM(1 / km) OVER (PARTITION BY airline) AS harmonic_km_window
FROM route_distances
WHERE km > 0
ORDER BY routes DESC
LIMIT 15;

SELECT '--- Option D: plain AVG() -- NOT the right tool here, shown for contrast ---' AS label;
SELECT airline, COUNT(*) AS routes, AVG(km) AS plain_avg_km
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 100
ORDER BY routes DESC
LIMIT 15;

-- Limits: x must be non-zero (see the km = 0 gotcha above); results are
-- floating-point; harmonic mean is the correct average for rates (like
-- our earlier speed example), not for distances -- it is shown here
-- purely as a like-for-like comparison against the same real dataset.