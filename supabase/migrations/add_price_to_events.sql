-- events tablosuna price kolonu ekle (yoksa)
ALTER TABLE events ADD COLUMN IF NOT EXISTS price NUMERIC(10, 2) DEFAULT NULL;

-- external_id unique index (upsert için)
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_external_id ON events(external_id)
  WHERE external_id IS NOT NULL;
