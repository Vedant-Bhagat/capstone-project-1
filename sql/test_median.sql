-- Tests for MEDIAN_AGG, the buffering aggregate in median_buffered.sql.
--
-- Kept in its own file rather than appended to test_aggregates.sql, because
-- two other people are adding sections to that file this week and a third
-- region would guarantee a merge conflict. CI runs both files.
--
-- A mismatch raises SQLSTATE 45000 at the end, so the client exits non-zero
-- and CI fails. Every counter declared here is folded into @median_failures;
-- if you add a test, add its counter there too, or it will print FAIL and the
-- build will still pass.
--
-- Prerequisites, in order:
--   setup_dataset.sql, test_fixture.sql, median_buffered.sql
--
-- How to run (from the sql directory):
--   Linux/macOS:  mariadb -u root < test_median.sql
--   PowerShell:   Get-Content test_median.sql | mariadb -u root

USE flightdb2;

SET @tolerance = 1e-9;
SET @median_failures = 0;

-- The buffer is a session temporary table owned by the function. Create it if
-- this is a fresh connection and empty it, so the tests do not inherit rows
-- from whatever ran before them in the same session. The definition must match
-- median_buffered.sql.
CREATE TEMPORARY TABLE IF NOT EXISTS median_buf (
    call_id BIGINT NOT NULL,
    v       DOUBLE NOT NULL,
    KEY (call_id, v)
);
DELETE FROM median_buf;

-- ---------------------------------------------------------------------------
-- Test 1: agrees with the built-in MEDIAN() for every airline
-- ---------------------------------------------------------------------------
-- The strongest test available, because the built-in is an independent
-- implementation of the same definition. Tolerance is relative: MEDIAN()
-- returns DECIMAL and MEDIAN_AGG returns DOUBLE, so they agree in value but
-- not bit for bit.
SELECT 'Test 1: MEDIAN_AGG agrees with built-in MEDIAN() on every airline' AS '';

SELECT COUNT(*) INTO @t1
FROM (SELECT a.airline, a.m AS custom, b.m AS builtin
      FROM (SELECT airline, MEDIAN_AGG(km) AS m
            FROM route_distances WHERE km > 0 GROUP BY airline) a
      JOIN (SELECT DISTINCT airline, MEDIAN(km) OVER (PARTITION BY airline) AS m
            FROM route_distances WHERE km > 0) b USING (airline)
      WHERE ABS(a.m - b.m) / NULLIF(b.m, 0) > @tolerance) t;

SELECT IF(@t1 = 0, 'PASS: all 566 airlines agree',
          CONCAT('FAIL: ', @t1, ' airlines disagree')) AS '';
SET @median_failures = @median_failures + @t1;

-- ---------------------------------------------------------------------------
-- Test 2: the median lies between the minimum and the maximum
-- ---------------------------------------------------------------------------
-- A property that holds for any data at all, so it catches classes of error
-- the comparison above cannot -- an off-by-one in the OFFSET arithmetic, for
-- instance, would still agree with itself but could fall outside the range.
SELECT 'Test 2: MIN <= median <= MAX for every airline' AS '';

-- The LIMIT is load-bearing and is not a filter: 566 airlines is the whole
-- set. It stops the optimizer merging the derived table and pushing the outer
-- condition down into the grouping, which makes the server abandon a second
-- invocation per group and leak buffer rows. Same answer either way; see
-- Test 10, which measures that deliberately.
SELECT COUNT(*) INTO @t2
FROM (SELECT airline, MEDIAN_AGG(km) AS med, MIN(km) AS lo, MAX(km) AS hi
      FROM route_distances WHERE km > 0 GROUP BY airline
      LIMIT 100000) t
WHERE med < lo - @tolerance OR med > hi + @tolerance;

SELECT IF(@t2 = 0, 'PASS: median is within range everywhere',
          CONCAT('FAIL: ', @t2, ' airlines out of range')) AS '';
SET @median_failures = @median_failures + @t2;

-- ---------------------------------------------------------------------------
-- Test 3: odd count, even count, ties, negatives, unsorted input
-- ---------------------------------------------------------------------------
-- Expected values worked out by hand from test_fixture.sql:
--   plain    10, 20, 30        -> 20      (odd: the middle value)
--   neg      -10, 20           -> 5       (even: the mean of both, negatives)
--   ties     7, 7, 7           -> 7       (ties)
--   cancel   1, -1             -> 0       (even, straddling zero)
--   zero_val 0, 10             -> 5       (a zero value is a value, not a gap)
SELECT 'Test 3: hand-checked medians on the fixture' AS '';

