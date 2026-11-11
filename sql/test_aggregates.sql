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

-- ===========================================================================
-- WEIGHTED_AVERAGE (Tests 12-18)
-- ===========================================================================
-- Defined in janhavi_example.sql, together with the airline_route_stats view
-- (per-airline mean distance and route count, joined on routes.alid). Numbered
-- from 12 because Tests 4-11 are HARMONIC_MEAN's.

-- ---------------------------------------------------------------------------
-- Test 12: WEIGHTED_AVERAGE agrees with SUM(v*w) / SUM(w)
-- ---------------------------------------------------------------------------
-- The main correctness test, same shape as Test 1, over every country. The
-- country count is checked too, so an empty join cannot pass vacuously.
-- The comparison is written inverted (`<= @tolerance) IS NOT TRUE`) so that a
-- country whose comparison cannot be evaluated -- a NULL `custom`, say -- counts
-- as a failure. `SUM(x > y)` would be NULL if every row were NULL, and a NULL
-- addend would make @total_failures NULL and silence the SIGNAL below.
SELECT 'Test 12: WEIGHTED_AVERAGE vs SUM(v*w)/SUM(w)' AS '';

SELECT COUNT(*), SUM((ABS(custom - closed_form) / closed_form <= @tolerance) IS NOT TRUE)
  INTO @wa_countries, @wa_failures
FROM (SELECT al.country,
             WEIGHTED_AVERAGE(x.mean_km, x.route_count)       AS custom,
             SUM(x.mean_km * x.route_count) / SUM(x.route_count) AS closed_form
      FROM airline_route_stats x
      JOIN airlines al ON al.alid = x.alid
      GROUP BY al.country) t;

SET @wa_failures = IF(@wa_countries > 0, @wa_failures, 1);

SELECT IF(@wa_failures = 0,
          CONCAT('PASS: all ', @wa_countries, ' countries agree'),
          CONCAT('FAIL: ', @wa_failures, ' of ', @wa_countries, ' countries disagree')) AS '';

-- ---------------------------------------------------------------------------
-- Test 13: equal weights reduce to AVG()
-- ---------------------------------------------------------------------------
-- A property that holds regardless of data. With every weight 1 the weighted
-- mean is the plain mean: (10 + 20 + 30) / 3 = 20.
SELECT 'Test 13: WEIGHTED_AVERAGE with equal weights equals AVG()' AS '';

SELECT WEIGHTED_AVERAGE(val, weight), AVG(val) INTO @wa_plain, @wa_plain_avg
FROM agg_edge_cases WHERE grp = 'plain';

SET @wa_plain_ok = (ABS(@wa_plain - @wa_plain_avg) / @wa_plain_avg <= @tolerance
                    AND ABS(@wa_plain - 20) / 20 <= @tolerance);

SELECT IF(@wa_plain_ok,
          'PASS: equal weights give AVG() = 20',
          CONCAT('FAIL: got ', IFNULL(@wa_plain, 'NULL'),
                 ', AVG() is ', IFNULL(@wa_plain_avg, 'NULL'))) AS '';

-- ---------------------------------------------------------------------------
-- Test 14: weighted mean of airline means == plain AVG over all routes
-- ---------------------------------------------------------------------------
-- The independent check janhavi_example.sql claims in its closing comment.
-- Because each airline's mean is weighted by its own route count, the result
-- must equal the ordinary average over every route the country's airlines fly.
-- It goes back to route_distances, so it does not share code with Test 12.
SELECT 'Test 14: WEIGHTED_AVERAGE of airline means == AVG(km) over all routes' AS '';

SELECT COUNT(*), SUM((ABS(w.weighted - p.pooled) / p.pooled <= @tolerance) IS NOT TRUE)
  INTO @wa_pool_countries, @wa_pool_failures
FROM (SELECT al.country, WEIGHTED_AVERAGE(x.mean_km, x.route_count) AS weighted
      FROM airline_route_stats x
      JOIN airlines al ON al.alid = x.alid
      GROUP BY al.country) w
JOIN (SELECT al.country, AVG(d.km) AS pooled
      FROM route_distances d
      JOIN routes r    ON r.rid = d.rid
      JOIN airlines al ON al.alid = r.alid
      WHERE d.km > 0
      GROUP BY al.country) p
  ON p.country <=> w.country;

