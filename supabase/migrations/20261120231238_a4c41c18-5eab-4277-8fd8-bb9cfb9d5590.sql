-- Chat deletion: hidden on every device; blocked numbers keep new messages hidden; restorable from the archive.
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS blocked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hidden_before timestamptz;