-- Determine the service level for a given customer
-- (this is directly based on Example 1 in the ICDE 2014 paper
--  "Decorrelation of User Defined Function Invocations in Queries", by Simhadri et.al).

DROP FUNCTION IF EXISTS service_level(int);
CREATE FUNCTION service_level(custkey int) RETURNS text AS
$$
  DECLARE
    totalbusiness float;
    level         text;
  BEGIN
    totalbusiness := (SELECT SUM(o.o_totalprice)
                      FROM   orders AS o
                      WHERE  o.o_custkey = custkey);

    IF totalbusiness > 1000000 THEN
      level := 'Platinum';
    ELSIF totalbusiness > 500000 THEN
      level := 'Gold';
    ELSE
      level := 'Regular';
    END IF;

    RETURN level;
  END;
$$
LANGUAGE PLPGSQL;

\timing on

-- Determine service level status for all customers
SELECT c.c_custkey AS customer, service_level(c.c_custkey) AS "service level"
FROM   (SELECT *
        FROM   customer
        ORDER BY c_custkey
        LIMIT :invocations) AS c;
