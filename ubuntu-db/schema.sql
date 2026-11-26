BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA honey;
CREATE TABLE public.customers (
    cno varchar(10) COLLATE "C" PRIMARY KEY CHECK (cno ~ '^[A-Z]{3}-[0-9]{3}$'),
    email text COLLATE "C" NOT NULL CHECK (email ~ '^[a-z0-9]+@gmail[.]com$'),
    full_name varchar(20) COLLATE "C" NOT NULL
);
CREATE TABLE honey.tokens (cno varchar(10) PRIMARY KEY REFERENCES public.customers);
CREATE SEQUENCE honey.event_seq;
\i :seed_file

\ir read-customers.sql
-- Only the owner should be able to issue procedural LOG messages in this lab.
REVOKE USAGE ON LANGUAGE plpgsql FROM PUBLIC;
COMMIT;