SET @wa_pool_failures = IF(@wa_pool_countries > 0, @wa_pool_failures, 1);

SELECT IF(@wa_pool_failures = 0,
          CONCAT('PASS: all ', @wa_pool_countries, ' countries agree with the pooled AVG'),
          CONCAT('FAIL: ', @wa_pool_failures, ' of ', @wa_pool_countries,
                 ' countries disagree')) AS '';

-- ---------------------------------------------------------------------------
-- Test 15: all-zero weights return NULL
-- ---------------------------------------------------------------------------
-- The function's explicit `IF weight_total = 0 THEN RETURN NULL` branch. A
-- weighted mean with no weight is undefined, so NULL and not 0 or an error.
SELECT 'Test 15: WEIGHTED_AVERAGE with all-zero weights returns NULL' AS '';

SELECT WEIGHTED_AVERAGE(val, weight) INTO @wa_zero_wt
FROM agg_edge_cases WHERE grp = 'zero_wt';

SELECT IF(@wa_zero_wt IS NULL,
          'PASS: all-zero weights give NULL',
          CONCAT('FAIL: all-zero weights gave ', @wa_zero_wt)) AS '';

-- ---------------------------------------------------------------------------
-- Test 16: a NULL value or a NULL weight makes the whole group NULL
-- ---------------------------------------------------------------------------
-- The limit documented in janhavi_example.sql, asserted rather than fixed.
-- val * weight is NULL, so weighted_sum goes NULL and stays NULL. This differs
-- from the inline formula, whose SUM() skips the NULL row: on has_null it gives
-- 13.33 and on null_wt 10, so the two are NOT interchangeable on dirty data.
SELECT 'Test 16: WEIGHTED_AVERAGE with a NULL value or weight returns NULL' AS '';

SELECT WEIGHTED_AVERAGE(val, weight) INTO @wa_null_val
FROM agg_edge_cases WHERE grp = 'has_null';
SELECT WEIGHTED_AVERAGE(val, weight) INTO @wa_null_wt
FROM agg_edge_cases WHERE grp = 'null_wt';

SET @wa_null_ok = (@wa_null_val IS NULL AND @wa_null_wt IS NULL);

SELECT IF(@wa_null_ok,
          'PASS: NULL value and NULL weight both give NULL',
          CONCAT('FAIL: NULL value gave ', IFNULL(@wa_null_val, 'NULL'),
                 ', NULL weight gave ', IFNULL(@wa_null_wt, 'NULL'))) AS '';

-- ---------------------------------------------------------------------------
-- Test 17: weights that cancel to zero return NULL
-- ---------------------------------------------------------------------------
-- Observed, then asserted. Weights 2 and -2 sum to 0 by cancellation, so the
-- same zero-weight branch as Test 15 fires and the result is NULL even though
-- both rows carry real data. (The inline formula divides by zero and is NULL
-- too.) A negative weight is not rejected -- it is accepted and can silently
-- erase the group; a negative VALUE with positive weights is fine (grp 'neg'
-- gives 5).
SELECT 'Test 17: WEIGHTED_AVERAGE with cancelling weights returns NULL' AS '';

SELECT WEIGHTED_AVERAGE(val, weight) INTO @wa_neg_wt
FROM agg_edge_cases WHERE grp = 'neg_wt';
SELECT WEIGHTED_AVERAGE(val, weight) INTO @wa_neg_val
FROM agg_edge_cases WHERE grp = 'neg';

SET @wa_neg_ok = (@wa_neg_wt IS NULL AND ABS(@wa_neg_val - 5) / 5 <= @tolerance);

SELECT IF(@wa_neg_ok,
          'PASS: cancelling weights give NULL; a negative value gives 5',
          CONCAT('FAIL: neg_wt gave ', IFNULL(@wa_neg_wt, 'NULL'),
                 ', neg gave ', IFNULL(@wa_neg_val, 'NULL'))) AS '';

-- ---------------------------------------------------------------------------
-- Test 18: text input
-- ---------------------------------------------------------------------------
-- Same structure as Test 10, for the same reasons: conversion to the DOUBLE
-- argument follows the caller's SESSION sql_mode, so each leg sets it.
--
-- a) Numeric strings coerce correctly: ('12.5' + '20') / 2 = 16.25. From a
--    derived table, as in Test 10a.
SELECT 'Test 18a: numeric strings coerce correctly' AS '';

