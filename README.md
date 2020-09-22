# One `WITH RECURSIVE` is Worth Many `GOTO`s

This repository contains the 13 PL/SQL UDFs discussed in 
Section 4 of the accompanying paper "_One `WITH RECURSIVE`
is Worth Many `GOTO`s_".  Each UDF is present in its original
PL/SQL form as well as the compiled SQL form.

The UDFs have been developed on PostgreSQL 11.3 (but any
recent version of PostgreSQL should run the functions just fine).
We have added SQL DDL and DML statements that set up tables
with test data so that all UDFs should be ready to run 
instantly.

Each UDF `<f>` is hosted in a subdirectory of the same name
(the names `<f>` correspond with those in Table 1 of the paper).
Subdirectory `<f>/` contains:

1. A database setup script `<f>-preparation.sql` with a data generator (if that is required).

1. The original, non-compiled PL/SQL UDF `<f>-pl.sql`.

1. The UDF's compiled SQL form `<f>-tr.sql`. 
   Minor simplifications to this SQL code have been applied manually 
   (e.g., simple SQL subexpressions have been inlined).

1. `run-experiment.sh`, which runs the setup, the original PL/SQL UDF, as well as the compiled SQL form.
   You may run this script or invoke the three scripts mentioned above individually.

Most of the UDF scenarios are self-contained and generate their own test
data using the `<f>-preparation.sql` script.  The UDFs `margin`, `packing`, 
`savings`, `scheduling` are based on the TPC-H database benchmark [^TPCH] [^TPCHkit]. 
The [`TPC-H/`](TPC-H/) folder contains everything needed to setup a tiny TPC-H 
instance with scaling factor `sf = 0.01`.
Shell script [`TPC-H/load.sh`](TPC-H/load.sh) performs all necessary TPC-H setup steps 
automatically.

\[^TPCH]: [http://www.tpc.org/tpch](http://www.tpc.org/tpch)

\[^TPCHkit]: [http://github.com/gregrahn/tpch-kit](http://github.com/gregrahn/tpch-kit)
