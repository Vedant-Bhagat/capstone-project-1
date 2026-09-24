-- Shared dataset setup for all examples in this repository.
--
-- Run this ONCE after loading MariaDB's OpenFlights dataset (see README).
-- It creates the derived view every example builds on.
--
-- How to run:
--   Linux/macOS:  mariadb -u root < setup_dataset.sql
--   PowerShell:   Get-Content setup_dataset.sql | mariadb -u root
--
-- Prerequisite: the flightdb2 database, loaded from
-- https://github.com/mariadb/openflights

USE flightdb2;

-- Every route's great-circle distance, derived by joining each route to the
-- coordinates of its origin and destination airport.
--
-- ST_Distance_Sphere is built into MariaDB and returns metres, so we divide
-- by 1000 to get kilometres. This gives ~66,771 rows spanning 0 to ~16,082 km
-- -- a spread wide enough that different kinds of mean give visibly different
-- answers, which is the point of the comparison.
--
-- The join drops routes whose endpoints are missing from the airports table
-- (~900 of 67,663), because a route with no coordinates has no distance.

CREATE OR REPLACE VIEW route_distances AS
SELECT r.rid,
       r.airline,
       ST_Distance_Sphere(POINT(a1.x, a1.y), POINT(a2.x, a2.y)) / 1000 AS km
FROM routes r
JOIN airports a1 ON a1.apid = r.src_apid
JOIN airports a2 ON a2.apid = r.dst_apid;

-- Sanity check, and a warning about the one row that breaks two of our three
-- aggregates: a route whose origin and destination share coordinates has
-- km = 0, which is undefined for LN() and a division by zero for 1/x.
-- Every query in this repository filters WHERE km > 0 because of it.

SELECT COUNT(*)            AS total_routes,
       SUM(km > 0)         AS usable_routes,
       SUM(km = 0)         AS zero_distance_routes,
       ROUND(MAX(km), 1)   AS longest_km
FROM route_distances;
