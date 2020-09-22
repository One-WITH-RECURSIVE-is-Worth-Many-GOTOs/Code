
-- Compute lighted polygon from source point light
DROP FUNCTION IF EXISTS light(point);
CREATE FUNCTION light(light point) RETURNS polygon AS
$$
  DECLARE
    points        point[];
    p0            point;
    p1            point;
    p2            point;
    phi           float := 0.001;  -- ray angle offset (± from p1, in radians)
    target        point;
    ins           point;
    intersections point[];
  BEGIN
    -- ➊ edge points of all polygons
    points := (SELECT array_agg(pt)
               FROM   scene AS s, LATERAL unnest(points(s.poly)) AS pt);

    intersections := array[] :: point[];

    -- ➋ find intersection points of rays from light to all polygon edge points (+ jittering)
    FOREACH p1 IN ARRAY points LOOP
      -- 𝑥′ = cx + (𝑥−cx)cos(𝜑) − (𝑦−cy)sin(𝜑)
      -- 𝑦′ = cy + (𝑥−cx)sin(𝜑) + (𝑦−cy)cos(𝜑)
      p0 := point(light[0] + (p1[0] - light[0]) * cos(phi)  - (p1[1] - light[1]) * sin(phi),
                  light[1] + (p1[0] - light[0]) * sin(phi)  + (p1[1] - light[1]) * cos(phi));
      p2 := point(light[0] + (p1[0] - light[0]) * cos(-phi) - (p1[1] - light[1]) * sin(-phi),
                  light[1] + (p1[0] - light[0]) * sin(-phi) + (p1[1] - light[1]) * cos(-phi));

      FOREACH target in ARRAY array[p0,p1,p2] LOOP
        ins := (SELECT ray(light, target) # lseg(seg0, seg1)
                FROM   scene AS s,
                       LATERAL points(s.poly) AS pts,
                       LATERAL ROWS FROM (unnest(pts), unnest(pts[2:] || pts[1])) AS _(seg0,seg1)
                ORDER BY light <-> (ray(light, target) # lseg(seg0, seg1))
                LIMIT 1);

        intersections := intersections || ins;
      END LOOP;

    END LOOP;

    -- ➌ sort intersection points by angle
    intersections := (SELECT array_agg(i ORDER BY degrees(atan2(light[0] - i[0], light[1] - i[1])))
                      FROM   unnest(intersections) AS i
                      WHERE  i IS NOT NULL);

    RETURN polygon(intersections);
  END;
$$
LANGUAGE PLPGSQL;


-- # of visibility computations (~ invocations)
\set N :invocations

-- # of obstacle polygons in scene (~ iterations)
\set OBSTACLES :iterations

-- Scene width and height that can hold all obstacles
\set WIDTH  (100 * :iterations)
\set HEIGHT (100 * :iterations)

-- Location of light source
\set LIGHT point(:WIDTH / 2, :HEIGHT / 2)

\timing on
SELECT light(:LIGHT) AS poly
FROM   generate_series(1, :N) AS i;
