-- Check how many active rooms and participants you have
SELECT 
  'Active Rooms' as metric,
  COUNT(*) as count
FROM rooms WHERE is_active = true
UNION ALL
SELECT 
  'Active Participants',
  COUNT(*)
FROM room_participants WHERE left_at IS NULL;