SELECT WEIGHTED_AVERAGE(v, 1) INTO @wa_text
FROM (SELECT '12.5' AS v UNION ALL SELECT '20') t;

SET @wa_text_ok = (ABS(@wa_text - 16.25e0) / 16.25e0 <= @tolerance);

SELECT IF(@wa_text_ok,
          'PASS: ''12.5'' and ''20'' coerce to 16.25',
          CONCAT('FAIL: got ', IFNULL(@wa_text, 'NULL'), ', expected 16.25')) AS '';

SET @saved_sql_mode = @@SESSION.sql_mode;

-- b) Strict: 'abc' raises error 1366 and nothing is assigned.
SELECT 'Test 18b (strict): junk text raises error 1366' AS '';
SET SESSION sql_mode = 'STRICT_ALL_TABLES';
SET @wa_junk = 'not assigned';
SET @wa_junk_errno = NULL;

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
            SET @wa_junk_errno = CONCAT_WS(',', @wa_junk_errno, e);
            SET i = i + 1;
        END WHILE;
    END;
    SELECT WEIGHTED_AVERAGE(val_text, weight) INTO @wa_junk
    FROM agg_edge_cases WHERE grp = 'text';
END //
DELIMITER ;

SET @wa_junk_strict_ok = (@wa_junk_errno <=> '1366' AND @wa_junk <=> 'not assigned');

SELECT IF(@wa_junk_strict_ok,
          'PASS: strict mode raised 1366, nothing assigned',
          CONCAT('FAIL: conditions ', IFNULL(@wa_junk_errno, 'none'),
                 ', result ', IFNULL(@wa_junk, 'NULL'))) AS '';

-- c) Non-strict: 'abc' becomes 0 with only warning 1366 and is COUNTED as a
--    real value: (12.5 + 20 + 0) / 3 = 10.8333. A plausible-looking wrong
--    number, not NULL. HARMONIC_MEAN returns NULL here only because its zero
--    guard catches the 0; WEIGHTED_AVERAGE has no such guard, and 0 is a
--    legitimate value for it, so nothing can catch it. Asserted as the real
--    behaviour, not fixed: the defence is strict sql_mode, which every
--    supported server version uses by default.
SELECT 'Test 18c (non-strict): junk text silently counts as 0' AS '';
SET SESSION sql_mode = '';
SET @wa_junk = 'not assigned';
SET @wa_junk_errno = NULL;

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
            SET @wa_junk_errno = CONCAT_WS(',', @wa_junk_errno, e);
            SET i = i + 1;
        END WHILE;
    END;
    SELECT WEIGHTED_AVERAGE(val_text, weight) INTO @wa_junk
    FROM agg_edge_cases WHERE grp = 'text';
END //
DELIMITER ;

SET @wa_junk_expected = (12.5e0 + 20e0 + 0e0) / 3;
SET @wa_junk_loose_ok = (@wa_junk_errno IS NULL
                         AND ABS(@wa_junk - @wa_junk_expected) / @wa_junk_expected <= @tolerance);

SELECT IF(@wa_junk_loose_ok,
          'PASS: non-strict mode counted ''abc'' as 0, giving 10.8333',
          CONCAT('FAIL: conditions ', IFNULL(@wa_junk_errno, 'none'),
                 ', result ', IFNULL(@wa_junk, 'NULL'),
                 ', expected ', @wa_junk_expected)) AS '';

SET SESSION sql_mode = @saved_sql_mode;

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
                    + IF(@hm_null IS NULL, 0, 1)
                    + @wa_failures + IF(@wa_plain_ok, 0, 1) + @wa_pool_failures
                    + IF(@wa_zero_wt IS NULL, 0, 1) + IF(@wa_null_ok, 0, 1)
                    + IF(@wa_neg_ok, 0, 1) + IF(@wa_text_ok, 0, 1)
                    + IF(@wa_junk_strict_ok, 0, 1) + IF(@wa_junk_loose_ok, 0, 1);

DELIMITER //
BEGIN NOT ATOMIC
    IF @total_failures > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Aggregate function tests failed';
    END IF;
END //
DELIMITER ;

SELECT 'All tests passed.' AS '';
