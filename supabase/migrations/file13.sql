-- ============================================
-- DIAMOND BETTING SYSTEM MIGRATION
-- Run this in Supabase SQL Editor
-- ============================================

-- Step 1: Add diamonds column to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS diamonds INTEGER NOT NULL DEFAULT 0 CHECK (diamonds >= 0);

-- Create index for faster diamond queries
CREATE INDEX IF NOT EXISTS idx_users_diamonds ON public.users(diamonds);

-- Step 2: Create diamond_transactions table
CREATE TABLE IF NOT EXISTS public.diamond_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'withdrawal', 'bet_deduct', 'bet_win', 'bet_refund')),
    amount INTEGER NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
    payment_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.diamond_transactions ENABLE ROW LEVEL SECURITY;

-- Policies for diamond_transactions
CREATE POLICY "Allow users to read own transactions" ON public.diamond_transactions
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Allow users to create own transactions" ON public.diamond_transactions
    FOR INSERT
    WITH CHECK (auth.uid() = user_id OR true);

CREATE POLICY "Allow users to update own transactions" ON public.diamond_transactions
    FOR UPDATE
    USING (auth.uid() = user_id OR true);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_diamond_transactions_user_id ON public.diamond_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_diamond_transactions_type ON public.diamond_transactions(type);
CREATE INDEX IF NOT EXISTS idx_diamond_transactions_status ON public.diamond_transactions(status);
CREATE INDEX IF NOT EXISTS idx_diamond_transactions_created_at ON public.diamond_transactions(created_at);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.diamond_transactions;

-- Step 3: Add betting columns to chess_games table
ALTER TABLE public.chess_games 
ADD COLUMN IF NOT EXISTS is_bet_match BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.chess_games 
ADD COLUMN IF NOT EXISTS bet_amount INTEGER CHECK (bet_amount IS NULL OR (bet_amount > 0 AND bet_amount <= 1000));

ALTER TABLE public.chess_games 
ADD COLUMN IF NOT EXISTS bet_status TEXT CHECK (bet_status IS NULL OR bet_status IN ('pending', 'locked', 'paid_out'));

-- Create index for bet matches
CREATE INDEX IF NOT EXISTS idx_chess_games_bet_match ON public.chess_games(is_bet_match, bet_status) 
WHERE is_bet_match = true;

