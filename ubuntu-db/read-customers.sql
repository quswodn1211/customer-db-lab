CREATE OR REPLACE FUNCTION public.read_customers(sort_by text DEFAULT 'cno', descending boolean DEFAULT false,
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
        'SELECT c AS customer, t.cno IS NOT NULL AS hit FROM public.customers c
         LEFT JOIN honey.tokens t ON c.cno=t.cno ORDER BY c.%I %s, c.cno LIMIT $1 OFFSET $2',
         lower(sort_by), CASE WHEN descending THEN 'DESC' ELSE 'ASC' END)
         USING page_size, skip_rows LOOP
        IF r.hit THEN
            RAISE LOG USING ERRCODE = 'HNY01', MESSAGE = json_build_object(
                'event','HONEYTOKEN_READ','event_id',current_database() || '-' || nextval('honey.event_seq'),
                'time',clock_timestamp(),'db',current_database(),'login',session_user,
                'client_ip',host(inet_client_addr()),'cno',(r.customer).cno)::text;
        END IF;
        result := r.customer;
        RETURN NEXT result;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.read_customers(text,boolean,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.read_customers(text,boolean,integer,integer) TO business_reader;
