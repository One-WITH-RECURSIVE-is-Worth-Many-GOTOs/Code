
-- Compute force on body using the Barnes-Hut tree barneshut,
-- parameter theta controls granularity/approximation.

-- Iterative PL/SQL UDF
DROP FUNCTION IF EXISTS force(bodies, float);
CREATE FUNCTION force(body bodies, theta float) RETURNS point AS
$$
  DECLARE
    force      point := point(0,0);
    G CONSTANT float := 6.67e-11;
    Q          barneshut[];
    node       barneshut;
    children   barneshut[];
    dist       float;
    dir        point;
    grav       point;
  BEGIN
    node = (SELECT b
            FROM   barneshut AS b
            WHERE  b.node = 0);
    Q = array[node];

    WHILE cardinality(Q) > 0 LOOP
      node = Q[1];
      Q    = Q[2:];
      dist = GREATEST(node.center<->body.pos, 1e-10);
      dir  = node.center - body.pos;
      grav = point(0,0);
      IF NOT EXISTS (SELECT 1
                     FROM   walls AS w
                     WHERE  (body.pos    <= body.pos    ## w.wall) <>
                            (node.center <= node.center ## w.wall)) THEN
        grav = (G * body.mass * node.mass / dist^2) * dir;  -- ⧆ relies on points.sql
      END IF;
      IF (node.node IS NULL) OR (width(node.bbox) / dist < theta) THEN
        force = force + grav;
      ELSE
        children = (SELECT array_agg(b)
                    FROM   barneshut AS b
                    WHERE  b.parent = node.node);
        Q = Q || children;
      END IF;
    END LOOP;

    RETURN force;
  END;
$$
LANGUAGE PLPGSQL STABLE STRICT;


\set area box(point(0,0), point(1000,1000))
\set F :invocations

SELECT setseed(0.42);

\timing on

SELECT force((point(width(:area) * random(), width(:area) * random()), 1.0), 0.5)
FROM   generate_series(1, :F);
