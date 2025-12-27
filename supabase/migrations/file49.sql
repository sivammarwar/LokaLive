-- ============================================
-- 🧹 CLEANUP EXISTING ROOMS
-- This resets all active rooms so you can test fresh
-- ============================================

-- Mark all participants as left
UPDATE room_participants 
SET left_at = NOW() 
WHERE left_at IS NULL;

-- Deactivate all rooms
UPDATE rooms 
SET is_active = false 
WHERE is_active = true;

-- Verify cleanup
SELECT 
    'Active Rooms' as metric,
    COUNT(*) as count
FROM rooms 
WHERE is_active = true
UNION ALL
SELECT 
    'Active Participants' as metric,
    COUNT(*) as count
FROM room_participants 
WHERE left_at IS NULL;

-- Should show 0 for both