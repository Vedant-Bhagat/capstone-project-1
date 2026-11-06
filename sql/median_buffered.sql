-- Custom Aggregate Functions in MariaDB: MEDIAN_AGG, the one that has to buffer
--
-- The other three aggregates in this repository (GEOMETRIC_MEAN, HARMONIC_MEAN,
-- WEIGHTED_AVERAGE) are all *streaming*: each row is folded into a running
-- total and then forgotten. That is what `FETCH GROUP NEXT ROW` is comfortable
-- with, because the cursor moves forward one row at a time and never rewinds.
--
-- A median cannot be computed that way. You cannot know which value sits in the
-- middle until you have seen them all, so the function must keep the whole
-- group in memory -- or somewhere -- before it can answer. That makes it the
-- interesting case for the feature, and it is why this file exists: the
-- repository README used to name this limit and stop there.
--
-- What it demonstrates, in order of how surprising it is:
--
--   1. A stored aggregate CAN buffer its group, in a TEMPORARY table created
--      inside the function body. This is not obvious -- stored functions are
--      barred from many statements -- but temporary-table DDL is allowed.
--   2. The obvious version is wrong. See "First attempt" below.
--   3. The fix cannot use the obvious tool either, because PREPARE is not
--      allowed in a function, so the buffer cannot be given a unique name.
--   4. It is about 5x slower than three alternatives that already exist, one
--      of which is a built-in MEDIAN(). Measured below.
--
-- Prerequisites: load the dataset and run setup_dataset.sql first (see the
-- README Setup section). It creates the `route_distances` view used here.
--
-- How to run (from the sql directory):
--   Linux/macOS:  mariadb -u root < median_buffered.sql
--   PowerShell:   Get-Content median_buffered.sql | mariadb -u root

USE flightdb2;

-- ---------------------------------------------------------------------------
-- Why the function is not called MEDIAN
-- ---------------------------------------------------------------------------
-- Because that name is taken, and not politely:
--
--   CREATE AGGREGATE FUNCTION MEDIAN(x DOUBLE) RETURNS DOUBLE ...
--   ERROR 1064 (42000): You have an error in your SQL syntax [...] near
--   'MEDIAN(x DOUBLE) RETURNS DOUBLE ...'
--
-- MEDIAN is a reserved word for the built-in window function, so the parser
-- rejects it as a routine name outright. That is the first hint of where this
-- file ends up: MariaDB already has a median, it just does not have one you
-- can use with GROUP BY.

-- ---------------------------------------------------------------------------
-- First attempt, and why it is wrong
-- ---------------------------------------------------------------------------
-- The natural shape is to create a fixed-name temporary table at the top of
-- the body and drop it at the bottom:
--
--     DROP TEMPORARY TABLE IF EXISTS median_buf;
--     CREATE TEMPORARY TABLE median_buf (v DOUBLE NOT NULL, KEY(v));
--     ... INSERT each row ...
--     SELECT v INTO lo FROM median_buf ORDER BY v LIMIT 1 OFFSET n/2;
--     DROP TEMPORARY TABLE median_buf;
--
-- That passes every test you are likely to write, because every test calls the
-- function once. Call it twice in one statement and it fails:
--
--     SELECT grp, MEDIAN_AGG(v), MEDIAN_AGG(v * 10) FROM t GROUP BY grp;
--     ERROR 1146 (42S02): Table 'flightdb2.median_buf' doesn't exist
--
-- The two invocations interleave, and the second one's DROP destroys the first
-- one's buffer while it is still filling it. The obvious fix -- give each
-- invocation its own table name -- is not available, because building a
-- statement from a variable needs PREPARE, and prepared statements are not
-- allowed inside a stored function.
--
-- So the buffer has to be shared and multiplexed instead: one table, created
-- once if absent and never dropped, with every row tagged by an invocation
-- counter kept in a session variable. Each call reads and deletes only its own
-- rows. That is the version below.

