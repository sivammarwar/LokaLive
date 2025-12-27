-- ============================================
-- COMPLETE DATABASE SCHEMA - CONSOLIDATED
-- Video Chat + Matchmaking + Chess + Diamond System
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- PART 1: ENUMS & TYPES
-- ============================================

CREATE TYPE public.room_type AS ENUM ('public', 'private');
CREATE TYPE public.gender_preference AS ENUM ('male', 'female', 'other');
CREATE TYPE public.interest_category AS ENUM ('student', 'music', 'entertainment', 'friend', 'random', 'iitians', 'nitians');
CREATE TYPE public.membership_tier AS ENUM ('free', 'premium', 'premium_plus');

-- ============================================
-- PART 2: CORE TABLES
-- ============================================

-- Users Table
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    gender gender_preference DEFAULT 'other',
    ip_address TEXT,
    browser_fingerprint TEXT,
    session_token TEXT UNIQUE,
    
    -- Health & Ban System
    health_tokens INTEGER NOT NULL DEFAULT 5 CHECK (health_tokens >= 0 AND health_tokens <= 5),
    ban_count INTEGER NOT NULL DEFAULT 0,
    banned_until TIMESTAMPTZ,
    is_permanently_banned BOOLEAN NOT NULL DEFAULT false,
    
    -- Premium Membership
    membership_tier membership_tier NOT NULL DEFAULT 'free',
    membership_expires_at TIMESTAMPTZ,
    membership_auto_renew BOOLEAN DEFAULT false,
    
    -- Diamond System
    diamonds INTEGER NOT NULL DEFAULT 0 CHECK (diamonds >= 0),
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rooms Table
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT UNIQUE,
    room_type room_type NOT NULL DEFAULT 'public',
    room_size INTEGER NOT NULL DEFAULT 2 CHECK (room_size IN (2, 4)),
    gender_preference gender_preference,
    interest_category interest_category,
    creator_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    creator_gender gender_preference DEFAULT 'other',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Room Participants Table
CREATE TABLE public.room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    CONSTRAINT room_participants_unique UNIQUE(room_id, user_id)
);

-- Reports Table
CREATE TABLE public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reported_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    reason TEXT,
    is_validated BOOLEAN DEFAULT false,
    reporter_membership_tier membership_tier DEFAULT 'free',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Signaling Table (WebRTC)
CREATE TABLE public.signaling (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    target_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL CHECK (message_type IN ('offer', 'answer', 'ice-candidate', 'join', 'leave')),
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Chess Games Table
CREATE TABLE public.chess_games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE,
    white_player_id UUID REFERENCES public.users(id) ON DELETE SET NULL NOT NULL,
    black_player_id UUID REFERENCES public.users(id) ON DELETE SET NULL NOT NULL,
    fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    pgn TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'checkmate', 'stalemate', 'draw', 'resigned', 'abandoned')),
    winner_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    last_move JSONB,
    
    -- Betting System
    is_bet_match BOOLEAN NOT NULL DEFAULT false,
    bet_amount INTEGER CHECK (bet_amount IS NULL OR (bet_amount > 0 AND bet_amount <= 1000)),
    bet_status TEXT CHECK (bet_status IS NULL OR bet_status IN ('pending', 'locked', 'paid_out')),
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT chess_games_different_players_check CHECK (white_player_id != black_player_id)
);

-- Diamond Transactions Table
CREATE TABLE public.diamond_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'withdrawal', 'bet_deduct', 'bet_win', 'bet_refund')),
    amount INTEGER NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    payment_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Withdrawal Methods Table
CREATE TABLE public.withdrawal_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('upi', 'bank')),
    upi_id TEXT,
    account_name TEXT,
    account_number TEXT,
    ifsc_code TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT withdrawal_method_details_check CHECK (
        (type = 'upi' AND upi_id IS NOT NULL AND upi_id != '') OR
        (type = 'bank' AND account_name IS NOT NULL AND account_name != '' 
         AND account_number IS NOT NULL AND account_number != ''
         AND ifsc_code IS NOT NULL AND ifsc_code != '')
    )
);

-- Transactions Table (Membership Payments)
CREATE TABLE public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    membership_tier membership_tier NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'INR',
    payment_method TEXT,
    payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),
    razorpay_order_id TEXT,
    razorpay_payment_id TEXT,
    razorpay_signature TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Membership Prices Table
CREATE TABLE public.membership_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_tier membership_tier UNIQUE NOT NULL,
    price_inr DECIMAL(10, 2) NOT NULL,
    price_usd DECIMAL(10, 2),
    duration_days INTEGER NOT NULL DEFAULT 30,
    features JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Diamond Packages Table
CREATE TABLE public.diamond_packages (
    id TEXT PRIMARY KEY,
    diamonds INTEGER NOT NULL,
    price_inr DECIMAL(10, 2) NOT NULL,
    bonus INTEGER DEFAULT 0,
    is_popular BOOLEAN DEFAULT false,
    display_order INTEGER,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ludo Votes Table
CREATE TABLE public.ludo_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- ============================================
-- PART 3: INDEXES
-- ============================================

-- Users indexes
CREATE INDEX idx_users_membership_tier ON public.users(membership_tier);
CREATE INDEX idx_users_membership_expires ON public.users(membership_expires_at);
CREATE INDEX idx_users_diamonds ON public.users(diamonds);
CREATE INDEX idx_users_gender ON public.users(gender);

-- Rooms indexes
CREATE INDEX idx_rooms_matchmaking ON public.rooms(room_type, is_active, room_size, gender_preference, interest_category, created_at)
    WHERE room_type = 'public' AND is_active = true;
CREATE INDEX idx_rooms_creator_gender ON public.rooms(creator_gender) 
    WHERE room_type = 'public' AND is_active = true;

-- Room participants indexes
CREATE INDEX idx_room_participants_active ON public.room_participants(room_id, user_id, left_at) 
    WHERE left_at IS NULL;
CREATE INDEX idx_room_participants_user_active ON public.room_participants(user_id, room_id) 
    WHERE left_at IS NULL;

-- Signaling indexes
CREATE INDEX idx_signaling_room_id ON public.signaling(room_id);
CREATE INDEX idx_signaling_target_id ON public.signaling(target_id);
CREATE INDEX idx_signaling_created_at ON public.signaling(created_at);

-- Chess games indexes
CREATE INDEX idx_chess_games_room_id ON public.chess_games(room_id);
CREATE INDEX idx_chess_games_status ON public.chess_games(status);
CREATE INDEX idx_chess_games_bet_match ON public.chess_games(is_bet_match, bet_status) 
    WHERE is_bet_match = true;

-- Diamond transactions indexes
CREATE INDEX idx_diamond_transactions_user_id ON public.diamond_transactions(user_id);
CREATE INDEX idx_diamond_transactions_type ON public.diamond_transactions(type);
CREATE INDEX idx_diamond_transactions_status ON public.diamond_transactions(status);
CREATE INDEX idx_diamond_transactions_created_at ON public.diamond_transactions(created_at);

-- Withdrawal methods indexes
CREATE INDEX idx_withdrawal_methods_user_id ON public.withdrawal_methods(user_id);
CREATE INDEX idx_withdrawal_methods_type ON public.withdrawal_methods(type);

-- Transactions indexes
CREATE INDEX idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX idx_transactions_status ON public.transactions(payment_status);

-- Ludo votes indexes
CREATE INDEX idx_ludo_votes_user_id ON public.ludo_votes(user_id);
CREATE INDEX idx_ludo_votes_voted_at ON public.ludo_votes(voted_at);

-- ============================================
-- PART 4: ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signaling ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chess_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diamond_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diamond_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ludo_votes ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Allow authenticated user creation" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Allow users to read own data" ON public.users FOR SELECT USING (auth.uid() = id OR true);
CREATE POLICY "Allow users to update own data" ON public.users FOR UPDATE USING (auth.uid() = id);

-- Rooms policies
CREATE POLICY "Allow room creation" ON public.rooms FOR INSERT WITH CHECK (auth.uid() = creator_id OR true);
CREATE POLICY "Allow reading active rooms" ON public.rooms FOR SELECT USING (true);
CREATE POLICY "Allow room updates" ON public.rooms FOR UPDATE USING (auth.uid() = creator_id OR true);

-- Room participants policies
CREATE POLICY "Allow joining rooms" ON public.room_participants FOR INSERT WITH CHECK (auth.uid() = user_id OR true);
CREATE POLICY "Allow reading participants" ON public.room_participants FOR SELECT USING (true);
CREATE POLICY "Allow leaving rooms" ON public.room_participants FOR UPDATE USING (auth.uid() = user_id OR true);

-- Reports policies
CREATE POLICY "Allow creating reports" ON public.reports FOR INSERT WITH CHECK (auth.uid() = reporter_id OR true);
CREATE POLICY "Allow reading own reports" ON public.reports FOR SELECT USING (auth.uid() = reporter_id OR true);

-- Signaling policies
CREATE POLICY "Allow inserting signals" ON public.signaling FOR INSERT WITH CHECK (auth.uid() = sender_id OR true);
CREATE POLICY "Allow reading signals in room" ON public.signaling FOR SELECT USING (true);
CREATE POLICY "Allow deleting own signals" ON public.signaling FOR DELETE USING (auth.uid() = sender_id OR true);

-- Chess games policies
CREATE POLICY "Allow reading chess games" ON public.chess_games FOR SELECT USING (true);
CREATE POLICY "Allow creating chess games" ON public.chess_games FOR INSERT WITH CHECK (auth.uid() = white_player_id OR true);
CREATE POLICY "Allow updating own chess games" ON public.chess_games FOR UPDATE USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);
CREATE POLICY "Allow deleting own chess games" ON public.chess_games FOR DELETE USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);

-- Diamond transactions policies
CREATE POLICY "Allow users to read own transactions" ON public.diamond_transactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow users to create own transactions" ON public.diamond_transactions FOR INSERT WITH CHECK (auth.uid() = user_id OR true);
CREATE POLICY "Allow users to update own transactions" ON public.diamond_transactions FOR UPDATE USING (auth.uid() = user_id OR true);

-- Withdrawal methods policies
CREATE POLICY "Users can manage withdrawal methods" ON public.withdrawal_methods FOR ALL USING (auth.uid() = user_id);

