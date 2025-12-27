-- ============================================
-- 🔧 PRODUCTION-READY BET MATCH SYSTEM FIX
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- FIX #1: Add missing chess_room_id column (if not exists)
-- ============================================
ALTER TABLE chess_games 
ADD COLUMN IF NOT EXISTS chess_room_id UUID REFERENCES rooms(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chess_games_chess_room_id 
ON chess_games(chess_room_id);

-- ============================================
-- FIX #2: Atomic Bet Deduction Function
-- Prevents partial failures and race conditions
-- ============================================
DROP FUNCTION IF EXISTS deduct_bet_from_both_players(UUID, UUID, UUID, INTEGER);

CREATE OR REPLACE FUNCTION deduct_bet_from_both_players(
    p_game_id UUID,
    p_player1_id UUID,
    p_player2_id UUID,
    p_bet_amount INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_player1_diamonds INTEGER;
    v_player2_diamonds INTEGER;
    v_error_message TEXT;
BEGIN
    -- Lock both users to prevent race conditions
    PERFORM * FROM users 
    WHERE id IN (p_player1_id, p_player2_id) 
    FOR UPDATE;
    
    -- Check player 1 balance
    SELECT diamonds INTO v_player1_diamonds
    FROM users WHERE id = p_player1_id;
    
    IF v_player1_diamonds IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player 1 not found'
        );
    END IF;
    
    IF v_player1_diamonds < p_bet_amount THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player 1 has insufficient diamonds',
            'player1_diamonds', v_player1_diamonds,
            'required', p_bet_amount
        );
    END IF;
    
    -- Check player 2 balance
    SELECT diamonds INTO v_player2_diamonds
    FROM users WHERE id = p_player2_id;
    
    IF v_player2_diamonds IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player 2 not found'
        );
    END IF;
    
    IF v_player2_diamonds < p_bet_amount THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player 2 has insufficient diamonds',
            'player2_diamonds', v_player2_diamonds,
            'required', p_bet_amount
        );
    END IF;
    
    -- ✅ ATOMIC DEDUCTION: Both or none
    BEGIN
        -- Deduct from player 1
        UPDATE users 
        SET diamonds = diamonds - p_bet_amount, updated_at = NOW()
        WHERE id = p_player1_id;
        
        -- Deduct from player 2
        UPDATE users 
        SET diamonds = diamonds - p_bet_amount, updated_at = NOW()
        WHERE id = p_player2_id;
        
        -- Record transactions
        INSERT INTO diamond_transactions (user_id, type, amount, description, status)
        VALUES 
            (p_player1_id, 'bet_deduct', -p_bet_amount, 
             'Chess bet locked: ' || p_bet_amount || ' diamonds (Game: ' || p_game_id || ')', 
             'completed'),
            (p_player2_id, 'bet_deduct', -p_bet_amount, 
             'Chess bet locked: ' || p_bet_amount || ' diamonds (Game: ' || p_game_id || ')', 
             'completed');
        
        -- Update game bet status
        UPDATE chess_games
        SET bet_status = 'locked', updated_at = NOW()
        WHERE id = p_game_id;
        
        RAISE NOTICE '✅ Bet deducted successfully: % diamonds from both players', p_bet_amount;
        
        RETURN json_build_object(
            'success', true,
            'message', 'Bet locked successfully',
            'player1_new_balance', v_player1_diamonds - p_bet_amount,
            'player2_new_balance', v_player2_diamonds - p_bet_amount
        );
        
    EXCEPTION WHEN OTHERS THEN
        -- Automatic rollback on any error
        v_error_message := SQLERRM;
        RAISE WARNING '❌ Bet deduction failed: %', v_error_message;
        
        RETURN json_build_object(
            'success', false,
            'error', 'Transaction failed: ' || v_error_message
        );
    END;
END;
$$;

GRANT EXECUTE ON FUNCTION deduct_bet_from_both_players(UUID, UUID, UUID, INTEGER) TO authenticated, anon;

-- ============================================
-- FIX #3: Enhanced Bet Payout with Validation
-- ============================================
DROP FUNCTION IF EXISTS process_bet_payout(UUID);

