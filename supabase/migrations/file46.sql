-- Drop the trigger first (correct name)
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON rooms;

-- Now drop the function
DROP FUNCTION IF EXISTS set_creator_gender() CASCADE;

-- Verify it's gone
SELECT trigger_name 
FROM information_schema.triggers 
WHERE event_object_table = 'rooms';
-- Should return empty