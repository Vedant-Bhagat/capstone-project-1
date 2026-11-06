-- Controlled rows for aggregate edge-case tests. The real dataset cannot
-- produce NULLs, negatives or ties, so they are constructed here.
--
-- Shared by sql/test_median.sql and by the WEIGHTED_AVERAGE and HARMONIC_MEAN
-- tests described in docs/task_janhavi_weighted_average_tests.md and
-- docs/task_pranesh_harmonic_mean_tests.md. Add groups rather than changing
-- existing ones: three test files read this table and expect these values.
--
-- How to run (from the sql directory):
--   Linux/macOS:  mariadb -u root < test_fixture.sql
--   PowerShell:   Get-Content test_fixture.sql | mariadb -u root

USE flightdb2;

DROP TABLE IF EXISTS agg_edge_cases;
CREATE TABLE agg_edge_cases (
    grp      VARCHAR(16)  NOT NULL,
    val      DOUBLE       NULL,
    weight   DOUBLE       NULL,
    val_text VARCHAR(16)  NULL,
    note     VARCHAR(80)  NOT NULL DEFAULT ''
);

INSERT INTO agg_edge_cases (grp, val, weight, val_text, note) VALUES
    ('plain',    10,    1, NULL, 'three ordinary positive values, equal weights'),
    ('plain',    20,    1, NULL, ''),
    ('plain',    30,    1, NULL, ''),
    ('has_null', 10,    1, NULL, 'one NULL value among valid ones'),
    ('has_null', NULL,  1, NULL, ''),
    ('has_null', 30,    1, NULL, ''),
    ('null_wt',  10,    1, NULL, 'one NULL weight'),
    ('null_wt',  20, NULL, NULL, ''),
    ('zero_wt',  10,    0, NULL, 'every weight is zero'),
    ('zero_wt',  20,    0, NULL, ''),
    ('neg_wt',   10,    2, NULL, 'weights that cancel to zero'),
    ('neg_wt',   20,   -2, NULL, ''),
    ('neg',     -10,    1, NULL, 'a negative value'),
    ('neg',      20,    1, NULL, ''),
    ('ties',      7,    1, NULL, 'three identical values'),
    ('ties',      7,    1, NULL, ''),
    ('ties',      7,    1, NULL, ''),
    ('cancel',    1,    1, NULL, 'reciprocals that cancel: 1/1 + 1/-1 = 0'),
    ('cancel',   -1,    1, NULL, ''),
    ('zero_val',  0,    1, NULL, 'a zero value: 1/0 is undefined'),
    ('zero_val', 10,    1, NULL, ''),
    ('text',   NULL,    1, '12.5', 'numeric strings and junk, for coercion'),
    ('text',   NULL,    1, '20',   ''),
    ('text',   NULL,    1, 'abc',  '');

SELECT CONCAT('test_fixture: ', COUNT(*), ' rows in ',
              COUNT(DISTINCT grp), ' groups') AS '' FROM agg_edge_cases;
