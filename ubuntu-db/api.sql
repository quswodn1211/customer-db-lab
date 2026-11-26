CREATE TABLE IF NOT EXISTS honey.api_keys (
    cno varchar(10) PRIMARY KEY REFERENCES public.customers,
    api_key text NOT NULL UNIQUE,
    key_hash text NOT NULL UNIQUE
);
CREATE OR REPLACE FUNCTION public.api_customer(digest text, peer inet)
RETURNS SETOF public.customers LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    customer public.customers;
BEGIN
    SELECT c.* INTO customer FROM public.customers c JOIN honey.api_keys k USING(cno)
    WHERE k.key_hash=digest;
    IF FOUND THEN
        IF EXISTS (SELECT 1 FROM honey.tokens t WHERE t.cno=customer.cno) THEN
            RAISE LOG USING ERRCODE='HNY01', MESSAGE=json_build_object(
                'event','HONEYTOKEN_API_USED','event_id',current_database() || '-' || nextval('honey.event_seq'),
                'time',clock_timestamp(),'db',current_database(),'login',session_user,
                'client_ip',host(peer),'cno',customer.cno)::text;
        END IF;
        RETURN NEXT customer;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.api_customer(text,inet) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.api_customer(text,inet) TO honey_api;
