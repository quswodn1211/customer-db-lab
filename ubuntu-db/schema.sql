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
INSERT INTO public.customers
SELECT CASE n WHEN 0 THEN 'AAA-000' WHEN 99 THEN 'ZZZ-999' ELSE 'CUS-' || lpad(n::text,3,'0') END,
       CASE n WHEN 0 THEN 'aa000' WHEN 99 THEN 'zz999' ELSE 'lab' || lpad(n::text,3,'0') END || '@gmail.com',
       CASE n WHEN 0 THEN 'Ahn Ara' WHEN 99 THEN 'Zun Yuri' ELSE 'Kim ' || lpad(n::text,3,'0') END
FROM generate_series(0,99) AS g(n);
INSERT INTO honey.tokens VALUES ('AAA-000'), ('ZZZ-999');
INSERT INTO honey.tokens
SELECT cno FROM public.customers WHERE cno LIKE 'CUS-%'
ORDER BY md5(:'seed' || cno), cno LIMIT (:ratio - 2);

CREATE FUNCTION public.read_customers(sort_by text DEFAULT 'cno', descending boolean DEFAULT false,
                                      page_size integer DEFAULT 100, skip_rows integer DEFAULT 0)
RETURNS SETOF public.customers
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    r record;
    result public.customers;
BEGIN
    IF sort_by IS NULL OR lower(sort_by) NOT IN ('cno','email','full_name') OR descending IS NULL
       OR page_size IS NULL OR page_size NOT BETWEEN 0 AND 100 OR skip_rows IS NULL OR skip_rows < 0 THEN
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
