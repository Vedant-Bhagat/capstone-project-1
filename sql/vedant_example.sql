-- Starter: Custom Aggregate Functions (MariaDB-only feature)
--
-- MariaDB lets you write your own SQL-level aggregate function with
-- CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW. This is not available
-- at the SQL level in MySQL, so it's a genuine "something only MariaDB has".
--
-- This script:
--   1. Builds a small sample dataset (exam scores per class).
--   2. Implements GEOMETRIC_MEAN as a custom aggregate function.
--   3. Compares it against the workaround people reach for instead:
--      the same formula written out at every call site (EXP(AVG(LN(x)))).
--   4. Shows the "before" world: what a client app has to do without any
--      SQL-side aggregate at all (fetch every row, compute client-side).
--
-- How to run (from the "sql" directory, with a local MariaDB server running):
--   "C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root < vedant_example.sql
--
-- MariaDB version this was built and tested against: 12.3.3-MariaDB (Windows)

DROP DATABASE IF EXISTS capstone_demo;
CREATE DATABASE capstone_demo;
USE capstone_demo;

CREATE TABLE exam_scores (
    id INT PRIMARY KEY AUTO_INCREMENT,
    class_name VARCHAR(20) NOT NULL,
    score INT NOT NULL
);

INSERT INTO exam_scores (class_name, score) VALUES
    ('CS101', 55), ('CS101', 62), ('CS101', 70), ('CS101', 71), ('CS101', 95),
    ('CS102', 40), ('CS102', 41), ('CS102', 88), ('CS102', 90),
    ('CS103', 100);

-- ---------------------------------------------------------------------------
-- Option A: custom aggregate function (the feature under test)
-- ---------------------------------------------------------------------------
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
        SET log_sum = log_sum + LN(x);
        SET cnt = cnt + 1;
    END LOOP main_loop;

    IF cnt = 0 THEN
        RETURN NULL;
    END IF;
    RETURN EXP(log_sum / cnt);
END //

DELIMITER ;

SELECT '--- Option A: custom aggregate function ---' AS label;
SELECT class_name, GEOMETRIC_MEAN(score) AS geometric_mean_score
FROM exam_scores
GROUP BY class_name;

-- ---------------------------------------------------------------------------
-- Option B: same result, formula repeated inline (the common workaround)
-- ---------------------------------------------------------------------------
SELECT '--- Option B: inline EXP(AVG(LN(x))) at the call site ---' AS label;
SELECT
    class_name,
    EXP(AVG(LN(score))) AS geometric_mean_score
FROM exam_scores
GROUP BY class_name;

-- ---------------------------------------------------------------------------
-- Option C: what a client application has to do with no SQL-side aggregate --
-- fetch every row and compute the geometric mean in application code.
-- ---------------------------------------------------------------------------
SELECT '--- Option C: raw rows a client app would fetch to compute this itself ---' AS label;
SELECT class_name, score FROM exam_scores ORDER BY class_name;
-- (the geometric mean would then be computed per class in application code
--  after fetching every row -- more data over the wire, and the aggregation
--  logic has to be reimplemented identically in every client language)

-- ---------------------------------------------------------------------------
-- Comparison notes:
--   - Option A (custom aggregate): one call site (GEOMETRIC_MEAN(score)),
--     the log/exp math lives in one place in the database, and it composes
--     with GROUP BY, HAVING, window frames, etc. like any built-in aggregate.
--   - Option B (inline formula): also one query, but every caller has to
--     know and correctly repeat EXP(AVG(LN(x))) -- easy to get wrong
--     (e.g. forgetting to guard against LN of a non-positive score).
--   - Option C (app-side): the whole table has to be transferred to the
--     client, and the math is duplicated in every client codebase.
-- ---------------------------------------------------------------------------
