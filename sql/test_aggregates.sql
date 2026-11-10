-- Tests for the custom aggregate functions.
--
-- Each test compares a custom aggregate against the closed-form expression it
-- is supposed to implement, across every airline in the dataset. A mismatch
-- beyond floating-point tolerance raises an error, so the MariaDB client exits
-- non-zero and CI fails.
--
-- Prerequisites: setup_dataset.sql, then the example scripts that define the
-- functions being tested.
-- test_fixture.sql must also run first: the edge-case tests read agg_edge_cases.
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
-- Test 6: N identical values have a harmonic mean equal to that value
-- ---------------------------------------------------------------------------
-- The "tie" case: three copies of 7 must give exactly 7.
SELECT 'Test 6: HARMONIC_MEAN of identical values' AS '';

SELECT HARMONIC_MEAN(val) INTO @hm_ties
FROM agg_edge_cases WHERE grp = 'ties';

SELECT IF(@hm_ties <=> 7,
          'PASS: three 7s give 7',
          CONCAT('FAIL: three 7s gave ', IFNULL(@hm_ties, 'NULL'))) AS '';

-- ---------------------------------------------------------------------------
-- Test 7: an empty group returns NULL
-- ---------------------------------------------------------------------------
-- Covers the function's IF cnt = 0 branch.
SELECT 'Test 7: HARMONIC_MEAN of an empty group returns NULL' AS '';

SELECT HARMONIC_MEAN(km) INTO @hm_empty
FROM route_distances WHERE km > 0 AND airline = '--no-such-airline--';

SELECT IF(@hm_empty IS NULL,
          'PASS: empty group is NULL',
          CONCAT('FAIL: empty group returned ', @hm_empty)) AS '';

-- ---------------------------------------------------------------------------
-- Test 8: a zero value makes the group NULL
-- ---------------------------------------------------------------------------
-- 1/0 is undefined. The function guards it, so this holds whatever the
-- sql_mode rather than raising error 1365 under ERROR_FOR_DIVISION_BY_ZERO.
SELECT 'Test 8: HARMONIC_MEAN with a zero value returns NULL' AS '';

SELECT HARMONIC_MEAN(val) INTO @hm_zero
FROM agg_edge_cases WHERE grp = 'zero_val';

SELECT IF(@hm_zero IS NULL,
          'PASS: zero value gives NULL',
          CONCAT('FAIL: zero value gave ', @hm_zero)) AS '';

-- ---------------------------------------------------------------------------
-- Test 9: reciprocals that cancel make the group NULL
-- ---------------------------------------------------------------------------
-- 1/1 + 1/-1 = 0, so the count is fine but the denominator is zero; the
-- function's inv_sum = 0 guard returns NULL instead of dividing by it.
--
-- Negative inputs are outside the harmonic mean's domain (positive reals).
-- They are unguarded by design and pass through as the plain formula result:
-- 2 / (1/-10 + 1/20) = -40. Asserted so that any change to that is deliberate.
SELECT 'Test 9: cancelling reciprocals return NULL; negatives pass through' AS '';

SELECT HARMONIC_MEAN(val) INTO @hm_cancel
FROM agg_edge_cases WHERE grp = 'cancel';

SELECT HARMONIC_MEAN(val) INTO @hm_neg
FROM agg_edge_cases WHERE grp = 'neg';

SET @hm_cancel_failures = IF(@hm_cancel IS NULL, 0, 1)
                        + IF(ABS(@hm_neg - (-40)) / 40 <= @tolerance, 0, 1);

SELECT IF(@hm_cancel_failures = 0,
          'PASS: cancel gives NULL, neg gives -40',
          CONCAT('FAIL: cancel gave ', IFNULL(@hm_cancel, 'NULL'),
                 ', neg gave ', IFNULL(@hm_neg, 'NULL'))) AS '';

-- ---------------------------------------------------------------------------
-- Test 10: text input
-- ---------------------------------------------------------------------------
-- a) Numeric strings coerce to the right DOUBLE. The two values come from a
--    derived table, not a WHERE filter on agg_edge_cases: a filtered-out
--    'abc' row there was observed to raise the conversion error on MariaDB
--    13.0.2 (cause not yet established). The expected value
--    uses e0 literals so it is computed in DOUBLE, not rounded DECIMAL.
SELECT 'Test 10a: numeric strings coerce correctly' AS '';

SELECT HARMONIC_MEAN(v) INTO @hm_text
FROM (SELECT '12.5' AS v UNION ALL SELECT '20') t;

SET @hm_text_expected = 2 / (1 / 12.5e0 + 1 / 20e0);

SELECT IF(ABS(@hm_text - @hm_text_expected) / @hm_text_expected <= @tolerance,
          'PASS: ''12.5'' and ''20'' coerce correctly',
          CONCAT('FAIL: got ', IFNULL(@hm_text, 'NULL'),
                 ', expected ', @hm_text_expected)) AS '';

-- b) Junk text never produces a number, asserted separately in each mode.
--    Converting 'abc' to the DOUBLE argument follows the caller's SESSION
--    sql_mode, not the mode stored with the function, so each leg sets the
--    session mode itself and the test does not depend on the server's
--    defaults. The original mode is restored afterwards for later tests.
--    A sentinel shows whether the statement completed: an error leaves
--    @hm_junk untouched, a warning does not. The handler is for SQLEXCEPTION,
--    which does not fire on the non-strict 1366 warning (a handler naming
--    SQLSTATE '22007' would); it records every condition's errno so a failure
--    message shows the full chain.
SET @saved_sql_mode = @@SESSION.sql_mode;