DROP FUNCTION IF EXISTS MEDIAN_AGG;

DELIMITER //

CREATE AGGREGATE FUNCTION MEDIAN_AGG(x DOUBLE) RETURNS DOUBLE
BEGIN
    DECLARE n       INT    DEFAULT 0;   -- values buffered for this call
    DECLARE lo      DOUBLE;             -- lower middle value
    DECLARE hi      DOUBLE;             -- upper middle value (= lo when n is odd)
    DECLARE skip_to INT    DEFAULT 0;
    DECLARE my_call BIGINT;             -- this invocation's tag
    DECLARE done    INT    DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Created once per session, never dropped: see "First attempt" above.
    -- The index on (call_id, v) is what makes the two ORDER BY ... OFFSET
    -- lookups at the end cheap instead of two sorts of the whole buffer.
    CREATE TEMPORARY TABLE IF NOT EXISTS median_buf (
        call_id BIGINT NOT NULL,
        v       DOUBLE NOT NULL,
        KEY (call_id, v)
    );

    SET @median_calls = COALESCE(@median_calls, 0) + 1;
    SET my_call = @median_calls;

    -- Defensive: if a previous call was interrupted mid-flight its rows are
    -- still here. The counter never repeats within a session, so this is
    -- cheap insurance rather than a real cleanup.
    DELETE FROM median_buf WHERE call_id = my_call;

    main_loop: LOOP
        FETCH GROUP NEXT ROW;
        IF done THEN
            LEAVE main_loop;
        END IF;
        -- NULLs are skipped, matching AVG() and the built-in MEDIAN(). Note
        -- that this differs from WEIGHTED_AVERAGE in this repository, where a
        -- single NULL makes the whole group NULL. Two aggregates in one project
        -- disagreeing about NULL is itself worth knowing.
        IF x IS NOT NULL THEN
            INSERT INTO median_buf (call_id, v) VALUES (my_call, x);
        END IF;
    END LOOP main_loop;

    SELECT COUNT(*) INTO n FROM median_buf WHERE call_id = my_call;
    IF n = 0 THEN
        RETURN NULL;                    -- empty group, or every value NULL
    END IF;

    -- Odd n: the single middle value. Even n: the mean of the two middle
    -- values, which is the convention the built-in MEDIAN() follows.
    SET skip_to = FLOOR((n - 1) / 2);
    SELECT v INTO lo FROM median_buf
     WHERE call_id = my_call ORDER BY v LIMIT 1 OFFSET skip_to;

    IF MOD(n, 2) = 1 THEN
        SET hi = lo;
    ELSE
        SET skip_to = skip_to + 1;
        SELECT v INTO hi FROM median_buf
         WHERE call_id = my_call ORDER BY v LIMIT 1 OFFSET skip_to;
    END IF;

    DELETE FROM median_buf WHERE call_id = my_call;
    RETURN (lo + hi) / 2;
END //

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Option A: the custom aggregate (the feature under test)
-- ---------------------------------------------------------------------------
-- Reads the way you want it to: one GROUP BY, one call site.
SELECT '--- Option A: custom aggregate MEDIAN_AGG(km) with GROUP BY ---' AS label;
SELECT airline,
       COUNT(*)                   AS routes,
       ROUND(AVG(km), 1)          AS mean_km,
       ROUND(MEDIAN_AGG(km), 1)   AS median_km
