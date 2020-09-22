
DROP FUNCTION "visible?"(point, point, int, int, int);
CREATE FUNCTION "visible?"(here point, there point, gridx int, gridy int, resolution int) RETURNS boolean AS
$$
  DECLARE
    step       point; -- direction of MAX scan
    loc        point; -- current point of MAX scan
    hhere      float; -- height at point here
    hloc       float; -- height of current point loc during MAX scan
    angle      float; -- angle between point here and current point of MAX scan
    max_angle  float; -- maximum angle measured during MAX scan
  BEGIN
    -- extent of landscape in x/y dimensions
    gridx := gridx - 1;
    gridy := gridy - 1;
    -- height of point here (see https://en.wikipedia.org/wiki/Bézier_surface)
    hhere := (SELECT SUM(((!! gridx) / ((!! s.x) * ((!! (gridx - s.x))))) * u^s.x * (1 - u)^(gridx - s.x) *
                         ((!! gridy) / ((!! s.y) * ((!! (gridy - s.y))))) * v^s.y * (1 - v)^(gridy - s.y) *
                         h) AS h
              FROM   -- iterate over all points (s.x,s.y) of surface
                     (SELECT x, y
                      FROM   generate_series(0, gridx) AS x,
                             generate_series(0, gridy) AS y) AS s(x,y)
                     -- add control points (c.x,c.y) where there are defined
                     LEFT JOIN controlp AS c ON (c.x,c.y) = (s.x,s.y),
                     LATERAL (VALUES ((here[0] / gridx) :: numeric, (here[1] / gridy :: numeric), COALESCE(c.z, 0))) AS _(u,v,h));

    step       := (there - here) / resolution;
    loc        := here;
    -- maximum angle observed so far (initially ¯\_(ツ)_/¯)
    max_angle := NULL :: float;
    -- perform a MAX scan along the line from here to there
    FOR i IN 1..resolution LOOP
      -- compute height at current location loc in scan
      loc  := loc + step;
      hloc := (SELECT SUM(((!! gridx) / ((!! s.x) * ((!! (gridx - s.x))))) * u^s.x * (1 - u)^(gridx - s.x) *
                          ((!! gridy) / ((!! s.y) * ((!! (gridy - s.y))))) * v^s.y * (1 - v)^(gridy - s.y) *
                          h) AS h
               FROM   -- iterate over all points (s.x,s.y) of surface
                      (SELECT x, y
                       FROM   generate_series(0, gridx) AS x,
                              generate_series(0, gridy) AS y) AS s(x,y)
                      -- add control points (c.x,c.y) where there are defined
                      LEFT JOIN controlp AS c ON (c.x,c.y) = (s.x,s.y),
                      LATERAL (VALUES ((loc[0] / gridx) :: numeric, (loc[1] / gridy) :: numeric, COALESCE(c.z, 0))) AS _(u,v,h));

      -- viewing angle between here and current location of MAX scan
      angle := degrees(atan((hloc - hhere) / (loc <-> here)));
      -- save MAX angle observed during the scan
      IF max_angle IS NULL OR angle > max_angle THEN
        max_angle := angle;
      END IF;
    END LOOP;

    -- point there is visible from here if its viewing angle is maximal
    RETURN angle = max_angle;
  END;
$$
LANGUAGE PLPGSQL;


-- # of visibility tests (~ invocations)
\set N :invocations

-- resolution of MAX scan (# of steps between here and there, ~ iterations)
\set RESOLUTION :iterations

-- # of grid units of 3D landscape in x/y dimension (~ iterations)
\set X 10
\set Y 10

SELECT setseed(0.42);
\timing on
-- test for visiblity (N times)
SELECT x, "visible?"(point(x,0), point(x,:Y-1), :X, :Y, :RESOLUTION) AS "visible?"
FROM   generate_series(1, :N) AS i,
       LATERAL (VALUES (random() * (:X - 1) + i - i)) AS _(x);

\timing off