-- Strict: the conversion must fail with error 1366 before the function body
-- runs, and nothing may be assigned. This leg checks MariaDB's conversion,
-- not the function: it passes with or without the zero guard.
SELECT 'Test 10b (strict): junk text raises error 1366' AS '';
SET SESSION sql_mode = 'STRICT_ALL_TABLES';
SET @hm_junk = 'not assigned';
SET @hm_junk_errno = NULL;

DELIMITER //
BEGIN NOT ATOMIC
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE i INT DEFAULT 1;
        DECLARE n INT;
        DECLARE e INT;
        GET DIAGNOSTICS n = NUMBER;
        WHILE i <= n DO
            GET DIAGNOSTICS CONDITION i e = MYSQL_ERRNO;
            SET @hm_junk_errno = CONCAT_WS(',', @hm_junk_errno, e);
            SET i = i + 1;
        END WHILE;
    END;
    SELECT HARMONIC_MEAN(val_text) INTO @hm_junk
    FROM agg_edge_cases WHERE grp = 'text';
END //
DELIMITER ;

SET @hm_junk_strict_ok = (@hm_junk_errno <=> '1366' AND @hm_junk <=> 'not assigned');

SELECT IF(@hm_junk_strict_ok,
          'PASS: strict mode raised 1366, nothing assigned',
          CONCAT('FAIL: conditions ', IFNULL(@hm_junk_errno, 'none'),
                 ', result ', IFNULL(@hm_junk, 'NULL'))) AS '';

-- Non-strict: 'abc' becomes 0 with warning 1366, reaches the body, and the
-- zero guard must return NULL. The statement must complete (sentinel
-- replaced) and the result must be NULL, not a number. This is the leg that
-- exercises the guard.
SELECT 'Test 10b (non-strict): junk text returns NULL via the zero guard' AS '';
SET SESSION sql_mode = '';
SET @hm_junk = 'not assigned';
SET @hm_junk_errno = NULL;

DELIMITER //
BEGIN NOT ATOMIC
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE i INT DEFAULT 1;
        DECLARE n INT;
        DECLARE e INT;
        GET DIAGNOSTICS n = NUMBER;
        WHILE i <= n DO
            GET DIAGNOSTICS CONDITION i e = MYSQL_ERRNO;
            SET @hm_junk_errno = CONCAT_WS(',', @hm_junk_errno, e);
            SET i = i + 1;
        END WHILE;
    END;
    SELECT HARMONIC_MEAN(val_text) INTO @hm_junk
    FROM agg_edge_cases WHERE grp = 'text';
END //
DELIMITER ;

SET @hm_junk_loose_ok = (@hm_junk IS NULL);

SELECT IF(@hm_junk_loose_ok,
          'PASS: non-strict mode returned NULL',
          CONCAT('FAIL: conditions ', IFNULL(@hm_junk_errno, 'none'),
                 ', result ', IFNULL(@hm_junk, 'NULL'))) AS '';

SET SESSION sql_mode = @saved_sql_mode;

-- ---------------------------------------------------------------------------
-- Test 11: a NULL value makes the whole group NULL
-- ---------------------------------------------------------------------------
-- The NULL case the supervisor's feedback asked for, which the task doc's
-- seven tests did not cover. 1/NULL is NULL, so inv_sum and the result go
-- NULL. This differs from built-in AVG, which skips NULLs: AVG over 10, NULL,
-- 30 is 20.
SELECT 'Test 11: HARMONIC_MEAN with a NULL value returns NULL' AS '';

SELECT HARMONIC_MEAN(val) INTO @hm_null
FROM agg_edge_cases WHERE grp = 'has_null';

SELECT IF(@hm_null IS NULL,
          'PASS: NULL value gives NULL',
          CONCAT('FAIL: NULL value gave ', @hm_null)) AS '';

-- ---------------------------------------------------------------------------
-- Fail the run if anything above failed
-- ---------------------------------------------------------------------------
-- SIGNAL makes the client exit non-zero, which is what CI checks. Without it
-- a failing test would print "FAIL" and the build would still go green.

SET @total_failures = @failures + @amgm_violations + IF(@empty_result IS NULL, 0, 1)
                    + @hm_failures + @hmgm_violations
                    + IF(@hm_ties <=> 7, 0, 1) + IF(@hm_empty IS NULL, 0, 1)
                    + IF(@hm_zero IS NULL, 0, 1) + @hm_cancel_failures
                    + IF(ABS(@hm_text - @hm_text_expected) / @hm_text_expected <= @tolerance, 0, 1)
                    + IF(@hm_junk_strict_ok, 0, 1) + IF(@hm_junk_loose_ok, 0, 1)
                    + IF(@hm_null IS NULL, 0, 1);

DELIMITER //
BEGIN NOT ATOMIC
    IF @total_failures > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Aggregate function tests failed';
    END IF;
END //
DELIMITER ;

SELECT 'All tests passed.' AS '';
