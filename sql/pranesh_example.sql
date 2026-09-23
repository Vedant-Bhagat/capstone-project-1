-- Starter: Custom Aggregate Functions (MariaDB-only feature)
-- HARMONIC_MEAN: the correct way to average speeds over equal distances.
-- How to run (from the sql directory): Get-Content pranesh_example.sql | mariadb -u root

DROP DATABASE IF EXISTS capstone_demo_pranesh;
CREATE DATABASE capstone_demo_pranesh;
USE capstone_demo_pranesh;

CREATE TABLE trip_legs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    trip_name VARCHAR(30) NOT NULL,
    speed_kmh DOUBLE NOT NULL   -- each leg covers the same distance
);

INSERT INTO trip_legs (trip_name, speed_kmh) VALUES
    ('Bengaluru-Mysuru', 45), ('Bengaluru-Mysuru', 75), ('Bengaluru-Mysuru', 90),
    ('Airport run', 25), ('Airport run', 100), ('Airport run', 55);

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

SELECT '--- Option A: custom aggregate function ---' AS label;
SELECT trip_name, HARMONIC_MEAN(speed_kmh) AS avg_speed
FROM trip_legs
GROUP BY trip_name;

SELECT '--- Option B: inline COUNT(*) / SUM(1/x) at the call site ---' AS label;
SELECT trip_name, COUNT(*) / SUM(1 / speed_kmh) AS avg_speed
FROM trip_legs
GROUP BY trip_name;

SELECT '--- Option C: plain AVG() gives the WRONG answer for speeds ---' AS label;
SELECT trip_name, AVG(speed_kmh) AS wrong_avg_speed
FROM trip_legs
GROUP BY trip_name;

-- Limits: x must be non-zero (1/x fails at 0), and results are floating-point.