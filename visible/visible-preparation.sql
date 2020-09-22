-- PL/SQL-based visibility of a point there from point here in a
-- 3D landscape modelled by a Bezier surface.  Based on a MAX angle
-- scan along a line from here to there.

-- Define aggregates, operations, comparisons on PostgreSQL points
\i points.sql

-- # of visibility tests (~ invocations)
\set N :invocations

-- resolution of MAX scan (# of steps between here and there, ~ iterations)
\set RESOLUTION :iterations

-- # of grid units of 3D landscape in x/y dimension
\set X 10
\set Y 10

-- Table of 3D control points
DROP TABLE IF EXISTS controlp;
CREATE TABLE controlp (
  x int,
  y int,
  z double precision,
  PRIMARY KEY (x,y)
);

-- All coordinates (x,y) not explicitly defined here
-- are assumed to be at height 0

-- Generate control points for a wavy surface using a 2D sin/cos parametric curve
INSERT INTO controlp(x,y,z)
  SELECT x, y,
         round(2 * cos(2 * (pi()/(:X - 1)) * x) * sin((pi()/(:Y - 1)) * y)) AS z
  FROM   generate_series(0, :X - 1) AS x,
         generate_series(0, :Y - 1) AS y;

-- INSERT INTO controlp(x,y,z) VALUES
--   (1, 1, 2),
--   (1, 2, 2),
--   (2, 1, 2),
--   (2, 2, 2);

/*
Can use the following Mathematica snippet to visualize the 3D landscape:

  pts = {{{0, 0, 1}, {0, 1, 0}, {0, 2, 0}, {0, 3, 0}},
         {{1, 0, 0}, {1, 1, 2}, {1, 2, 2}, {1, 3, 0}},
         {{2, 0, 0}, {2, 1, 2}, {2, 2, 2}, {2, 3, 0}},
         {{3, 0, 0}, {3, 1, 0}, {3, 2, 0}, {3, 3, 0}}}

  f = BezierFunction[pts]

  Show[Graphics3D[{PointSize[Medium], Red, Map[Point, pts]}],
       Graphics3D[{Gray, Line[pts], Line[Transpose[pts]]}],
       ParametricPlot3D[f[u, v], {u, 0, 1}, {v, 0, 1}, Mesh -> None]]
*/