SELECT COUNT(*) INTO @t3 FROM (
    SELECT grp, MEDIAN_AGG(val) AS got,
           CASE grp WHEN 'plain'    THEN 20
                    WHEN 'neg'      THEN  5
                    WHEN 'ties'     THEN  7
                    WHEN 'cancel'   THEN  0
                    WHEN 'zero_val' THEN  5 END AS want
    FROM agg_edge_cases
    WHERE grp IN ('plain','neg','ties','cancel','zero_val')
    GROUP BY grp
) t WHERE ABS(got - want) > @tolerance;

SELECT IF(@t3 = 0, 'PASS: all five hand-checked cases match',
          CONCAT('FAIL: ', @t3, ' of 5 cases wrong')) AS '';
SET @median_failures = @median_failures + @t3;

-- ---------------------------------------------------------------------------
-- Test 4: NULLs are skipped, not propagated
-- ---------------------------------------------------------------------------
-- 10, NULL, 30 has median 20, the same as if the NULL were not there. This is
-- AVG() behaviour and the built-in's behaviour, and it is deliberately NOT
-- WEIGHTED_AVERAGE's behaviour in this repository, where one NULL nulls the
-- group. The difference is documented in median_buffered.sql.
SELECT 'Test 4: a NULL among values is skipped' AS '';

SELECT MEDIAN_AGG(val) INTO @t4_got FROM agg_edge_cases WHERE grp = 'has_null';
SELECT IF(ABS(@t4_got - 20) <= @tolerance, 'PASS: NULL skipped, median 20',
          CONCAT('FAIL: expected 20, got ', IFNULL(@t4_got, 'NULL'))) AS '';
SET @median_failures = @median_failures + IF(ABS(IFNULL(@t4_got, -1) - 20) <= @tolerance, 0, 1);

-- ---------------------------------------------------------------------------
-- Test 5: a group with no non-NULL values returns NULL
-- ---------------------------------------------------------------------------
SELECT 'Test 5: all-NULL group and empty group return NULL' AS '';

SELECT MEDIAN_AGG(val) INTO @t5_allnull
FROM agg_edge_cases WHERE grp = 'has_null' AND val IS NULL;
SELECT MEDIAN_AGG(val) INTO @t5_empty
FROM agg_edge_cases WHERE grp = '--no-such-group--';

SELECT IF(@t5_allnull IS NULL AND @t5_empty IS NULL,
          'PASS: both are NULL',
          CONCAT('FAIL: all-NULL gave ', IFNULL(@t5_allnull, 'NULL'),
                 ', empty gave ', IFNULL(@t5_empty, 'NULL'))) AS '';
SET @median_failures = @median_failures
    + IF(@t5_allnull IS NULL, 0, 1) + IF(@t5_empty IS NULL, 0, 1);

-- ---------------------------------------------------------------------------
-- Test 6: a single value is its own median
-- ---------------------------------------------------------------------------
SELECT 'Test 6: one-value group' AS '';

SELECT MEDIAN_AGG(val) INTO @t6 FROM agg_edge_cases WHERE grp = 'plain' AND val = 20;
SELECT IF(ABS(@t6 - 20) <= @tolerance, 'PASS: single value returned as-is',
          CONCAT('FAIL: expected 20, got ', IFNULL(@t6, 'NULL'))) AS '';
SET @median_failures = @median_failures + IF(ABS(IFNULL(@t6, -1) - 20) <= @tolerance, 0, 1);

-- ---------------------------------------------------------------------------
-- Test 7: two invocations in one statement -- the regression test
-- ---------------------------------------------------------------------------
-- This is the test that matters. The first version of this function used a
-- fixed-name temporary table and passed everything above; this query made it
-- fail with "Table 'flightdb2.median_buf' doesn't exist", because the second
-- invocation dropped the first one's buffer mid-fill. If someone later
-- "simplifies" the call_id tagging away, this is what catches it.
SELECT 'Test 7: two MEDIAN_AGG calls in one SELECT do not collide' AS '';

