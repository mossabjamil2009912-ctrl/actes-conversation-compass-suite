-- Catalog platform (moved from the separate catalog app): categories, catalogs, page text chunks, product profiles.
CREATE TABLE public.catalog_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.catalog_categories TO service_role;
ALTER TABLE public.catalog_categories ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.catalogs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  keywords text NOT NULL DEFAULT '',
  category_id uuid REFERENCES public.catalog_categories(id) ON DELETE SET NULL,
  language text NOT NULL DEFAULT 'ar',
  file_path text NOT NULL,
  cover_path text,
  page_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.catalogs TO service_role;
ALTER TABLE public.catalogs ENABLE ROW LEVEL SECURITY;
CREATE INDEX catalogs_category_idx ON public.catalogs(category_id);

CREATE TABLE public.catalog_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_id uuid NOT NULL REFERENCES public.catalogs(id) ON DELETE CASCADE,
  page integer NOT NULL DEFAULT 1,
  content text NOT NULL,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.catalog_chunks TO service_role;
ALTER TABLE public.catalog_chunks ENABLE ROW LEVEL SECURITY;
CREATE INDEX catalog_chunks_catalog_idx ON public.catalog_chunks(catalog_id);
CREATE INDEX catalog_chunks_fts_idx ON public.catalog_chunks USING gin(fts);

CREATE TABLE public.catalog_profiles (
  catalog_id uuid PRIMARY KEY REFERENCES public.catalogs(id) ON DELETE CASCADE,
  summary_ar text NOT NULL DEFAULT '',
  summary_en text NOT NULL DEFAULT '',
  specs jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.catalog_profiles TO service_role;
ALTER TABLE public.catalog_profiles ENABLE ROW LEVEL SECURITY;

-- Word-OR full text search over catalog pages (any matching word counts; more matches rank higher).
CREATE OR REPLACE FUNCTION public.search_catalog_chunks(q text, lim integer DEFAULT 7)
RETURNS TABLE(catalog_id uuid, title text, page integer, content text, score real)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE tq tsquery; w text;
BEGIN
  FOR w IN SELECT DISTINCT x FROM regexp_split_to_table(lower(coalesce(q, '')), E'[\\s,،؟?!:;()"''|&<>*\\[\\]{}]+') x WHERE length(x) >= 2 LIMIT 30 LOOP
    IF plainto_tsquery('simple', w)::text <> '' THEN
      tq := CASE WHEN tq IS NULL THEN plainto_tsquery('simple', w) ELSE tq || plainto_tsquery('simple', w) END;
    END IF;
  END LOOP;
  IF tq IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT c.catalog_id, k.title, c.page, c.content, ts_rank(c.fts, tq) AS score
    FROM public.catalog_chunks c JOIN public.catalogs k ON k.id = c.catalog_id
    WHERE c.fts @@ tq
    ORDER BY score DESC
    LIMIT lim;
END $$;
REVOKE ALL ON FUNCTION public.search_catalog_chunks(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_catalog_chunks(text, integer) TO service_role;