FROM route_distances
WHERE km > 0
GROUP BY airline
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Option B: the built-in MEDIAN(), which is window-only
-- ---------------------------------------------------------------------------
-- MariaDB has had MEDIAN() since 10.3, but only as a window function. There is
-- no GROUP BY form, so the group has to be rebuilt with PARTITION BY and then
-- collapsed again with DISTINCT. This is the same limitation the README notes
-- from the other direction: a custom aggregate cannot be a window function,
-- and the built-in median cannot be anything else.
--
-- The PARTITION BY is also repeated per column rather than named once with
-- WINDOW w AS (...), because MEDIAN() will not accept a named window:
--
--   SELECT MEDIAN(km) OVER w ... WINDOW w AS (PARTITION BY airline)
--   ERROR 1064 (42000): ... syntax ... near 'w, 1) AS median_km'
--
-- AVG(km) OVER w in the same statement is fine, so this is specific to the
-- percentile family: PERCENTILE_CONT and PERCENTILE_DISC refuse a named
-- window too. Verified on 12.3.3.
SELECT '--- Option B: built-in MEDIAN(km) OVER (PARTITION BY airline) ---' AS label;
SELECT DISTINCT airline,
       COUNT(*)         OVER (PARTITION BY airline)       AS routes,
       ROUND(AVG(km)    OVER (PARTITION BY airline), 1)   AS mean_km,
       ROUND(MEDIAN(km) OVER (PARTITION BY airline), 1)   AS median_km
FROM route_distances
WHERE km > 0
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Option C: PERCENTILE_CONT(0.5), also window-only
-- ---------------------------------------------------------------------------
SELECT '--- Option C: PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY km) ---' AS label;
SELECT DISTINCT airline,
       COUNT(*) OVER (PARTITION BY airline) AS routes,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY km)
             OVER (PARTITION BY airline), 1) AS median_km
FROM route_distances
WHERE km > 0
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Option D: the hand-rolled median, no median feature of any kind
-- ---------------------------------------------------------------------------
-- What you would write if neither the custom aggregate nor MEDIAN() existed:
-- number the rows within each group, count them, and average whichever one or
-- two land in the middle. Correct, portable, and the reason people reach for a
-- custom aggregate in the first place -- nobody wants this at every call site.
SELECT '--- Option D: ROW_NUMBER() and pick the middle row(s) ---' AS label;
SELECT airline,
       MAX(c)              AS routes,
       ROUND(AVG(km), 1)   AS median_km
FROM (SELECT airline, km,
             ROW_NUMBER() OVER (PARTITION BY airline ORDER BY km) AS rn,
             COUNT(*)     OVER (PARTITION BY airline)             AS c
      FROM route_distances
      WHERE km > 0) t
WHERE rn IN (FLOOR((c + 1) / 2), FLOOR((c + 2) / 2))
GROUP BY airline
ORDER BY routes DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Does the custom aggregate actually agree with the built-in?
-- ---------------------------------------------------------------------------
-- Across all 566 airlines, not just the 15 printed above. Nothing below is
-- allowed to be taken on trust: sql/test_median.sql asserts it in CI.
SELECT '--- Agreement with the built-in across every airline (expect 0) ---' AS label;
SELECT COUNT(*) AS airlines_disagreeing
FROM (SELECT a.airline
      FROM (SELECT airline, MEDIAN_AGG(km) AS m
            FROM route_distances WHERE km > 0 GROUP BY airline) a
      JOIN (SELECT DISTINCT airline, MEDIAN(km) OVER (PARTITION BY airline) AS m
            FROM route_distances WHERE km > 0) b USING (airline)
      WHERE ABS(a.m - b.m) > 1e-9) t;

-- ---------------------------------------------------------------------------
-- What the median says that the mean does not
-- ---------------------------------------------------------------------------
-- The reason to want a median on this dataset at all. A long-haul outlier
-- pulls the mean up; the median ignores it. The gap is the skew of an
-- airline's route mix, which is the sort of thing a mean hides.
SELECT '--- Where mean and median disagree most (airlines with >= 100 routes) ---' AS label;
SELECT airline,
       COUNT(*)                                  AS routes,
       ROUND(AVG(km), 1)                         AS mean_km,
       ROUND(MEDIAN_AGG(km), 1)                  AS median_km,
       ROUND(AVG(km) - MEDIAN_AGG(km), 1)        AS mean_minus_median
