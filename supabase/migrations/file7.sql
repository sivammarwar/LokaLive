-- Step 1a: First, let's see what data exists
SELECT DISTINCT gender FROM public.users;

-- Step 1b: Update any invalid gender values to 'other'
UPDATE public.users 
SET gender = 'other' 
WHERE gender NOT IN ('male', 'female', 'other') 
OR gender IS NULL;

-- Step 1c: Now safely convert the column type
ALTER TABLE public.users 
ALTER COLUMN gender DROP DEFAULT;

ALTER TABLE public.users 
ALTER COLUMN gender TYPE gender_preference 
USING gender::gender_preference;

ALTER TABLE public.users 
ALTER COLUMN gender SET DEFAULT 'other';

-- Step 1d: Do the same for rooms table
UPDATE public.rooms 
SET creator_gender = 'other' 
WHERE creator_gender NOT IN ('male', 'female', 'other') 
OR creator_gender IS NULL;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender DROP DEFAULT;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender TYPE gender_preference 
USING creator_gender::gender_preference;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender SET DEFAULT 'other';