-- Determine preferred shipping mode (ground, air, mail) for all
-- customers.
--
-- (Transcribed for TPC-H from Microsoft Query Q5 over TPC-DS data.)

DROP FUNCTION IF EXISTS preferred_shipmode(int);
CREATE FUNCTION preferred_shipmode(custkey int) RETURNS TEXT AS
$$
  DECLARE
    ground int;
    air    int;
    mail   int;
  BEGIN
    -- collect shipping mode statistics
    ground := (SELECT COUNT(*)
               FROM   lineitem AS l, orders AS o
               WHERE  l.l_orderkey = o.o_orderkey AND o.o_custkey = custkey
               AND    l.l_shipmode IN ('RAIL', 'TRUCK'));
    air :=    (SELECT COUNT(*)
               FROM   lineitem AS l, orders AS o
               WHERE  l.l_orderkey = o.o_orderkey AND o.o_custkey = custkey
               AND    l.l_shipmode IN ('AIR', 'REG AIR'));
    mail :=   (SELECT COUNT(*)
               FROM   lineitem AS l, orders AS o
               WHERE  l.l_orderkey = o.o_orderkey AND o.o_custkey = custkey
               AND    l.l_shipmode = 'MAIL');
    -- determine preferred shipping mode
    IF ground >= air AND ground >= mail THEN
      RETURN 'ground';
    ELSIF air >= ground AND air >= mail THEN
      RETURN 'air';
    ELSIF mail >= ground AND mail >= air THEN
      RETURN 'mail';
    END IF;
    -- not reached
    RETURN NULL;
  END;
$$
LANGUAGE PLPGSQL;

\timing on

SELECT c.c_custkey AS "customer", c.c_name AS "name", preferred_shipmode(c.c_custkey) AS "preferred ship mode"
FROM   (SELECT *
        FROM   customer
        ORDER BY c_custkey
        LIMIT :invocations) AS c;
