-- Add gender column to users table
ALTER TABLE public.users ADD COLUMN gender text DEFAULT 'other';

-- Add creator_gender column to rooms table for matching
ALTER TABLE public.rooms ADD COLUMN creator_gender text DEFAULT 'other';