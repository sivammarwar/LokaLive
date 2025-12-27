-- ============================================
-- LUDO VOTING SYSTEM DATABASE SETUP
-- Run this in Supabase SQL Editor
-- ============================================

-- Step 1: Create ludo_votes table
CREATE TABLE IF NOT EXISTS public.ludo_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id) -- One vote per user
);

-- Step 2: Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_ludo_votes_user_id ON public.ludo_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_ludo_votes_voted_at ON public.ludo_votes(voted_at);

-- Step 3: Enable Row Level Security
ALTER TABLE public.ludo_votes ENABLE ROW LEVEL SECURITY;

-- Step 4: Create RLS Policies
-- Users can view all votes
CREATE POLICY "Anyone can view ludo votes" 
    ON public.ludo_votes
    FOR SELECT
    USING (true);

-- Users can only insert their own vote
CREATE POLICY "Users can vote once" 
    ON public.ludo_votes
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users cannot update or delete votes (permanent)
CREATE POLICY "Votes cannot be deleted" 
    ON public.ludo_votes
    FOR DELETE
    USING (false);

-- Step 5: Enable Realtime for live vote count updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_votes;

-- Step 6: Create function to get total vote count
CREATE OR REPLACE FUNCTION get_ludo_vote_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    vote_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO vote_count
    FROM public.ludo_votes;
    
    RETURN COALESCE(vote_count, 0);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_ludo_vote_count() TO authenticated;
GRANT EXECUTE ON FUNCTION get_ludo_vote_count() TO anon;

-- Step 7: Create function to check if user has voted
CREATE OR REPLACE FUNCTION has_user_voted_ludo(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    has_voted BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM public.ludo_votes
        WHERE user_id = p_user_id
    ) INTO has_voted;
    
    RETURN COALESCE(has_voted, false);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION has_user_voted_ludo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_user_voted_ludo(UUID) TO anon;

-- Step 8: Create view for vote statistics
CREATE OR REPLACE VIEW public.ludo_vote_stats AS
SELECT 
    COUNT(*) as total_votes,
    COUNT(DISTINCT DATE(voted_at)) as days_with_votes,
    MIN(voted_at) as first_vote,
    MAX(voted_at) as latest_vote,
    COUNT(CASE WHEN voted_at > NOW() - INTERVAL '24 hours' THEN 1 END) as votes_last_24h,
    COUNT(CASE WHEN voted_at > NOW() - INTERVAL '7 days' THEN 1 END) as votes_last_week
FROM public.ludo_votes;

-- Grant access
GRANT SELECT ON public.ludo_vote_stats TO authenticated;
GRANT SELECT ON public.ludo_vote_stats TO anon;

-- Step 9: Add comments for documentation
COMMENT ON TABLE public.ludo_votes IS 'Stores votes for Ludo feature - each user can vote once';
COMMENT ON FUNCTION get_ludo_vote_count() IS 'Returns total number of votes for Ludo feature';
COMMENT ON FUNCTION has_user_voted_ludo(UUID) IS 'Checks if a specific user has already voted for Ludo';

-- Step 10: Verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ LUDO VOTING SYSTEM INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Created:';
    RAISE NOTICE '  ✓ ludo_votes table';
    RAISE NOTICE '  ✓ RLS policies (view all, vote once)';
    RAISE NOTICE '  ✓ Realtime subscription enabled';
    RAISE NOTICE '  ✓ Helper functions';
    RAISE NOTICE '  ✓ Vote statistics view';
    RAISE NOTICE '';
    RAISE NOTICE 'Features:';
    RAISE NOTICE '  • One vote per user (enforced)';
    RAISE NOTICE '  • Real-time vote count updates';
    RAISE NOTICE '  • Vote statistics tracking';
    RAISE NOTICE '  • Permanent votes (cannot delete)';
    RAISE NOTICE '';
    RAISE NOTICE 'Current Status:';
END $$;

-- Show current vote count
SELECT 
    'Total Votes' as metric,
    COUNT(*)::TEXT as value
FROM public.ludo_votes
UNION ALL
SELECT 
    'Target' as metric,
    '1,000,000' as value
UNION ALL
SELECT 
    'Progress' as metric,
    ROUND((COUNT(*)::DECIMAL / 1000000) * 100, 4)::TEXT || '%' as value
FROM public.ludo_votes;

