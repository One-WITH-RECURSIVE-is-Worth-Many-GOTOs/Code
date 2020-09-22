-- Given a set of obstacle polygons in 2D, compute the lighted polygon
-- from a specified light source point in the scene
--
-- Based on https://ncase.light/sight-and-light/

-- # of visibility computations (~ invocations)
\set N :invocations

-- # of obstacle polygons in scene (~ iterations)
\set OBSTACLES :iterations

-- Scene width and height that can hold all obstacles
\set WIDTH  (100 * :iterations)
\set HEIGHT (100 * :iterations)

-- Arithmetic on points
\i points.sql

SELECT setseed(0.42);

-- Auxiliary functions: convert between polygon and arrays of points
-- (PostgreSQL really should have these built in).
DROP FUNCTION  IF EXISTS points(polygon);
CREATE FUNCTION points(p polygon) RETURNS point[] AS
$$
  SELECT array_agg(point('(' || pt.p || ')') ORDER BY pt.pos)
  FROM   unnest(regexp_split_to_array(rtrim(ltrim(p :: text, '('), ')'), '\),\(')) WITH ORDINALITY AS pt(p,pos);
$$
LANGUAGE SQL STABLE STRICT;

DROP FUNCTION IF EXISTS polygon(point[]);
CREATE FUNCTION polygon(pts point[]) RETURNS polygon AS
$$
  SELECT polygon('(' || replace(rtrim(ltrim(pts :: text, '{'), '}'), '"', '') || ')');
$$
LANGUAGE SQL STABLE STRICT;

-- New type: ray with origin and direction
DROP TYPE IF EXISTS ray CASCADE;
CREATE TYPE ray AS (
  orig point,  -- origin of ray
  dir  point   -- direction of ray
);

-- Ray pointing from p1 towards p2
DROP FUNCTION IF EXISTS ray(point,point);
CREATE FUNCTION ray(p1 point, p2 point) RETURNS ray AS
$$
  SELECT (p1, p2 - p1) :: ray;
$$
LANGUAGE SQL STABLE STRICT;

-- Intersection of ray r with line seglightnt s (NULL if no intersection)
DROP FUNCTION IF EXISTS intersection(ray, lseg);
CREATE FUNCTION intersection(r ray, s lseg) RETURNS point AS
$$
  SELECT CASE
    WHEN lseg(r.orig, r.orig + r.dir) ?|| s THEN NULL
    ELSE (SELECT CASE WHEN t1 > 0 AND t2 BETWEEN 0 AND 1 THEN r.orig + t1 * r.dir
                      ELSE NULL
                 END
          FROM   (VALUES (r.orig[0], r.orig[1], r.dir[0], r.dir[1],
                          (s[0])[0], (s[0])[1], (s[1] - s[0])[0], (s[1] - s[0])[1])) AS _(r_px, r_py, r_dx, r_dy, s_px, s_py, s_dx, s_dy),
                 LATERAL (VALUES ((r_dx*(s_py-r_py) + r_dy*(r_px-s_px))/(s_dx*r_dy - s_dy*r_dx))) AS __(t2),
                 LATERAL (VALUES ((s_px+s_dx*t2-r_px)/r_dx)) AS ___(t1))
  END;
$$
LANGUAGE SQL STABLE STRICT;
DROP OPERATOR IF EXISTS #(ray, lseg);
CREATE OPERATOR #(FUNCTION = intersection, LEFTARG = ray, RIGHTARG = lseg);

-----------------------------------------------------------------------

-- Scene (obstacle polygons)
DROP TABLE IF EXISTS scene;
CREATE TABLE scene (
  id    int GENERATED ALWAYS AS IDENTITY,
  color text,    -- SVG fill color of polygon
  poly  polygon
);


-- Generate random scene
INSERT INTO scene(color, poly) VALUES
  ('none', polygon(box(point(0,0), point(:WIDTH, :HEIGHT))));  -- scene border containing all obstacles

INSERT INTO scene(color, poly)
  SELECT 'lightgrey' AS color,
         polygon(box(point(GREATEST(x - 10, 0),
                           GREATEST(y - 10, 0)),
                     point(LEAST(x + 10 + random() * 100, :WIDTH),
                           LEAST(y + 10 + random() * 100, :HEIGHT)))) AS poly
  FROM   generate_series(1, :OBSTACLES) AS i,
         LATERAL (VALUES (random() * :WIDTH - i + i, random() * :HEIGHT - i + i)) AS _(x,y);

-----------------------------------------------------------------------
