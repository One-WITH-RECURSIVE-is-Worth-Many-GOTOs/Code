-- Ray tracing

DROP FUNCTION IF EXISTS raytrace(int, int);
CREATE FUNCTION raytrace(w int, h int) RETURNS int[] AS
$$
  DECLARE
    cam           vec3    := (0.0, 0.0, -4.5);  /* position of camera */
    cam_lookat    vec3    := (0.0, 0.0, 0.0);   /* position at which camera looks at */
    cam_up        vec3    := (0.0, 1.0, 0.0);   /* camera'a up vector */
    light         vec3;                         /* position of light source (read off the spheres table) */
    light_r       real;                         /* radius of light source */
    fov           real    := 50.0;              /* field of view (in degrees) */
    shadows       boolean := true;              /* shadows enabled? */
    max_rec_depth int     := 10;                /* recursion depth for reflections */
    aspect_ratio  real    := w :: real/h;
    epsilon       real    := 0.000001;
    ntriangles    int;
    nspheres      int;
    nprimitives   int;
    cd            vec3;                         /* camera direction */
    tlen          real;
    rotx1         real;
    rotx2         real;
    rotx3         real;
    roty1         real;
    roty2         real;
    roty3         real;
    rotz1         real;
    rotz2         real;
    rotz3         real;
    degx          real;
    degy          real;
    t             vec3;
    rd            vec3;
    ro            vec3;
    do_ray        boolean;
    shadow_done   boolean;
    c             rgb;
    intersection  boolean;
    mindist       real;
    material      material;
    mat           material;
    ho            rgb;
    col           rgb;
    no            vec3;
    triangle      triangles;
    sphere        spheres;
    prim_hit      boolean;
    v1            vec3;
    v2            vec3;
    v3            vec3;
    e1            vec3;
    e2            vec3;
    P             vec3;
    T1            vec3;                         -- NB: in original code: T
    Q             vec3;
    det           real;
    u             real;
    v             real;
    tdist         real;
    tdot          real;
    sp            vec3;
    spr           real;
    L             vec3;
    tca           real;
    d2            real;
    thc           real;
    li            vec3;
    r             int[]   := array[] :: int[];  -- pixel array
  BEGIN
    ntriangles  := (SELECT COUNT(*) FROM triangles);
    nspheres    := (SELECT COUNT(*) FROM spheres);
    nprimitives := ntriangles + nspheres;

    -- find light source among spheres
    sphere      := (SELECT sph FROM spheres AS sph WHERE sph.mat = 'l');
    light       := sphere.center;
    light_r     := sphere.radius;

    fov   := fov * (pi() / 180.0);

    cd    := (cam_lookat.x - cam.x, cam_lookat.y - cam.y, cam_lookat.z - cam.z);
    tlen  := sqrt(cd.x^2 + cd.y^2 + cd.z^2);
    rotz1   := cd.x / tlen;
    rotz2   := cd.y / tlen;
    rotz3   := cd.z / tlen;
    rotx1   := cam_up.y * rotz3 - cam_up.z * rotz2;
    rotx2   := cam_up.z * rotz1 - cam_up.x * rotz3;
    rotx3   := cam_up.x * rotz2 - cam_up.y * rotz1;
    tlen    := sqrt(rotx1^2 + rotx2^2 + rotx3^2);
    rotx1   := rotx1 / tlen;
    rotx2   := rotx2 / tlen;
    rotx3   := rotx3 / tlen;
    roty1   := rotz2 * rotx3 - rotz3 * rotx2;
    roty2   := rotz3 * rotx1 - rotz1 * rotx3;
    roty3   := rotz1 * rotx2 - rotz2 * rotx1;

    FOR pxy IN 0 .. h-1 LOOP
      FOR pxx IN 0 .. w-1 LOOP
        degx        := (((pxx + 0.5) / w) - 0.5) * fov * aspect_ratio;
        degy        := (((pxy + 0.5) / h) - 0.5) * fov;
        t           := (sin(degx), sin(degy), 1.0);
        rd          := (t.x*rotx1 + t.y*roty1 + t.z*rotz1,
                        t.x*rotx2 + t.y*roty2 + t.z*rotz2,
                        t.x*rotx3 + t.y*roty3 + t.z*rotz3);
        ro          := cam;
        do_ray      := true;
        shadow_done := false;
        c           := (0.0, 0.0, 0.0);

        FOR rec IN 1 .. (1 + max_rec_depth + shadows :: int) LOOP
          IF do_ray THEN
            do_ray       := false;
            tlen         := sqrt(rd.x^2 + rd.y^2 + rd.z^2);
            rd           := (rd.x / tlen, rd.y / tlen, rd.z / tlen);
            intersection := false;
            mindist      := 999999;
            material     := 'n';
            no           := (0.0, 0.0, 0.0);

            FOR i IN 1 .. nprimitives LOOP
              prim_hit := false;
              IF i <= ntriangles THEN
                triangle := (SELECT tri FROM triangles AS tri WHERE tri.id = i);
                v1       := triangle.p1;
                v2       := triangle.p2;
                v3       := triangle.p3;
                mat      := triangle.mat;
                col      := triangle.color;
                e1       := (v2.x - v1.x, v2.y - v1.y, v2.z - v1.z);
                e2       := (v3.x - v1.x, v3.y - v1.y, v3.z - v1.z);
                P        := (rd.y*e2.z - rd.z*e2.y, rd.z*e2.x - rd.x*e2.z, rd.x*e2.y - rd.y*e2.x);
                det      := e1.x*P.x + e1.y*P.y + e1.z*P.z;
                IF abs(det) > epsilon THEN
                  det := 1.0 / det;
                  T1  := (ro.x - v1.x, ro.y - v1.y, ro.z - v1.z);
                  u   := (T1.x*P.x + T1.y*P.y + T1.z*P.z) * det;
                  IF u BETWEEN 0.0 AND 1.0 THEN
                    Q := (T1.y*e1.z - T1.z*e1.y, T1.z*e1.x-T1.x*e1.z, T1.x*e1.y-T1.y*e1.x);
                    v := (rd.x*Q.x + rd.y*Q.y + rd.z*Q.z) * det;
                    IF v >= 0.0 AND u + v <= 1.0 THEN
                      tdist := (e2.x*Q.x + e2.y*Q.y + e2.z*Q.z) * det;
                      IF tdist > epsilon AND tdist < mindist THEN
                        prim_hit     := true;
                        intersection := true;
                        mindist      := tdist;
                        no           := (e2.y*e1.z - e2.z*e1.y, e2.z*e1.x - e2.x*e1.z, e2.x*e1.y - e2.y*e1.x);
                        tlen         := sqrt(no.x^2 + no.y^2 + no.z^2);
                        no           := (no.x / tlen, no.y / tlen, no.z / tlen);
                        tdot         := no.x*rd.x + no.y*rd.y + no.z*rd.z;
                        IF tdot > 0.0 THEN
                          no := (-no.x, -no.y, -no.z);
                        END IF; -- tdot > 0.0
                      END IF; -- tdist > epsilon AND tdist < mindist
                    END IF; -- v >= 0.0 AND u + v <= 1.0
                  END IF; -- u BETWEEN 0.0 AND 1.0
                END IF; -- abs(det) > epsilon
              ELSE
                sphere := (SELECT sph FROM spheres AS sph WHERE sph.id = i - ntriangles);
                sp     := sphere.center;
                spr    := sphere.radius;
                mat    := sphere.mat;
                col    := sphere.color;
                L      := (sp.x - ro.x, sp.y - ro.y, sp.z - ro.z);
                tca    := L.x*rd.x + L.y*rd.y + L.z*rd.z;
                d2     := L.x^2 + L.y^2 + L.z^2 - tca^2;
                IF d2 <= spr^2 THEN
                  thc   := sqrt(spr^2 - d2);
                  tdist := 0.0;
                  IF tca - thc > 0.0 THEN
                    tdist := tca - thc;
                  END IF;
                  IF tca + thc > 0.0 THEN
                    tdist := LEAST(tca + thc, tdist);
                  END IF;
                  IF tdist > 0.0 AND tdist < mindist THEN
                    prim_hit     := true;
                    intersection := true;
                    mindist      := tdist;
                    no           := (ro.x+tdist*rd.x-sp.x, ro.y+tdist*rd.y-sp.y, ro.z+tdist*rd.z-sp.z);
                    tlen         := sqrt(no.x^2 + no.y^2 + no.z^2);
                    no           := (no.x / tlen, no.y / tlen, no.z / tlen);
                  END IF; -- tdist > 0.0 AND tdist < mindist
                END IF; -- d2 <= spr^2
              END IF; -- i < ntriangles
              IF prim_hit THEN
                material := mat; -- if no primitive was hit by ray, material remains 'n'
                IF material = 'm' THEN
                  ho := col;
                END IF;
              END IF; -- prim_hit
            END LOOP; -- i
            IF shadow_done THEN
              IF material <> 'l' THEN
                c := (0.0, 0.0, 0.0);
              END IF; -- material <> 'l'
            ELSE
              IF material = 'l' THEN
                c := (1.0, 1.0, 1.0);
              END IF; -- material = 'l'
              IF material = 'm' THEN
                li   := (light.x-(ro.x+rd.x*mindist), light.y-(ro.y+rd.y*mindist), light.z-(ro.z+rd.z*mindist));
                tlen := sqrt(li.x^2 + li.y^2 + li.z^2);
                li   := (li.x / tlen, li.y / tlen, li.z / tlen);
                tdot := GREATEST(0.0, li.x*no.x + li.y*no.y + li.z*no.z);
                c    := (ho.r * tdot, ho.g * tdot, ho.b * tdot);
                IF shadows AND NOT shadow_done THEN
                  shadow_done := true;
                  ro          := (ro.x+rd.x*mindist+no.x*epsilon, ro.y+rd.y*mindist+no.y*epsilon, ro.z+rd.z*mindist+no.z*epsilon);
                  rd          := (light.x - ro.x, light.y - ro.y, light.z - ro.z);
                  do_ray      := true;
                END IF; -- shadows AND NOT shadow_done
              END IF; -- material = 'm'
              IF material = 'r' THEN
                tdot   := rd.x*no.x + rd.y*no.y + rd.z*no.z;
                ro     := (ro.x+rd.x*mindist+no.x*epsilon, ro.y+rd.y*mindist+no.y*epsilon, ro.z+rd.z*mindist+no.z*epsilon);
                rd     := (rd.x-2.0*no.x*tdot, rd.y-2.0*no.y*tdot, rd.z-2.0*no.z*tdot);
                do_ray := true;
              END IF; -- material = 'r'
            END IF; -- shadow_done
          END IF; -- do_ray
        END LOOP; -- rec
        IF intersection THEN
          r := r || array[(c.b * 255) :: int, (c.g * 255) :: int, (c.r * 255) :: int];
        ELSE
          r := r || array[0, 0, 0];
        END IF; -- intersection
      END LOOP; -- pxx
    END LOOP; -- pxy
    RETURN r;
  END;
$$
LANGUAGE PLPGSQL;


-----------------------------------------------------------------------
-- Run ray tracer (optionally pipe into external base64 decoder)

-- # of raytracer runs (~ invocations)
\set N :invocations

-- width/height of generated image (~iterations, will render (10 × :iterations) pixels)
\set w sqrt(10 * :iterations) :: int
\set h sqrt(10 * :iterations) :: int

\timing on
SELECT raytrace(:w, :h)
FROM   generate_series(1, :N) AS i;

-- COPY (SELECT base64(bmp(:w, :h, raytrace(:w, :h))))
-- TO   PROGRAM 'base64 -D -o /tmp/out.tmp';

