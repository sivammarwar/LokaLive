-- Clean up all old rooms
UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- Verify cleanup
SELECT COUNT(*) as active_rooms FROM rooms WHERE is_active = true;
-- Should return 0