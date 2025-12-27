-- ============================================
-- 🔧 SIMPLE FIX: Online Users Count
-- Run this in Supabase SQL Editor
-- No test conflicts - just the essential fix
-- ============================================

-- Step 1: Drop existing functions
DROP FUNCTION IF EXISTS get_active_users_by_gender();
DROP FUNCTION IF EXISTS get_online_users_by_gender();

-- Step 2: Create the correct function
CREATE OR REPLACE FUNCTION get_active_users_by_gender()
RETURNS TABLE(
    male_count BIGINT,
    female_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'male') as male_count,
        COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'female') as female_count
    FROM room_participants rp
    INNER JOIN users u ON u.id = rp.user_id
    INNER JOIN rooms r ON r.id = rp.room_id
    WHERE rp.left_at IS NULL
      AND r.is_active = true
      AND r.room_type = 'public'
      AND u.gender IN ('male', 'female');
END;
$$;

-- Step 3: Grant permissions
GRANT EXECUTE ON FUNCTION get_active_users_by_gender() TO authenticated, anon;

-- Step 4: Test it (safe test with current data)
DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM get_active_users_by_gender();
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ONLINE USERS FUNCTION INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Current Online Users:';
    RAISE NOTICE '  • Males: %', COALESCE(result.male_count, 0);
    RAISE NOTICE '  • Females: %', COALESCE(result.female_count, 0);
    RAISE NOTICE '';
    RAISE NOTICE '🧪 Test in your app:';
    RAISE NOTICE '  const { data } = await supabase.rpc("get_active_users_by_gender")';
    RAISE NOTICE '  console.log(data[0].male_count, data[0].female_count)';
    RAISE NOTICE '========================================';
END $$;