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

CREATE FUNCTION public.read_customers(sort_by text DEFAULT 'cno', descending boolean DEFAULT false,
                                      page_size integer DEFAULT 200, skip_rows integer DEFAULT 0)
RETURNS SETOF public.customers
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    r record;
    result public.customers;
BEGIN
    IF sort_by IS NULL OR lower(sort_by) NOT IN ('cno','email','full_name') OR descending IS NULL
       OR page_size IS NULL OR page_size NOT BETWEEN 0 AND 200 OR skip_rows IS NULL OR skip_rows < 0 THEN
        RAISE EXCEPTION 'Invalid sort field, direction, page size or offset';
    END IF;
    FOR r IN EXECUTE format(
        'SELECT c.*, t.cno IS NOT NULL AS hit FROM public.customers c
         LEFT JOIN honey.tokens t ON c.cno=t.cno ORDER BY c.%I %s, c.cno LIMIT $1 OFFSET $2',
         lower(sort_by), CASE WHEN descending THEN 'DESC' ELSE 'ASC' END)
         USING page_size, skip_rows LOOP
        IF r.hit THEN
            RAISE LOG USING ERRCODE = 'HNY01', MESSAGE = json_build_object(
                'event','HONEYTOKEN_READ','event_id',current_database() || '-' || nextval('honey.event_seq'),
                'time',clock_timestamp(),'db',current_database(),'login',session_user,
                'client_ip',host(inet_client_addr()),'cno',r.cno)::text;
        END IF;
        result := ROW(r.cno,r.email,r.full_name);
        RETURN NEXT result;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.read_customers(text,boolean,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.read_customers(text,boolean,integer,integer) TO business_reader;
-- Only the owner should be able to issue procedural LOG messages in this lab.
REVOKE USAGE ON LANGUAGE plpgsql FROM PUBLIC;
COMMIT;
