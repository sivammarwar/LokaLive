-- ============================================
-- COMPLETE DATABASE SCHEMA - PRODUCTION READY
-- Video Chat + Matchmaking + Chess + Diamond System
-- Run this ONCE in Supabase SQL Editor
-- ============================================

-- Clean slate (use cautiously in production)
-- DROP SCHEMA public CASCADE;
-- CREATE SCHEMA public;
-- GRANT ALL ON SCHEMA public TO postgres;
-- GRANT ALL ON SCHEMA public TO public;

-- ============================================
-- ENUMS
-- ============================================

DO $$ BEGIN CREATE TYPE room_type AS ENUM ('public', 'private'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE gender_preference AS ENUM ('male', 'female', 'other'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE interest_category AS ENUM ('student', 'music', 'entertainment', 'friend', 'random', 'iitians', 'nitians'); EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN CREATE TYPE membership_tier AS ENUM ('free', 'premium', 'premium_plus'); EXCEPTION WHEN duplicate_object THEN null; END $$;

-- ============================================
-- TABLES
-- ============================================

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    gender gender_preference DEFAULT 'other',
    health_tokens INTEGER NOT NULL DEFAULT 5 CHECK (health_tokens >= 0 AND health_tokens <= 5),
    ban_count INTEGER NOT NULL DEFAULT 0,
    banned_until TIMESTAMPTZ,
    is_permanently_banned BOOLEAN NOT NULL DEFAULT false,
    membership_tier membership_tier NOT NULL DEFAULT 'free',
    membership_expires_at TIMESTAMPTZ,
    diamonds INTEGER NOT NULL DEFAULT 0 CHECK (diamonds >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT UNIQUE,
    room_type room_type NOT NULL DEFAULT 'public',
    room_size INTEGER NOT NULL DEFAULT 2 CHECK (room_size IN (2, 4)),
    gender_preference gender_preference,
    interest_category interest_category,
    creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    creator_gender gender_preference,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES rooms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    UNIQUE(room_id, user_id)
);

CREATE TABLE IF NOT EXISTS signaling (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES rooms(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    target_id UUID REFERENCES users(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL CHECK (message_type IN ('offer', 'answer', 'ice-candidate', 'join', 'leave')),
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chess_games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES rooms(id) ON DELETE CASCADE,
    chess_room_id UUID REFERENCES rooms(id) ON DELETE SET NULL,
    original_room_id UUID REFERENCES rooms(id) ON DELETE SET NULL,
    white_player_id UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
    black_player_id UUID REFERENCES users(id) ON DELETE SET NULL NOT NULL,
    fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    pgn TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'checkmate', 'stalemate', 'draw', 'resigned', 'abandoned')),
    winner_id UUID REFERENCES users(id) ON DELETE SET NULL,
    last_move JSONB,
    is_bet_match BOOLEAN NOT NULL DEFAULT false,
    bet_amount INTEGER CHECK (bet_amount IS NULL OR (bet_amount > 0 AND bet_amount <= 1000)),
    bet_status TEXT CHECK (bet_status IS NULL OR bet_status IN ('pending', 'locked', 'paid_out')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (white_player_id != black_player_id)
);

CREATE TABLE IF NOT EXISTS chess_signaling (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chess_game_id UUID NOT NULL REFERENCES chess_games(id) ON DELETE CASCADE,
    from_user UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user UUID NOT NULL REFERENCES users(id),
    signal_type TEXT NOT NULL,
    signal_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS diamond_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'withdrawal', 'bet_deduct', 'bet_win', 'bet_refund')),
    amount INTEGER NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS membership_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_tier membership_tier UNIQUE NOT NULL,
    price_inr DECIMAL(10, 2) NOT NULL,
    duration_days INTEGER NOT NULL DEFAULT 30,
    features JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS diamond_packages (
    id TEXT PRIMARY KEY,
    diamonds INTEGER NOT NULL,
    price_inr DECIMAL(10, 2) NOT NULL,
    bonus INTEGER DEFAULT 0,
    is_popular BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_users_gender ON users(gender) WHERE gender IN ('male', 'female');
CREATE INDEX IF NOT EXISTS idx_rooms_matchmaking ON rooms(room_type, is_active, room_size, creator_gender, gender_preference, created_at) WHERE room_type = 'public' AND is_active = true;
CREATE INDEX IF NOT EXISTS idx_room_participants_active ON room_participants(room_id, user_id, left_at) WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_signaling_room_id ON signaling(room_id);
CREATE INDEX IF NOT EXISTS idx_chess_games_room_id ON chess_games(room_id);
CREATE INDEX IF NOT EXISTS idx_chess_games_original_room ON chess_games(original_room_id);
CREATE INDEX IF NOT EXISTS idx_chess_signaling_to_user ON chess_signaling(to_user);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE signaling ENABLE ROW LEVEL SECURITY;
ALTER TABLE chess_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE chess_signaling ENABLE ROW LEVEL SECURITY;
ALTER TABLE diamond_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE membership_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE diamond_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read" ON users;
DROP POLICY IF EXISTS "Users update own" ON users;
DROP POLICY IF EXISTS "Public rooms" ON rooms;
DROP POLICY IF EXISTS "Public participants" ON room_participants;
DROP POLICY IF EXISTS "Public signaling" ON signaling;
DROP POLICY IF EXISTS "Public chess games" ON chess_games;
DROP POLICY IF EXISTS "Chess signaling access" ON chess_signaling;
DROP POLICY IF EXISTS "Own transactions" ON diamond_transactions;
DROP POLICY IF EXISTS "Public prices" ON membership_prices;
DROP POLICY IF EXISTS "Public packages" ON diamond_packages;

CREATE POLICY "Public read" ON users FOR SELECT USING (true);
CREATE POLICY "Users update own" ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Public rooms" ON rooms FOR ALL USING (true);
CREATE POLICY "Public participants" ON room_participants FOR ALL USING (true);
CREATE POLICY "Public signaling" ON signaling FOR ALL USING (true);
CREATE POLICY "Public chess games" ON chess_games FOR ALL USING (true);
CREATE POLICY "Chess signaling access" ON chess_signaling FOR ALL USING (auth.uid() IN (from_user, to_user));
CREATE POLICY "Own transactions" ON diamond_transactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Public prices" ON membership_prices FOR SELECT USING (is_active = true);
CREATE POLICY "Public packages" ON diamond_packages FOR SELECT USING (is_active = true);

-- ============================================
-- CORE FUNCTIONS
-- ============================================

-- Auto-set room code for private rooms
CREATE OR REPLACE FUNCTION set_room_code() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.room_type = 'private' AND NEW.room_code IS NULL THEN
        NEW.room_code := substr(md5(random()::text), 1, 6);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_set_room_code ON rooms;
CREATE TRIGGER trigger_set_room_code BEFORE INSERT ON rooms FOR EACH ROW EXECUTE FUNCTION set_room_code();

-- Auto-join creator to room
CREATE OR REPLACE FUNCTION auto_join_creator() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO room_participants (room_id, user_id) VALUES (NEW.id, NEW.creator_id)
    ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, joined_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_auto_join_creator ON rooms;
CREATE TRIGGER trigger_auto_join_creator AFTER INSERT ON rooms FOR EACH ROW EXECUTE FUNCTION auto_join_creator();

-- Handle new user
CREATE OR REPLACE FUNCTION handle_new_user() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO users (id, email, display_name) 
    VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Auto-deactivate full rooms
CREATE OR REPLACE FUNCTION deactivate_full_room() RETURNS TRIGGER AS $$
DECLARE v_size INT; v_count INT;
BEGIN
    IF NEW.left_at IS NULL THEN
        SELECT room_size INTO v_size FROM rooms WHERE id = NEW.room_id;
        SELECT COUNT(*) INTO v_count FROM room_participants WHERE room_id = NEW.room_id AND left_at IS NULL;
        IF v_count >= v_size THEN UPDATE rooms SET is_active = false WHERE id = NEW.room_id; END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_deactivate_full_room ON room_participants;
CREATE TRIGGER trigger_deactivate_full_room AFTER INSERT OR UPDATE ON room_participants FOR EACH ROW EXECUTE FUNCTION deactivate_full_room();

-- Auto-deactivate empty rooms
CREATE OR REPLACE FUNCTION deactivate_empty_room() RETURNS TRIGGER AS $$
DECLARE v_count INT;
BEGIN
    IF OLD.left_at IS NULL AND NEW.left_at IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count FROM room_participants WHERE room_id = NEW.room_id AND left_at IS NULL;
        IF v_count = 0 THEN UPDATE rooms SET is_active = false WHERE id = NEW.room_id; END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_deactivate_empty_room ON room_participants;
CREATE TRIGGER trigger_deactivate_empty_room AFTER UPDATE ON room_participants FOR EACH ROW EXECUTE FUNCTION deactivate_empty_room();

-- ============================================
-- MATCHMAKING FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION find_compatible_room_simple(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_room_size INTEGER
)
RETURNS TABLE(matched_room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_found UUID;
    v_created UUID;
    v_opposite gender_preference;
BEGIN
    IF p_user_gender NOT IN ('male', 'female') THEN RAISE EXCEPTION 'Gender must be male or female'; END IF;
    v_opposite := CASE WHEN p_user_gender = 'male' THEN 'female'::gender_preference ELSE 'male'::gender_preference END;
    
    UPDATE users SET gender = p_user_gender WHERE id = p_user_id;
    UPDATE room_participants SET left_at = NOW() WHERE user_id = p_user_id AND left_at IS NULL;
    
    -- Cleanup stale rooms
    UPDATE rooms SET is_active = false 
    WHERE is_active = true AND room_type = 'public' AND (
        (SELECT COUNT(*) FROM room_participants WHERE room_id = rooms.id AND left_at IS NULL) >= room_size
        OR created_at < NOW() - INTERVAL '5 minutes'
    );
    
    -- Find opposite gender room
    SELECT r.id INTO v_found FROM rooms r
    WHERE r.room_type = 'public' AND r.is_active = true AND r.room_size = p_room_size
      AND r.creator_gender = v_opposite AND r.gender_preference = p_user_gender
      AND r.creator_id != p_user_id
      AND (SELECT COUNT(*) FROM room_participants WHERE room_id = r.id AND left_at IS NULL) < p_room_size
    ORDER BY r.created_at LIMIT 1;
    
    IF v_found IS NOT NULL THEN RETURN QUERY SELECT v_found, false; RETURN; END IF;
    
    -- Find same gender room
    SELECT r.id INTO v_found FROM rooms r
    WHERE r.room_type = 'public' AND r.is_active = true AND r.room_size = p_room_size
      AND r.creator_gender = p_user_gender AND r.creator_id != p_user_id
      AND (SELECT COUNT(*) FROM room_participants WHERE room_id = r.id AND left_at IS NULL) < p_room_size
    ORDER BY r.created_at LIMIT 1;
    
    IF v_found IS NOT NULL THEN RETURN QUERY SELECT v_found, false; RETURN; END IF;
    
    -- Create new room
    INSERT INTO rooms (room_type, room_size, gender_preference, interest_category, creator_id, creator_gender, is_active)
    VALUES ('public', p_room_size, v_opposite, 'random', p_user_id, p_user_gender, true)
    RETURNING id INTO v_created;
    
    PERFORM pg_sleep(0.1);
    RETURN QUERY SELECT v_created, true;
END;
$$;

-- ============================================
-- ROOM FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION join_room_if_available(p_room_id UUID, p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_size INT; v_count INT; v_active BOOL;
BEGIN
    SELECT room_size, is_active INTO v_size, v_active FROM rooms WHERE id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'room_not_found'); END IF;
    IF NOT v_active THEN RETURN json_build_object('success', false, 'error', 'room_inactive'); END IF;
    
    SELECT COUNT(*) INTO v_count FROM room_participants WHERE room_id = p_room_id AND left_at IS NULL AND user_id != p_user_id;
    IF v_count >= v_size THEN
        UPDATE rooms SET is_active = false WHERE id = p_room_id;
        RETURN json_build_object('success', false, 'error', 'room_full');
    END IF;
    
    INSERT INTO room_participants (room_id, user_id) VALUES (p_room_id, p_user_id)
    ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, joined_at = NOW();
    
    RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INT;
BEGIN
    UPDATE room_participants SET left_at = NOW() WHERE user_id = p_user_id AND left_at IS NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION get_active_users_by_gender()
RETURNS TABLE(male_count BIGINT, female_count BIGINT)
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'male'), 0),
        COALESCE(COUNT(DISTINCT rp.user_id) FILTER (WHERE u.gender = 'female'), 0)
    FROM room_participants rp
    INNER JOIN users u ON u.id = rp.user_id
    INNER JOIN rooms r ON r.id = rp.room_id
    WHERE rp.left_at IS NULL AND r.is_active = true AND r.room_type = 'public'
      AND u.gender IN ('male', 'female');
END;
$$;

-- ============================================
-- CHESS FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION store_original_room_for_chess(p_game_id UUID, p_original_room_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE chess_games SET original_room_id = p_original_room_id WHERE id = p_game_id;
END;
$$;

CREATE OR REPLACE FUNCTION return_to_original_room(p_game_id UUID, p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_original UUID; v_chess UUID; v_active BOOL;
BEGIN
    SELECT original_room_id, chess_room_id INTO v_original, v_chess FROM chess_games WHERE id = p_game_id;
    IF v_original IS NULL THEN RETURN json_build_object('success', false, 'error', 'no_original_room'); END IF;
    
    SELECT is_active INTO v_active FROM rooms WHERE id = v_original;
    IF NOT v_active THEN RETURN json_build_object('success', false, 'error', 'room_inactive'); END IF;
    
    UPDATE room_participants SET left_at = NOW() WHERE user_id = p_user_id AND room_id = v_chess AND left_at IS NULL;
    INSERT INTO room_participants (room_id, user_id) VALUES (v_original, p_user_id)
    ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL, joined_at = NOW();
    
    RETURN json_build_object('success', true, 'original_room_id', v_original);
END;
$$;

-- ============================================
-- DIAMOND SYSTEM
-- ============================================

CREATE OR REPLACE FUNCTION add_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
    UPDATE users SET diamonds = diamonds + p_amount WHERE id = p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION deduct_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_current INT;
BEGIN
    SELECT diamonds INTO v_current FROM users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;
    IF v_current < p_amount THEN RAISE EXCEPTION 'Insufficient diamonds'; END IF;
    UPDATE users SET diamonds = diamonds - p_amount WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION deduct_bet_from_both_players(
    p_game_id UUID, p_player1_id UUID, p_player2_id UUID, p_bet_amount INTEGER
)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_d1 INT; v_d2 INT;
BEGIN
    PERFORM * FROM users WHERE id IN (p_player1_id, p_player2_id) FOR UPDATE;
    
    SELECT diamonds INTO v_d1 FROM users WHERE id = p_player1_id;
    SELECT diamonds INTO v_d2 FROM users WHERE id = p_player2_id;
    
    IF v_d1 < p_bet_amount THEN RETURN json_build_object('success', false, 'error', 'Player 1 insufficient diamonds'); END IF;
    IF v_d2 < p_bet_amount THEN RETURN json_build_object('success', false, 'error', 'Player 2 insufficient diamonds'); END IF;
    
    UPDATE users SET diamonds = diamonds - p_bet_amount WHERE id IN (p_player1_id, p_player2_id);
    INSERT INTO diamond_transactions (user_id, type, amount, description, status) VALUES
        (p_player1_id, 'bet_deduct', -p_bet_amount, 'Chess bet locked', 'completed'),
        (p_player2_id, 'bet_deduct', -p_bet_amount, 'Chess bet locked', 'completed');
    UPDATE chess_games SET bet_status = 'locked' WHERE id = p_game_id;
    
    RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION process_bet_payout(p_game_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_game RECORD; v_payout INT;
BEGIN
    SELECT * INTO v_game FROM chess_games WHERE id = p_game_id FOR UPDATE;
    IF NOT v_game.is_bet_match OR v_game.bet_status != 'locked' OR v_game.winner_id IS NULL THEN
        RETURN json_build_object('success', false);
    END IF;
    
    v_payout := v_game.bet_amount * 2;
    UPDATE users SET diamonds = diamonds + v_payout WHERE id = v_game.winner_id;
    INSERT INTO diamond_transactions (user_id, type, amount, description, status)
    VALUES (v_game.winner_id, 'bet_win', v_payout, 'Won chess bet', 'completed');
    UPDATE chess_games SET bet_status = 'paid_out' WHERE id = p_game_id;
    
    RETURN json_build_object('success', true);
END;
$$;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

-- ============================================
-- REALTIME
-- ============================================

ALTER PUBLICATION supabase_realtime ADD TABLE rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE room_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE users;
ALTER PUBLICATION supabase_realtime ADD TABLE signaling;
ALTER PUBLICATION supabase_realtime ADD TABLE chess_games;
ALTER PUBLICATION supabase_realtime ADD TABLE chess_signaling;
ALTER PUBLICATION supabase_realtime ADD TABLE diamond_transactions;

-- ============================================
-- SEED DATA
-- ============================================

INSERT INTO membership_prices (membership_tier, price_inr, duration_days, features) VALUES
('premium', 99.00, 30, '{"color": "blue", "badge": "Premium"}'::jsonb),
('premium_plus', 199.00, 30, '{"color": "golden", "badge": "Premium Plus"}'::jsonb)
ON CONFLICT (membership_tier) DO NOTHING;

INSERT INTO diamond_packages (id, diamonds, price_inr, bonus, is_popular) VALUES 
('pack_15', 15, 100.00, 0, false),
('pack_80', 80, 500.00, 5, true),
('pack_170', 170, 1000.00, 20, false)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE INSTALLATION COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Features installed:';
    RAISE NOTICE '  ✓ Video Chat Rooms (2 & 4 person)';
    RAISE NOTICE '  ✓ Gender-Based Matchmaking';
    RAISE NOTICE '  ✓ Chess Games with Betting';
    RAISE NOTICE '  ✓ Diamond System';
    RAISE NOTICE '  ✓ Premium Memberships';
    RAISE NOTICE '  ✓ WebRTC Signaling';
    RAISE NOTICE '  ✓ Auto-cleanup & Maintenance';
    RAISE NOTICE '========================================';
END $$;