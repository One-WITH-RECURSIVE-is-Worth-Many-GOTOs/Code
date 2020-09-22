
DROP FUNCTION IF EXISTS march(vec2);
CREATE FUNCTION march(start vec2) RETURNS vec2[] AS
$$
  DECLARE
    "track?" boolean  := false;
    goal     vec2;
    march    vec2[]  := array[] :: vec2[];
    current  vec2    := start;
    square   squares;
    dir      directions;
  BEGIN
    WHILE true LOOP
      IF "track?" AND current = goal THEN
        EXIT;
      END IF;

      -- Options:
      -- ➊ merge squares + directions queries
      -- ➋ unfold computation of squares here
      square := (SELECT s
                 FROM   squares AS s
                 WHERE  s.xy = current);
      dir := (SELECT d
              FROM   directions AS d
              WHERE  (square.ll, square.lr, square.ul, square.ur) = (d.ll, d.lr, d.ul, d.ur));

      IF NOT "track?" AND dir."track?" THEN
        "track?" := true;
        goal     := current;
      END IF;
      IF "track?" THEN
        march := march || current;
      END IF;

      current := (current.x + (dir.dir).x, current.y + (dir.dir).y) :: vec2;
    END LOOP;

    RETURN march;
  END;
$$
LANGUAGE PLPGSQL STRICT;


\set N :invocations
\set X :iterations
\set Y :iterations
\set STRIPE 8


SELECT setseed(0.425);

\timing on

-- Trace the shape's border in the 2D map, starting from varying points
-- on the map's left-hand side within the stripe.  Repeat N times.
SELECT march((x, y) :: vec2)
FROM   generate_series(1, :N) AS i,
       LATERAL (VALUES (floor(    random() * :STRIPE  + i - i),
                        floor(1 + random() * (:Y - 1) + i - i))) AS _(x,y);
