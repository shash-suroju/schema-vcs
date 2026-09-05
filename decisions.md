# Day 1 · Repo, Skeleton, Deploy
 
**Java is my strongest language; I chose Python because the deciding constraint was hours available for the hard sub-problem, not language comfort.**


**Why psycopg3 over asyncpg: Generating DDL from user-supplied identifiers. psycopg3 ships sql.Identifier / sql.SQL for safe composition; asyncpg has no equivalent and It'd be hand-rolling quoting for a SQL-injection surface.**