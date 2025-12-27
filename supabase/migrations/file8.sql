-- Fix 2: Add indexes for faster matching
CREATE INDEX IF NOT EXISTS idx_rooms_matching 
ON public.rooms(room_type, is_active, room_size, gender_preference, interest_category)
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_rooms_creator_gender 
ON public.rooms(creator_gender) 
WHERE room_type = 'public';

CREATE INDEX IF NOT EXISTS idx_room_participants_active 
ON public.room_participants(room_id, left_at) 
WHERE left_at IS NULL;

-- Fix 3: Prevent users from joining full rooms
CREATE OR REPLACE FUNCTION check_room_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    participant_count INTEGER;
    max_size INTEGER;
BEGIN
    SELECT COUNT(*), r.room_size 
    INTO participant_count, max_size
    FROM public.room_participants rp
    JOIN public.rooms r ON r.id = NEW.room_id
    WHERE rp.room_id = NEW.room_id 
    AND rp.left_at IS NULL
    GROUP BY r.room_size;
    
    IF participant_count >= max_size THEN
        RAISE EXCEPTION 'Room is full';
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_room_capacity ON public.room_participants;
CREATE TRIGGER enforce_room_capacity
BEFORE INSERT ON public.room_participants
FOR EACH ROW
EXECUTE FUNCTION check_room_capacity();

-- Fix 4: Auto-cleanup empty rooms
CREATE OR REPLACE FUNCTION cleanup_empty_rooms()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.rooms
    SET is_active = false
    WHERE id IN (
        SELECT r.id
        FROM public.rooms r
        LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
        WHERE r.is_active = true
        GROUP BY r.id
        HAVING COUNT(rp.id) = 0
        AND r.created_at < now() - INTERVAL '5 minutes'
    );
END;
$$;