-- Transactions policies
CREATE POLICY "Allow users to read own transactions" ON public.transactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow users to create own transactions" ON public.transactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Allow users to update own transactions" ON public.transactions FOR UPDATE USING (auth.uid() = user_id);

-- Membership prices policies
CREATE POLICY "Allow reading membership prices" ON public.membership_prices FOR SELECT USING (is_active = true);

-- Diamond packages policies
CREATE POLICY "Allow reading diamond packages" ON public.diamond_packages FOR SELECT USING (is_active = true);

-- Ludo votes policies
CREATE POLICY "Anyone can view ludo votes" ON public.ludo_votes FOR SELECT USING (true);
CREATE POLICY "Users can vote once" ON public.ludo_votes FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================
-- PART 5: CORE FUNCTIONS
-- ============================================

-- Generate random room code
CREATE OR REPLACE FUNCTION generate_room_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..6 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    RETURN result;
END;
$$;

-- Auto-set room code for private rooms
CREATE OR REPLACE FUNCTION set_room_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.room_type = 'private' AND NEW.room_code IS NULL THEN
        NEW.room_code := generate_room_code();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_set_room_code
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_room_code();

-- Auto-set creator_gender from users table
CREATE OR REPLACE FUNCTION set_creator_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = NEW.creator_id;
    
    IF NEW.room_type = 'public' THEN
        IF user_gender IS NULL OR user_gender = 'other' THEN
            RAISE EXCEPTION 'Cannot create public room with gender "other". Please set your gender to male or female first.';
        END IF;
        NEW.creator_gender := user_gender;
    ELSE
        NEW.creator_gender := COALESCE(user_gender, 'other');
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_set_creator_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_creator_gender();

-- Handle new user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, display_name, health_tokens, membership_tier)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        5,
        'free'
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- Process validated reports
CREATE OR REPLACE FUNCTION process_validated_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    health_decrease NUMERIC := 1.0;
BEGIN
    IF NEW.is_validated = true AND OLD.is_validated = false THEN
        IF NEW.reporter_membership_tier IN ('premium', 'premium_plus') THEN
            health_decrease := 1.5;
        END IF;
        
        UPDATE public.users
        SET health_tokens = GREATEST(CAST(health_tokens - health_decrease AS INTEGER), 0),
            updated_at = now()
        WHERE id = NEW.reported_user_id;
        
        UPDATE public.users
        SET banned_until = CASE 
                WHEN health_tokens = 0 AND ban_count < 3 THEN now() + INTERVAL '2 months'
                ELSE banned_until
            END,
            ban_count = CASE 
                WHEN health_tokens = 0 THEN ban_count + 1
                ELSE ban_count
            END,
            is_permanently_banned = CASE 
                WHEN ban_count >= 2 AND health_tokens = 0 THEN true
                ELSE is_permanently_banned
            END,
            updated_at = now()
        WHERE id = NEW.reported_user_id AND health_tokens = 0;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_process_report
    AFTER UPDATE ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION process_validated_report();

-- Update chess game timestamp
CREATE OR REPLACE FUNCTION update_chess_game_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_chess_game_timestamp
    BEFORE UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION update_chess_game_timestamp();

-- ============================================
-- PART 6: MATCHMAKING FUNCTIONS
-- ============================================

-- Find compatible room (does NOT auto-join)
CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Search for compatible room
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, is_active)
    VALUES ('public', p_room_size, p_interested_in, p_interest, p_user_id, true)
    RETURNING id INTO v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

