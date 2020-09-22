-- Iterative PL/SQL UDF that implements the VM instructions.  The
-- parameter represents the machine's register file (each register holds
-- one integer).

DROP FUNCTION IF EXISTS run(numeric[]);
CREATE FUNCTION run(regs numeric[]) RETURNS numeric AS
$$
  DECLARE
    ip  int := 0;
    ins instruction;
  BEGIN
    LOOP
      ins := (SELECT p
              FROM   program AS p
              WHERE  p.loc = ip);
      ip := ip + 1;

      IF    ins.opc = 'lod' THEN regs := regs[:ins.reg1-1] || ins.reg2       || regs[ins.reg1+1:];
      ELSIF ins.opc = 'mov' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'jeq' THEN IF regs[ins.reg1] = regs[ins.reg2] THEN ip := ins.reg3 :: int4; END IF;
      ELSIF ins.opc = 'jmp' THEN ip := ins.reg1 :: int4;
      ELSIF ins.opc = 'add' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] + regs[ins.reg3] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'sub' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] - regs[ins.reg3] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'mul' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] * regs[ins.reg3] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'div' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] / regs[ins.reg3] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'mod' THEN regs := regs[:ins.reg1-1] || regs[ins.reg2] % regs[ins.reg3] || regs[ins.reg1+1:];
      ELSIF ins.opc = 'hlt' THEN RETURN regs[ins.reg1];
      END IF;

    END LOOP;
  END;
$$
LANGUAGE PLPGSQL;


-- Virtual machine (VM) featuring three-address opcodes

-- # of VM runs (~ invocations)
\set N :invocations

-- Run the VM program
\timing on
SELECT run(array[:iterations,0,0,0,0,0,0]) AS padovan
FROM   generate_series(0,:N) AS _;

