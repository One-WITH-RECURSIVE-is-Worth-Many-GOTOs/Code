
DROP FUNCTION IF EXISTS bbox(vec2);
CREATE FUNCTION bbox(start vec2) RETURNS box AS
$$
  DECLARE
    "track?" boolean  := false;
    goal     vec2;
    bbox     box      := NULL;
    current  vec2     := start;
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
        bbox     := box(point(goal.x, goal.y));
      END IF;
      IF "track?" THEN
        bbox := bound_box(bbox, box(point(current.x, current.y)));
      END IF;

      current := (current.x + (dir.dir).x, current.y + (dir.dir).y) :: vec2;
    END LOOP;

    RETURN bbox;
  END;
$$
LANGUAGE PLPGSQL STRICT;


\set N :invocations
\set X :iterations
\set Y :iterations
\set STRIPE 8


SELECT setseed(0.425);

\timing on

-- Trace the shape's bounding box in the 2D map, starting from varying points
-- on the map's left-hand side within the stripe.  Repeat N times.
SELECT bbox((x, y) :: vec2)
FROM   generate_series(1, :N) AS i,
       LATERAL (VALUES (floor(    random() * :STRIPE  + i - i),
                        floor(1 + random() * (:Y - 1) + i - i))) AS _(x,y);