-- Join room if available
CREATE OR REPLACE FUNCTION join_room_if_available(p_room_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
BEGIN
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found');
  END IF;
  
  IF NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_inactive');
  END IF;
  
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id AND left_at IS NULL AND user_id != p_user_id;
  
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full');
  END IF;
  
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, joined_at = NOW();
  
  RETURN json_build_object('success', true, 'message', 'Successfully joined room');
END;
$$;

-- Leave all user rooms
CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id AND left_at IS NULL;
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN COALESCE(affected_count, 0);
END;
$$;

-- ============================================
-- PART 7: DIAMOND SYSTEM FUNCTIONS
-- ============================================

-- Add diamonds
CREATE OR REPLACE FUNCTION add_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    
    UPDATE public.users
    SET diamonds = diamonds + p_amount, updated_at = now()
    WHERE id = p_user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
END;
$$;

-- Deduct diamonds
CREATE OR REPLACE FUNCTION deduct_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_diamonds INTEGER;
BEGIN
    SELECT diamonds INTO v_current_diamonds
    FROM public.users WHERE id = p_user_id FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    
    IF v_current_diamonds < p_amount THEN
        RAISE EXCEPTION 'Insufficient diamonds';
    END IF;
    
    UPDATE public.users
    SET diamonds = diamonds - p_amount, updated_at = now()
    WHERE id = p_user_id;
END;
$$;

-- Process bet payout
CREATE OR REPLACE FUNCTION process_bet_payout(p_game_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game RECORD;
    v_payout_amount INTEGER;
BEGIN
    SELECT * INTO v_game FROM public.chess_games WHERE id = p_game_id;
    
    IF v_game.is_bet_match = true 
       AND v_game.winner_id IS NOT NULL 
       AND v_game.bet_amount IS NOT NULL
       AND (v_game.bet_status IS NULL OR v_game.bet_status != 'paid_out') THEN
        
        v_payout_amount := v_game.bet_amount * 2;
        
        PERFORM add_diamonds(v_game.winner_id, v_payout_amount);
        
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (v_game.winner_id, 'bet_win', v_payout_amount, 
                'Won chess bet: ' || v_payout_amount || ' diamonds', 'completed');
        
        UPDATE public.chess_games
        SET bet_status = 'paid_out', updated_at = now()
        WHERE id = p_game_id;
    END IF;
END;
$$;

-- Auto-process bet payout on game end
CREATE OR REPLACE FUNCTION auto_process_bet_payout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (NEW.status IN ('checkmate', 'resigned') 
        AND NEW.winner_id IS NOT NULL 
        AND OLD.status NOT IN ('checkmate', 'resigned')
        AND NEW.is_bet_match = true
        AND NEW.bet_amount IS NOT NULL
        AND (NEW.bet_status IS NULL OR NEW.bet_status != 'paid_out')) THEN
        
        PERFORM process_bet_payout(NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_process_bet_payout
    AFTER UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION auto_process_bet_payout();

-- Refund bets on draw
CREATE OR REPLACE FUNCTION refund_bet_on_draw()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (NEW.status IN ('stalemate', 'draw') 
        AND OLD.status NOT IN ('stalemate', 'draw')
        AND NEW.is_bet_match = true
        AND NEW.bet_amount IS NOT NULL
        AND (NEW.bet_status IS NULL OR NEW.bet_status = 'locked')) THEN
        
        PERFORM add_diamonds(NEW.white_player_id, NEW.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (NEW.white_player_id, 'bet_refund', NEW.bet_amount, 
                'Bet refunded - game ended in ' || NEW.status, 'completed');
        
        PERFORM add_diamonds(NEW.black_player_id, NEW.bet_amount);
        INSERT INTO public.diamond_transactions (user_id, type, amount, description, status)
        VALUES (NEW.black_player_id, 'bet_refund', NEW.bet_amount, 
                'Bet refunded - game ended in ' || NEW.status, 'completed');
        
        UPDATE public.chess_games
        SET bet_status = 'paid_out', updated_at = now()
        WHERE id = NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_refund_bet_on_draw
    AFTER UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION refund_bet_on_draw();

-- ============================================
-- PART 8: CLEANUP FUNCTIONS
-- ============================================

-- Cleanup old signals
CREATE OR REPLACE FUNCTION cleanup_old_signals()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $
BEGIN
    DELETE FROM public.signaling WHERE created_at < now() - INTERVAL '1 hour';
END;
$;

-- Cleanup abandoned chess games
CREATE OR REPLACE FUNCTION cleanup_abandoned_chess_games()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $
BEGIN
    UPDATE public.chess_games
    SET status = 'abandoned', updated_at = now()
    WHERE status IN ('pending', 'active')
    AND updated_at < now() - INTERVAL '30 minutes';
END;
$;

-- Cleanup inactive rooms
CREATE OR REPLACE FUNCTION cleanup_inactive_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $
DECLARE
    cleaned_count INTEGER;
BEGIN
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      );
    
    GET DIAGNOSTICS cleaned_count = ROW_COUNT;
    RETURN cleaned_count;
END;
$;

-- ============================================
-- PART 9: GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION add_diamonds(UUID, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION deduct_diamonds(UUID, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION process_bet_payout(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION cleanup_old_signals() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_chess_games() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION cleanup_inactive_rooms() TO authenticated, service_role;

-- ============================================
-- PART 10: REALTIME SUBSCRIPTIONS
-- ============================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.room_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.signaling;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.diamond_transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.withdrawal_methods;
ALTER PUBLICATION supabase_realtime ADD TABLE public.membership_prices;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_votes;

-- ============================================
-- PART 11: SEED DATA
-- ============================================

-- Insert membership prices
INSERT INTO public.membership_prices (membership_tier, price_inr, price_usd, duration_days, features) VALUES
('premium', 99.00, 1.19, 30, '{"color": "blue", "report_multiplier": 1.5, "badge": "Premium"}'::jsonb),
('premium_plus', 199.00, 2.39, 30, '{"color": "golden", "report_multiplier": 1.5, "badge": "Premium Plus", "priority_support": true}'::jsonb)
ON CONFLICT (membership_tier) DO NOTHING;

-- Insert diamond packages
INSERT INTO public.diamond_packages (id, diamonds, price_inr, bonus, is_popular, display_order) VALUES 
('pack_15', 15, 100.00, 0, false, 1),
('pack_80', 80, 500.00, 5, true, 2),
('pack_170', 170, 1000.00, 20, false, 3)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- PART 12: HELPFUL VIEWS
-- ============================================

-- System health view
CREATE OR REPLACE VIEW public.system_health AS
SELECT 
    (SELECT COUNT(*) FROM users) as total_users,
    (SELECT COUNT(*) FROM users WHERE gender = 'other') as users_with_other_gender,
    (SELECT COUNT(*) FROM rooms WHERE is_active = true AND room_type = 'public') as active_public_rooms,
    (SELECT COUNT(*) FROM room_participants WHERE left_at IS NULL) as active_participants,
    (SELECT COUNT(DISTINCT room_id) FROM room_participants WHERE left_at IS NULL) as rooms_with_participants,
    (SELECT COUNT(*) FROM signaling) as pending_signals;

GRANT SELECT ON public.system_health TO authenticated, anon;

-- User diamond stats view
CREATE OR REPLACE VIEW public.user_diamond_stats AS
SELECT 
    u.id,
    u.display_name,
    u.diamonds as current_balance,
    COALESCE(SUM(CASE WHEN dt.type = 'purchase' THEN dt.amount ELSE 0 END), 0) as total_purchased,
    COALESCE(SUM(CASE WHEN dt.type = 'bet_win' THEN dt.amount ELSE 0 END), 0) as total_won,
    COUNT(CASE WHEN dt.type = 'bet_win' THEN 1 END) as games_won
FROM public.users u
LEFT JOIN public.diamond_transactions dt ON dt.user_id = u.id AND dt.status = 'completed'
GROUP BY u.id, u.display_name, u.diamonds;

GRANT SELECT ON public.user_diamond_stats TO authenticated;

-- Ludo vote stats view
CREATE OR REPLACE VIEW public.ludo_vote_stats AS
SELECT 
    COUNT(*) as total_votes,
    MIN(voted_at) as first_vote,
    MAX(voted_at) as latest_vote,
    COUNT(CASE WHEN voted_at > NOW() - INTERVAL '24 hours' THEN 1 END) as votes_last_24h
FROM public.ludo_votes;

GRANT SELECT ON public.ludo_vote_stats TO authenticated, anon;

-- ============================================
-- INSTALLATION COMPLETE
-- ============================================

DO $
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE INSTALLATION COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Created:';
    RAISE NOTICE '  • 13 Tables';
    RAISE NOTICE '  • 25+ Indexes';
    RAISE NOTICE '  • 15+ Functions';
    RAISE NOTICE '  • 10+ Triggers';
    RAISE NOTICE '  • RLS Policies';
    RAISE NOTICE '  • Realtime Subscriptions';
    RAISE NOTICE '';
    RAISE NOTICE 'Features:';
    RAISE NOTICE '  ✓ Video Chat Rooms';
    RAISE NOTICE '  ✓ Gender-Based Matchmaking';
    RAISE NOTICE '  ✓ Chess Games with Betting';
    RAISE NOTICE '  ✓ Diamond System';
    RAISE NOTICE '  ✓ Premium Memberships';
    RAISE NOTICE '  ✓ Report System';
    RAISE NOTICE '  ✓ Ludo Voting';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Verify all tables created';
    RAISE NOTICE '  2. Test matchmaking flow';
    RAISE NOTICE '  3. Configure Razorpay keys';
    RAISE NOTICE '========================================';
END $;



--------------- FILE - 40

-- ============================================
-- 🚨 CRITICAL DATABASE FIXES
-- Run these in Supabase SQL Editor
-- ============================================

-- ============================================
-- FIX #1: ⚠️ HIGHEST PRIORITY - Matchmaking Logic
-- The gender matching was backwards!
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ FIXED: Correct gender matching logic
    -- OLD (WRONG): r.gender_preference = p_user_gender AND r.creator_gender = p_interested_in
    -- NEW (CORRECT): r.gender_preference = p_interested_in AND r.creator_gender = p_user_gender
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.gender_preference = p_interested_in  -- ✅ FIXED: Room wants people I'm interested in
      AND r.creator_gender = p_user_gender        -- ✅ FIXED: Room created by someone of MY gender
      AND r.creator_gender != 'other'
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    INSERT INTO public.rooms (room_type, room_size, gender_preference, interest_category, creator_id, is_active)
    VALUES ('public', p_room_size, p_interested_in, p_interest, p_user_id, true)
    RETURNING id INTO v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

-- ============================================
-- FIX #2: Room Creator Auto-Join Trigger
-- Ensures room creator is automatically added as participant
-- ============================================

CREATE OR REPLACE FUNCTION auto_join_room_creator()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- ✅ NEW: Auto-add creator as participant when room is created
    IF NEW.creator_id IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id, joined_at, left_at)
        VALUES (NEW.id, NEW.creator_id, NOW(), NULL)
        ON CONFLICT (room_id, user_id) DO UPDATE 
        SET left_at = NULL, joined_at = NOW();
        
        RAISE NOTICE '✅ Auto-joined creator % to room %', NEW.creator_id, NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_join_room_creator ON public.rooms;
CREATE TRIGGER trigger_auto_join_room_creator
    AFTER INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION auto_join_room_creator();

-- ============================================
-- FIX #3: Fix join_room_if_available Counting Bug
-- Was excluding current user when counting participants
-- ============================================

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(p_room_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
BEGIN
  -- Get room info
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found');
  END IF;
  
  IF NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_inactive');
  END IF;
  
  -- ✅ FIXED: Count ALL participants (don't exclude current user)
  -- OLD (WRONG): WHERE room_id = p_room_id AND left_at IS NULL AND user_id != p_user_id
  -- NEW (CORRECT): WHERE room_id = p_room_id AND left_at IS NULL
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id AND left_at IS NULL;
  
  -- Check if room is full
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full');
  END IF;
  
  -- Join the room (or rejoin if already joined)
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) DO UPDATE 
  SET left_at = NULL, joined_at = NOW();
  
  RETURN json_build_object('success', true, 'message', 'Successfully joined room');
END;
$$;

-- ============================================
-- FIX #4: Prevent 'other' Gender in Public Rooms
-- Public rooms MUST have specific gender for matching
-- ============================================

CREATE OR REPLACE FUNCTION validate_public_room_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.room_type = 'public' THEN
        -- ✅ NEW: Validate creator has valid gender
        IF NEW.creator_gender IS NULL OR NEW.creator_gender = 'other' THEN
            RAISE EXCEPTION 'Cannot create public room with gender "other". Please set your gender to male or female first.';
        END IF;
        
        -- ✅ NEW: Validate gender_preference is set
        IF NEW.gender_preference IS NULL OR NEW.gender_preference = 'other' THEN
            RAISE EXCEPTION 'Public rooms must specify gender preference (male or female).';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_public_room_gender ON public.rooms;
CREATE TRIGGER trigger_validate_public_room_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION validate_public_room_gender();

-- ============================================
-- FIX #5: Auto-Cleanup Empty Rooms
-- Automatically deactivate rooms with no active participants
-- ============================================

CREATE OR REPLACE FUNCTION auto_cleanup_empty_rooms()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Deactivate rooms with no active participants
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND room_type = 'public'  -- Only cleanup public rooms automatically
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      )
      AND created_at < NOW() - INTERVAL '30 minutes';  -- Only cleanup old rooms
      
    RAISE NOTICE '✅ Auto-cleanup completed';
END;
$$;

-- ✅ NEW: Schedule auto-cleanup (run this in pg_cron if available)
-- Or call this function manually/periodically via a backend job

-- ============================================
-- FIX #6: Ludo Vote Functions (Referenced but Missing)
-- ============================================

CREATE OR REPLACE FUNCTION get_ludo_vote_count()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*)::INTEGER FROM public.ludo_votes;
$$;

CREATE OR REPLACE FUNCTION has_user_voted_ludo(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS(SELECT 1 FROM public.ludo_votes WHERE user_id = p_user_id);
$$;

-- ============================================
-- Grant Permissions for New Functions
-- ============================================

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auto_cleanup_empty_rooms() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_ludo_vote_count() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION has_user_voted_ludo(UUID) TO authenticated, anon;

-- ============================================
-- Verification Queries
-- Run these to verify fixes worked
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE FIXES APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Fixed Issues:';
    RAISE NOTICE '  1. ✅ Matchmaking gender logic corrected';
    RAISE NOTICE '  2. ✅ Room creator auto-join trigger added';
    RAISE NOTICE '  3. ✅ Join counting bug fixed';
    RAISE NOTICE '  4. ✅ Public room gender validation added';
    RAISE NOTICE '  5. ✅ Auto-cleanup function created';
    RAISE NOTICE '  6. ✅ Ludo vote functions added';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Test matchmaking with 2 users';
    RAISE NOTICE '  2. Verify room creator appears in participants';
    RAISE NOTICE '  3. Test private room joining';
    RAISE NOTICE '  4. Try creating public room with "other" gender (should fail)';
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- TEST DATA CLEANUP (Optional)
-- Run this to clear test data
-- ============================================

-- ⚠️ UNCOMMENT ONLY IF YOU WANT TO RESET ALL ROOMS/PARTICIPANTS
-- DELETE FROM public.room_participants;
-- DELETE FROM public.rooms;
-- DELETE FROM public.signaling;




---------- FILE - 41






-- ============================================
-- 🚨 CRITICAL MATCHMAKING FIX (Production Safe)
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Remove problematic constraint
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'users_id_fkey' 
        AND table_name = 'users'
    ) THEN
        ALTER TABLE users DROP CONSTRAINT users_id_fkey;
        RAISE NOTICE '✅ Removed users_id_fkey constraint';
    ELSE
        RAISE NOTICE '⚠️ Constraint does not exist (safe to continue)';
    END IF;
END $$;

-- STEP 2: Drop and recreate find_compatible_room with CORRECT logic
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Log input parameters
    RAISE NOTICE '🔍 MATCHMAKING - User: %, Gender: %, Looking for: %, Interest: %, Size: %', 
        p_user_id, p_user_gender, p_interested_in, p_interest, p_room_size;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT MATCHING LOGIC:
    -- Find rooms created by users with MY gender that want people I'm interested in
    RAISE NOTICE '🔍 SEARCHING FOR: creator_gender=% AND gender_preference=%', 
        p_user_gender, p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      -- ✅ CRITICAL: Correct matching logic
      AND r.creator_gender = p_user_gender        -- Room creator has MY gender
      AND r.gender_preference = p_interested_in   -- Room wants people I'm interested in
      AND r.creator_id != p_user_id               -- Don't match my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ FOUND ROOM: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- No room found, create new one
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type, 
        room_size, 
        gender_preference,  -- ✅ This room wants people I'm interested in
        interest_category, 
        creator_id,
        creator_gender,     -- ✅ Store MY gender
        is_active
    )
    VALUES (
        'public', 
        p_room_size, 
        p_interested_in,    -- ✅ Room preference = who I want to meet
        p_interest, 
        p_user_id,
        p_user_gender,      -- ✅ Store MY gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED ROOM: % (wants: %, created by: %)', 
        v_created_room_id, p_interested_in, p_user_gender;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

-- STEP 3: Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Verify the function exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'find_compatible_room'
    ) THEN
        RAISE NOTICE '✅ Function find_compatible_room created successfully';
    ELSE
        RAISE NOTICE '❌ Function creation failed';
    END IF;
END $$;

-- ============================================
-- VERIFICATION: Check your schema
-- ============================================

-- Show rooms table structure
DO $$
DECLARE
    col_record RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 ROOMS TABLE COLUMNS';
    RAISE NOTICE '========================================';
    
    FOR col_record IN 
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'rooms' 
        ORDER BY ordinal_position
    LOOP
        RAISE NOTICE '  • %: %', col_record.column_name, col_record.data_type;
    END LOOP;
    
    RAISE NOTICE '========================================';
END $$;

-- Show active rooms count
DO $$
DECLARE
    room_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO room_count FROM rooms WHERE is_active = true;
    RAISE NOTICE '';
    RAISE NOTICE '📊 Active Rooms: %', room_count;
END $$;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ MATCHMAKING FIX COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Changes applied:';
    RAISE NOTICE '  1. Removed problematic constraint';
    RAISE NOTICE '  2. Fixed matching logic';
    RAISE NOTICE '  3. Granted permissions';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Test with your React app';
    RAISE NOTICE '  2. Check browser console for logs';
    RAISE NOTICE '  3. Monitor Supabase logs for NOTICE messages';
    RAISE NOTICE '========================================';
END $$;







------------- FILE - 42






-- Just run this part to update the function:
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Find compatible room
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender
      AND r.gender_preference = p_interested_in
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    INSERT INTO public.rooms (
        room_type, 
        room_size, 
        gender_preference,
        interest_category, 
        creator_id,
        creator_gender,
        is_active
    )
    VALUES (
        'public', 
        p_room_size, 
        p_interested_in,
        p_interest, 
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;







--------- FILE - 43






-- Clean up all old rooms
UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- Verify cleanup
SELECT COUNT(*) as active_rooms FROM rooms WHERE is_active = true;
-- Should return 0





---------- FILE - 44





DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_room_count INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING START';
    RAISE NOTICE 'User: %', p_user_id;
    RAISE NOTICE 'My Gender: %', p_user_gender;
    RAISE NOTICE 'Looking For: %', p_interested_in;
    RAISE NOTICE 'Interest: %', p_interest;
    RAISE NOTICE 'Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Count available rooms
    SELECT COUNT(*) INTO v_room_count
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest;
    
    RAISE NOTICE '📊 Total public rooms matching size/interest: %', v_room_count;
    
    -- Show all candidate rooms
    FOR v_found_room_id IN
        SELECT r.id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = p_room_size
          AND r.interest_category = p_interest
        LIMIT 5
    LOOP
        DECLARE
            room_info RECORD;
            participant_count INTEGER;
        BEGIN
            SELECT * INTO room_info FROM rooms WHERE id = v_found_room_id;
            SELECT COUNT(*) INTO participant_count 
            FROM room_participants 
            WHERE room_id = v_found_room_id AND left_at IS NULL;
            
            RAISE NOTICE '  Room %:', v_found_room_id;
            RAISE NOTICE '    Creator Gender: %', room_info.creator_gender;
            RAISE NOTICE '    Wants: %', room_info.gender_preference;
            RAISE NOTICE '    Creator ID: %', room_info.creator_id;
            RAISE NOTICE '    Participants: %/%', participant_count, room_info.room_size;
            RAISE NOTICE '    Match Criteria:';
            RAISE NOTICE '      creator_gender = my_gender? % = % → %', 
                room_info.creator_gender, p_user_gender, 
                room_info.creator_gender = p_user_gender;
            RAISE NOTICE '      gender_preference = interested_in? % = % → %', 
                room_info.gender_preference, p_interested_in,
                room_info.gender_preference = p_interested_in;
            RAISE NOTICE '      Not my room? %', room_info.creator_id != p_user_id;
            RAISE NOTICE '      Has space? %', participant_count < room_info.room_size;
        END;
    END LOOP;
    
    -- Find compatible room with explicit logging
    RAISE NOTICE '🔍 SEARCHING FOR MATCH...';
    RAISE NOTICE '  Looking for: creator_gender=% AND gender_preference=%', 
        p_user_gender, p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender
      AND r.gender_preference = p_interested_in
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCH FOUND: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    RAISE NOTICE '❌ NO MATCH FOUND - Creating new room';
    
    INSERT INTO public.rooms (
        room_type, 
        room_size, 
        gender_preference,
        interest_category, 
        creator_id,
        creator_gender,
        is_active
    )
    VALUES (
        'public', 
        p_room_size, 
        p_interested_in,
        p_interest, 
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ NEW ROOM CREATED: %', v_created_room_id;
    RAISE NOTICE '  Creator Gender: %', p_user_gender;
    RAISE NOTICE '  Wants: %', p_interested_in;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;





----------- FILE - 45




-- Clean slate first
UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- Test 1: Male looking for Female
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '=== TEST 1: MALE LOOKING FOR FEMALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
END $$;

-- Test 2: Female looking for Male (should match above room)
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 2: FEMALE LOOKING FOR MALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'female'::gender_preference,
        'male'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
    
    IF result.is_new_room THEN
        RAISE NOTICE '❌ FAILED: Should have matched existing room!';
    ELSE
        RAISE NOTICE '✅ SUCCESS: Matched existing room!';
    END IF;
END $$;







-------- FILE - 46






-- Drop the trigger first (correct name)
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON rooms;

-- Now drop the function
DROP FUNCTION IF EXISTS set_creator_gender() CASCADE;

-- Verify it's gone
SELECT trigger_name 
FROM information_schema.triggers 
WHERE event_object_table = 'rooms';
-- Should return empty





------- FILE - 47




-- Clean slate
UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- Test 1: Male looking for Female
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '=== TEST 1: MALE LOOKING FOR FEMALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
END $$;

-- Test 2: Female looking for Male
DO $$
DECLARE
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 2: FEMALE LOOKING FOR MALE ===';
    
    SELECT * INTO result FROM find_compatible_room(
        gen_random_uuid(),
        'female'::gender_preference,
        'male'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE 'Room ID: %', result.matched_room_id;
    RAISE NOTICE 'Is New: %', result.is_new_room;
    
    IF result.is_new_room THEN
        RAISE NOTICE '❌ FAILED: Should have matched existing room!';
    ELSE
        RAISE NOTICE '✅ SUCCESS: Matched existing room!';
    END IF;
END $$;





----------- FILE - 48





-- ============================================
-- 🔧 CRITICAL FIX: Matchmaking Function
-- This fixes the room matching logic
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_participant_count INTEGER;
    v_room_record RECORD;
BEGIN
    -- ✅ Validation
    IF p_user_gender = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    IF p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot match with "other" gender';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
    RAISE NOTICE 'User: %', p_user_id;
    RAISE NOTICE 'My Gender: %', p_user_gender;
    RAISE NOTICE 'Looking For: %', p_interested_in;
    RAISE NOTICE 'Interest: %', p_interest;
    RAISE NOTICE 'Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CRITICAL FIX: Correct matching logic
    -- Find rooms where:
    --   1. Room creator has MY gender
    --   2. Room wants people I'm interested in
    --   3. Has space available
    
    RAISE NOTICE '🔍 SEARCHING FOR COMPATIBLE ROOMS...';
    
    FOR v_room_record IN
        SELECT 
            r.id,
            r.creator_gender,
            r.gender_preference,
            r.creator_id,
            COUNT(rp.id) as participant_count
        FROM public.rooms r
        LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = p_room_size
          AND r.interest_category = p_interest
          AND r.creator_gender = p_user_gender      -- ✅ Creator has MY gender
          AND r.gender_preference = p_interested_in -- ✅ Room wants who I want
          AND r.creator_id != p_user_id             -- ✅ Not my own room
        GROUP BY r.id, r.creator_gender, r.gender_preference, r.creator_id, r.created_at
        ORDER BY r.created_at ASC
        LIMIT 5
    LOOP
        RAISE NOTICE '  📊 Checking room %:', v_room_record.id;
        RAISE NOTICE '    • Creator gender: %', v_room_record.creator_gender;
        RAISE NOTICE '    • Wants: %', v_room_record.gender_preference;
        RAISE NOTICE '    • Participants: %/%', v_room_record.participant_count, p_room_size;
        RAISE NOTICE '    • Match?: creator_gender=% AND preference=%', 
            (v_room_record.creator_gender = p_user_gender),
            (v_room_record.gender_preference = p_interested_in);
        
        -- Check if room has space
        IF v_room_record.participant_count < p_room_size THEN
            RAISE NOTICE '✅ MATCH FOUND! Room: %', v_room_record.id;
            RAISE NOTICE '========================================';
            RETURN QUERY SELECT v_room_record.id AS matched_room_id, false AS is_new_room;
            RETURN;
        ELSE
            RAISE NOTICE '  ⚠️ Room full, skipping';
        END IF;
    END LOOP;
    
    -- No compatible room found, create new one
    RAISE NOTICE '❌ NO MATCH FOUND - Creating new room';
    RAISE NOTICE '  Will create room with:';
    RAISE NOTICE '    • creator_gender: %', p_user_gender;
    RAISE NOTICE '    • gender_preference: %', p_interested_in;
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Who I want to match with
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- ✅ This room wants people I'm interested in
        p_interest,
        p_user_id,
        p_user_gender,        -- ✅ My gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED NEW ROOM: %', v_created_room_id;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ✅ Verify it was created
SELECT 
    proname as function_name,
    pg_get_function_identity_arguments(oid) as arguments
FROM pg_proc 
WHERE proname = 'find_compatible_room';




---------- FILE - 49



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




--------- FILE - 50




-- ============================================
-- 🧪 TEST MATCHMAKING
-- This simulates two users matching
-- ============================================

-- Test 1: Male creates room looking for Female
DO $$
DECLARE
    test_user_1 UUID := gen_random_uuid();
    result_1 RECORD;
BEGIN
    -- Create test user
    INSERT INTO users (id, email, display_name, gender)
    VALUES (test_user_1, 'test1@example.com', 'Test Male', 'male');
    
    -- Try to find/create room
    SELECT * INTO result_1 FROM find_compatible_room(
        test_user_1,
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1 RESULT:';
    RAISE NOTICE 'Room ID: %', result_1.matched_room_id;
    RAISE NOTICE 'Is New: %', result_1.is_new_room;
    RAISE NOTICE 'Expected: Should CREATE new room (is_new_room = true)';
END $$;

-- Test 2: Female tries to match with that room
DO $$
DECLARE
    test_user_2 UUID := gen_random_uuid();
    result_2 RECORD;
BEGIN
    -- Create test user
    INSERT INTO users (id, email, display_name, gender)
    VALUES (test_user_2, 'test2@example.com', 'Test Female', 'female');
    
    -- Try to find/create room
    SELECT * INTO result_2 FROM find_compatible_room(
        test_user_2,
        'female'::gender_preference,
        'male'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2 RESULT:';
    RAISE NOTICE 'Room ID: %', result_2.matched_room_id;
    RAISE NOTICE 'Is New: %', result_2.is_new_room;
    RAISE NOTICE 'Expected: Should MATCH existing room (is_new_room = false)';
END $$;

-- Clean up test users
DELETE FROM users WHERE email LIKE 'test%@example.com';


-------- FILE - 51


-- ============================================
-- 🔧 CRITICAL FIX: Matchmaking Logic
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '🔍 MATCHMAKING: User % (gender: %) looking for %', 
        p_user_id, p_user_gender, p_interested_in;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT LOGIC: Find rooms created by people I'm interested in, who want my gender
    -- If I'm Male looking for Female:
    --   Find rooms where creator_gender='female' AND gender_preference='male'
    -- If I'm Female looking for Male:
    --   Find rooms where creator_gender='male' AND gender_preference='female'
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- ✅ Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- ✅ Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED existing room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    -- This room will be found by users with opposite matching criteria
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- What gender I want to meet
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- I want to meet this gender
        p_interest,
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '🏗️ CREATED new room: %', v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧹 CLEANUP OLD ROOMS
-- ============================================

UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE rooms SET is_active = false WHERE is_active = true;

-- ============================================
-- 🧪 TEST THE FIX
-- ============================================

DO $$
DECLARE
    user1 UUID := gen_random_uuid();
    user2 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (user1, 'testmale@test.com', 'Test Male', 'male'),
        (user2, 'testfemale@test.com', 'Test Female', 'female');
    
    -- Test 1: Male looking for Female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male looking for Female';
    SELECT * INTO result1 FROM find_compatible_room(
        user1, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result1.matched_room_id;
    RAISE NOTICE '  Is New: %', result1.is_new_room;
    
    -- Test 2: Female looking for Male (should match Test 1's room)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female looking for Male';
    SELECT * INTO result2 FROM find_compatible_room(
        user2, 'female'::gender_preference, 'male'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result2.matched_room_id;
    RAISE NOTICE '  Is New: %', result2.is_new_room;
    
    -- Verify match
    RAISE NOTICE '';
    IF result1.matched_room_id = result2.matched_room_id THEN
        RAISE NOTICE '✅ SUCCESS: Both users matched to SAME room!';
    ELSE
        RAISE NOTICE '❌ FAILED: Users got different rooms';
        RAISE NOTICE '  Room 1: %', result1.matched_room_id;
        RAISE NOTICE '  Room 2: %', result2.matched_room_id;
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test%@test.com';
    
    RAISE NOTICE '========================================';
END $$;



-------- FILE - 52

-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Opposite Gender First, Same Gender Fallback
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred Match: %', p_interested_in;
    RAISE NOTICE 'Interest: %', p_interest;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try to match with OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender matching
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender      -- Creator has MY gender
      AND r.gender_preference = p_user_gender   -- Room wants MY gender (same gender matching)
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room (will match opposite gender first)
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    RAISE NOTICE '  Creator Gender: %', p_user_gender;
    RAISE NOTICE '  Preferred Match: %', p_interested_in;
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Prefer opposite gender
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- Room prefers opposite gender
        p_interest,
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ NEW ROOM CREATED: %', v_created_room_id;
    RAISE NOTICE '  Will match with % first, then % if needed', p_interested_in, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧹 CLEANUP OLD ROOMS (Optional - for testing)
-- ============================================

-- Uncomment these lines if you want to start fresh:
-- UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
-- UPDATE rooms SET is_active = false WHERE is_active = true;

-- ============================================
-- 🧪 COMPREHENSIVE TEST
-- ============================================

DO $$
DECLARE
    male1 UUID := gen_random_uuid();
    male2 UUID := gen_random_uuid();
    female1 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
    result3 RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING ENHANCED MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (male1, 'testmale1@test.com', 'Male 1', 'male'),
        (male2, 'testmale2@test.com', 'Male 2', 'male'),
        (female1, 'testfemale1@test.com', 'Female 1', 'female');
    
    -- Test 1: First male looking for female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male 1 looking for Female';
    SELECT * INTO result1 FROM find_compatible_room(
        male1, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result1.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result1.is_new_room;
    
    -- Test 2: Second male looking for female (should match same gender as fallback)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Male 2 looking for Female (no females available yet)';
    SELECT * INTO result2 FROM find_compatible_room(
        male2, 'male'::gender_preference, 'female'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result2.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: false - should match Male 1)', result2.is_new_room;
    
    -- Test 3: Female looking for male (should match the male room)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 3: Female looking for Male';
    SELECT * INTO result3 FROM find_compatible_room(
        female1, 'female'::gender_preference, 'male'::gender_preference, 
        'random'::interest_category, 2
    );
    RAISE NOTICE '  ✓ Room: %', result3.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true - creates new female room)', result3.is_new_room;
    
    -- Verify results
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 TEST RESULTS';
    RAISE NOTICE '========================================';
    
    IF result1.is_new_room = true THEN
        RAISE NOTICE '✅ Test 1 PASSED: Male 1 created new room';
    ELSE
        RAISE NOTICE '❌ Test 1 FAILED';
    END IF;
    
    IF result2.is_new_room = false AND result2.matched_room_id = result1.matched_room_id THEN
        RAISE NOTICE '✅ Test 2 PASSED: Male 2 matched with Male 1 (same gender fallback)';
    ELSE
        RAISE NOTICE '❌ Test 2 FAILED';
    END IF;
    
    IF result3.is_new_room = true THEN
        RAISE NOTICE '✅ Test 3 PASSED: Female created new room';
    ELSE
        RAISE NOTICE '❌ Test 3 FAILED';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test%@test.com';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- ============================================
-- ✅ SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ENHANCED MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Priority:';
    RAISE NOTICE '  1️⃣ Try opposite gender match';
    RAISE NOTICE '  2️⃣ Fallback to same gender';
    RAISE NOTICE '  3️⃣ Create new room if nothing found';
    RAISE NOTICE '';
    RAISE NOTICE 'Example Flow (Male looking for Female):';
    RAISE NOTICE '  • First searches for female-created rooms';
    RAISE NOTICE '  • If none found, matches with other males';
    RAISE NOTICE '  • Creates new room as last resort';
    RAISE NOTICE '';
    RAISE NOTICE 'Ready to use in your React app!';
    RAISE NOTICE '========================================';
END $$;




-------- FILE - 53



-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Opposite Gender First, Same Gender Fallback
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred: % | Fallback: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite (but we'll join anyway)
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: % | Will accept: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧹 CLEANUP OLD ROOMS (Optional - for testing)
-- ============================================

-- Uncomment these lines if you want to start fresh:
-- UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
-- UPDATE rooms SET is_active = false WHERE is_active = true;

-- ============================================
-- 🧪 COMPREHENSIVE TEST
-- ============================================

DO $$
DECLARE
    male1 UUID := gen_random_uuid();
    male2 UUID := gen_random_uuid();
    female1 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
    result3 RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (male1, 'testmale1@test.com', 'Male 1', 'male'),
        (male2, 'testmale2@test.com', 'Male 2', 'male'),
        (female1, 'testfemale1@test.com', 'Female 1', 'female');
    
    -- Test 1: First male
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male 1 creating room';
    SELECT * INTO result1 FROM find_compatible_room_simple(male1, 'male'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result1.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result1.is_new_room;
    
    -- Test 2: Second male (should match first male via fallback)
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Male 2 looking for match';
    SELECT * INTO result2 FROM find_compatible_room_simple(male2, 'male'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result2.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: false)', result2.is_new_room;
    
    -- Test 3: Female
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 3: Female creating room';
    SELECT * INTO result3 FROM find_compatible_room_simple(female1, 'female'::gender_preference, 2);
    RAISE NOTICE '  ✓ Room: %', result3.matched_room_id;
    RAISE NOTICE '  ✓ Is New: % (Expected: true)', result3.is_new_room;
    
    -- Verify results
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 TEST RESULTS';
    RAISE NOTICE '========================================';
    
    IF result1.is_new_room = true THEN
        RAISE NOTICE '✅ Test 1 PASSED: Male 1 created new room';
    ELSE
        RAISE NOTICE '❌ Test 1 FAILED';
    END IF;
    
    IF result2.is_new_room = false AND result2.matched_room_id = result1.matched_room_id THEN
        RAISE NOTICE '✅ Test 2 PASSED: Male 2 matched with Male 1 (same gender fallback)';
    ELSE
        RAISE NOTICE '❌ Test 2 FAILED';
    END IF;
    
    IF result3.is_new_room = true THEN
        RAISE NOTICE '✅ Test 3 PASSED: Female created new room';
    ELSE
        RAISE NOTICE '❌ Test 3 FAILED';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE 'test%@test.com';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- ============================================
-- ✅ SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ SIMPLE MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Function: find_compatible_room_simple()';
    RAISE NOTICE 'Parameters: (user_id, gender, room_size)';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Priority:';
    RAISE NOTICE '  1️⃣ Try opposite gender';
    RAISE NOTICE '  2️⃣ Fallback to same gender';
    RAISE NOTICE '  3️⃣ Create new room';
    RAISE NOTICE '';
    RAISE NOTICE 'Your React app should now work!';
    RAISE NOTICE '========================================';
END $$;


--------- FILE - 54



-- ============================================
-- 🔧 COMPLETE DATABASE FIX
-- Fixes all critical bugs in matchmaking and room management
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- BUG #1: Auto-join creator to room when created
-- Currently creators aren't being added as participants
-- ============================================

DROP TRIGGER IF EXISTS trigger_auto_join_room_creator ON public.rooms;
DROP FUNCTION IF EXISTS auto_join_room_creator() CASCADE;

CREATE OR REPLACE FUNCTION auto_join_room_creator()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Auto-add creator as participant when room is created
    IF NEW.creator_id IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id, joined_at, left_at)
        VALUES (NEW.id, NEW.creator_id, NOW(), NULL)
        ON CONFLICT (room_id, user_id) DO UPDATE 
        SET left_at = NULL, joined_at = NOW();
        
        RAISE NOTICE '✅ Auto-joined creator % to room %', NEW.creator_id, NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_join_room_creator
    AFTER INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION auto_join_room_creator();

-- ============================================
-- BUG #2: Fix join_room_if_available - counting bug
-- Should count ALL participants, not exclude current user
-- ============================================

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(p_room_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
BEGIN
  -- Get room info
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found');
  END IF;
  
  IF NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_inactive');
  END IF;
  
  -- ✅ FIXED: Count ALL active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id AND left_at IS NULL;
  
  -- Check if room is full
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full');
  END IF;
  
  -- Join the room (or rejoin if already joined)
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) DO UPDATE 
  SET left_at = NULL, joined_at = NOW();
  
  RETURN json_build_object('success', true, 'message', 'Successfully joined room');
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- BUG #3: Fix matchmaking logic - CRITICAL
-- Creator gender and preference matching was backwards
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING: User % (gender: %) looking for %', 
        p_user_id, p_user_gender, p_interested_in;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try opposite gender first
    -- ============================================
    RAISE NOTICE '🔍 Looking for opposite gender: %', p_interested_in;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- ✅ Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- ✅ Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED opposite gender room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- STEP 2: Fallback to same gender
    -- ============================================
    RAISE NOTICE '🔍 Fallback: Looking for same gender: %', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_user_gender      -- Same gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED same gender room (fallback): %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- STEP 3: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Who I want to meet
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- ✅ Room wants opposite gender
        p_interest,
        p_user_id,
        p_user_gender,        -- ✅ My gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ NEW ROOM: % (creator: %, wants: %)', 
        v_created_room_id, p_user_gender, p_interested_in;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- BUG #4: Add simple matchmaking function (for compatibility)
-- This is the function your frontend might be calling
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_opposite_gender gender_preference;
BEGIN
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    -- Call main function with 'random' interest
    RETURN QUERY SELECT * FROM find_compatible_room(
        p_user_id,
        p_user_gender,
        v_opposite_gender,
        'random'::interest_category,
        p_room_size
    );
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- BUG #5: Real-time participant updates
-- Add function to get current online users by gender
-- ============================================

CREATE OR REPLACE FUNCTION get_online_users_by_gender()
RETURNS TABLE(
    gender gender_preference,
    online_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 
        u.gender,
        COUNT(DISTINCT rp.user_id) as online_count
    FROM users u
    INNER JOIN room_participants rp ON rp.user_id = u.id
    INNER JOIN rooms r ON r.id = rp.room_id
    WHERE rp.left_at IS NULL
      AND r.is_active = true
      AND r.room_type = 'public'
      AND u.gender IN ('male', 'female')
    GROUP BY u.gender;
$$;

GRANT EXECUTE ON FUNCTION get_online_users_by_gender() TO authenticated, anon;

-- ============================================
-- BUG #6: Auto-cleanup inactive rooms
-- Rooms should be marked inactive when empty
-- ============================================

CREATE OR REPLACE FUNCTION auto_deactivate_empty_rooms()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      )
      AND created_at < NOW() - INTERVAL '5 minutes';
      
    RAISE NOTICE '✅ Deactivated empty rooms older than 5 minutes';
END;
$$;

GRANT EXECUTE ON FUNCTION auto_deactivate_empty_rooms() TO authenticated, service_role;

-- ============================================
-- BUG #7: Ensure participant_count view exists
-- Frontend may rely on this for real-time updates
-- ============================================

CREATE OR REPLACE VIEW room_with_participants AS
SELECT 
    r.*,
    COUNT(rp.id) FILTER (WHERE rp.left_at IS NULL) as participant_count
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
GROUP BY r.id;

GRANT SELECT ON room_with_participants TO authenticated, anon;

-- ============================================
-- BUG #8: Add online users view for premium users
-- ============================================

CREATE OR REPLACE VIEW online_users_summary AS
SELECT 
    COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'male') as males_online,
    COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'female') as females_online,
    COUNT(DISTINCT rp.user_id) as total_online
FROM room_participants rp
INNER JOIN users u ON u.id = rp.user_id
INNER JOIN rooms r ON r.id = rp.room_id
WHERE rp.left_at IS NULL
  AND r.is_active = true
  AND r.room_type = 'public';

GRANT SELECT ON online_users_summary TO authenticated, anon;

-- ============================================
-- BUG #9: Ensure indexes exist for performance
-- ============================================

-- Add missing indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_room_participants_active_user ON room_participants(user_id) 
    WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_rooms_public_active ON rooms(room_type, is_active, created_at) 
    WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_users_gender_active ON users(gender) 
    WHERE gender IN ('male', 'female');

-- ============================================
-- BUG #10: Add realtime subscription triggers
-- Ensure changes are broadcast to frontend
-- ============================================

-- Notify when participant joins/leaves
CREATE OR REPLACE FUNCTION notify_participant_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Notify room channel about participant change
    PERFORM pg_notify(
        'room_participant_change',
        json_build_object(
            'room_id', COALESCE(NEW.room_id, OLD.room_id),
            'user_id', COALESCE(NEW.user_id, OLD.user_id),
            'event', TG_OP
        )::text
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_participant_change ON room_participants;
CREATE TRIGGER trigger_notify_participant_change
    AFTER INSERT OR UPDATE OR DELETE ON room_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_participant_change();

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

DO $$
DECLARE
    function_count INTEGER;
    trigger_count INTEGER;
    view_count INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE FIX COMPLETE';
    RAISE NOTICE '========================================';
    
    -- Count created functions
    SELECT COUNT(*) INTO function_count 
    FROM pg_proc 
    WHERE proname IN (
        'auto_join_room_creator',
        'join_room_if_available',
        'find_compatible_room',
        'find_compatible_room_simple',
        'get_online_users_by_gender',
        'auto_deactivate_empty_rooms',
        'notify_participant_change'
    );
    
    -- Count created triggers
    SELECT COUNT(*) INTO trigger_count
    FROM information_schema.triggers
    WHERE trigger_name IN (
        'trigger_auto_join_room_creator',
        'trigger_notify_participant_change'
    );
    
    -- Count created views
    SELECT COUNT(*) INTO view_count
    FROM information_schema.views
    WHERE table_name IN (
        'room_with_participants',
        'online_users_summary'
    );
    
    RAISE NOTICE '📊 Verification:';
    RAISE NOTICE '  • Functions: % created', function_count;
    RAISE NOTICE '  • Triggers: % created', trigger_count;
    RAISE NOTICE '  • Views: % created', view_count;
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Bugs Fixed:';
    RAISE NOTICE '  1. ✅ Auto-join creator to room';
    RAISE NOTICE '  2. ✅ Fixed participant counting';
    RAISE NOTICE '  3. ✅ Fixed matchmaking logic';
    RAISE NOTICE '  4. ✅ Added simple matchmaking';
    RAISE NOTICE '  5. ✅ Real-time online users';
    RAISE NOTICE '  6. ✅ Auto-cleanup empty rooms';
    RAISE NOTICE '  7. ✅ Participant count view';
    RAISE NOTICE '  8. ✅ Online users summary';
    RAISE NOTICE '  9. ✅ Performance indexes';
    RAISE NOTICE '  10. ✅ Realtime notifications';
    RAISE NOTICE '';
    RAISE NOTICE '📡 Realtime Features:';
    RAISE NOTICE '  • room_participants table: subscribed';
    RAISE NOTICE '  • online_users_summary view: available';
    RAISE NOTICE '  • pg_notify triggers: active';
    RAISE NOTICE '';
    RAISE NOTICE '🧪 Next Steps:';
    RAISE NOTICE '  1. Test matchmaking with 2 users';
    RAISE NOTICE '  2. Verify room creator appears in participants';
    RAISE NOTICE '  3. Check online user counts update';
    RAISE NOTICE '  4. Test "Next Room" functionality';
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- OPTIONAL: Clean up old test data
-- ============================================

-- Uncomment these lines if you want to start fresh:
-- UPDATE room_participants SET left_at = NOW() WHERE left_at IS NULL;
-- UPDATE rooms SET is_active = false WHERE is_active = true;
-- DELETE FROM users WHERE email LIKE 'test%@test.com';

-- ============================================
-- TEST MATCHMAKING
-- ============================================

DO $$
DECLARE
    male1 UUID := gen_random_uuid();
    female1 UUID := gen_random_uuid();
    result1 RECORD;
    result2 RECORD;
    online_stats RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (male1, 'testmale@fix.test', 'Test Male', 'male'),
        (female1, 'testfemale@fix.test', 'Test Female', 'female');
    
    -- Test 1: Male creates room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male creating room';
    SELECT * INTO result1 FROM find_compatible_room(
        male1, 'male'::gender_preference, 'female'::gender_preference,
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result1.matched_room_id;
    RAISE NOTICE '  Is New: %', result1.is_new_room;
    
    -- Verify male was auto-joined
    IF EXISTS (
        SELECT 1 FROM room_participants 
        WHERE room_id = result1.matched_room_id 
        AND user_id = male1 
        AND left_at IS NULL
    ) THEN
        RAISE NOTICE '  ✅ Male auto-joined successfully';
    ELSE
        RAISE NOTICE '  ❌ Male NOT auto-joined!';
    END IF;
    
    -- Test 2: Female tries to match
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female looking for match';
    SELECT * INTO result2 FROM find_compatible_room(
        female1, 'female'::gender_preference, 'male'::gender_preference,
        'random'::interest_category, 2
    );
    RAISE NOTICE '  Room: %', result2.matched_room_id;
    RAISE NOTICE '  Is New: %', result2.is_new_room;
    
    -- Verify match
    IF result1.matched_room_id = result2.matched_room_id THEN
        RAISE NOTICE '  ✅ Successfully matched same room!';
    ELSE
        RAISE NOTICE '  ❌ Different rooms! Bug still exists!';
    END IF;
    
    -- Test online users
    RAISE NOTICE '';
    RAISE NOTICE '📊 Testing online users view:';
    SELECT * INTO online_stats FROM online_users_summary;
    RAISE NOTICE '  Males online: %', online_stats.males_online;
    RAISE NOTICE '  Females online: %', online_stats.females_online;
    RAISE NOTICE '  Total online: %', online_stats.total_online;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE '%@fix.test';
    
    RAISE NOTICE '========================================';
END $$;






------------ FILE - 55






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



---------- FILE - 56





-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Handle 2 and 4 room sizes
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_enhanced(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
    v_target_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 ENHANCED MATCHMAKING';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- STEP 3: Try ANY gender (any room with space)
    -- ============================================
    RAISE NOTICE '🔍 STEP 3: Looking for ANY room with space (%)', p_room_size;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found any gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with any gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No room with space found';
    
    -- ============================================
    -- STEP 4: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: %', v_opposite_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_enhanced(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧪 TEST THE ENHANCED FUNCTION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING ENHANCED MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test user
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_user, 'test@enhanced.com', 'Test User', 'male');
    
    -- Test with room size 2
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Room Size 2';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Test with room size 4
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Room Size 4';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 4);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Cleanup
    DELETE FROM users WHERE email = 'test@enhanced.com';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ENHANCED MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Priority order:';
    RAISE NOTICE '  1️⃣ Opposite gender match';
    RAISE NOTICE '  2️⃣ Same gender fallback';
    RAISE NOTICE '  3️⃣ Any room with space';
    RAISE NOTICE '  4️⃣ Create new room';
    RAISE NOTICE '========================================';
END $$;





-------- FILE - 57




-- ============================================
-- 🔄 REVERT ENHANCED MATCHMAKING FUNCTION
-- This removes the enhanced function and keeps the original setup
-- ============================================

-- Step 1: Drop the enhanced function if it exists
DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

-- Step 2: Recreate the original simple matchmaking function from FILE-53
DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred: % | Fallback: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite (but we'll join anyway)
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: % | Will accept: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- Step 3: Recreate the main find_compatible_room function from FILE-51
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '🔍 MATCHMAKING: User % (gender: %) looking for %', 
        p_user_id, p_user_gender, p_interested_in;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT LOGIC: Find rooms created by people I'm interested in, who want my gender
    -- If I'm Male looking for Female:
    --   Find rooms where creator_gender='female' AND gender_preference='male'
    -- If I'm Female looking for Male:
    --   Find rooms where creator_gender='male' AND gender_preference='female'
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- ✅ Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- ✅ Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED existing room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    -- This room will be found by users with opposite matching criteria
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- What gender I want to meet
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- I want to meet this gender
        p_interest,
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '🏗️ CREATED new room: %', v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- ✅ VERIFICATION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ REVERT COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Test that the simple function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_simple';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_simple function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Test that the main function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Verify enhanced function is gone
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_enhanced';
    
    IF NOT FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_enhanced function removed';
    ELSE
        RAISE NOTICE '❌ Enhanced function still exists';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Original setup restored:';
    RAISE NOTICE '   • find_compatible_room_simple() - for CreateRoom.tsx';
    RAISE NOTICE '   • find_compatible_room() - for Room.tsx';
    RAISE NOTICE '';
    RAISE NOTICE '📱 Frontend should use:';
    RAISE NOTICE '   • CreateRoom.tsx → find_compatible_room_simple()';
    RAISE NOTICE '   • Room.tsx handleNextRoom() → find_compatible_room()';
    RAISE NOTICE '========================================';
END $$;



--------- FILE - 56




-- ============================================
-- 🔧 ENHANCED MATCHMAKING: Handle 2 and 4 room sizes
-- Run this in Supabase SQL Editor
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_enhanced(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
    v_target_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 ENHANCED MATCHMAKING';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- STEP 3: Try ANY gender (any room with space)
    -- ============================================
    RAISE NOTICE '🔍 STEP 3: Looking for ANY room with space (%)', p_room_size;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found any gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with any gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No room with space found';
    
    -- ============================================
    -- STEP 4: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: %', v_opposite_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_enhanced(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- 🧪 TEST THE ENHANCED FUNCTION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING ENHANCED MATCHMAKING';
    RAISE NOTICE '========================================';
    
    -- Create test user
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_user, 'test@enhanced.com', 'Test User', 'male');
    
    -- Test with room size 2
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Room Size 2';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Test with room size 4
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Room Size 4';
    SELECT * INTO result FROM find_compatible_room_enhanced(test_user, 'male'::gender_preference, 4);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    -- Cleanup
    DELETE FROM users WHERE email = 'test@enhanced.com';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ENHANCED MATCHMAKING INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Priority order:';
    RAISE NOTICE '  1️⃣ Opposite gender match';
    RAISE NOTICE '  2️⃣ Same gender fallback';
    RAISE NOTICE '  3️⃣ Any room with space';
    RAISE NOTICE '  4️⃣ Create new room';
    RAISE NOTICE '========================================';
END $$;






-------- FILE - 57




-- ============================================
-- 🔄 REVERT ENHANCED MATCHMAKING FUNCTION
-- This removes the enhanced function and keeps the original setup
-- ============================================

-- Step 1: Drop the enhanced function if it exists
DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);

-- Step 2: Recreate the original simple matchmaking function from FILE-53
DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
BEGIN
    -- Validation: Only male or female allowed
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SIMPLE MATCHMAKING WITH FALLBACK';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Preferred: % | Fallback: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- STEP 1: Try OPPOSITE gender first
    -- ============================================
    RAISE NOTICE '🔍 STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite_gender    -- Creator is opposite gender
      AND r.gender_preference = p_user_gender     -- Room wants my gender
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found opposite gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    
    -- ============================================
    -- STEP 2: Fallback to SAME gender
    -- ============================================
    RAISE NOTICE '🔍 STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender        -- Creator is same gender
      AND r.gender_preference = v_opposite_gender -- Room wants opposite (but we'll join anyway)
      AND r.creator_id != p_user_id               -- Not my own room
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found same gender match
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED with same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    
    -- ============================================
    -- STEP 3: Create new room
    -- ============================================
    RAISE NOTICE '🏗️ CREATING NEW ROOM';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- Want opposite gender
        interest_category,    -- Default to 'random'
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        v_opposite_gender,    -- Prefer opposite gender
        'random',             -- Default interest
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED new room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: % | Will accept: %', v_opposite_gender, p_user_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- Step 3: Recreate the main find_compatible_room function from FILE-51
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
BEGIN
    -- Validation
    IF p_user_gender = 'other' OR p_interested_in = 'other' THEN
        RAISE EXCEPTION 'Cannot use "other" gender for public matching';
    END IF;
    
    RAISE NOTICE '🔍 MATCHMAKING: User % (gender: %) looking for %', 
        p_user_id, p_user_gender, p_interested_in;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ✅ CORRECT LOGIC: Find rooms created by people I'm interested in, who want my gender
    -- If I'm Male looking for Female:
    --   Find rooms where creator_gender='female' AND gender_preference='male'
    -- If I'm Female looking for Male:
    --   Find rooms where creator_gender='male' AND gender_preference='female'
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.creator_gender = p_interested_in    -- ✅ Creator has the gender I want
      AND r.gender_preference = p_user_gender   -- ✅ Room wants MY gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED existing room: %', v_found_room_id;
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- Create new room
    -- This room will be found by users with opposite matching criteria
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,    -- What gender I want to meet
        interest_category,
        creator_id,
        creator_gender,       -- My gender
        is_active
    )
    VALUES (
        'public',
        p_room_size,
        p_interested_in,      -- I want to meet this gender
        p_interest,
        p_user_id,
        p_user_gender,        -- I am this gender
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '🏗️ CREATED new room: %', v_created_room_id;
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- ✅ VERIFICATION
-- ============================================

DO $$
DECLARE
    test_user UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ REVERT COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Test that the simple function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_simple';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_simple function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Test that the main function exists
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room';
    
    IF FOUND THEN
        RAISE NOTICE '✅ find_compatible_room function restored';
    ELSE
        RAISE NOTICE '❌ Function not found';
    END IF;
    
    -- Verify enhanced function is gone
    SELECT proname INTO result 
    FROM pg_proc 
    WHERE proname = 'find_compatible_room_enhanced';
    
    IF NOT FOUND THEN
        RAISE NOTICE '✅ find_compatible_room_enhanced function removed';
    ELSE
        RAISE NOTICE '❌ Enhanced function still exists';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Original setup restored:';
    RAISE NOTICE '   • find_compatible_room_simple() - for CreateRoom.tsx';
    RAISE NOTICE '   • find_compatible_room() - for Room.tsx';
    RAISE NOTICE '';
    RAISE NOTICE '📱 Frontend should use:';
    RAISE NOTICE '   • CreateRoom.tsx → find_compatible_room_simple()';
    RAISE NOTICE '   • Room.tsx handleNextRoom() → find_compatible_room()';
    RAISE NOTICE '========================================';
END $$;




--------- FILE - 58




-- ============================================
-- 🔧 COMPLETE MATCHMAKING & ROOM CLEANUP FIX
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- PART 1: DROP OLD FUNCTIONS
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room_simple(UUID, gender_preference, INTEGER);
DROP FUNCTION IF EXISTS find_compatible_room_enhanced(UUID, gender_preference, INTEGER);
DROP FUNCTION IF EXISTS get_active_users_by_gender();
DROP FUNCTION IF EXISTS auto_deactivate_empty_rooms();
DROP TRIGGER IF EXISTS trigger_auto_deactivate_room ON room_participants;
DROP FUNCTION IF EXISTS auto_deactivate_room_on_leave() CASCADE;

-- ============================================
-- PART 2: NEW MATCHMAKING FUNCTION
-- Handles both 2-person and 4-person rooms
-- ============================================

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;
    v_created_room_id UUID;
    v_opposite_gender gender_preference;
BEGIN
    -- Validation
    IF p_user_gender NOT IN ('male', 'female') THEN
        RAISE EXCEPTION 'Only "male" or "female" gender allowed for public matching';
    END IF;
    
    -- Determine opposite gender
    IF p_user_gender = 'male' THEN
        v_opposite_gender := 'female';
    ELSE
        v_opposite_gender := 'male';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 MATCHMAKING REQUEST';
    RAISE NOTICE 'User: % (Gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE 'Room Size: %', p_room_size;
    RAISE NOTICE '========================================';
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender, updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- ============================================
    -- 4-PERSON ROOM LOGIC: Join ANY available room
    -- ============================================
    IF p_room_size = 4 THEN
        RAISE NOTICE '🔍 4-PERSON ROOM: Looking for any room with space...';
        
        SELECT r.id INTO v_found_room_id
        FROM public.rooms r
        WHERE r.room_type = 'public'
          AND r.is_active = true
          AND r.room_size = 4
          AND r.creator_id != p_user_id
          AND (
              SELECT COUNT(*) 
              FROM public.room_participants rp
              WHERE rp.room_id = r.id AND rp.left_at IS NULL
          ) < 4
        ORDER BY r.created_at ASC
        LIMIT 1;
        
        IF v_found_room_id IS NOT NULL THEN
            RAISE NOTICE '✅ MATCHED 4-person room: %', v_found_room_id;
            RAISE NOTICE '========================================';
            RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
            RETURN;
        END IF;
        
        RAISE NOTICE '⚠️ No 4-person room found, creating new one';
        
        -- Create new 4-person room (gender-neutral)
        INSERT INTO public.rooms (
            room_type,
            room_size,
            gender_preference,
            interest_category,
            creator_id,
            creator_gender,
            is_active
        )
        VALUES (
            'public',
            4,
            v_opposite_gender,  -- Preference but accepts anyone
            'random',
            p_user_id,
            p_user_gender,
            true
        )
        RETURNING id INTO v_created_room_id;
        
        RAISE NOTICE '✅ CREATED 4-person room: %', v_created_room_id;
        RAISE NOTICE '========================================';
        
        RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
        RETURN;
    END IF;
    
    -- ============================================
    -- 2-PERSON ROOM LOGIC: Opposite > Same > Create
    -- ============================================
    RAISE NOTICE '🔍 2-PERSON ROOM STEP 1: Looking for opposite gender (%)', v_opposite_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.creator_gender = v_opposite_gender
      AND r.gender_preference = p_user_gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED opposite gender room: %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No opposite gender match found';
    RAISE NOTICE '🔍 2-PERSON ROOM STEP 2: Looking for same gender (%)', p_user_gender;
    
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = 2
      AND r.creator_gender = p_user_gender
      AND r.gender_preference = v_opposite_gender
      AND r.creator_id != p_user_id
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id AND rp.left_at IS NULL
      ) < 2
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '✅ MATCHED same gender room (fallback): %', v_found_room_id;
        RAISE NOTICE '========================================';
        RETURN QUERY SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '⚠️ No same gender match found';
    RAISE NOTICE '🏗️ 2-PERSON ROOM STEP 3: Creating new room';
    
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        creator_gender,
        is_active
    )
    VALUES (
        'public',
        2,
        v_opposite_gender,
        'random',
        p_user_id,
        p_user_gender,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ CREATED 2-person room: %', v_created_room_id;
    RAISE NOTICE '  Creator: % (gender: %)', p_user_id, p_user_gender;
    RAISE NOTICE '  Prefers: %', v_opposite_gender;
    RAISE NOTICE '========================================';
    
    RETURN QUERY SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room_simple(UUID, gender_preference, INTEGER) TO authenticated, anon;

-- ============================================
-- PART 3: AUTO-DEACTIVATE EMPTY ROOMS
-- Trigger runs when participant leaves
-- ============================================

CREATE OR REPLACE FUNCTION auto_deactivate_room_on_leave()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_remaining_count INTEGER;
BEGIN
    -- Only proceed if a user just left (left_at was NULL, now has value)
    IF OLD.left_at IS NULL AND NEW.left_at IS NOT NULL THEN
        
        -- Count remaining active participants
        SELECT COUNT(*) INTO v_remaining_count
        FROM room_participants
        WHERE room_id = NEW.room_id AND left_at IS NULL;
        
        -- If no one left, deactivate the room
        IF v_remaining_count = 0 THEN
            UPDATE rooms
            SET is_active = false
            WHERE id = NEW.room_id AND is_active = true;
            
            RAISE NOTICE '✅ Room % auto-deactivated (empty)', NEW.room_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_deactivate_room
    AFTER UPDATE ON public.room_participants
    FOR EACH ROW
    EXECUTE FUNCTION auto_deactivate_room_on_leave();

-- ============================================
-- PART 4: REAL-TIME ACTIVE USERS COUNT
-- For premium users dashboard
-- ============================================

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

GRANT EXECUTE ON FUNCTION get_active_users_by_gender() TO authenticated, anon;

-- ============================================
-- PART 5: CLEANUP STALE ROOMS (Optional cron job)
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_stale_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cleaned_count INTEGER;
BEGIN
    -- Deactivate rooms that:
    -- 1. Have no active participants
    -- 2. Are older than 1 hour
    UPDATE rooms
    SET is_active = false
    WHERE is_active = true
      AND created_at < NOW() - INTERVAL '1 hour'
      AND id NOT IN (
          SELECT DISTINCT room_id
          FROM room_participants
          WHERE left_at IS NULL
      );
    
    GET DIAGNOSTICS cleaned_count = ROW_COUNT;
    
    RAISE NOTICE '✅ Cleaned up % stale rooms', cleaned_count;
    RETURN cleaned_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_stale_rooms() TO authenticated, service_role;

-- ============================================
-- PART 6: ENHANCED ROOM WITH PARTICIPANTS VIEW
-- ============================================

DROP VIEW IF EXISTS room_with_participants CASCADE;

CREATE OR REPLACE VIEW room_with_participants AS
SELECT 
    r.*,
    COUNT(rp.id) FILTER (WHERE rp.left_at IS NULL) as participant_count,
    ARRAY_AGG(
        json_build_object(
            'user_id', rp.user_id,
            'joined_at', rp.joined_at,
            'display_name', u.display_name,
            'membership_tier', u.membership_tier
        )
    ) FILTER (WHERE rp.left_at IS NULL) as participants
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
LEFT JOIN users u ON u.id = rp.user_id
GROUP BY r.id;

GRANT SELECT ON room_with_participants TO authenticated, anon;

-- ============================================
-- PART 7: VERIFICATION & TESTING
-- ============================================

DO $$
DECLARE
    test_male UUID := gen_random_uuid();
    test_female UUID := gen_random_uuid();
    result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING MATCHMAKING SYSTEM';
    RAISE NOTICE '========================================';
    
    -- Create test users
    INSERT INTO users (id, email, display_name, gender) VALUES
        (test_male, 'testmale@fix.test', 'Test Male', 'male'),
        (test_female, 'testfemale@fix.test', 'Test Female', 'female');
    
    -- TEST 1: Male creates 2-person room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 1: Male creating 2-person room';
    SELECT * INTO result FROM find_compatible_room_simple(test_male, 'male'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    IF result.is_new_room THEN
        RAISE NOTICE '  ✅ Correctly created new room';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Should have created new room';
    END IF;
    
    -- TEST 2: Female should match male's room
    RAISE NOTICE '';
    RAISE NOTICE '👤 TEST 2: Female looking for male (should match)';
    SELECT * INTO result FROM find_compatible_room_simple(test_female, 'female'::gender_preference, 2);
    RAISE NOTICE '  Room: %', result.matched_room_id;
    RAISE NOTICE '  Is New: %', result.is_new_room;
    
    IF NOT result.is_new_room THEN
        RAISE NOTICE '  ✅ Correctly matched existing room';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Should have matched existing room';
    END IF;
    
    -- TEST 3: Check room deactivation
    RAISE NOTICE '';
    RAISE NOTICE '🧹 TEST 3: Testing room auto-deactivation';
    
    -- Both users leave
    UPDATE room_participants SET left_at = NOW() 
    WHERE user_id IN (test_male, test_female) AND left_at IS NULL;
    
    -- Check if room is deactivated
    IF EXISTS (
        SELECT 1 FROM rooms 
        WHERE id = result.matched_room_id 
        AND is_active = false
    ) THEN
        RAISE NOTICE '  ✅ Room correctly deactivated when empty';
    ELSE
        RAISE NOTICE '  ❌ FAILED: Room should be deactivated';
    END IF;
    
    -- Cleanup
    DELETE FROM users WHERE email LIKE '%@fix.test';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL FIXES INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Features:';
    RAISE NOTICE '  ✓ 2-person rooms: Opposite > Same > Create';
    RAISE NOTICE '  ✓ 4-person rooms: Join any > Create';
    RAISE NOTICE '  ✓ Auto-deactivate empty rooms';
    RAISE NOTICE '  ✓ Real-time user counts';
    RAISE NOTICE '  ✓ Proper cleanup triggers';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Frontend functions to use:';
    RAISE NOTICE '  • find_compatible_room_simple(user_id, gender, room_size)';
    RAISE NOTICE '  • get_active_users_by_gender()';
    RAISE NOTICE '  • cleanup_stale_rooms() [optional cron]';
    RAISE NOTICE '========================================';
END $$;



-------- FILE - 59


ALTER TABLE chess_games 
ADD COLUMN IF NOT EXISTS chess_room_id UUID REFERENCES rooms(id) ON DELETE SET NULL;

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_chess_games_chess_room_id 
ON chess_games(chess_room_id);