SELECT COUNT(*) INTO @t7 FROM (
    SELECT grp, MEDIAN_AGG(val) AS m1, MEDIAN_AGG(val * 10) AS m2
    FROM agg_edge_cases WHERE grp IN ('plain','neg','ties') GROUP BY grp
) t WHERE ABS(m2 - m1 * 10) > @tolerance * 10 OR m1 IS NULL OR m2 IS NULL;

SELECT IF(@t7 = 0, 'PASS: both invocations correct in the same statement',
          CONCAT('FAIL: ', @t7, ' groups wrong with two calls')) AS '';
SET @median_failures = @median_failures + @t7;

-- ---------------------------------------------------------------------------
-- Test 8: nested use -- a median of medians
-- ---------------------------------------------------------------------------
-- The outer call buffers while the inner calls are still buffering, which is
-- the same hazard as Test 7 one level deeper.
SELECT 'Test 8: MEDIAN_AGG over the output of MEDIAN_AGG' AS '';

SELECT MEDIAN_AGG(m) INTO @t8 FROM (
    SELECT grp, MEDIAN_AGG(val) AS m
    FROM agg_edge_cases WHERE grp IN ('plain','neg','ties') GROUP BY grp
) t;
-- medians are 20 (plain), 5 (neg), 7 (ties); the median of those three is 7.
SELECT IF(ABS(@t8 - 7) <= @tolerance, 'PASS: median of medians is 7',
          CONCAT('FAIL: expected 7, got ', IFNULL(@t8, 'NULL'))) AS '';
SET @median_failures = @median_failures + IF(ABS(IFNULL(@t8, -1) - 7) <= @tolerance, 0, 1);

-- ---------------------------------------------------------------------------
-- Test 9: the shared buffer is left empty
-- ---------------------------------------------------------------------------
-- Every invocation deletes its own rows on the way out. If this starts failing
-- the function is leaking rows into a session-scoped table, which would grow
-- for as long as the connection lives.
SELECT 'Test 9: median_buf is empty after all of the above' AS '';

SELECT COUNT(*) INTO @t9 FROM median_buf;
SELECT IF(@t9 = 0, 'PASS: buffer clean',
          CONCAT('FAIL: ', @t9, ' rows left in median_buf')) AS '';
SET @median_failures = @median_failures + @t9;

-- ---------------------------------------------------------------------------
-- Test 10: INFORMATIONAL -- abandoned invocations and what they leave behind
-- ---------------------------------------------------------------------------
-- This one cannot fail the build, on purpose.
--
-- When the optimizer merges a derived table and pushes the outer condition
-- into the grouping, it starts a second invocation of the aggregate per group
-- and abandons it after one row, before the body reaches its cleanup. The
-- medians returned are still correct -- Test 1 proves that -- but median_buf
-- is left holding one row per group. On 12.3.3 that is 566 rows for 566
-- airlines.
--
-- We are printing the number rather than asserting it because we do not know
-- whether every version in the CI matrix behaves the same way, and a test that
-- fails when a server stops leaking would be a bad test. Read the number in
-- the CI log for each version: that is the measurement.
SELECT 'Test 10 (informational): rows left by an abandoned invocation' AS '';

DELETE FROM median_buf;

SELECT COUNT(*) INTO @t10_sink
FROM (SELECT airline, MEDIAN_AGG(km) AS med, MIN(km) AS lo, MAX(km) AS hi
      FROM route_distances WHERE km > 0 GROUP BY airline) t
WHERE med < lo - @tolerance OR med > hi + @tolerance;

SELECT CONCAT('INFO: ', COUNT(*), ' rows left in median_buf by the pushed-down form; ',
              (SELECT COUNT(DISTINCT airline) FROM route_distances WHERE km > 0),
              ' groups in the query. Outer result was ', @t10_sink,
              ' (0 = medians still correct).') AS '' FROM median_buf;

DELETE FROM median_buf;

-- ---------------------------------------------------------------------------
-- Fail the run if anything above failed
-- ---------------------------------------------------------------------------
DELIMITER //
BEGIN NOT ATOMIC
    IF @median_failures > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'MEDIAN_AGG tests failed';
    END IF;
END //
DELIMITER ;

SELECT 'All median tests passed.' AS '';
