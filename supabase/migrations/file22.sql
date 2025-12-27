-- Clean up any potential duplicate active participations
WITH duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (PARTITION BY user_id, room_id ORDER BY joined_at DESC) as rn
  FROM room_participants
  WHERE left_at IS NULL
)
UPDATE room_participants rp
SET left_at = NOW()
FROM duplicates d
WHERE rp.id = d.id 
  AND d.rn > 1;

-- Ensure all users are only in one active room at a time
WITH user_multiple_rooms AS (
  SELECT 
    user_id,
    COUNT(DISTINCT room_id) as room_count
  FROM room_participants
  WHERE left_at IS NULL
  GROUP BY user_id
  HAVING COUNT(DISTINCT room_id) > 1
),
latest_room AS (
  SELECT DISTINCT ON (user_id) 
    user_id,
    room_id,
    joined_at
  FROM room_participants
  WHERE left_at IS NULL
    AND user_id IN (SELECT user_id FROM user_multiple_rooms)
  ORDER BY user_id, joined_at DESC
)
UPDATE room_participants rp
SET left_at = NOW()
FROM latest_room lr
WHERE rp.user_id = lr.user_id 
  AND rp.room_id != lr.room_id
  AND rp.left_at IS NULL;