-- ============================================
-- DIAMOND SYSTEM TEST SETUP
-- Run this AFTER the main migration
-- ============================================

-- Step 1: Give yourself some test diamonds (replace with your user email)
DO $$
DECLARE
    my_user_id UUID;
    test_email TEXT := 'your-email@example.com'; -- CHANGE THIS TO YOUR EMAIL
BEGIN
    -- Get your user ID
    SELECT id INTO my_user_id
    FROM public.users
    WHERE email = test_email;
    
    IF my_user_id IS NULL THEN
        RAISE NOTICE 'User not found. Please update the email in this script.';
        RAISE NOTICE 'Available users:';
        FOR my_user_id IN 
            SELECT id FROM public.users LIMIT 5
        LOOP
            RAISE NOTICE 'User ID: %', my_user_id;
        END LOOP;
    ELSE
        -- Give test diamonds
        UPDATE public.users
        SET diamonds = 500,
            updated_at = now()
        WHERE id = my_user_id;
        
        -- Log the transaction
        INSERT INTO public.diamond_transactions (
            user_id,
            type,
            amount,
            description,
            status
        ) VALUES (
            my_user_id,
            'purchase',
            500,
            'Test diamonds for development',
            'completed'
        );
        
        RAISE NOTICE '✅ Added 500 test diamonds to user: %', test_email;
        RAISE NOTICE 'User ID: %', my_user_id;
    END IF;
END $$;

-- Step 2: Verify the diamond system
SELECT 
    'System Check' as test_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'users' AND column_name = 'diamonds'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as users_diamonds_column,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'diamond_transactions'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as diamond_transactions_table,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'chess_games' AND column_name = 'is_bet_match'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as chess_bet_columns,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_name = 'add_diamonds'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as add_diamonds_function,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_name = 'deduct_diamonds'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as deduct_diamonds_function,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.routines 
            WHERE routine_name = 'process_bet_payout'
        ) THEN '✅ Pass'
        ELSE '❌ Fail'
    END as process_bet_payout_function;

-- Step 3: Show current user balances
SELECT 
    display_name,
    email,
    diamonds,
    membership_tier,
    created_at
FROM public.users
ORDER BY diamonds DESC, created_at DESC
LIMIT 10;

-- Step 4: Test diamond functions (optional - uncomment to test)
/*
DO $$
DECLARE
    test_user_id UUID;
BEGIN
    -- Get a test user
    SELECT id INTO test_user_id FROM public.users LIMIT 1;
    
    RAISE NOTICE 'Testing with user: %', test_user_id;
    
    -- Test add_diamonds
    PERFORM add_diamonds(test_user_id, 100);
    RAISE NOTICE '✅ add_diamonds() works';
    
    -- Test deduct_diamonds
    PERFORM deduct_diamonds(test_user_id, 50);
    RAISE NOTICE '✅ deduct_diamonds() works';
    
    -- Check final balance
    DECLARE
        final_balance INTEGER;
    BEGIN
        SELECT diamonds INTO final_balance FROM public.users WHERE id = test_user_id;
        RAISE NOTICE 'Final balance: % diamonds', final_balance;
    END;
END $$;
*/

-- Step 5: Create sample diamond packages (for reference)
-- These match what's in your DiamondPurchase.tsx component
CREATE TABLE IF NOT EXISTS public.diamond_packages (
    id TEXT PRIMARY KEY,
    diamonds INTEGER NOT NULL,
    price_inr DECIMAL(10, 2) NOT NULL,
    bonus INTEGER DEFAULT 0,
    is_popular BOOLEAN DEFAULT false,
    display_order INTEGER,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.diamond_packages ENABLE ROW LEVEL SECURITY;

-- Allow everyone to read packages
CREATE POLICY "Allow reading diamond packages" ON public.diamond_packages
    FOR SELECT
    USING (is_active = true);

-- Insert the three packages
INSERT INTO public.diamond_packages (id, diamonds, price_inr, bonus, is_popular, display_order)
VALUES 
    ('pack_15', 15, 100.00, 0, false, 1),
    ('pack_80', 80, 500.00, 5, true, 2),
    ('pack_170', 170, 1000.00, 20, false, 3)
ON CONFLICT (id) DO UPDATE SET
    diamonds = EXCLUDED.diamonds,
    price_inr = EXCLUDED.price_inr,
    bonus = EXCLUDED.bonus,
    is_popular = EXCLUDED.is_popular,
    display_order = EXCLUDED.display_order;

-- Step 6: Useful queries for monitoring

-- View all diamond transactions
CREATE OR REPLACE VIEW public.recent_diamond_activity AS
SELECT 
    dt.id,
    u.display_name,
    dt.type,
    dt.amount,
    dt.description,
    dt.status,
    dt.created_at
FROM public.diamond_transactions dt
JOIN public.users u ON u.id = dt.user_id
ORDER BY dt.created_at DESC
LIMIT 50;

GRANT SELECT ON public.recent_diamond_activity TO authenticated;

-- View active bet matches
CREATE OR REPLACE VIEW public.active_bet_matches AS
SELECT 
    cg.id as game_id,
    cg.status,
    cg.bet_amount,
    cg.bet_status,
    w.display_name as white_player,
    b.display_name as black_player,
    winner.display_name as winner_name,
    cg.created_at,
    cg.updated_at
FROM public.chess_games cg
JOIN public.users w ON w.id = cg.white_player_id
JOIN public.users b ON b.id = cg.black_player_id
LEFT JOIN public.users winner ON winner.id = cg.winner_id
WHERE cg.is_bet_match = true
AND cg.status IN ('pending', 'active')
ORDER BY cg.created_at DESC;

GRANT SELECT ON public.active_bet_matches TO authenticated;

-- Step 7: Final verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DIAMOND SYSTEM IS READY!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'What you can do now:';
    RAISE NOTICE '1. Go to /diamond-purchase to buy diamonds';
    RAISE NOTICE '2. Challenge someone to a bet match';
    RAISE NOTICE '3. Play and win to earn diamonds';
    RAISE NOTICE '';
    RAISE NOTICE 'Diamond Economy:';
    RAISE NOTICE '  • 1 Diamond = 5 INR';
    RAISE NOTICE '  • Min withdrawal: 15 diamonds (75 INR)';
    RAISE NOTICE '  • Max bet per match: 1000 diamonds';
    RAISE NOTICE '  • Winner gets 2x the bet amount';
    RAISE NOTICE '';
    RAISE NOTICE 'Monitoring Views Created:';
    RAISE NOTICE '  • user_diamond_stats';
    RAISE NOTICE '  • recent_diamond_activity';
    RAISE NOTICE '  • active_bet_matches';
    RAISE NOTICE '========================================';
END $$;

-- Step 8: Quick stats
SELECT 
    'Total Users' as metric,
    COUNT(*)::TEXT as value
FROM public.users

UNION ALL

SELECT 
    'Users with Diamonds' as metric,
    COUNT(*)::TEXT as value
FROM public.users
WHERE diamonds > 0

UNION ALL

SELECT 
    'Total Diamonds in System' as metric,
    SUM(diamonds)::TEXT as value
FROM public.users

UNION ALL

SELECT 
    'Total Transactions' as metric,
    COUNT(*)::TEXT as value
FROM public.diamond_transactions

UNION ALL

SELECT 
    'Active Bet Matches' as metric,
    COUNT(*)::TEXT as value
FROM public.chess_games
WHERE is_bet_match = true
AND status IN ('pending', 'active');