CREATE OR REPLACE FUNCTION process_bet_payout(p_game_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game RECORD;
    v_payout_amount INTEGER;
    v_winner_balance INTEGER;
BEGIN
    -- Get game details with lock
    SELECT * INTO v_game 
    FROM chess_games 
    WHERE id = p_game_id 
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Game not found');
    END IF;
    
    -- Validate bet match
    IF v_game.is_bet_match = false THEN
        RETURN json_build_object('success', false, 'error', 'Not a bet match');
    END IF;
    
    -- Check if already paid out
    IF v_game.bet_status = 'paid_out' THEN
        RETURN json_build_object('success', false, 'error', 'Already paid out');
    END IF;
    
    -- Validate bet was locked
    IF v_game.bet_status != 'locked' THEN
        RETURN json_build_object('success', false, 'error', 'Bet was not locked');
    END IF;
    
    -- Validate winner exists
    IF v_game.winner_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'No winner declared');
    END IF;
    
    -- Validate bet amount
    IF v_game.bet_amount IS NULL OR v_game.bet_amount <= 0 THEN
        RETURN json_build_object('success', false, 'error', 'Invalid bet amount');
    END IF;
    
    -- Calculate payout (winner gets 2x bet)
    v_payout_amount := v_game.bet_amount * 2;
    
    -- Award diamonds to winner
    UPDATE users
    SET diamonds = diamonds + v_payout_amount, updated_at = NOW()
    WHERE id = v_game.winner_id
    RETURNING diamonds INTO v_winner_balance;
    
    -- Record transaction
    INSERT INTO diamond_transactions (user_id, type, amount, description, status)
    VALUES (
        v_game.winner_id, 
        'bet_win', 
        v_payout_amount, 
        'Won chess bet: ' || v_payout_amount || ' diamonds (Game: ' || p_game_id || ')', 
        'completed'
    );
    
    -- Mark as paid out
    UPDATE chess_games
    SET bet_status = 'paid_out', updated_at = NOW()
    WHERE id = p_game_id;
    
    RAISE NOTICE '✅ Paid out % diamonds to winner %', v_payout_amount, v_game.winner_id;
    
    RETURN json_build_object(
        'success', true,
        'winner_id', v_game.winner_id,
        'payout_amount', v_payout_amount,
        'winner_new_balance', v_winner_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION process_bet_payout(UUID) TO authenticated, anon;

-- ============================================
-- FIX #4: Bet Refund Function (for draws/abandons)
-- ============================================
DROP FUNCTION IF EXISTS refund_bet_to_both_players(UUID);

CREATE OR REPLACE FUNCTION refund_bet_to_both_players(p_game_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game RECORD;
BEGIN
    -- Get game details with lock
    SELECT * INTO v_game 
    FROM chess_games 
    WHERE id = p_game_id 
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Game not found');
    END IF;
    
    -- Validate bet match
    IF v_game.is_bet_match = false OR v_game.bet_amount IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Not a bet match');
    END IF;
    
    -- Check if already refunded or paid out
    IF v_game.bet_status = 'paid_out' THEN
        RETURN json_build_object('success', false, 'error', 'Already processed');
    END IF;
    
    -- Validate bet was locked
    IF v_game.bet_status != 'locked' THEN
        RETURN json_build_object('success', false, 'error', 'Bet was not locked');
    END IF;
    
    -- Refund both players
    UPDATE users
    SET diamonds = diamonds + v_game.bet_amount, updated_at = NOW()
    WHERE id IN (v_game.white_player_id, v_game.black_player_id);
    
    -- Record refund transactions
    INSERT INTO diamond_transactions (user_id, type, amount, description, status)
    VALUES 
        (v_game.white_player_id, 'bet_refund', v_game.bet_amount, 
         'Bet refunded - game ended in ' || v_game.status || ' (Game: ' || p_game_id || ')', 
         'completed'),
        (v_game.black_player_id, 'bet_refund', v_game.bet_amount, 
         'Bet refunded - game ended in ' || v_game.status || ' (Game: ' || p_game_id || ')', 
         'completed');
    
    -- Mark as paid out (refunded)
    UPDATE chess_games
    SET bet_status = 'paid_out', updated_at = NOW()
    WHERE id = p_game_id;
    
    RAISE NOTICE '✅ Refunded % diamonds to both players', v_game.bet_amount;
    
    RETURN json_build_object(
        'success', true,
        'refund_amount', v_game.bet_amount,
        'message', 'Bet refunded to both players'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION refund_bet_to_both_players(UUID) TO authenticated, anon;

-- ============================================
-- FIX #5: Updated Auto-Payout Trigger
-- ============================================
DROP TRIGGER IF EXISTS trigger_auto_process_bet_payout ON chess_games;
DROP FUNCTION IF EXISTS auto_process_bet_payout() CASCADE;

CREATE OR REPLACE FUNCTION auto_process_bet_payout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Only process bet matches
    IF NEW.is_bet_match = false OR NEW.bet_amount IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Check if bet is locked and not already paid out
    IF NEW.bet_status != 'locked' OR OLD.bet_status = 'paid_out' THEN
        RETURN NEW;
    END IF;
    
    -- ✅ WINNER DETERMINED (checkmate or resignation)
    IF (NEW.status IN ('checkmate', 'resigned') 
        AND NEW.winner_id IS NOT NULL 
        AND OLD.status NOT IN ('checkmate', 'resigned')) THEN
        
        RAISE NOTICE '🏆 Processing bet payout for winner: %', NEW.winner_id;
        
        SELECT * INTO v_result FROM process_bet_payout(NEW.id);
        
        IF (v_result->>'success')::boolean THEN
            RAISE NOTICE '✅ Bet payout successful';
        ELSE
            RAISE WARNING '❌ Bet payout failed: %', v_result->>'error';
        END IF;
    END IF;
    
    -- ✅ DRAW/STALEMATE (refund both players)
    IF (NEW.status IN ('stalemate', 'draw') 
        AND OLD.status NOT IN ('stalemate', 'draw')) THEN
        
        RAISE NOTICE '🔄 Refunding bet to both players (game ended in %)', NEW.status;
        
        SELECT * INTO v_result FROM refund_bet_to_both_players(NEW.id);
        
        IF (v_result->>'success')::boolean THEN
            RAISE NOTICE '✅ Bet refund successful';
        ELSE
            RAISE WARNING '❌ Bet refund failed: %', v_result->>'error';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_process_bet_payout
    AFTER UPDATE ON chess_games
    FOR EACH ROW
    EXECUTE FUNCTION auto_process_bet_payout();

-- ============================================
-- FIX #6: Cleanup Abandoned Bet Matches
-- ============================================
DROP FUNCTION IF EXISTS cleanup_abandoned_bet_matches();

CREATE OR REPLACE FUNCTION cleanup_abandoned_bet_matches()
RETURNS TABLE(
    games_cleaned INTEGER,
    diamonds_refunded INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_games_cleaned INTEGER := 0;
    v_diamonds_refunded INTEGER := 0;
    v_game RECORD;
    v_result JSON;
BEGIN
    -- Find abandoned bet matches (locked for >30 mins, not finished)
    FOR v_game IN
        SELECT * FROM chess_games
        WHERE is_bet_match = true
          AND bet_status = 'locked'
          AND status NOT IN ('checkmate', 'resigned', 'stalemate', 'draw')
          AND updated_at < NOW() - INTERVAL '30 minutes'
    LOOP
        -- Mark as abandoned
        UPDATE chess_games
        SET status = 'abandoned', updated_at = NOW()
        WHERE id = v_game.id;
        
        -- Refund bets
        SELECT * INTO v_result FROM refund_bet_to_both_players(v_game.id);
        
        IF (v_result->>'success')::boolean THEN
            v_games_cleaned := v_games_cleaned + 1;
            v_diamonds_refunded := v_diamonds_refunded + (v_game.bet_amount * 2);
            RAISE NOTICE '✅ Cleaned abandoned game: %, refunded: % diamonds', 
                v_game.id, v_game.bet_amount * 2;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT v_games_cleaned, v_diamonds_refunded;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_abandoned_bet_matches() TO authenticated, service_role;

-- ============================================
-- FIX #7: Validation View for Debugging
-- ============================================
DROP VIEW IF EXISTS bet_match_status CASCADE;

CREATE OR REPLACE VIEW bet_match_status AS
SELECT 
    cg.id as game_id,
    cg.status as game_status,
    cg.bet_status,
    cg.bet_amount,
    cg.is_bet_match,
    cg.winner_id,
    cg.created_at,
    cg.updated_at,
    
    -- Player 1 info
    u1.display_name as white_player_name,
    u1.diamonds as white_player_diamonds,
    
    -- Player 2 info
    u2.display_name as black_player_name,
    u2.diamonds as black_player_diamonds,
    
    -- Validation checks
    CASE 
        WHEN cg.is_bet_match = false THEN 'Not a bet match'
        WHEN cg.bet_status = 'paid_out' THEN 'Already processed'
        WHEN cg.bet_status = 'locked' AND cg.status IN ('checkmate', 'resigned') THEN 'Ready for payout'
        WHEN cg.bet_status = 'locked' AND cg.status IN ('stalemate', 'draw') THEN 'Ready for refund'
        WHEN cg.bet_status = 'locked' AND cg.updated_at < NOW() - INTERVAL '30 minutes' THEN 'Abandoned - needs refund'
        WHEN cg.bet_status = 'pending' THEN 'Waiting for acceptance'
        ELSE 'In progress'
    END as status_message

FROM chess_games cg
LEFT JOIN users u1 ON u1.id = cg.white_player_id
LEFT JOIN users u2 ON u2.id = cg.black_player_id
WHERE cg.is_bet_match = true
ORDER BY cg.created_at DESC;

GRANT SELECT ON bet_match_status TO authenticated, anon;

-- ============================================
-- VERIFICATION TESTS
-- ============================================
DO $$
DECLARE
    test_game_id UUID;
    test_player1 UUID := gen_random_uuid();
    test_player2 UUID := gen_random_uuid();
    deduct_result JSON;
    payout_result JSON;
    refund_result JSON;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING BET MATCH SYSTEM';
    RAISE NOTICE '========================================';
    
    -- Create test users with 1000 diamonds each
    INSERT INTO users (id, email, display_name, diamonds, gender) VALUES
        (test_player1, 'testbet1@test.com', 'Test Player 1', 1000, 'male'),
        (test_player2, 'testbet2@test.com', 'Test Player 2', 1000, 'female');
    
    -- Create test game
    INSERT INTO chess_games (white_player_id, black_player_id, is_bet_match, bet_amount, bet_status, status)
    VALUES (test_player1, test_player2, true, 100, 'pending', 'pending')
    RETURNING id INTO test_game_id;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ Test game created: %', test_game_id;
    
    -- TEST 1: Atomic bet deduction
    RAISE NOTICE '';
    RAISE NOTICE '📊 TEST 1: Atomic bet deduction';
    SELECT * INTO deduct_result FROM deduct_bet_from_both_players(
        test_game_id, test_player1, test_player2, 100
    );
    
    IF (deduct_result->>'success')::boolean THEN
        RAISE NOTICE '  ✅ PASSED: Bet deducted successfully';
        RAISE NOTICE '    Player 1 balance: %', deduct_result->>'player1_new_balance';
        RAISE NOTICE '    Player 2 balance: %', deduct_result->>'player2_new_balance';
    ELSE
        RAISE NOTICE '  ❌ FAILED: %', deduct_result->>'error';
    END IF;
    
    -- TEST 2: Payout on win
    RAISE NOTICE '';
    RAISE NOTICE '📊 TEST 2: Bet payout';
    UPDATE chess_games 
    SET status = 'checkmate', winner_id = test_player1
    WHERE id = test_game_id;
    
    SELECT * INTO payout_result FROM process_bet_payout(test_game_id);
    
    IF (payout_result->>'success')::boolean THEN
        RAISE NOTICE '  ✅ PASSED: Payout successful';
        RAISE NOTICE '    Winner balance: %', payout_result->>'winner_new_balance';
        RAISE NOTICE '    Payout amount: %', payout_result->>'payout_amount';
    ELSE
        RAISE NOTICE '  ❌ FAILED: %', payout_result->>'error';
    END IF;
    
    -- TEST 3: Refund on draw
    INSERT INTO chess_games (white_player_id, black_player_id, is_bet_match, bet_amount, bet_status, status)
    VALUES (test_player1, test_player2, true, 50, 'locked', 'active')
    RETURNING id INTO test_game_id;
    
    RAISE NOTICE '';
    RAISE NOTICE '📊 TEST 3: Bet refund on draw';
    UPDATE chess_games 
    SET status = 'stalemate'
    WHERE id = test_game_id;
    
    SELECT * INTO refund_result FROM refund_bet_to_both_players(test_game_id);
    
    IF (refund_result->>'success')::boolean THEN
        RAISE NOTICE '  ✅ PASSED: Refund successful';
        RAISE NOTICE '    Refund amount: %', refund_result->>'refund_amount';
    ELSE
        RAISE NOTICE '  ❌ FAILED: %', refund_result->>'error';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'testbet%@test.com';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL TESTS COMPLETED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📋 New Functions:';
    RAISE NOTICE '  • deduct_bet_from_both_players() - Atomic bet locking';
    RAISE NOTICE '  • process_bet_payout() - Secure winner payout';
    RAISE NOTICE '  • refund_bet_to_both_players() - Draw/abandon refunds';
    RAISE NOTICE '  • cleanup_abandoned_bet_matches() - Auto-cleanup';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Monitoring View:';
    RAISE NOTICE '  • bet_match_status - View all bet match statuses';
    RAISE NOTICE '';
    RAISE NOTICE '🔒 Security Features:';
    RAISE NOTICE '  ✓ Atomic transactions (all or nothing)';
    RAISE NOTICE '  ✓ Row-level locking (no race conditions)';
    RAISE NOTICE '  ✓ Balance validation before deduction';
    RAISE NOTICE '  ✓ Duplicate payout prevention';
    RAISE NOTICE '  ✓ Complete transaction logging';
    RAISE NOTICE '========================================';
END $$;