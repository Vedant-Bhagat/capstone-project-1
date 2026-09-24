-- Timing harness: custom aggregate vs inline formula vs window function.
--
-- Runs each of the three approaches N times over the full ~66,770-row route
-- set and reports mean, min, max and standard deviation in milliseconds.
-- Single measurements on a laptop are noise; the spread is the point.
--
-- Method. Each query is wrapped in SELECT COUNT(*) FROM (...) so that the
-- server fully executes and materialises it without shipping rows to the
-- client -- otherwise the measurement is dominated by result transfer rather
-- than by the aggregation being compared. That wrapper costs the same for all
-- three variants, so it does not bias the comparison between them, but it does
-- mean these are relative figures rather than absolute query costs.
--
-- Prerequisites: setup_dataset.sql, then vedant_example.sql (which defines
-- GEOMETRIC_MEAN).
--
-- How to run:
--   Linux/macOS:  mariadb -u root < bench.sql
--   PowerShell:   Get-Content bench.sql | mariadb -u root
--
-- Report the machine you ran it on alongside the numbers. Results from
-- different hardware are not comparable.

USE flightdb2;

DROP TABLE IF EXISTS bench_results;
CREATE TABLE bench_results (
    variant    VARCHAR(40) NOT NULL,
    run_no     INT         NOT NULL,
    elapsed_ms DOUBLE      NOT NULL
);

DROP PROCEDURE IF EXISTS run_benchmark;

DELIMITER //

CREATE PROCEDURE run_benchmark(IN runs INT)
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE t0 DATETIME(6);
    DECLARE sink INT;

    WHILE i <= runs DO

        -- A: custom aggregate function
        SET t0 = NOW(6);
        SELECT COUNT(*) INTO sink FROM (
            SELECT airline, GEOMETRIC_MEAN(km) AS g
            FROM route_distances WHERE km > 0 GROUP BY airline
        ) a;
        INSERT INTO bench_results VALUES
            ('A: custom aggregate', i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)) / 1000);

        -- B: the same formula written out inline
        SET t0 = NOW(6);
        SELECT COUNT(*) INTO sink FROM (
            SELECT airline, EXP(AVG(LN(km))) AS g
            FROM route_distances WHERE km > 0 GROUP BY airline
        ) b;
        INSERT INTO bench_results VALUES
            ('B: inline formula', i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)) / 1000);

        -- C: window function, with the scaffolding it needs to return one row
        -- per airline
        SET t0 = NOW(6);
        SELECT COUNT(*) INTO sink FROM (
            SELECT DISTINCT airline, g FROM (
                SELECT airline, EXP(AVG(LN(km)) OVER (PARTITION BY airline)) AS g
                FROM route_distances WHERE km > 0
            ) w
        ) c;
        INSERT INTO bench_results VALUES
            ('C: window function', i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)) / 1000);

        SET i = i + 1;
    END WHILE;
END //

DELIMITER ;

-- One untimed pass first, so that the first measured run is not paying for a
-- cold buffer pool while the other two benefit from a warm one.
SELECT 'Warming up...' AS '';
CALL run_benchmark(1);
DELETE FROM bench_results;

SELECT 'Benchmarking (10 runs per variant)...' AS '';
CALL run_benchmark(10);

SELECT VERSION() AS mariadb_version;

SELECT variant,
       COUNT(*)                  AS runs,
       ROUND(AVG(elapsed_ms), 1) AS mean_ms,
       ROUND(MIN(elapsed_ms), 1) AS min_ms,
       ROUND(MAX(elapsed_ms), 1) AS max_ms,
       ROUND(STDDEV_SAMP(elapsed_ms), 1) AS stddev_ms
FROM bench_results
GROUP BY variant
ORDER BY variant;
