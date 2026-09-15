-- Starter: Custom Aggregate Functions (MariaDB-only feature)
--
-- WEIGHTED_AVERAGE(value, weight) is a two-argument custom aggregate --
-- this shows CREATE AGGREGATE FUNCTION works with more than one input,
-- unlike a plain built-in aggregate like AVG().
--
-- How to run (from the "sql" directory, with a local MariaDB server running):
--   mariadb -u root < janhavi_example.sql

DROP DATABASE IF EXISTS capstone_demo_janhavi;
CREATE DATABASE capstone_demo_janhavi;
USE capstone_demo_janhavi;

CREATE TABLE product_reviews (
    id INT PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(30) NOT NULL,
    rating INT NOT NULL,        -- 1 to 5
    reviewer_weight DOUBLE NOT NULL  -- e.g. a trust/verified-purchase score
);

INSERT INTO product_reviews (product_name, rating, reviewer_weight) VALUES
    ('Widget A', 5, 2.0), ('Widget A', 3, 1.0), ('Widget A', 4, 0.5),
    ('Widget B', 1, 1.0), ('Widget B', 5, 3.0), ('Widget B', 2, 1.0);

-- ---------------------------------------------------------------------------
-- Option A: custom aggregate function (the feature under test)
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

SELECT '--- Option A: custom aggregate function ---' AS label;
SELECT product_name, WEIGHTED_AVERAGE(rating, reviewer_weight) AS weighted_avg_rating
FROM product_reviews
GROUP BY product_name;

-- ---------------------------------------------------------------------------
-- Option B: same result, formula repeated inline (the common workaround)
-- ---------------------------------------------------------------------------
SELECT '--- Option B: inline SUM(val*weight)/SUM(weight) at the call site ---' AS label;
SELECT
    product_name,
    SUM(rating * reviewer_weight) / SUM(reviewer_weight) AS weighted_avg_rating
FROM product_reviews
GROUP BY product_name;

-- ---------------------------------------------------------------------------
-- Comparison notes:
--   - Option A (custom aggregate): one call site, WEIGHTED_AVERAGE(rating,
--     reviewer_weight) -- the formula lives in one place and can't be
--     gotten wrong at the call site.
--   - Option B (inline formula): same result, but every query that needs
--     a weighted average has to repeat and correctly pair up the SUM()s.
-- ---------------------------------------------------------------------------
