-- ============================================
-- 🔧 AUTO-MAINTAIN WEBRTC CONNECTIONS
-- ============================================

-- Function to check and cleanup stale participants
CREATE OR REPLACE FUNCTION auto_cleanup_stale_participants()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cleaned_count INTEGER;
BEGIN
    -- Mark participants as left if:
    -- 1. They've been in the room for > 30 minutes
    -- 2. OR if their last activity was > 5 minutes ago (for chess returns)
    UPDATE room_participants
    SET left_at = NOW()
    WHERE left_at IS NULL
      AND (
          -- Been in room too long
          joined_at < NOW() - INTERVAL '30 minutes'
          OR
          -- No recent signaling activity (for chess returns)
          user_id IN (
            SELECT DISTINCT rp.user_id
            FROM room_participants rp
            LEFT JOIN signaling s ON s.sender_id = rp.user_id 
              AND s.created_at > NOW() - INTERVAL '5 minutes'
            WHERE rp.left_at IS NULL
              AND s.id IS NULL
          )
      );
    
    GET DIAGNOSTICS cleaned_count = ROW_COUNT;
    
    IF cleaned_count > 0 THEN
        RAISE NOTICE '✅ Auto-cleaned % stale participants', cleaned_count;
    END IF;
    
    RETURN cleaned_count;
END;
$$;

-- Function to get active room participants with their connection status
CREATE OR REPLACE FUNCTION get_active_participants_with_status(p_room_id UUID)
RETURNS TABLE(
    user_id UUID,
    display_name TEXT,
    is_connected BOOLEAN,
    last_signal_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rp.user_id,
        u.display_name,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM signaling s
                WHERE s.sender_id = rp.user_id
                  AND s.room_id = p_room_id
                  AND s.created_at > NOW() - INTERVAL '1 minute'
            ) THEN true
            ELSE false
        END as is_connected,
        (
            SELECT MAX(created_at) 
            FROM signaling 
            WHERE sender_id = rp.user_id 
              AND room_id = p_room_id
        ) as last_signal_at
    FROM room_participants rp
    INNER JOIN users u ON u.id = rp.user_id
    WHERE rp.room_id = p_room_id
      AND rp.left_at IS NULL
    ORDER BY is_connected DESC, rp.joined_at ASC;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION auto_cleanup_stale_participants() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_active_participants_with_status(UUID) TO authenticated, anon;

-- Create a scheduled job to run cleanup (if using pg_cron)
-- Uncomment if you have pg_cron enabled
-- SELECT cron.schedule('cleanup-stale-participants', '*/5 * * * *', 
--   'SELECT auto_cleanup_stale_participants();');