FROM route_distances
WHERE km > 0
GROUP BY airline
HAVING routes >= 100
ORDER BY mean_minus_median DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Comparison notes
-- ---------------------------------------------------------------------------
-- Measured on 12.3.3, local server, warm cache, 66,771 routes in 566 airline
-- groups, best of three runs, whole-statement wall clock from the client:
--
--   Option A  custom aggregate MEDIAN_AGG          1,460 ms
--   Option B  built-in MEDIAN() OVER                 250 ms
--   Option C  PERCENTILE_CONT(0.5)                   265 ms
--   Option D  ROW_NUMBER(), pick the middle          295 ms
--
-- All four produce identical medians. The custom aggregate is the slowest by
-- roughly 5x, and unlike the geometric-mean case there is no readability
-- argument to set against it, because Option B is a built-in that is shorter
-- to write. **On this dataset, writing your own median is the wrong choice.**
-- It is in this repository because the exercise is to find where the feature
-- runs out, and this is where.
--
-- Where the 1,460 ms goes, varying the group count over the same 66,771 rows:
--
--   1 group                1,365 ms
--   566 groups (airlines)  1,460 ms
--   5,000 groups           2,140 ms
--
-- So roughly 0.02 ms per row buffered and 0.16 ms per group. The cost is
-- dominated by the one INSERT per row, not by the per-group table setup --
-- which is the opposite of what we assumed before measuring, and it means the
-- shape of the fix would have to be "do not buffer", not "buffer more cheaply".
--
-- Limits specific to this function:
--   * The buffer is a session-scoped temporary table shared by every
--     invocation and never dropped. It is emptied as it goes, so it holds at
--     most one group per concurrent invocation, but it does survive until the
--     connection closes.
--   * It relies on the session variable @median_calls. Setting that variable
--     by hand between calls in one statement would corrupt a result. Nothing
--     stops a caller doing that.
--   * NULLs are skipped (matching AVG() and the built-in), which deliberately
--     differs from WEIGHTED_AVERAGE in this repository.
--   * Like every custom aggregate here, it cannot be used as a window
--     function: there is no MEDIAN_AGG(km) OVER (PARTITION BY airline).
--   * It cannot be used in HAVING either, which a built-in can:
--
--       ... GROUP BY airline HAVING AVG(km) > 0          -- fine
--       ... GROUP BY airline HAVING MEDIAN_AGG(km) > 0   -- ERROR 1054
--                                                        -- Unknown column 'km'
--     The column does not resolve inside HAVING for a stored aggregate, so a
--     filter on the result needs a derived table or a subquery instead.
--   * **The server does not promise to finish an invocation.** This one cost
--     an afternoon. In this shape --
--
--       SELECT COUNT(*) FROM (SELECT airline, MEDIAN_AGG(km) AS med,
--                                    MIN(km) AS lo, MAX(km) AS hi
--                             FROM route_distances WHERE km > 0
--                             GROUP BY airline) t
--        WHERE med < lo OR med > hi;
--
--     the derived table is merged and the outer condition pushed down, and
--     median_buf is left holding exactly one row per group afterwards: 566
--     rows for 566 airlines. The medians it returns are still correct, and
--     agree with the built-in. What happens is that a second invocation per
--     group is started, fed one row, and abandoned before the body reaches
--     its cleanup, so the DELETE never runs. Adding LIMIT to the derived
--     table blocks the merge and the leak disappears.
--
--     A streaming aggregate would never show this, because it has no state
--     outside its own variables. A buffering one does, and nothing in the
--     documentation says an aggregate body is guaranteed to run to
--     completion. sql/test_median.sql measures it rather than asserting it,
--     because we do not know yet whether it behaves the same on every
--     version in the CI matrix.
--   * DOUBLE in, DOUBLE out. The built-in MEDIAN() returns a DECIMAL, so the
--     two agree in value but not in printed precision -- compare them with a
--     tolerance, as sql/test_median.sql does.
-- ---------------------------------------------------------------------------
