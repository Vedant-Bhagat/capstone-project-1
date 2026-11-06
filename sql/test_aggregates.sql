-- Tests for the custom aggregate functions.
--
-- Each test compares a custom aggregate against the closed-form expression it
-- is supposed to implement, across every airline in the dataset. A mismatch
-- beyond floating-point tolerance raises an error, so the MariaDB client exits
-- non-zero and CI fails.
--
-- Prerequisites: setup_dataset.sql, then the example scripts that define the
-- functions being tested.
--
-- How to run:
--   Linux/macOS:  mariadb -u root < test_aggregates.sql
--   PowerShell:   Get-Content test_aggregates.sql | mariadb -u root

USE flightdb2;

-- Tolerance is relative, not absolute: these are DOUBLEs in the hundreds to
-- thousands, so comparing them for exact equality would be a test that fails
-- for reasons having nothing to do with the code.
SET @tolerance = 1e-9;

-- ---------------------------------------------------------------------------
-- Test 1: GEOMETRIC_MEAN agrees with EXP(AVG(LN(x)))
-- ---------------------------------------------------------------------------
SELECT 'Test 1: GEOMETRIC_MEAN vs EXP(AVG(LN(x)))' AS '';

SELECT COUNT(*) INTO @failures
FROM (SELECT airline,
             GEOMETRIC_MEAN(km) AS custom,
             EXP(AVG(LN(km)))   AS closed_form
      FROM route_distances
      WHERE km > 0
      GROUP BY airline) t
WHERE ABS(custom - closed_form) / closed_form > @tolerance;

SELECT IF(@failures = 0,
          'PASS: all airlines agree',
          CONCAT('FAIL: ', @failures, ' airlines disagree')) AS '';

-- ---------------------------------------------------------------------------
-- Test 2: an empty group returns NULL rather than raising or returning zero
-- ---------------------------------------------------------------------------
SELECT 'Test 2: empty group returns NULL' AS '';

SELECT GEOMETRIC_MEAN(km) INTO @empty_result
FROM route_distances WHERE km > 0 AND airline = '--no-such-airline--';

SELECT IF(@empty_result IS NULL,
          'PASS: empty group is NULL',
          CONCAT('FAIL: empty group returned ', @empty_result)) AS '';

-- ---------------------------------------------------------------------------
-- Test 3: the geometric mean never exceeds the arithmetic mean
-- ---------------------------------------------------------------------------
-- This is the AM-GM inequality, which holds for any set of positive reals. If
-- it is ever violated the implementation is wrong, whatever the other tests
-- say. A property worth asserting precisely because it does not depend on the
-- dataset.
SELECT 'Test 3: AM-GM inequality holds for every airline' AS '';

SELECT COUNT(*) INTO @amgm_violations
FROM (SELECT airline,
             GEOMETRIC_MEAN(km) AS geo,
             AVG(km)            AS arith
      FROM route_distances
      WHERE km > 0
      GROUP BY airline) t
WHERE geo > arith * (1 + @tolerance);

SELECT IF(@amgm_violations = 0,
          'PASS: AM-GM holds everywhere',
          CONCAT('FAIL: ', @amgm_violations, ' violations')) AS '';

-- ---------------------------------------------------------------------------
-- Test 4: HARMONIC_MEAN agrees with COUNT(*) / SUM(1/x)
-- ---------------------------------------------------------------------------
SELECT 'Test 4: HARMONIC_MEAN vs COUNT(*) / SUM(1/x)' AS '';

SELECT COUNT(*) INTO @hm_failures
FROM (SELECT airline,
             HARMONIC_MEAN(km)      AS custom,
             COUNT(*) / SUM(1 / km) AS closed_form
      FROM route_distances
      WHERE km > 0
      GROUP BY airline) t
WHERE ABS(custom - closed_form) / closed_form > @tolerance;

SELECT IF(@hm_failures = 0,
          'PASS: all airlines agree',
          CONCAT('FAIL: ', @hm_failures, ' airlines disagree')) AS '';

-- ---------------------------------------------------------------------------
-- Test 5: the harmonic mean never exceeds the geometric mean
-- ---------------------------------------------------------------------------
-- Test 3 asserts GM <= AM; this completes the chain HM <= GM <= AM, which
-- holds for any set of positive reals. Like Test 3 it depends on no dataset,
-- so it catches errors the closed-form comparison in Test 4 cannot.
SELECT 'Test 5: HM <= GM holds for every airline' AS '';

SELECT COUNT(*) INTO @hmgm_violations
FROM (SELECT airline,
             HARMONIC_MEAN(km)  AS harm,
             GEOMETRIC_MEAN(km) AS geo
      FROM route_distances
      WHERE km > 0
      GROUP BY airline) t
WHERE harm > geo * (1 + @tolerance);

SELECT IF(@hmgm_violations = 0,
          'PASS: HM <= GM holds everywhere',
          CONCAT('FAIL: ', @hmgm_violations, ' violations')) AS '';

-- ---------------------------------------------------------------------------
-- Fail the run if anything above failed
-- ---------------------------------------------------------------------------
-- SIGNAL makes the client exit non-zero, which is what CI checks. Without it
-- a failing test would print "FAIL" and the build would still go green.

SET @total_failures = @failures + @amgm_violations + IF(@empty_result IS NULL, 0, 1)
                    + @hm_failures + @hmgm_violations;

DELIMITER //
BEGIN NOT ATOMIC
    IF @total_failures > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Aggregate function tests failed';
    END IF;
END //
DELIMITER ;

SELECT 'All tests passed.' AS '';