-- Step 4: Function to add diamonds (used for purchases and winnings)
CREATE OR REPLACE FUNCTION add_diamonds(
    p_user_id UUID,
    p_amount INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET diamonds = diamonds + p_amount,
        updated_at = now()
    WHERE id = p_user_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION add_diamonds(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION add_diamonds(UUID, INTEGER) TO anon;

-- Step 5: Function to deduct diamonds (used for bets)
CREATE OR REPLACE FUNCTION deduct_diamonds(
    p_user_id UUID,
    p_amount INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_diamonds INTEGER;
BEGIN
    -- Get current diamond balance
    SELECT diamonds INTO current_diamonds
    FROM public.users
    WHERE id = p_user_id;
    
    -- Check if user has enough diamonds
    IF current_diamonds < p_amount THEN
        RAISE EXCEPTION 'Insufficient diamonds. Have: %, Need: %', current_diamonds, p_amount;
    END IF;
    
    -- Deduct diamonds
    UPDATE public.users
    SET diamonds = diamonds - p_amount,
        updated_at = now()
    WHERE id = p_user_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION deduct_diamonds(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION deduct_diamonds(UUID, INTEGER) TO anon;

-- Step 6: Function to process bet payout (called when game ends)
CREATE OR REPLACE FUNCTION process_bet_payout(
    p_game_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game RECORD;
    v_payout_amount INTEGER;
BEGIN
    -- Get game details
    SELECT * INTO v_game
    FROM public.chess_games
    WHERE id = p_game_id;
    
    -- Only process if it's a bet match with a winner and not already paid out
    IF v_game.is_bet_match = true 
       AND v_game.winner_id IS NOT NULL 
       AND v_game.bet_amount IS NOT NULL
       AND (v_game.bet_status IS NULL OR v_game.bet_status != 'paid_out') THEN
        
        -- Calculate payout (winner gets 2x the bet amount)
        v_payout_amount := v_game.bet_amount * 2;
        
        -- Add diamonds to winner
        PERFORM add_diamonds(v_game.winner_id, v_payout_amount);
        
        -- Log transaction
        INSERT INTO public.diamond_transactions (
            user_id,
            type,
            amount,
            description,
            status
        ) VALUES (
            v_game.winner_id,
            'bet_win',
            v_payout_amount,
            'Won chess bet: ' || v_payout_amount || ' diamonds (game: ' || p_game_id || ')',
            'completed'
        );
        
        -- Mark bet as paid out
        UPDATE public.chess_games
        SET bet_status = 'paid_out',
            updated_at = now()
        WHERE id = p_game_id;
        
        RAISE NOTICE 'Payout processed: % diamonds to winner %', v_payout_amount, v_game.winner_id;
    END IF;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION process_bet_payout(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION process_bet_payout(UUID) TO anon;

-- Step 7: Trigger to auto-process bet payouts when game ends
CREATE OR REPLACE FUNCTION auto_process_bet_payout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- When game status changes to checkmate or resigned with a winner
    IF (NEW.status IN ('checkmate', 'resigned') 
        AND NEW.winner_id IS NOT NULL 
        AND OLD.status NOT IN ('checkmate', 'resigned')
        AND NEW.is_bet_match = true
        AND NEW.bet_amount IS NOT NULL
        AND (NEW.bet_status IS NULL OR NEW.bet_status != 'paid_out')) THEN
        
        -- Process the payout
        PERFORM process_bet_payout(NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_process_bet_payout ON public.chess_games;
CREATE TRIGGER trigger_auto_process_bet_payout
    AFTER UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION auto_process_bet_payout();

-- Step 8: Function to handle stalemate refunds
CREATE OR REPLACE FUNCTION refund_bet_on_draw()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- When game ends in stalemate or draw, refund both players
    IF (NEW.status IN ('stalemate', 'draw') 
        AND OLD.status NOT IN ('stalemate', 'draw')
        AND NEW.is_bet_match = true
        AND NEW.bet_amount IS NOT NULL
        AND (NEW.bet_status IS NULL OR NEW.bet_status = 'locked')) THEN
        
        -- Refund white player
        PERFORM add_diamonds(NEW.white_player_id, NEW.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (NEW.white_player_id, 'bet_refund', NEW.bet_amount, 
                'Bet refunded - game ended in ' || NEW.status || ' (game: ' || NEW.id || ')', 
                'completed');
        
        -- Refund black player
        PERFORM add_diamonds(NEW.black_player_id, NEW.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (NEW.black_player_id, 'bet_refund', NEW.bet_amount, 
                'Bet refunded - game ended in ' || NEW.status || ' (game: ' || NEW.id || ')', 
                'completed');
        
        -- Mark as paid out (refunded)
        UPDATE public.chess_games
        SET bet_status = 'paid_out',
            updated_at = now()
        WHERE id = NEW.id;
        
        RAISE NOTICE 'Refunded % diamonds to both players due to %', NEW.bet_amount, NEW.status;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_refund_bet_on_draw ON public.chess_games;
CREATE TRIGGER trigger_refund_bet_on_draw
    AFTER UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION refund_bet_on_draw();

-- Step 9: Function to handle abandoned bet games (refund after 30 min)
CREATE OR REPLACE FUNCTION cleanup_abandoned_bet_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    game_record RECORD;
BEGIN
    -- Find abandoned bet games
    FOR game_record IN 
        SELECT * FROM public.chess_games
        WHERE is_bet_match = true
        AND bet_amount IS NOT NULL
        AND status IN ('pending', 'active')
        AND updated_at < now() - INTERVAL '30 minutes'
        AND (bet_status IS NULL OR bet_status = 'locked')
    LOOP
        -- Refund both players
        PERFORM add_diamonds(game_record.white_player_id, game_record.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (game_record.white_player_id, 'bet_refund', game_record.bet_amount, 
                'Bet refunded - game abandoned (game: ' || game_record.id || ')', 
                'completed');
        
        PERFORM add_diamonds(game_record.black_player_id, game_record.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (game_record.black_player_id, 'bet_refund', game_record.bet_amount, 
                'Bet refunded - game abandoned (game: ' || game_record.id || ')', 
                'completed');
        
        -- Mark game as abandoned and bet as paid out
        UPDATE public.chess_games
        SET status = 'abandoned',
            bet_status = 'paid_out',
            updated_at = now()
        WHERE id = game_record.id;
    END LOOP;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION cleanup_abandoned_bet_games() TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_bet_games() TO service_role;

-- Step 10: Comments for documentation
COMMENT ON COLUMN public.users.diamonds IS 'User diamond balance. 1 diamond = 5 INR. Min withdrawal: 15 diamonds';
COMMENT ON COLUMN public.chess_games.is_bet_match IS 'Whether this is a bet match where diamonds are at stake';
COMMENT ON COLUMN public.chess_games.bet_amount IS 'Amount of diamonds each player bet. Winner gets 2x this amount. Max: 1000';
COMMENT ON COLUMN public.chess_games.bet_status IS 'Status of bet: pending (not started), locked (deducted), paid_out (winner received)';
COMMENT ON TABLE public.diamond_transactions IS 'All diamond transactions including purchases, withdrawals, bets';

-- Step 11: Create a view for user diamond stats (optional but useful)
CREATE OR REPLACE VIEW public.user_diamond_stats AS
SELECT 
    u.id,
    u.display_name,
    u.diamonds as current_balance,
    COALESCE(SUM(CASE WHEN dt.type = 'purchase' THEN dt.amount ELSE 0 END), 0) as total_purchased,
    COALESCE(SUM(CASE WHEN dt.type = 'withdrawal' THEN dt.amount ELSE 0 END), 0) as total_withdrawn,
    COALESCE(SUM(CASE WHEN dt.type = 'bet_win' THEN dt.amount ELSE 0 END), 0) as total_won,
    COALESCE(SUM(CASE WHEN dt.type = 'bet_deduct' THEN ABS(dt.amount) ELSE 0 END), 0) as total_bet,
    COUNT(CASE WHEN dt.type = 'bet_win' THEN 1 END) as games_won,
    COUNT(CASE WHEN dt.type = 'bet_deduct' THEN 1 END) as games_played
FROM public.users u
LEFT JOIN public.diamond_transactions dt ON dt.user_id = u.id AND dt.status = 'completed'
GROUP BY u.id, u.display_name, u.diamonds;

-- Grant access to the view
GRANT SELECT ON public.user_diamond_stats TO authenticated;

-- Step 12: Verify installation
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'DIAMOND BETTING SYSTEM INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Added columns:';
    RAISE NOTICE '  - users.diamonds';
    RAISE NOTICE '  - chess_games.is_bet_match';
    RAISE NOTICE '  - chess_games.bet_amount';
    RAISE NOTICE '  - chess_games.bet_status';
    RAISE NOTICE '';
    RAISE NOTICE 'Created tables:';
    RAISE NOTICE '  - diamond_transactions';
    RAISE NOTICE '';
    RAISE NOTICE 'Created functions:';
    RAISE NOTICE '  - add_diamonds()';
    RAISE NOTICE '  - deduct_diamonds()';
    RAISE NOTICE '  - process_bet_payout()';
    RAISE NOTICE '  - cleanup_abandoned_bet_games()';
    RAISE NOTICE '';
    RAISE NOTICE 'Created triggers:';
    RAISE NOTICE '  - auto_process_bet_payout';
    RAISE NOTICE '  - refund_bet_on_draw';
    RAISE NOTICE '';
    RAISE NOTICE 'System is ready! 💎';
    RAISE NOTICE '========================================';
END $$;

-- Step 13: Test queries (optional - comment these out after testing)
/*
-- Check if columns were added
SELECT 
    column_name, 
    data_type, 
    column_default
FROM information_schema.columns
WHERE table_name = 'users' 
AND column_name = 'diamonds';

SELECT 
    column_name, 
    data_type
FROM information_schema.columns
WHERE table_name = 'chess_games' 
AND column_name IN ('is_bet_match', 'bet_amount', 'bet_status');

-- Check if table was created
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'diamond_transactions'
);

-- Check if functions were created
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name IN ('add_diamonds', 'deduct_diamonds', 'process_bet_payout', 'cleanup_abandoned_bet_games')
AND routine_schema = 'public';
*/