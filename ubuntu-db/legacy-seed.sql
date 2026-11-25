INSERT INTO public.customers
SELECT CASE n WHEN 0 THEN 'AAA-000' WHEN 99 THEN 'ZZZ-999' ELSE 'CUS-' || lpad(n::text,3,'0') END,
       CASE n WHEN 0 THEN 'aa000' WHEN 99 THEN 'zz999' ELSE 'lab' || lpad(n::text,3,'0') END || '@gmail.com',
       CASE n WHEN 0 THEN 'Ahn Ara' WHEN 99 THEN 'Zun Yuri' ELSE 'Kim ' || lpad(n::text,3,'0') END
FROM generate_series(0,99) AS g(n);
INSERT INTO honey.tokens VALUES ('AAA-000'), ('ZZZ-999');
INSERT INTO honey.tokens
SELECT cno FROM public.customers WHERE cno LIKE 'CUS-%'
ORDER BY md5(:'seed' || cno), cno LIMIT (:ratio - 2);
