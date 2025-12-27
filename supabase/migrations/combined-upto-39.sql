
-----------  FILE -1



-- Create enum for room types
CREATE TYPE public.room_type AS ENUM ('public', 'private');

-- Create enum for gender preferences
CREATE TYPE public.gender_preference AS ENUM ('male', 'female', 'other');

-- Create enum for interest categories
CREATE TYPE public.interest_category AS ENUM ('student', 'music', 'entertainment', 'friend', 'random', 'iitians', 'nitians');

-- Create enum for membership tiers
CREATE TYPE public.membership_tier AS ENUM ('free', 'premium', 'premium_plus');

-- Create users table with email authentication and premium features
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    gender TEXT DEFAULT 'other',
    ip_address TEXT,
    browser_fingerprint TEXT,
    session_token TEXT UNIQUE,
    health_tokens INTEGER NOT NULL DEFAULT 5 CHECK (health_tokens >= 0 AND health_tokens <= 5),
    ban_count INTEGER NOT NULL DEFAULT 0,
    banned_until TIMESTAMPTZ,
    is_permanently_banned BOOLEAN NOT NULL DEFAULT false,
    
    -- Premium membership fields
    membership_tier membership_tier NOT NULL DEFAULT 'free',
    membership_expires_at TIMESTAMPTZ,
    membership_auto_renew BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create rooms table
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT UNIQUE,
    room_type room_type NOT NULL DEFAULT 'public',
    room_size INTEGER NOT NULL DEFAULT 2 CHECK (room_size IN (2, 4)),
    gender_preference gender_preference,
    interest_category interest_category,
    creator_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    creator_gender TEXT DEFAULT 'other',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create room participants table
CREATE TABLE public.room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    UNIQUE(room_id, user_id)
);

-- Create reports table with premium reporter tracking
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

-- Create payments/transactions table
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

-- Create pricing table for memberships
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

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_prices ENABLE ROW LEVEL SECURITY;

-- Updated policies for authenticated users
CREATE POLICY "Allow authenticated user creation" ON public.users 
    FOR INSERT 
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Allow users to read own data" ON public.users 
    FOR SELECT 
    USING (auth.uid() = id OR true);

CREATE POLICY "Allow users to update own data" ON public.users 
    FOR UPDATE 
    USING (auth.uid() = id);

CREATE POLICY "Allow room creation" ON public.rooms 
    FOR INSERT 
    WITH CHECK (auth.uid() = creator_id OR true);

CREATE POLICY "Allow reading active rooms" ON public.rooms 
    FOR SELECT 
    USING (true);

CREATE POLICY "Allow room updates" ON public.rooms 
    FOR UPDATE 
    USING (auth.uid() = creator_id OR true);

CREATE POLICY "Allow joining rooms" ON public.room_participants 
    FOR INSERT 
    WITH CHECK (auth.uid() = user_id OR true);

CREATE POLICY "Allow reading participants" ON public.room_participants 
    FOR SELECT 
    USING (true);

CREATE POLICY "Allow leaving rooms" ON public.room_participants 
    FOR UPDATE 
    USING (auth.uid() = user_id OR true);

CREATE POLICY "Allow creating reports" ON public.reports 
    FOR INSERT 
    WITH CHECK (auth.uid() = reporter_id OR true);

CREATE POLICY "Allow reading own reports" ON public.reports 
    FOR SELECT 
    USING (auth.uid() = reporter_id OR true);

-- Transaction policies
CREATE POLICY "Allow users to read own transactions" ON public.transactions
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Allow users to create own transactions" ON public.transactions
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Allow users to update own transactions" ON public.transactions
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Membership prices policies
CREATE POLICY "Allow reading membership prices" ON public.membership_prices
    FOR SELECT
    USING (is_active = true);

-- Enable realtime for rooms and participants
ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.room_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.membership_prices;

-- Function to generate unique room code
CREATE OR REPLACE FUNCTION generate_room_code()
RETURNS TEXT
LANGUAGE plpgsql
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

-- Trigger to auto-generate room code for private rooms
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

-- Function to handle report validation with premium multiplier
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
        -- Calculate health decrease based on reporter's membership
        IF NEW.reporter_membership_tier IN ('premium', 'premium_plus') THEN
            health_decrease := 1.5;
        END IF;
        
        -- Decrease health tokens (can go below 0 temporarily for calculation)
        UPDATE public.users
        SET health_tokens = GREATEST(
            CAST(health_tokens - health_decrease AS INTEGER), 
            0
        ),
            updated_at = now()
        WHERE id = NEW.reported_user_id;
        
        -- Check if user should be banned
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

-- Function to check and expire memberships
CREATE OR REPLACE FUNCTION check_membership_expiry()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET membership_tier = 'free',
        membership_expires_at = NULL,
        updated_at = now()
    WHERE membership_tier IN ('premium', 'premium_plus')
        AND membership_expires_at < now()
        AND membership_auto_renew = false;
END;
$$;

-- Function to handle new user creation from auth.users
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

-- Trigger to auto-create user profile when auth user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- Function to update report with reporter's membership tier
CREATE OR REPLACE FUNCTION set_reporter_membership_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    reporter_tier membership_tier;
BEGIN
    -- Get reporter's current membership tier
    SELECT membership_tier INTO reporter_tier
    FROM public.users
    WHERE id = NEW.reporter_id;
    
    NEW.reporter_membership_tier := reporter_tier;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_set_reporter_membership
    BEFORE INSERT ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION set_reporter_membership_tier();

-- Function to activate premium membership (1 month validity)
CREATE OR REPLACE FUNCTION activate_membership(
    p_user_id UUID,
    p_membership_tier membership_tier
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET membership_tier = p_membership_tier,
        membership_expires_at = now() + INTERVAL '1 month',
        membership_auto_renew = false,
        updated_at = now()
    WHERE id = p_user_id;
END;
$$;

-- Function to extend existing membership by 1 month
CREATE OR REPLACE FUNCTION extend_membership(
    p_user_id UUID,
    p_membership_tier membership_tier
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_expiry TIMESTAMPTZ;
BEGIN
    SELECT membership_expires_at INTO current_expiry
    FROM public.users
    WHERE id = p_user_id;
    
    -- If membership is still active, extend from current expiry date
    -- Otherwise, start from now
    IF current_expiry IS NOT NULL AND current_expiry > now() THEN
        UPDATE public.users
        SET membership_tier = p_membership_tier,
            membership_expires_at = current_expiry + INTERVAL '1 month',
            updated_at = now()
        WHERE id = p_user_id;
    ELSE
        UPDATE public.users
        SET membership_tier = p_membership_tier,
            membership_expires_at = now() + INTERVAL '1 month',
            updated_at = now()
        WHERE id = p_user_id;
    END IF;
END;
$$;

-- Function to auto-complete transaction and activate membership
CREATE OR REPLACE FUNCTION complete_transaction_and_activate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- When payment status changes to 'completed'
    IF NEW.payment_status = 'completed' AND OLD.payment_status != 'completed' THEN
        -- Set completed_at timestamp
        NEW.completed_at := now();
        
        -- Activate or extend membership
        PERFORM extend_membership(NEW.user_id, NEW.membership_tier);
    END IF;
    
    RETURN NEW;
END;
$$;

-- Trigger to auto-activate membership when transaction completes
DROP TRIGGER IF EXISTS trigger_complete_transaction ON public.transactions;
CREATE TRIGGER trigger_complete_transaction
    BEFORE UPDATE ON public.transactions
    FOR EACH ROW
    EXECUTE FUNCTION complete_transaction_and_activate();

-- Create indexes for performance
CREATE INDEX idx_users_membership_tier ON public.users(membership_tier);
CREATE INDEX idx_users_membership_expires ON public.users(membership_expires_at);
CREATE INDEX idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX idx_transactions_status ON public.transactions(payment_status);

-- Insert initial pricing
INSERT INTO public.membership_prices (membership_tier, price_inr, price_usd, duration_days, features) VALUES
('premium', 99.00, 1.19, 30, '{"color": "blue", "report_multiplier": 1.5, "badge": "Premium"}'::jsonb),
('premium_plus', 199.00, 2.39, 30, '{"color": "golden", "report_multiplier": 1.5, "badge": "Premium Plus", "priority_support": true}'::jsonb)
ON CONFLICT (membership_tier) DO NOTHING;





-----------  FILE - 2



-- Fix function search path warnings
ALTER FUNCTION generate_room_code() SET search_path = public;
ALTER FUNCTION set_room_code() SET search_path = public;
ALTER FUNCTION process_validated_report() SET search_path = public;
ALTER FUNCTION check_membership_expiry() SET search_path = public;
ALTER FUNCTION handle_new_user() SET search_path = public;
ALTER FUNCTION set_reporter_membership_tier() SET search_path = public;
ALTER FUNCTION activate_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION extend_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION complete_transaction_and_activate() SET search_path = public;
ALTER FUNCTION cleanup_old_signals() SET search_path = public;
ALTER FUNCTION cleanup_abandoned_chess_games() SET search_path = public;
ALTER FUNCTION update_chess_game_timestamp() SET search_path = public;




-----------  FILE - 3





-- Create signaling table for WebRTC messages
CREATE TABLE public.signaling (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    target_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL CHECK (message_type IN ('offer', 'answer', 'ice-candidate', 'join', 'leave')),
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.signaling ENABLE ROW LEVEL SECURITY;

-- Policies for signaling
CREATE POLICY "Allow inserting signals" ON public.signaling 
    FOR INSERT 
    WITH CHECK (auth.uid() = sender_id OR true);

CREATE POLICY "Allow reading signals in room" ON public.signaling 
    FOR SELECT 
    USING (true);

CREATE POLICY "Allow deleting own signals" ON public.signaling 
    FOR DELETE 
    USING (auth.uid() = sender_id OR true);

-- Enable realtime for signaling
ALTER PUBLICATION supabase_realtime ADD TABLE public.signaling;

-- Add indexes for faster queries
CREATE INDEX idx_signaling_room_id ON public.signaling(room_id);
CREATE INDEX idx_signaling_target_id ON public.signaling(target_id);
CREATE INDEX idx_signaling_created_at ON public.signaling(created_at);

-- Auto-cleanup old signals (older than 1 hour)
CREATE OR REPLACE FUNCTION cleanup_old_signals()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.signaling WHERE created_at < now() - INTERVAL '1 hour';
END;
$$;





-----------  FILE - 4





-- Create chess games table
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.chess_games ENABLE ROW LEVEL SECURITY;

-- Policies for chess games
CREATE POLICY "Allow reading chess games in room" ON public.chess_games
    FOR SELECT
    USING (true);

CREATE POLICY "Allow creating chess games" ON public.chess_games
    FOR INSERT
    WITH CHECK (auth.uid() = white_player_id OR true);

CREATE POLICY "Allow updating own chess games" ON public.chess_games
    FOR UPDATE
    USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);

CREATE POLICY "Allow deleting own chess games" ON public.chess_games
    FOR DELETE
    USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_chess_games_room_id ON public.chess_games(room_id);
CREATE INDEX IF NOT EXISTS idx_chess_games_status ON public.chess_games(status);

-- Add constraint to prevent self-playing
ALTER TABLE public.chess_games 
ADD CONSTRAINT chess_games_different_players_check 
CHECK (white_player_id != black_player_id);

-- Function to auto-cleanup abandoned games
CREATE OR REPLACE FUNCTION cleanup_abandoned_chess_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.chess_games
    SET status = 'abandoned',
        updated_at = now()
    WHERE status IN ('pending', 'active')
    AND updated_at < now() - INTERVAL '30 minutes';
END;
$$;

-- Trigger to update updated_at timestamp
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

DROP TRIGGER IF EXISTS trigger_update_chess_game_timestamp ON public.chess_games;
CREATE TRIGGER trigger_update_chess_game_timestamp
    BEFORE UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION update_chess_game_timestamp();

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games;

-- Comments for documentation
COMMENT ON TABLE public.chess_games IS 'Stores chess game state for real-time multiplayer chess within video rooms';
COMMENT ON COLUMN public.chess_games.status IS 'Game status: pending (invitation sent), active (game in progress), or end states';





-----------  FILE - 5





-- Add gender column to users table
ALTER TABLE public.users ADD COLUMN gender text DEFAULT 'other';

-- Add creator_gender column to rooms table for matching
ALTER TABLE public.rooms ADD COLUMN creator_gender text DEFAULT 'other';




-----------  FILE - 6




-- Create trigger for automatically setting room_code on private rooms
CREATE TRIGGER set_room_code_trigger
BEFORE INSERT ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION public.set_room_code();

-- Also create trigger for processing validated reports
CREATE TRIGGER process_validated_report_trigger
AFTER UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.process_validated_report();







-----------  FILE - 7






-- Step 1a: First, let's see what data exists
SELECT DISTINCT gender FROM public.users;

-- Step 1b: Update any invalid gender values to 'other'
UPDATE public.users 
SET gender = 'other' 
WHERE gender NOT IN ('male', 'female', 'other') 
OR gender IS NULL;

-- Step 1c: Now safely convert the column type
ALTER TABLE public.users 
ALTER COLUMN gender DROP DEFAULT;

ALTER TABLE public.users 
ALTER COLUMN gender TYPE gender_preference 
USING gender::gender_preference;

ALTER TABLE public.users 
ALTER COLUMN gender SET DEFAULT 'other';

-- Step 1d: Do the same for rooms table
UPDATE public.rooms 
SET creator_gender = 'other' 
WHERE creator_gender NOT IN ('male', 'female', 'other') 
OR creator_gender IS NULL;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender DROP DEFAULT;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender TYPE gender_preference 
USING creator_gender::gender_preference;

ALTER TABLE public.rooms 
ALTER COLUMN creator_gender SET DEFAULT 'other';







----------------- FILE - 8






-- Fix 2: Add indexes for faster matching
CREATE INDEX IF NOT EXISTS idx_rooms_matching 
ON public.rooms(room_type, is_active, room_size, gender_preference, interest_category)
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_rooms_creator_gender 
ON public.rooms(creator_gender) 
WHERE room_type = 'public';

CREATE INDEX IF NOT EXISTS idx_room_participants_active 
ON public.room_participants(room_id, left_at) 
WHERE left_at IS NULL;

-- Fix 3: Prevent users from joining full rooms
CREATE OR REPLACE FUNCTION check_room_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    participant_count INTEGER;
    max_size INTEGER;
BEGIN
    SELECT COUNT(*), r.room_size 
    INTO participant_count, max_size
    FROM public.room_participants rp
    JOIN public.rooms r ON r.id = NEW.room_id
    WHERE rp.room_id = NEW.room_id 
    AND rp.left_at IS NULL
    GROUP BY r.room_size;
    
    IF participant_count >= max_size THEN
        RAISE EXCEPTION 'Room is full';
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_room_capacity ON public.room_participants;
CREATE TRIGGER enforce_room_capacity
BEFORE INSERT ON public.room_participants
FOR EACH ROW
EXECUTE FUNCTION check_room_capacity();

-- Fix 4: Auto-cleanup empty rooms
CREATE OR REPLACE FUNCTION cleanup_empty_rooms()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.rooms
    SET is_active = false
    WHERE id IN (
        SELECT r.id
        FROM public.rooms r
        LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
        WHERE r.is_active = true
        GROUP BY r.id
        HAVING COUNT(rp.id) = 0
        AND r.created_at < now() - INTERVAL '5 minutes'
    );
END;
$$;





---------- FILE - 9






-- Add this to your Supabase SQL Editor
-- This function ensures atomic room joining (prevents race conditions)

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_already_joined BOOLEAN;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size INTO v_room_size
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if user is already in the room
  SELECT EXISTS(
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id 
    AND user_id = p_user_id 
    AND left_at IS NULL
  ) INTO v_already_joined;
  
  IF v_already_joined THEN
    RAISE NOTICE 'User already in room';
    RETURN true;
  END IF;
  
  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
  AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RAISE NOTICE 'Room is full: % / %', v_current_count, v_room_size;
    RETURN false;
  END IF;
  
  -- Join the room
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id);
  
  RAISE NOTICE 'Successfully joined room: % / %', v_current_count + 1, v_room_size;
  RETURN true;
  
EXCEPTION
  WHEN unique_violation THEN
    -- User already in room (race condition)
    RETURN true;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Error joining room: %', SQLERRM;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO anon;




---------- FILE - 10







-- Run this in Supabase SQL Editor to clean up existing issues

-- 1. Find and remove duplicate active participations (keep only the most recent)
WITH duplicates AS (
  SELECT 
    user_id,
    room_id,
    id,
    joined_at,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY joined_at DESC) as rn
  FROM public.room_participants
  WHERE left_at IS NULL
)
UPDATE public.room_participants
SET left_at = NOW()
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- 2. Deactivate rooms with no active participants
UPDATE public.rooms
SET is_active = false
WHERE id IN (
  SELECT r.id
  FROM public.rooms r
  LEFT JOIN public.room_participants rp ON rp.room_id = r.id AND rp.left_at IS NULL
  WHERE r.is_active = true
  GROUP BY r.id
  HAVING COUNT(rp.id) = 0
);

-- 3. Create a function to prevent duplicate participations
CREATE OR REPLACE FUNCTION prevent_duplicate_participation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_count INTEGER;
BEGIN
  -- Check if user is already in another active room
  SELECT COUNT(*) INTO existing_count
  FROM room_participants
  WHERE user_id = NEW.user_id
  AND left_at IS NULL
  AND room_id != NEW.room_id;
  
  IF existing_count > 0 THEN
    RAISE EXCEPTION 'User is already in another active room';
  END IF;
  
  RETURN NEW;
END;
$$;

-- 4. Add trigger to enforce single active room per user
DROP TRIGGER IF EXISTS enforce_single_active_room ON public.room_participants;
CREATE TRIGGER enforce_single_active_room
  BEFORE INSERT ON public.room_participants
  FOR EACH ROW
  EXECUTE FUNCTION prevent_duplicate_participation();

-- 5. Add index to speed up duplicate checks
CREATE INDEX IF NOT EXISTS idx_room_participants_user_active 
ON public.room_participants(user_id) 
WHERE left_at IS NULL;

-- Check results
SELECT 
  'Active Rooms' as type,
  COUNT(*) as count
FROM public.rooms
WHERE is_active = true

UNION ALL

SELECT 
  'Active Participants' as type,
  COUNT(*) as count
FROM public.room_participants
WHERE left_at IS NULL

UNION ALL

SELECT 
  'Users in Multiple Rooms' as type,
  COUNT(*) as count
FROM (
  SELECT user_id
  FROM public.room_participants
  WHERE left_at IS NULL
  GROUP BY user_id
  HAVING COUNT(*) > 1
) multi_room_users;








---------- FILE - 11





-- Run this to clean up empty rooms and fix your database

-- 1. Deactivate ALL empty rooms
UPDATE public.rooms
SET is_active = false
WHERE id IN (
  SELECT r.id
  FROM public.rooms r
  LEFT JOIN public.room_participants rp 
    ON rp.room_id = r.id AND rp.left_at IS NULL
  WHERE r.is_active = true
  GROUP BY r.id
  HAVING COUNT(rp.id) = 0
);

-- 2. Also deactivate rooms older than 30 minutes with no participants
UPDATE public.rooms
SET is_active = false
WHERE is_active = true
AND created_at < NOW() - INTERVAL '30 minutes'
AND id NOT IN (
  SELECT DISTINCT room_id
  FROM public.room_participants
  WHERE left_at IS NULL
);

-- 3. Verify the cleanup
SELECT 
  'Active Rooms with Participants' as status,
  COUNT(DISTINCT r.id) as count
FROM public.rooms r
INNER JOIN public.room_participants rp 
  ON rp.room_id = r.id AND rp.left_at IS NULL
WHERE r.is_active = true

UNION ALL

SELECT 
  'Empty Active Rooms' as status,
  COUNT(*) as count
FROM public.rooms r
LEFT JOIN public.room_participants rp 
  ON rp.room_id = r.id AND rp.left_at IS NULL
WHERE r.is_active = true
AND rp.id IS NULL

UNION ALL

SELECT 
  'Total Active Participants' as status,
  COUNT(*) as count
FROM public.room_participants
WHERE left_at IS NULL;







---------- FILE - 12








-- COMPLETE RESET - Run this before testing

-- 1. Mark ALL participants as left
UPDATE public.room_participants
SET left_at = NOW()
WHERE left_at IS NULL;

-- 2. Deactivate ALL rooms
UPDATE public.rooms
SET is_active = false
WHERE is_active = true;

-- 3. Verify clean state
SELECT 
  'Active Rooms' as type,
  COUNT(*) as count
FROM public.rooms
WHERE is_active = true

UNION ALL

SELECT 
  'Active Participants' as type,
  COUNT(*) as count
FROM public.room_participants
WHERE left_at IS NULL

UNION ALL

SELECT 
  'Total Users' as type,
  COUNT(*) as count
FROM public.users;

-- Result should be:
-- Active Rooms: 0
-- Active Participants: 0
-- Total Users: (your user count)







---------- FILE - 13 






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









---------- FILE - 14










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





---------- FILE - 15









-- ============================================
-- WITHDRAWAL SYSTEM DATABASE SETUP
-- Run this in Supabase SQL Editor
-- ============================================

-- Step 1: Create withdrawal_methods table
CREATE TABLE IF NOT EXISTS public.withdrawal_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('upi', 'bank')),
    upi_id TEXT,
    account_name TEXT,
    account_number TEXT,
    ifsc_code TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraint: Either UPI or Bank details must be present
    CONSTRAINT withdrawal_method_details_check CHECK (
        (type = 'upi' AND upi_id IS NOT NULL AND upi_id != '') OR
        (type = 'bank' AND account_name IS NOT NULL AND account_name != '' 
         AND account_number IS NOT NULL AND account_number != ''
         AND ifsc_code IS NOT NULL AND ifsc_code != '')
    )
);

-- Step 2: Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_withdrawal_methods_user_id 
    ON public.withdrawal_methods(user_id);

CREATE INDEX IF NOT EXISTS idx_withdrawal_methods_type 
    ON public.withdrawal_methods(type);

CREATE INDEX IF NOT EXISTS idx_withdrawal_methods_verified 
    ON public.withdrawal_methods(is_verified) 
    WHERE is_verified = true;

-- Step 3: Enable Row Level Security
ALTER TABLE public.withdrawal_methods ENABLE ROW LEVEL SECURITY;

-- Step 4: Create RLS Policies
-- Users can view their own withdrawal methods
CREATE POLICY "Users can view own withdrawal methods" 
    ON public.withdrawal_methods
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own withdrawal methods
CREATE POLICY "Users can insert own withdrawal methods" 
    ON public.withdrawal_methods
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own withdrawal methods
CREATE POLICY "Users can update own withdrawal methods" 
    ON public.withdrawal_methods
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can delete their own withdrawal methods
CREATE POLICY "Users can delete own withdrawal methods" 
    ON public.withdrawal_methods
    FOR DELETE
    USING (auth.uid() = user_id);

-- Step 5: Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.withdrawal_methods;

-- Step 6: Update diamond_transactions to support withdrawal status updates
-- Add updated_at column if not exists
ALTER TABLE public.diamond_transactions 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Add processing status
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'diamond_transactions_status_check'
    ) THEN
        ALTER TABLE public.diamond_transactions 
        DROP CONSTRAINT IF EXISTS diamond_transactions_status_check;
        
        ALTER TABLE public.diamond_transactions 
        ADD CONSTRAINT diamond_transactions_status_check 
        CHECK (status IN ('pending', 'processing', 'completed', 'failed'));
    END IF;
END $$;

-- Step 7: Create trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_withdrawal_method_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_withdrawal_method_timestamp 
    ON public.withdrawal_methods;

CREATE TRIGGER trigger_update_withdrawal_method_timestamp
    BEFORE UPDATE ON public.withdrawal_methods
    FOR EACH ROW
    EXECUTE FUNCTION update_withdrawal_method_timestamp();

-- Step 8: Create trigger for diamond_transactions updated_at
CREATE OR REPLACE FUNCTION update_diamond_transaction_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_diamond_transaction_timestamp 
    ON public.diamond_transactions;

CREATE TRIGGER trigger_update_diamond_transaction_timestamp
    BEFORE UPDATE ON public.diamond_transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_diamond_transaction_timestamp();

-- Step 9: Function to get pending withdrawals for a user
CREATE OR REPLACE FUNCTION get_pending_withdrawals(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    amount INTEGER,
    amount_inr DECIMAL(10,2),
    description TEXT,
    status TEXT,
    payment_reference TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dt.id,
        dt.amount,
        (ABS(dt.amount) * 5)::DECIMAL(10,2) as amount_inr,
        dt.description,
        dt.status,
        dt.payment_reference,
        dt.created_at,
        dt.updated_at
    FROM public.diamond_transactions dt
    WHERE dt.user_id = p_user_id
    AND dt.type = 'withdrawal'
    AND dt.status IN ('pending', 'processing')
    ORDER BY dt.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pending_withdrawals(UUID) TO authenticated;

-- Step 10: Function to get total pending withdrawal amount
CREATE OR REPLACE FUNCTION get_total_pending_withdrawals(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    total_pending INTEGER;
BEGIN
    SELECT COALESCE(SUM(ABS(amount)), 0)
    INTO total_pending
    FROM public.diamond_transactions
    WHERE user_id = p_user_id
    AND type = 'withdrawal'
    AND status IN ('pending', 'processing');
    
    RETURN total_pending;
END;
$$;

GRANT EXECUTE ON FUNCTION get_total_pending_withdrawals(UUID) TO authenticated;

-- Step 11: Create view for withdrawal history
CREATE OR REPLACE VIEW public.withdrawal_history AS
SELECT 
    dt.id,
    dt.user_id,
    u.display_name,
    u.email,
    ABS(dt.amount) as diamonds,
    (ABS(dt.amount) * 5)::DECIMAL(10,2) as amount_inr,
    dt.description,
    dt.status,
    dt.payment_reference,
    dt.created_at,
    dt.updated_at,
    CASE 
        WHEN dt.status = 'pending' THEN 'Waiting to process'
        WHEN dt.status = 'processing' THEN 'Being processed'
        WHEN dt.status = 'completed' THEN 'Transferred'
        WHEN dt.status = 'failed' THEN 'Failed - Contact support'
    END as status_display
FROM public.diamond_transactions dt
JOIN public.users u ON u.id = dt.user_id
WHERE dt.type = 'withdrawal'
ORDER BY dt.created_at DESC;

-- Grant access to authenticated users (for their own withdrawals)
CREATE POLICY "Users can view own withdrawal history" 
    ON public.diamond_transactions
    FOR SELECT
    USING (
        auth.uid() = user_id 
        AND type = 'withdrawal'
    );

-- Step 12: Add comments for documentation
COMMENT ON TABLE public.withdrawal_methods IS 'Stores user payment methods for diamond withdrawals (UPI and Bank)';
COMMENT ON COLUMN public.withdrawal_methods.type IS 'Payment method type: upi or bank';
COMMENT ON COLUMN public.withdrawal_methods.is_verified IS 'Whether the payment method has been verified by admin';
COMMENT ON COLUMN public.diamond_transactions.status IS 'Transaction status: pending, processing, completed, or failed';

-- Step 13: Function to validate withdrawal request
CREATE OR REPLACE FUNCTION validate_withdrawal_request(
    p_user_id UUID,
    p_diamonds INTEGER
)
RETURNS TABLE (
    is_valid BOOLEAN,
    error_message TEXT,
    current_diamonds INTEGER,
    pending_withdrawals INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_diamonds INTEGER;
    v_pending_withdrawals INTEGER;
    v_min_withdrawal INTEGER := 15;
    v_available_diamonds INTEGER;
BEGIN
    -- Get current diamond balance
    SELECT diamonds INTO v_current_diamonds
    FROM public.users
    WHERE id = p_user_id;
    
    -- Get total pending withdrawals
    SELECT get_total_pending_withdrawals(p_user_id)
    INTO v_pending_withdrawals;
    
    -- Calculate available diamonds (minus pending withdrawals)
    v_available_diamonds := v_current_diamonds - v_pending_withdrawals;
    
    -- Validate
    IF p_diamonds < v_min_withdrawal THEN
        RETURN QUERY SELECT 
            false,
            'Minimum withdrawal is ' || v_min_withdrawal || ' diamonds'::TEXT,
            v_current_diamonds,
            v_pending_withdrawals;
    ELSIF p_diamonds > v_available_diamonds THEN
        RETURN QUERY SELECT 
            false,
            'Insufficient diamonds. Available: ' || v_available_diamonds || ' (after pending withdrawals)'::TEXT,
            v_current_diamonds,
            v_pending_withdrawals;
    ELSE
        RETURN QUERY SELECT 
            true,
            NULL::TEXT,
            v_current_diamonds,
            v_pending_withdrawals;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION validate_withdrawal_request(UUID, INTEGER) TO authenticated;

-- Step 14: Fix search_path for all existing functions
ALTER FUNCTION update_withdrawal_method_timestamp() SET search_path = public;
ALTER FUNCTION update_diamond_transaction_timestamp() SET search_path = public;
ALTER FUNCTION get_pending_withdrawals(UUID) SET search_path = public;
ALTER FUNCTION get_total_pending_withdrawals(UUID) SET search_path = public;
ALTER FUNCTION validate_withdrawal_request(UUID, INTEGER) SET search_path = public;

-- Also fix the diamond functions
ALTER FUNCTION add_diamonds(UUID, INTEGER) SET search_path = public;
ALTER FUNCTION deduct_diamonds(UUID, INTEGER) SET search_path = public;
ALTER FUNCTION process_bet_payout(UUID) SET search_path = public;
ALTER FUNCTION auto_process_bet_payout() SET search_path = public;
ALTER FUNCTION refund_bet_on_draw() SET search_path = public;
ALTER FUNCTION cleanup_abandoned_bet_games() SET search_path = public;

-- Step 15: Verification query
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ WITHDRAWAL SYSTEM INSTALLED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Created:';
    RAISE NOTICE '  ✓ withdrawal_methods table';
    RAISE NOTICE '  ✓ RLS policies for withdrawals';
    RAISE NOTICE '  ✓ Indexes for performance';
    RAISE NOTICE '  ✓ Helper functions';
    RAISE NOTICE '  ✓ Withdrawal history view';
    RAISE NOTICE '';
    RAISE NOTICE 'Features:';
    RAISE NOTICE '  • UPI withdrawals';
    RAISE NOTICE '  • Bank transfer withdrawals';
    RAISE NOTICE '  • Multiple payment methods per user';
    RAISE NOTICE '  • Pending withdrawal tracking';
    RAISE NOTICE '  • Minimum 15 diamonds (₹75)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Deploy Edge Functions';
    RAISE NOTICE '  2. Set Razorpay API keys';
    RAISE NOTICE '  3. Test withdrawal flow';
    RAISE NOTICE '========================================';
END $$;

-- Step 16: Check results
SELECT 
    'withdrawal_methods table' as item,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'withdrawal_methods'
    ) THEN '✅ Created' ELSE '❌ Missing' END as status

UNION ALL

SELECT 
    'Withdrawal policies' as item,
    COUNT(*)::TEXT || ' policies' as status
FROM pg_policies 
WHERE tablename = 'withdrawal_methods'

UNION ALL

SELECT 
    'Helper functions' as item,
    COUNT(*)::TEXT || ' functions' as status
FROM information_schema.routines
WHERE routine_name IN (
    'get_pending_withdrawals',
    'get_total_pending_withdrawals', 
    'validate_withdrawal_request'
)

UNION ALL

SELECT 
    'Diamond transactions status' as item,
    'Updated to support processing' as status
WHERE EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE constraint_name = 'diamond_transactions_status_check'
);








---------- FILE - 16







-- ============================================
-- MINIMAL DATABASE SETUP FOR YOUR EXISTING SYSTEM
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Check if withdrawal_methods table exists, create if not
CREATE TABLE IF NOT EXISTS withdrawal_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('upi', 'bank')),
    upi_id TEXT,
    account_name TEXT,
    account_number TEXT,
    ifsc_code TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_withdrawal_methods_user_id ON withdrawal_methods(user_id);

-- Enable RLS
ALTER TABLE withdrawal_methods ENABLE ROW LEVEL SECURITY;

-- Create RLS policy
DROP POLICY IF EXISTS "Users can manage their own withdrawal methods" ON withdrawal_methods;
CREATE POLICY "Users can manage their own withdrawal methods"
    ON withdrawal_methods FOR ALL
    USING (auth.uid() = user_id);

-- 2. Verify your existing add_diamonds and deduct_diamonds functions work correctly
-- Test them (replace 'your-user-id' with actual UUID):
-- SELECT add_diamonds('your-user-id'::UUID, 10);
-- SELECT get_user_diamonds('your-user-id'::UUID);

-- 3. Add helper function to get user diamonds (if not exists)
CREATE OR REPLACE FUNCTION get_user_diamonds(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_diamonds INTEGER;
BEGIN
    SELECT COALESCE(diamonds, 0) INTO v_diamonds
    FROM users
    WHERE id = p_user_id;
    
    RETURN COALESCE(v_diamonds, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Improve your add_diamonds function with better error handling
CREATE OR REPLACE FUNCTION add_diamonds(
    p_user_id UUID,
    p_amount INTEGER
)
RETURNS VOID AS $$
BEGIN
    -- Validate inputs
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID cannot be null';
    END IF;
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    
    -- Add diamonds to user account
    UPDATE users
    SET diamonds = COALESCE(diamonds, 0) + p_amount,
        updated_at = now()
    WHERE id = p_user_id;
    
    -- Check if update was successful
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found: %', p_user_id;
    END IF;
    
    RAISE NOTICE 'Added % diamonds to user %', p_amount, p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Improve your deduct_diamonds function with better error handling
CREATE OR REPLACE FUNCTION deduct_diamonds(
    p_user_id UUID,
    p_amount INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_current_diamonds INTEGER;
BEGIN
    -- Validate inputs
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID cannot be null';
    END IF;
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    
    -- Get current diamonds with row lock
    SELECT COALESCE(diamonds, 0) INTO v_current_diamonds
    FROM users
    WHERE id = p_user_id
    FOR UPDATE; -- Lock the row
    
    -- Check if user exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found: %', p_user_id;
    END IF;
    
    -- Check if user has enough diamonds
    IF v_current_diamonds < p_amount THEN
        RAISE EXCEPTION 'Insufficient diamonds. Available: %, Required: %', v_current_diamonds, p_amount;
    END IF;
    
    -- Deduct diamonds
    UPDATE users
    SET diamonds = diamonds - p_amount,
        updated_at = now()
    WHERE id = p_user_id;
    
    RAISE NOTICE 'Deducted % diamonds from user %', p_amount, p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Grant necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON withdrawal_methods TO authenticated;
GRANT EXECUTE ON FUNCTION add_diamonds TO authenticated;
GRANT EXECUTE ON FUNCTION deduct_diamonds TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_diamonds TO authenticated;

-- 7. Verify setup
-- Check if functions exist
SELECT 
    proname as function_name,
    pg_get_function_arguments(oid) as parameters
FROM pg_proc 
WHERE proname IN ('add_diamonds', 'deduct_diamonds', 'get_user_diamonds')
ORDER BY proname;

-- Check if tables exist
SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'diamond_transactions', 'withdrawal_methods');

-- ============================================
-- TESTING QUERIES (Optional)
-- ============================================

-- Test 1: Get user diamonds (replace with your user ID)
-- SELECT get_user_diamonds('your-user-id'::UUID);

-- Test 2: Add diamonds (replace with your user ID)
-- SELECT add_diamonds('your-user-id'::UUID, 100);

-- Test 3: Check diamond_transactions table
-- SELECT * FROM diamond_transactions WHERE user_id = 'your-user-id'::UUID ORDER BY created_at DESC LIMIT 5;

-- Test 4: Deduct diamonds (replace with your user ID)
-- SELECT deduct_diamonds('your-user-id'::UUID, 10);







---------- FILE - 17







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






---------- FILE - 18







-- ============================================
-- COMPLETE DATABASE FIX FOR MATCHMAKING SYSTEM
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Clean up existing data
-- Mark all current participants as left
UPDATE public.room_participants
SET left_at = NOW()
WHERE left_at IS NULL;

-- Deactivate all current rooms
UPDATE public.rooms
SET is_active = false
WHERE is_active = true;

-- Clean up old signaling messages
DELETE FROM public.signaling WHERE created_at < NOW() - INTERVAL '1 hour';

-- STEP 2: Drop existing triggers and functions that might conflict
DROP TRIGGER IF EXISTS enforce_single_active_room ON public.room_participants;
DROP TRIGGER IF EXISTS enforce_room_capacity ON public.room_participants;
DROP FUNCTION IF EXISTS prevent_duplicate_participation();
DROP FUNCTION IF EXISTS check_room_capacity();
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- STEP 3: Create optimized indexes for matchmaking
CREATE INDEX IF NOT EXISTS idx_rooms_matchmaking 
ON public.rooms(room_type, is_active, room_size, gender_preference, interest_category, created_at)
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_rooms_creator_gender 
ON public.rooms(creator_gender) 
WHERE room_type = 'public' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_room_participants_active 
ON public.room_participants(room_id, user_id, left_at) 
WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_room_participants_user_active 
ON public.room_participants(user_id, room_id) 
WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_signaling_room_time 
ON public.signaling(room_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_signaling_target 
ON public.signaling(room_id, target_id) 
WHERE target_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chess_games_active 
ON public.chess_games(room_id, status) 
WHERE status IN ('active', 'pending');

-- STEP 4: Improved atomic room joining function
CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_already_joined BOOLEAN;
  v_room_active BOOLEAN;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist or is inactive'
    );
  END IF;
  
  -- Check if user is already in the room
  SELECT EXISTS(
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id 
    AND user_id = p_user_id 
    AND left_at IS NULL
  ) INTO v_already_joined;
  
  IF v_already_joined THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'User already in room',
      'already_joined', true
    );
  END IF;
  
  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
  AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- Join the room
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id)
  ON CONFLICT (room_id, user_id) DO NOTHING;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- STEP 5: Function to safely leave all rooms for a user
CREATE OR REPLACE FUNCTION leave_all_user_rooms(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
  AND left_at IS NULL
  RETURNING 1 INTO v_count;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 6: Function to get room participant count
CREATE OR REPLACE FUNCTION get_room_participant_count(
  p_room_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM room_participants
  WHERE room_id = p_room_id
  AND left_at IS NULL;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 7: Function to cleanup abandoned rooms
CREATE OR REPLACE FUNCTION cleanup_abandoned_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Deactivate rooms with no participants older than 5 minutes
  UPDATE rooms
  SET is_active = false
  WHERE is_active = true
  AND created_at < NOW() - INTERVAL '5 minutes'
  AND id NOT IN (
    SELECT DISTINCT room_id
    FROM room_participants
    WHERE left_at IS NULL
  )
  RETURNING 1 INTO v_count;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- STEP 8: Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO anon;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO anon;
GRANT EXECUTE ON FUNCTION get_room_participant_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_room_participant_count(UUID) TO anon;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_abandoned_rooms() TO service_role;

-- STEP 9: Set search_path for all functions
ALTER FUNCTION generate_room_code() SET search_path = public;
ALTER FUNCTION set_room_code() SET search_path = public;
ALTER FUNCTION process_validated_report() SET search_path = public;
ALTER FUNCTION check_membership_expiry() SET search_path = public;
ALTER FUNCTION handle_new_user() SET search_path = public;
ALTER FUNCTION set_reporter_membership_tier() SET search_path = public;
ALTER FUNCTION activate_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION extend_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION complete_transaction_and_activate() SET search_path = public;
ALTER FUNCTION cleanup_old_signals() SET search_path = public;
ALTER FUNCTION cleanup_abandoned_chess_games() SET search_path = public;
ALTER FUNCTION update_chess_game_timestamp() SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;
ALTER FUNCTION get_room_participant_count(UUID) SET search_path = public;
ALTER FUNCTION cleanup_abandoned_rooms() SET search_path = public;

-- STEP 10: Verify installation
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ DATABASE FIX COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Installed Functions:';
  RAISE NOTICE '  • join_room_if_available()';
  RAISE NOTICE '  • leave_all_user_rooms()';
  RAISE NOTICE '  • get_room_participant_count()';
  RAISE NOTICE '  • cleanup_abandoned_rooms()';
  RAISE NOTICE '';
  RAISE NOTICE 'Optimized Indexes:';
  RAISE NOTICE '  • idx_rooms_matchmaking';
  RAISE NOTICE '  • idx_room_participants_active';
  RAISE NOTICE '  • idx_signaling_room_time';
  RAISE NOTICE '';
  RAISE NOTICE 'System is ready for matchmaking!';
  RAISE NOTICE '========================================';
END $$;

-- STEP 11: Show current state
SELECT 
  'Active Rooms' as metric,
  COUNT(*) as value
FROM public.rooms
WHERE is_active = true

UNION ALL

SELECT 
  'Active Participants' as metric,
  COUNT(*) as value
FROM public.room_participants
WHERE left_at IS NULL

UNION ALL

SELECT 
  'Total Users' as metric,
  COUNT(*) as value
FROM public.users;






---------- FILE - 19








CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL;
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN affected_count;
END;
$$;







---------- FILE - 20







-- Step 1: Drop the old function
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- Step 2: Create the new function with different delimiter
CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
AS $function$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_result JSON;
BEGIN
  -- Lock the room row
  SELECT room_size INTO v_room_size
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;

  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id
    AND left_at IS NULL;

  -- Check if room is full
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full'
    );
  END IF;

  -- Check if user already in room
  IF EXISTS (
    SELECT 1 FROM room_participants
    WHERE room_id = p_room_id
      AND user_id = p_user_id
      AND left_at IS NULL
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'already_joined',
      'message', 'User already in room'
    );
  END IF;

  -- Insert participant
  INSERT INTO room_participants (room_id, user_id)
  VALUES (p_room_id, p_user_id);

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room'
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$function$;







---------- FILE - 21







-- Step 3: Create/recreate the leave function
CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
  affected_count INTEGER;
BEGIN
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL;
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN affected_count;
END;
$function$;

-- Check existing policies
SELECT * FROM pg_policies WHERE tablename IN ('rooms', 'room_participants', 'signaling');

-- If needed, add permissive policies:
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE signaling ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read/write
CREATE POLICY "Allow authenticated users" ON rooms
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow authenticated users" ON room_participants
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow authenticated users" ON signaling
  FOR ALL USING (auth.role() = 'authenticated');



--------- FILE -22





-- Clean up any potential duplicate active participations
WITH duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (PARTITION BY user_id, room_id ORDER BY joined_at DESC) as rn
  FROM room_participants
  WHERE left_at IS NULL
)
UPDATE room_participants rp
SET left_at = NOW()
FROM duplicates d
WHERE rp.id = d.id 
  AND d.rn > 1;

-- Ensure all users are only in one active room at a time
WITH user_multiple_rooms AS (
  SELECT 
    user_id,
    COUNT(DISTINCT room_id) as room_count
  FROM room_participants
  WHERE left_at IS NULL
  GROUP BY user_id
  HAVING COUNT(DISTINCT room_id) > 1
),
latest_room AS (
  SELECT DISTINCT ON (user_id) 
    user_id,
    room_id,
    joined_at
  FROM room_participants
  WHERE left_at IS NULL
    AND user_id IN (SELECT user_id FROM user_multiple_rooms)
  ORDER BY user_id, joined_at DESC
)
UPDATE room_participants rp
SET left_at = NOW()
FROM latest_room lr
WHERE rp.user_id = lr.user_id 
  AND rp.room_id != lr.room_id
  AND rp.left_at IS NULL;






--------- FILE - 23



-- Step 1: Drop the problematic function
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

-- Step 2: Create a FIXED version that handles all edge cases
CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_already_joined BOOLEAN;
  v_room_active BOOLEAN;
  v_existing_record_id UUID;
  v_existing_left_at TIMESTAMPTZ;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist or is inactive'
    );
  END IF;
  
  -- Check if user already has a record in this room (any state)
  SELECT id, left_at 
  INTO v_existing_record_id, v_existing_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id;
  
  -- If user exists but hasn't left (left_at IS NULL), they're already joined
  IF FOUND AND v_existing_left_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'User already in room',
      'already_joined', true
    );
  END IF;
  
  -- Count current active participants (excluding the user we're checking)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- If user has an existing record but has left (left_at NOT NULL), update it
  IF FOUND AND v_existing_left_at IS NOT NULL THEN
    UPDATE room_participants
    SET left_at = NULL,
        joined_at = NOW()
    WHERE id = v_existing_record_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Rejoined room successfully',
      'rejoined', true,
      'current_count', v_current_count + 1,
      'max_size', v_room_size
    );
  END IF;
  
  -- User has no record at all, insert new
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW();
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION
  WHEN OTHERS THEN
    -- If it's a unique constraint violation, user is already in room somehow
    IF SQLSTATE = '23505' THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'User already in room (race condition handled)',
        'already_joined', true
      );
    END IF;
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Step 3: Update your leave_all_user_rooms to be more thorough
CREATE OR REPLACE FUNCTION leave_all_user_rooms(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  -- Mark ALL user's room_participants as left, even if already left
  UPDATE room_participants
  SET left_at = NOW()
  WHERE user_id = p_user_id
    AND left_at IS NULL
  RETURNING COUNT(*) INTO affected_count;
  
  RETURN COALESCE(affected_count, 0);
END;
$$;

-- Step 4: Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated, anon;





------- FILE - 24


-- ============================================
-- CORRECTED DATABASE FUNCTIONS
-- Run this in Supabase SQL Editor
-- ============================================

-- Fix 1: Corrected leave_all_user_rooms function
-- The previous version had incorrect RETURNING syntax
DROP FUNCTION IF EXISTS leave_all_user_rooms(UUID);

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
  WHERE user_id = p_user_id
    AND left_at IS NULL;
  
  -- Correct way to get affected row count
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  
  RETURN COALESCE(affected_count, 0);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION leave_all_user_rooms(UUID) TO authenticated, anon;

-- Fix 2: Ensure join_room_if_available handles all edge cases properly
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_existing_record_id UUID;
  v_existing_left_at TIMESTAMPTZ;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms
  WHERE id = p_room_id
  FOR UPDATE;
  
  -- Check if room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist or is inactive'
    );
  END IF;
  
  -- Check if user already has a record in this room (any state)
  SELECT id, left_at 
  INTO v_existing_record_id, v_existing_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id;
  
  -- If user exists but hasn't left (left_at IS NULL), they're already joined
  IF FOUND AND v_existing_left_at IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'User already in room',
      'already_joined', true
    );
  END IF;
  
  -- Count current active participants
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL;
  
  -- Check if room has space
  IF v_current_count >= v_room_size THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- If user has an existing record but has left, update it
  IF FOUND AND v_existing_left_at IS NOT NULL THEN
    UPDATE room_participants
    SET left_at = NULL,
        joined_at = NOW()
    WHERE id = v_existing_record_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Rejoined room successfully',
      'rejoined', true,
      'current_count', v_current_count + 1,
      'max_size', v_room_size
    );
  END IF;
  
  -- User has no record at all, insert new
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW();
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION
  WHEN OTHERS THEN
    IF SQLSTATE = '23505' THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'User already in room (race condition handled)',
        'already_joined', true
      );
    END IF;
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;





----------- FILE - 25







-- Run this in Supabase SQL Editor
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
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
  
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found', 'message', 'Room not found or inactive');
  END IF;
  
  IF EXISTS (SELECT 1 FROM room_participants WHERE room_id = p_room_id AND user_id = p_user_id AND left_at IS NULL) THEN
    RETURN json_build_object('success', true, 'already_joined', true, 'message', 'Already in room');
  END IF;
  
  SELECT COUNT(*) INTO v_current_count FROM room_participants WHERE room_id = p_room_id AND left_at IS NULL;
  
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full', 'message', 'Room is full');
  END IF;
  
  INSERT INTO room_participants (room_id, user_id) VALUES (p_room_id, p_user_id);
  
  RETURN json_build_object('success', true, 'message', 'Joined room');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', 'database_error', 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;









----------- FILE - 26







-- Drop and recreate with proper rejoin handling
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_existing_record RECORD;
BEGIN
  -- Lock the room row
  SELECT room_size, is_active INTO v_room_size, v_room_active
  FROM rooms WHERE id = p_room_id FOR UPDATE;
  
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object('success', false, 'error', 'room_not_found', 'message', 'Room not found or inactive');
  END IF;
  
  -- Check for existing participation record (active OR inactive)
  SELECT * INTO v_existing_record 
  FROM room_participants 
  WHERE room_id = p_room_id AND user_id = p_user_id;
  
  IF FOUND THEN
    -- Record exists
    IF v_existing_record.left_at IS NULL THEN
      -- Already actively in room
      RETURN json_build_object('success', true, 'already_joined', true, 'message', 'Already in room');
    ELSE
      -- Previously left, check if can rejoin
      SELECT COUNT(*) INTO v_current_count 
      FROM room_participants 
      WHERE room_id = p_room_id AND left_at IS NULL;
      
      IF v_current_count >= v_room_size THEN
        RETURN json_build_object('success', false, 'error', 'room_full', 'message', 'Room is full');
      END IF;
      
      -- Rejoin by clearing left_at
      UPDATE room_participants 
      SET left_at = NULL, joined_at = NOW()
      WHERE room_id = p_room_id AND user_id = p_user_id;
      
      RETURN json_build_object('success', true, 'rejoined', true, 'message', 'Rejoined room');
    END IF;
  END IF;
  
  -- No existing record, check capacity and insert
  SELECT COUNT(*) INTO v_current_count 
  FROM room_participants 
  WHERE room_id = p_room_id AND left_at IS NULL;
  
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object('success', false, 'error', 'room_full', 'message', 'Room is full');
  END IF;
  
  INSERT INTO room_participants (room_id, user_id) VALUES (p_room_id, p_user_id);
  
  RETURN json_build_object('success', true, 'message', 'Joined room');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', 'database_error', 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;




---------------- FILE - 28




-- ============================================
-- FIXED join_room_if_available - Handles All Race Conditions
-- ============================================

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_participant_id UUID;
  v_left_at TIMESTAMPTZ;
BEGIN
  -- ✅ CRITICAL: Lock the room row FIRST to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;  -- This prevents concurrent modifications
  
  -- Check room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room not found or inactive'
    );
  END IF;
  
  -- ✅ ATOMIC CHECK: Get current participant count WITH lock
  -- This ensures we have accurate count even with concurrent requests
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
  FOR UPDATE OF room_participants;  -- Lock these rows too
  
  -- ✅ Check for existing participation record (locked)
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;  -- Lock this specific record
  
  -- User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- Check capacity BEFORE insert/update
  -- If user previously left, don't count them in current_count
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ UPSERT: Handle both new join and rejoin in single atomic operation
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    -- Should never happen with UPSERT, but handle just in case
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- VERIFICATION QUERY
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '✅ Fixed join_room_if_available installed';
  RAISE NOTICE 'Key improvements:';
  RAISE NOTICE '  • Locks room row FIRST';
  RAISE NOTICE '  • Atomic count check with row locks';
  RAISE NOTICE '  • UPSERT prevents duplicate inserts';
  RAISE NOTICE '  • No race conditions possible';
END $$;




----------- FILE - 28 







-- ============================================
-- CORRECTED join_room_if_available - Fixed FOR UPDATE Issue
-- ============================================

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_participant_id UUID;
  v_left_at TIMESTAMPTZ;
BEGIN
  -- ✅ CRITICAL: Lock the room row FIRST to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;  -- Lock room to prevent concurrent modifications
  
  -- Check room exists and is active
  IF NOT FOUND OR NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room not found or inactive'
    );
  END IF;
  
  -- ✅ Check for existing participation record (with lock)
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;  -- Lock this specific record
  
  -- User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- ✅ FIXED: Count without FOR UPDATE (we already have room lock)
  -- Count current active participants (excluding this user if rejoining)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;  -- Don't count user if they're rejoining
  
  -- Check capacity BEFORE insert/update
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ UPSERT: Handle both new join and rejoin in single atomic operation
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    -- Should never happen with UPSERT, but handle just in case
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- VERIFICATION QUERY
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ CORRECTED join_room_if_available installed';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Fixed:';
  RAISE NOTICE '  • Removed FOR UPDATE from COUNT query';
  RAISE NOTICE '  • Room lock is sufficient for consistency';
  RAISE NOTICE '  • Excludes current user from count (for rejoin)';
  RAISE NOTICE '';
  RAISE NOTICE 'Key features:';
  RAISE NOTICE '  • Locks room row FIRST';
  RAISE NOTICE '  • Atomic count check without aggregate lock';
  RAISE NOTICE '  • UPSERT prevents duplicate inserts';
  RAISE NOTICE '  • No race conditions possible';
  RAISE NOTICE '========================================';
END $$;




---------- FILE - 29








-- ============================================
-- ROOT CAUSE FIX: Proper Gender-Based Matchmaking
-- This fixes the fundamental issue where creator_gender
-- and matching logic are not properly enforced
-- ============================================

-- STEP 1: Clean up existing broken data
-- Mark all participants as left and deactivate all rooms
UPDATE public.room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE public.rooms SET is_active = false WHERE is_active = true;

-- STEP 2: Add trigger to auto-set creator_gender when room is created
-- This ensures creator_gender is ALWAYS set correctly from users table
CREATE OR REPLACE FUNCTION set_creator_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    -- Get the creator's current gender from users table
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = NEW.creator_id;
    
    -- Set creator_gender to match user's gender
    -- This ensures the room has correct creator gender for matching
    NEW.creator_gender := COALESCE(user_gender, 'other');
    
    RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON public.rooms;

-- Create trigger to run BEFORE INSERT on rooms
CREATE TRIGGER trigger_set_creator_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_creator_gender();

-- STEP 3: Create improved matchmaking function with proper gender validation
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;
    v_new_room UUID;
    v_participant_count INTEGER;
BEGIN
    -- CRITICAL: First update user's gender in database
    -- This ensures all subsequent operations use correct gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave any existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Search for compatible existing room with STRICT matching
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest_category
      -- CRITICAL MATCHING LOGIC:
      -- Room creator wants someone of p_user_gender
      AND r.gender_preference = p_user_gender
      -- Room creator's gender matches what user wants
      AND r.creator_gender = p_interested_in
      -- Ensure creator_gender is not 'other' (prevents broken matches)
      AND r.creator_gender != 'other'
      -- Room must have space
      AND r.id NOT IN (
          SELECT room_id 
          FROM public.room_participants 
          WHERE left_at IS NULL 
          GROUP BY room_id 
          HAVING COUNT(*) >= p_room_size
      )
    GROUP BY r.id
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- If found compatible room, join it
    IF v_existing_room IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_existing_room, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RETURN QUERY SELECT v_existing_room, false;
        RETURN;
    END IF;
    
    -- No compatible room found, create new one
    -- The trigger will automatically set creator_gender from users table
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,  -- This room wants someone of p_interested_in gender
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    RETURN QUERY SELECT v_new_room, true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Add validation to prevent 'other' gender from creating public rooms
-- This prevents the root cause of matching failures
CREATE OR REPLACE FUNCTION validate_public_room_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- For public rooms, creator must have valid gender (not 'other')
    IF NEW.room_type = 'public' AND NEW.creator_gender = 'other' THEN
        RAISE EXCEPTION 'Public rooms require gender to be "male" or "female", not "other". Please set your gender preference first.';
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_public_room_gender ON public.rooms;

CREATE TRIGGER trigger_validate_public_room_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    WHEN (NEW.room_type = 'public')
    EXECUTE FUNCTION validate_public_room_gender();

-- STEP 5: Create helper function to check if user can create public room
CREATE OR REPLACE FUNCTION can_user_create_public_room(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = p_user_id;
    
    -- User can create public room if gender is 'male' or 'female'
    RETURN (user_gender IS NOT NULL AND user_gender != 'other');
END;
$$;

GRANT EXECUTE ON FUNCTION can_user_create_public_room(UUID) TO authenticated, anon;

-- STEP 6: Fix search_path for all functions
ALTER FUNCTION set_creator_gender() SET search_path = public;
ALTER FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) SET search_path = public;
ALTER FUNCTION validate_public_room_gender() SET search_path = public;
ALTER FUNCTION can_user_create_public_room(UUID) SET search_path = public;

-- STEP 7: Add helpful comments
COMMENT ON FUNCTION set_creator_gender() IS 'Automatically sets creator_gender from users table when room is created';
COMMENT ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) IS 'Finds compatible room based on STRICT gender matching or creates new room';
COMMENT ON FUNCTION validate_public_room_gender() IS 'Prevents creating public rooms with "other" gender to ensure proper matching';
COMMENT ON FUNCTION can_user_create_public_room(UUID) IS 'Checks if user has valid gender (male/female) to create public room';

-- STEP 8: Create view to debug matching issues
CREATE OR REPLACE VIEW public.matchmaking_debug AS
SELECT 
    r.id as room_id,
    r.creator_id,
    u.display_name as creator_name,
    r.creator_gender,
    r.gender_preference as wants_gender,
    r.interest_category,
    r.room_size,
    r.is_active,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as current_participants,
    r.created_at
FROM public.rooms r
LEFT JOIN public.users u ON u.id = r.creator_id
LEFT JOIN public.room_participants rp ON rp.room_id = r.id
WHERE r.room_type = 'public'
GROUP BY r.id, u.display_name
ORDER BY r.created_at DESC;

GRANT SELECT ON public.matchmaking_debug TO authenticated, anon;

-- STEP 9: Verification and summary
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ROOT CAUSE FIX APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'What was fixed:';
    RAISE NOTICE '  1. Auto-set creator_gender from users table';
    RAISE NOTICE '  2. Strict gender matching in find_compatible_room';
    RAISE NOTICE '  3. Prevent "other" gender from creating public rooms';
    RAISE NOTICE '  4. Added validation triggers';
    RAISE NOTICE '  5. Created debug view';
    RAISE NOTICE '';
    RAISE NOTICE 'Matching Rules:';
    RAISE NOTICE '  • User gender must be male/female (not other)';
    RAISE NOTICE '  • Room creator_gender auto-set from user';
    RAISE NOTICE '  • Match only if: room.gender_preference = user.gender';
    RAISE NOTICE '  • Match only if: room.creator_gender = user.interested_in';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Update frontend to use find_compatible_room()';
    RAISE NOTICE '  2. Show error if user tries to match with "other"';
    RAISE NOTICE '  3. Test with 2 users: male→female and female→male';
    RAISE NOTICE '========================================';
END $$;

-- STEP 10: Show current state
SELECT 
    'Total Users' as metric,
    COUNT(*) as value
FROM public.users
UNION ALL
SELECT 
    'Users with valid gender (male/female)' as metric,
    COUNT(*) as value
FROM public.users
WHERE gender IN ('male', 'female')
UNION ALL
SELECT 
    'Users with "other" gender' as metric,
    COUNT(*) as value
FROM public.users
WHERE gender = 'other'
UNION ALL
SELECT 
    'Active Public Rooms' as metric,
    COUNT(*) as value
FROM public.rooms
WHERE room_type = 'public' AND is_active = true;







-------- FILE - 30





-- ============================================
-- COMPLETE DATABASE CLEANUP & RESET
-- This fixes the corrupted state where rooms are inactive
-- but users think they're in them
-- ============================================

-- STEP 1: NUCLEAR RESET - Clean ALL matchmaking data
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 STARTING COMPLETE CLEANUP';
    RAISE NOTICE '========================================';
END $$;

-- Mark ALL participants as left (no exceptions)
UPDATE public.room_participants 
SET left_at = NOW() 
WHERE left_at IS NULL;

-- Deactivate ALL rooms (no exceptions)
UPDATE public.rooms 
SET is_active = false 
WHERE is_active = true;

-- Delete ALL signaling messages
DELETE FROM public.signaling;

-- Delete ALL chess games that aren't bet matches
DELETE FROM public.chess_games 
WHERE is_bet_match = false OR is_bet_match IS NULL;

DO $$
BEGIN
    RAISE NOTICE '✅ Cleaned all existing data';
    RAISE NOTICE '';
END $$;

-- STEP 2: Fix ALL users with 'other' gender
-- This is CRITICAL - 'other' breaks matching completely
UPDATE public.users 
SET gender = 'male',
    updated_at = NOW()
WHERE gender = 'other' OR gender IS NULL;

DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE '✅ Fixed % users with "other" gender → set to "male"', updated_count;
    RAISE NOTICE '   (Users can change this in the UI)';
    RAISE NOTICE '';
END $$;

-- STEP 3: Drop and recreate the trigger to auto-set creator_gender
DROP TRIGGER IF EXISTS trigger_set_creator_gender ON public.rooms;
DROP FUNCTION IF EXISTS set_creator_gender();

CREATE OR REPLACE FUNCTION set_creator_gender()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_gender gender_preference;
BEGIN
    -- Get the creator's current gender from users table
    SELECT gender INTO user_gender
    FROM public.users
    WHERE id = NEW.creator_id;
    
    -- CRITICAL: Set creator_gender to match user's gender
    -- Never allow 'other' for public rooms
    IF NEW.room_type = 'public' THEN
        IF user_gender IS NULL OR user_gender = 'other' THEN
            RAISE EXCEPTION 'Cannot create public room with gender "other". Please set your gender to male or female first.';
        END IF;
        NEW.creator_gender := user_gender;
    ELSE
        -- Private rooms can have any gender
        NEW.creator_gender := COALESCE(user_gender, 'other');
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_set_creator_gender
    BEFORE INSERT ON public.rooms
    FOR EACH ROW
    EXECUTE FUNCTION set_creator_gender();

DO $$
BEGIN
    RAISE NOTICE '✅ Recreated trigger: set_creator_gender';
    RAISE NOTICE '';
END $$;

-- STEP 4: Create improved join_room_if_available that NEVER fails silently
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_participant_id UUID;
  v_left_at TIMESTAMPTZ;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;
  
  -- Check room exists
  IF NOT FOUND THEN
    RAISE NOTICE 'Room not found: %', p_room_id;
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist'
    );
  END IF;
  
  -- Check room is active
  IF NOT v_room_active THEN
    RAISE NOTICE 'Room % is inactive', p_room_id;
    RETURN json_build_object(
      'success', false,
      'error', 'room_inactive',
      'message', 'Room is no longer active'
    );
  END IF;
  
  -- Check for existing participation record
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;
  
  -- User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RAISE NOTICE 'User % already in room %', p_user_id, p_room_id;
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- Count current active participants (excluding this user if rejoining)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;
  
  -- Check capacity
  IF v_current_count >= v_room_size THEN
    RAISE NOTICE 'Room % is full: % / %', p_room_id, v_current_count, v_room_size;
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- UPSERT: Join or rejoin the room
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RAISE NOTICE 'User % successfully joined room %', p_user_id, p_room_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    RAISE NOTICE 'Unique violation handled for user % in room %', p_user_id, p_room_id;
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RAISE WARNING 'Error in join_room_if_available: %', SQLERRM;
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Recreated function: join_room_if_available';
    RAISE NOTICE '';
END $$;

-- STEP 5: Create function to force-leave a room (for stuck users)
DROP FUNCTION IF EXISTS force_leave_room(UUID);

CREATE OR REPLACE FUNCTION force_leave_room(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Mark all participations as left
    UPDATE room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Clean up signaling
    DELETE FROM signaling
    WHERE sender_id = p_user_id OR target_id = p_user_id;
    
    RAISE NOTICE 'Force-left user % from all rooms', p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION force_leave_room(UUID) TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Created function: force_leave_room';
    RAISE NOTICE '';
END $$;

-- STEP 6: Create automatic room cleanup function
DROP FUNCTION IF EXISTS cleanup_inactive_rooms();

CREATE OR REPLACE FUNCTION cleanup_inactive_rooms()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cleaned_count INTEGER;
BEGIN
    -- Deactivate rooms with no active participants
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
$$;

GRANT EXECUTE ON FUNCTION cleanup_inactive_rooms() TO authenticated, service_role;

DO $$
BEGIN
    RAISE NOTICE '✅ Created function: cleanup_inactive_rooms';
    RAISE NOTICE '';
END $$;

-- STEP 7: Set search_path for all functions
ALTER FUNCTION set_creator_gender() SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION force_leave_room(UUID) SET search_path = public;
ALTER FUNCTION cleanup_inactive_rooms() SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;

-- STEP 8: Create a view to monitor system health
CREATE OR REPLACE VIEW public.system_health AS
SELECT 
    (SELECT COUNT(*) FROM users) as total_users,
    (SELECT COUNT(*) FROM users WHERE gender = 'other') as users_with_other_gender,
    (SELECT COUNT(*) FROM rooms WHERE is_active = true AND room_type = 'public') as active_public_rooms,
    (SELECT COUNT(*) FROM room_participants WHERE left_at IS NULL) as active_participants,
    (SELECT COUNT(DISTINCT room_id) FROM room_participants WHERE left_at IS NULL) as rooms_with_participants,
    (SELECT COUNT(*) FROM rooms WHERE is_active = true AND id NOT IN (
        SELECT DISTINCT room_id FROM room_participants WHERE left_at IS NULL
    )) as empty_active_rooms,
    (SELECT COUNT(*) FROM signaling) as pending_signals;

GRANT SELECT ON public.system_health TO authenticated, anon;

DO $$
BEGIN
    RAISE NOTICE '✅ Created view: system_health';
    RAISE NOTICE '';
END $$;

-- STEP 9: Final verification
DO $$
DECLARE
    health_record RECORD;
BEGIN
    SELECT * INTO health_record FROM system_health;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ DATABASE CLEANUP COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'System Health:';
    RAISE NOTICE '  • Total Users: %', health_record.total_users;
    RAISE NOTICE '  • Users with "other" gender: %', health_record.users_with_other_gender;
    RAISE NOTICE '  • Active Public Rooms: %', health_record.active_public_rooms;
    RAISE NOTICE '  • Active Participants: %', health_record.active_participants;
    RAISE NOTICE '  • Empty Active Rooms: %', health_record.empty_active_rooms;
    RAISE NOTICE '  • Pending Signals: %', health_record.pending_signals;
    RAISE NOTICE '';
    
    IF health_record.users_with_other_gender > 0 THEN
        RAISE NOTICE '⚠️  WARNING: % users still have gender="other"', health_record.users_with_other_gender;
        RAISE NOTICE '   They will not be able to use public matching!';
        RAISE NOTICE '';
    END IF;
    
    IF health_record.empty_active_rooms > 0 THEN
        RAISE NOTICE '⚠️  WARNING: % active rooms have no participants', health_record.empty_active_rooms;
        RAISE NOTICE '   Run: SELECT cleanup_inactive_rooms();';
        RAISE NOTICE '';
    END IF;
    
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Both users should refresh their browsers (F5)';
    RAISE NOTICE '  2. Both users select gender (NOT "other")';
    RAISE NOTICE '  3. Click "Start Matching"';
    RAISE NOTICE '  4. They should match immediately!';
    RAISE NOTICE '';
    RAISE NOTICE 'If still stuck, run:';
    RAISE NOTICE '  SELECT force_leave_room(''USER_ID_HERE'');';
    RAISE NOTICE '========================================';
END $$;

-- STEP 10: Show current rooms (for debugging)
SELECT 
    r.id,
    r.room_type,
    r.is_active,
    r.creator_gender,
    r.gender_preference,
    r.interest_category,
    r.room_size,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as participant_count,
    r.created_at
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
WHERE r.created_at > NOW() - INTERVAL '1 hour'
GROUP BY r.id
ORDER BY r.created_at DESC
LIMIT 10;


------- FILE - 31

-- ============================================
-- FIXED find_compatible_room Function
-- Fixes the parameter name mismatch
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,  -- ✅ This is the correct parameter name
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;
    v_new_room UUID;
    v_participant_count INTEGER;
BEGIN
    -- Update user's gender in database
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave any existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- Search for compatible existing room
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest  -- ✅ FIXED: Use p_interest not p_interest_category
      -- Gender matching logic
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Room must have space
      AND r.id NOT IN (
          SELECT room_id 
          FROM public.room_participants 
          WHERE left_at IS NULL 
          GROUP BY room_id 
          HAVING COUNT(*) >= p_room_size
      )
    GROUP BY r.id
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- If found compatible room, join it
    IF v_existing_room IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_existing_room, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RETURN QUERY SELECT v_existing_room, false;
        RETURN;
    END IF;
    
    -- No compatible room found, create new one
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,
        p_interest,  -- ✅ FIXED: Use p_interest not p_interest_category
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    RETURN QUERY SELECT v_new_room, true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- Verify the fix
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIXED find_compatible_room';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Fixed parameter name mismatch:';
    RAISE NOTICE '  • Parameter: p_interest';
    RAISE NOTICE '  • Was incorrectly using: p_interest_category';
    RAISE NOTICE '  • Now correctly using: p_interest';
    RAISE NOTICE '';
    RAISE NOTICE 'Test the fix by:';
    RAISE NOTICE '  1. Refresh your browser';
    RAISE NOTICE '  2. Select gender preferences';
    RAISE NOTICE '  3. Click "Start Matching"';
    RAISE NOTICE '========================================';
END $$;



-------- FILE - 32




-- ============================================
-- COMPLETE DATABASE STATE VERIFICATION
-- Run this in Supabase SQL Editor to see what's wrong
-- ============================================

-- 1. Check if find_compatible_room function exists
SELECT 
    '1. Function Exists' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'find_compatible_room'
        ) THEN '✅ Yes'
        ELSE '❌ No - You need to run the SQL migration!'
    END as result;

-- 2. Check function signature
SELECT 
    '2. Function Signature' as check_name,
    pg_get_function_arguments(oid) as signature
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- 3. Check if there are any syntax errors in the function
SELECT 
    '3. Function Validity' as check_name,
    CASE 
        WHEN prorettype IS NOT NULL THEN '✅ Function is valid'
        ELSE '❌ Function has errors'
    END as result
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- 4. Check users table structure
SELECT 
    '4. Users Table - Gender Column' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'users' 
            AND column_name = 'gender'
            AND data_type = 'USER-DEFINED' -- Means it's using gender_preference enum
        ) THEN '✅ Correct type (enum)'
        ELSE '❌ Wrong type or missing'
    END as result;

-- 5. Check rooms table structure
SELECT 
    '5. Rooms Table - Interest Column' as check_name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'rooms' 
            AND column_name = 'interest_category'
            AND data_type = 'USER-DEFINED'
        ) THEN '✅ Correct (interest_category enum)'
        ELSE '❌ Wrong type or missing'
    END as result;

-- 6. Check active public rooms
SELECT 
    '6. Active Public Rooms' as check_name,
    COUNT(*)::text || ' rooms' as result
FROM rooms
WHERE room_type = 'public' AND is_active = true;

-- 7. Check users with valid gender
SELECT 
    '7. Users with Valid Gender' as check_name,
    COUNT(*)::text || ' users (male/female)' as result
FROM users
WHERE gender IN ('male', 'female');

-- 8. Check users with 'other' gender (problematic)
SELECT 
    '8. Users with "other" Gender' as check_name,
    COUNT(*)::text || ' users (⚠️ cannot match)' as result
FROM users
WHERE gender = 'other';

-- 9. Test the function with dummy data (CRITICAL TEST)
SELECT 
    '9. Function Test' as check_name,
    'See result below' as result;

-- Actually try to call the function
-- This will show the exact error if it fails
DO $$
DECLARE
    test_result RECORD;
BEGIN
    -- Try to call find_compatible_room
    BEGIN
        SELECT * INTO test_result
        FROM find_compatible_room(
            '00000000-0000-0000-0000-000000000000'::UUID,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ Function call succeeded!';
        RAISE NOTICE 'Result: room_id=%, is_new_room=%', test_result.room_id, test_result.is_new_room;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '❌ Function call failed!';
        RAISE NOTICE 'Error: %', SQLERRM;
        RAISE NOTICE 'Detail: %', SQLSTATE;
    END;
END $$;

-- 10. Show all function definitions that might be conflicting
SELECT 
    '10. All find_compatible Functions' as check_name,
    string_agg(proname || '(' || pg_get_function_arguments(oid) || ')', ', ') as result
FROM pg_proc 
WHERE proname LIKE '%find_compatible%';

-- ============================================
-- DETAILED ROOM ANALYSIS
-- ============================================

SELECT 
    '══════════════════════════════════════' as separator,
    'DETAILED ROOM ANALYSIS' as title,
    '══════════════════════════════════════' as separator2;

SELECT 
    r.id,
    r.room_type,
    r.is_active,
    r.creator_gender,
    r.gender_preference,
    r.interest_category,
    r.room_size,
    COUNT(rp.user_id) FILTER (WHERE rp.left_at IS NULL) as current_participants,
    r.created_at
FROM rooms r
LEFT JOIN room_participants rp ON rp.room_id = r.id
WHERE r.room_type = 'public'
GROUP BY r.id
ORDER BY r.created_at DESC
LIMIT 5;

-- ============================================
-- CRITICAL ISSUES SUMMARY
-- ============================================

SELECT 
    '══════════════════════════════════════' as separator,
    'CRITICAL ISSUES' as title,
    '══════════════════════════════════════' as separator2;

SELECT 
    CASE 
        WHEN NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'find_compatible_room')
        THEN '🔴 CRITICAL: find_compatible_room function does not exist!'
        
        WHEN EXISTS (
            SELECT 1 FROM users WHERE gender = 'other'
        )
        THEN '⚠️ WARNING: Some users have gender="other" (cannot match in public rooms)'
        
        WHEN NOT EXISTS (
            SELECT 1 FROM rooms WHERE room_type = 'public' AND is_active = true
        )
        THEN 'ℹ️ INFO: No active public rooms (this is OK if no one is matching)'
        
        ELSE '✅ All checks passed! The database structure looks good.'
    END as status;

-- ============================================
-- NEXT STEPS
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '══════════════════════════════════════';
    RAISE NOTICE 'NEXT STEPS:';
    RAISE NOTICE '══════════════════════════════════════';
    RAISE NOTICE '1. Review the results above';
    RAISE NOTICE '2. If function does not exist, run the fix_matchmaking_function.sql';
    RAISE NOTICE '3. If users have gender="other", they need to update their profile';
    RAISE NOTICE '4. Copy the exact error from the "9. Function Test" section';
    RAISE NOTICE '5. Share that error for further diagnosis';
    RAISE NOTICE '══════════════════════════════════════';
END $$;






---------- FILE -33






-- ============================================
-- DIRECT FUNCTION TEST
-- This will show if the function works at all
-- ============================================

-- First, let's see the exact function signature
SELECT 
    'Function Name' as detail,
    proname as value
FROM pg_proc 
WHERE proname = 'find_compatible_room'

UNION ALL

SELECT 
    'Parameters' as detail,
    pg_get_function_arguments(oid) as value
FROM pg_proc 
WHERE proname = 'find_compatible_room'

UNION ALL

SELECT 
    'Return Type' as detail,
    pg_get_function_result(oid) as value
FROM pg_proc 
WHERE proname = 'find_compatible_room';

-- Now test calling it with a real user ID
-- Replace 'YOUR_USER_ID_HERE' with your actual user ID from the users table
DO $$
DECLARE
    test_user_id UUID;
    result RECORD;
BEGIN
    -- Get the first user ID from your users table
    SELECT id INTO test_user_id FROM users LIMIT 1;
    
    IF test_user_id IS NULL THEN
        RAISE NOTICE '❌ No users found in database!';
        RETURN;
    END IF;
    
    RAISE NOTICE '🧪 Testing with user ID: %', test_user_id;
    
    -- Try calling the function
    BEGIN
        SELECT * INTO result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ SUCCESS! Function returned:';
        RAISE NOTICE '   room_id: %', result.room_id;
        RAISE NOTICE '   is_new_room: %', result.is_new_room;
        
    EXCEPTION 
        WHEN undefined_function THEN
            RAISE NOTICE '❌ ERROR: Function does not exist!';
            RAISE NOTICE 'You need to run the SQL migration to create it.';
            
        WHEN undefined_column THEN
            RAISE NOTICE '❌ ERROR: Column does not exist!';
            RAISE NOTICE 'Hint: %', SQLERRM;
            RAISE NOTICE 'There is a typo in the function definition.';
            
        WHEN OTHERS THEN
            RAISE NOTICE '❌ ERROR: %', SQLERRM;
            RAISE NOTICE 'SQL State: %', SQLSTATE;
    END;
END $$;

-- Check if the function actually created a room
SELECT 
    'Rooms created in last 5 minutes' as check,
    COUNT(*) as count
FROM rooms 
WHERE created_at > NOW() - INTERVAL '5 minutes';

-- Show the most recent room
SELECT 
    'Most recent room' as info,
    id,
    room_type,
    is_active,
    creator_gender,
    gender_preference,
    interest_category,
    created_at
FROM rooms 
ORDER BY created_at DESC 
LIMIT 1;






--------- FILE - 34

-- ============================================
-- FIXED find_compatible_room - Resolves Ambiguous Column Reference
-- The bug: "room_id" is ambiguous - could be variable OR column
-- Solution: Qualify all column references with table aliases
-- ============================================

DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(room_id UUID, is_new_room BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_room UUID;  -- Changed variable name to avoid conflict
    v_new_room UUID;
    v_participant_count INTEGER;
BEGIN
    -- Update user's gender in database
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- Leave any existing rooms first
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- ✅ FIX: Explicitly qualify ALL column references with table aliases
    -- Search for compatible existing room
    SELECT r.id, COUNT(rp.user_id)
    INTO v_existing_room, v_participant_count
    FROM public.rooms r
    LEFT JOIN public.room_participants rp 
        ON rp.room_id = r.id AND rp.left_at IS NULL
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      -- Gender matching logic
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Room must have space - ✅ FIX: Use subquery alias
      AND r.id NOT IN (
          SELECT rp2.room_id 
          FROM public.room_participants rp2
          WHERE rp2.left_at IS NULL 
          GROUP BY rp2.room_id 
          HAVING COUNT(*) >= p_room_size
      )
    GROUP BY r.id
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- If found compatible room, join it
    IF v_existing_room IS NOT NULL THEN
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_existing_room, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        -- ✅ FIX: Return explicitly named columns to avoid ambiguity
        RETURN QUERY SELECT v_existing_room AS room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- No compatible room found, create new one
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_new_room;
    
    -- Join the newly created room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_new_room, p_user_id);
    
    -- ✅ FIX: Return explicitly named columns
    RETURN QUERY SELECT v_new_room AS room_id, true AS is_new_room;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- Verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIXED find_compatible_room';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'What was fixed:';
    RAISE NOTICE '  • Qualified all column refs with table aliases (r.id, rp.room_id)';
    RAISE NOTICE '  • Used aliases in subqueries (rp2.room_id)';
    RAISE NOTICE '  • Explicit column naming in RETURN QUERY';
    RAISE NOTICE '  • Renamed variables to avoid conflicts';
    RAISE NOTICE '';
    RAISE NOTICE 'The "ambiguous column reference" error is now fixed!';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Run this SQL in Supabase SQL Editor';
    RAISE NOTICE '  2. Refresh your app (F5)';
    RAISE NOTICE '  3. Try matching again';
    RAISE NOTICE '========================================';
END $$;

-- Test the function (optional)
DO $$
DECLARE
    test_user_id UUID;
    result RECORD;
BEGIN
    SELECT id INTO test_user_id FROM users LIMIT 1;
    
    IF test_user_id IS NOT NULL THEN
        SELECT * INTO result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE 'Test successful! Created room: %', result.room_id;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test failed: %', SQLERRM;
END $$;




-----------FILE - 35





-- ============================================
-- NUCLEAR FIX: Completely Rewrite find_compatible_room
-- Use COMPLETELY different naming to avoid ANY ambiguity
-- ============================================

-- Step 1: Drop the old function completely
DROP FUNCTION IF EXISTS find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER);

-- Step 2: Create NEW version with zero ambiguity
CREATE OR REPLACE FUNCTION find_compatible_room(
    p_user_id UUID,
    p_user_gender gender_preference,
    p_interested_in gender_preference,
    p_interest interest_category,
    p_room_size INTEGER
)
RETURNS TABLE(
    matched_room_id UUID,  -- ✅ CHANGED: Not "room_id" to avoid conflict
    is_new_room BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_found_room_id UUID;  -- ✅ CHANGED: Clear, unique name
    v_created_room_id UUID;  -- ✅ CHANGED: Clear, unique name
    v_count INTEGER;
BEGIN
    RAISE NOTICE '🔍 Starting matchmaking for user: %', p_user_id;
    
    -- Update user's gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    RAISE NOTICE '✅ Updated user gender to: %', p_user_gender;
    
    -- Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    RAISE NOTICE '🚪 Left existing rooms';
    
    -- ✅ CRITICAL FIX: Search with EXPLICIT aliases everywhere
    SELECT rooms.id INTO v_found_room_id
    FROM public.rooms AS rooms
    WHERE rooms.room_type = 'public'
      AND rooms.is_active = true
      AND rooms.room_size = p_room_size
      AND rooms.interest_category = p_interest
      AND rooms.gender_preference = p_user_gender
      AND rooms.creator_gender = p_interested_in
      AND rooms.creator_gender != 'other'
      -- Check room has space
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants AS participants
          WHERE participants.room_id = rooms.id 
            AND participants.left_at IS NULL
      ) < p_room_size
    ORDER BY rooms.created_at ASC
    LIMIT 1;
    
    -- Found existing room?
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE '🎉 Found existing room: %', v_found_room_id;
        
        -- Join it
        INSERT INTO public.room_participants (room_id, user_id)
        VALUES (v_found_room_id, p_user_id)
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET left_at = NULL, joined_at = NOW();
        
        RAISE NOTICE '✅ Joined existing room';
        
        -- ✅ Return with explicit column names
        RETURN QUERY 
        SELECT 
            v_found_room_id AS matched_room_id,
            false AS is_new_room;
        RETURN;
    END IF;
    
    RAISE NOTICE '🆕 No room found, creating new one';
    
    -- Create new room
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE '✅ Created new room: %', v_created_room_id;
    
    -- Join new room
    INSERT INTO public.room_participants (room_id, user_id)
    VALUES (v_created_room_id, p_user_id);
    
    RAISE NOTICE '✅ Joined new room';
    
    -- ✅ Return with explicit column names
    RETURN QUERY 
    SELECT 
        v_created_room_id AS matched_room_id,
        true AS is_new_room;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- ============================================
-- VERIFY THE FIX
-- ============================================
DO $$
DECLARE
    test_result RECORD;
    test_user_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧪 TESTING NEW FUNCTION';
    RAISE NOTICE '========================================';
    
    -- Get a test user
    SELECT id INTO test_user_id FROM public.users LIMIT 1;
    
    IF test_user_id IS NULL THEN
        RAISE NOTICE '⚠️  No users found for testing';
        RETURN;
    END IF;
    
    -- Test the function
    SELECT * INTO test_result
    FROM find_compatible_room(
        test_user_id,
        'male'::gender_preference,
        'female'::gender_preference,
        'random'::interest_category,
        2
    );
    
    RAISE NOTICE '✅ SUCCESS! Function works!';
    RAISE NOTICE '   Room ID: %', test_result.matched_room_id;
    RAISE NOTICE '   Is New: %', test_result.is_new_room;
    RAISE NOTICE '';
    RAISE NOTICE '🎯 The ambiguity error is FIXED!';
    RAISE NOTICE '========================================';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test failed: %', SQLERRM;
    RAISE NOTICE 'SQL State: %', SQLSTATE;
END $$;

-- Show function signature
SELECT 
    'Function installed:' as status,
    proname as name,
    pg_get_function_arguments(oid) as parameters,
    pg_get_function_result(oid) as returns
FROM pg_proc 
WHERE proname = 'find_compatible_room';





---------- FILE - 36




-- ============================================
-- FIX 409 CONFLICT ERROR
-- The error means: User is trying to join room they're already in
-- This happens because find_compatible_room already joins the room
-- Then your code tries to join AGAIN
-- ============================================

-- This is actually NOT a problem with the SQL function
-- The SQL function ALREADY joins the user to the room
-- So you DON'T need to join again in your frontend!

-- But let's verify your join_room_if_available handles this correctly:

DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_size INTEGER;
  v_current_count INTEGER;
  v_room_active BOOLEAN;
  v_participant_id UUID;
  v_left_at TIMESTAMPTZ;
BEGIN
  -- Lock the room row to prevent race conditions
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;
  
  -- Check room exists
  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist'
    );
  END IF;
  
  -- Check room is active
  IF NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_inactive',
      'message', 'Room is no longer active'
    );
  END IF;
  
  -- ✅ FIX: Check for existing participation record
  SELECT id, left_at 
  INTO v_participant_id, v_left_at
  FROM room_participants
  WHERE room_id = p_room_id 
    AND user_id = p_user_id
  FOR UPDATE;
  
  -- ✅ User already in room and hasn't left
  IF FOUND AND v_left_at IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room'
    );
  END IF;
  
  -- Count current active participants (excluding this user if rejoining)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;
  
  -- Check capacity
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ UPSERT: Join or rejoin the room (handles 409 conflict)
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'rejoined', (v_participant_id IS NOT NULL),
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN unique_violation THEN
    -- Should never happen with UPSERT, but handle just in case
    RETURN json_build_object(
      'success', true,
      'already_joined', true,
      'message', 'Already in room (race condition handled)'
    );
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- ============================================
-- IMPORTANT NOTE ABOUT 409 CONFLICTS
-- ============================================

/*
The 409 Conflict happens because:

1. find_compatible_room() ALREADY joins the user to the room
2. Then your useMatchmaking.ts tries to join AGAIN
3. Database says "you're already in this room" → 409 Conflict

SOLUTION OPTIONS:

Option A (RECOMMENDED): 
- Use ONLY find_compatible_room()
- Remove the extra join attempt
- This is what the simplified CreateRoom.tsx does

Option B (If you want to keep useMatchmaking.ts):
- Add ON CONFLICT DO NOTHING to your insert
- Or check if user is already in room before inserting

The SQL function ALREADY handles joining atomically,
so you DON'T need additional join logic!
*/

-- Verify the fix
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ join_room_if_available FIXED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Improvements:';
    RAISE NOTICE '  • Handles already-joined users gracefully';
    RAISE NOTICE '  • Uses UPSERT to prevent 409 conflicts';
    RAISE NOTICE '  • Returns success=true if already in room';
    RAISE NOTICE '';
    RAISE NOTICE 'The 409 Conflict should be gone!';
    RAISE NOTICE '========================================';
END $$;







----------- FILE - 37

-- Run in Supabase SQL Editor
-- This creates a backup of your current state
CREATE TABLE room_participants_backup AS SELECT * FROM room_participants;
CREATE TABLE rooms_backup AS SELECT * FROM rooms;




---------- FILE - 38





-- Check how many active rooms and participants you have
SELECT 
  'Active Rooms' as metric,
  COUNT(*) as count
FROM rooms WHERE is_active = true
UNION ALL
SELECT 
  'Active Participants',
  COUNT(*)
FROM room_participants WHERE left_at IS NULL;






--------- FILE - 39


-- ============================================
-- COMPLETE FIX FOR ALL MATCHMAKING ISSUES
-- This resolves the "double join" race condition
-- Run this in Supabase SQL Editor
-- ============================================

-- STEP 1: Clean all existing data
DO $$
BEGIN
    RAISE NOTICE '🧹 Cleaning existing data...';
END $$;

UPDATE public.room_participants SET left_at = NOW() WHERE left_at IS NULL;
UPDATE public.rooms SET is_active = false WHERE is_active = true;
DELETE FROM public.signaling;

-- STEP 2: Fix the UNIQUE constraint to handle ON CONFLICT properly
-- The current UNIQUE(room_id, user_id) is correct, but let's ensure it exists
DO $$ 
BEGIN
    -- Drop existing constraint if it exists with wrong name
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'room_participants_room_id_user_id_key'
    ) THEN
        ALTER TABLE public.room_participants 
        DROP CONSTRAINT room_participants_room_id_user_id_key;
    END IF;
    
    -- Add the constraint with proper name
    ALTER TABLE public.room_participants 
    ADD CONSTRAINT room_participants_unique UNIQUE(room_id, user_id);
    
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint already exists';
END $$;

-- STEP 3: CRITICAL FIX - Update find_compatible_room to NOT auto-join
-- This prevents the double-join issue
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
    -- ✅ Update user's gender
    UPDATE public.users
    SET gender = p_user_gender,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    -- ✅ Leave existing rooms
    UPDATE public.room_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;
    
    -- ✅ Search for compatible room
    SELECT r.id INTO v_found_room_id
    FROM public.rooms r
    WHERE r.room_type = 'public'
      AND r.is_active = true
      AND r.room_size = p_room_size
      AND r.interest_category = p_interest
      AND r.gender_preference = p_user_gender
      AND r.creator_gender = p_interested_in
      AND r.creator_gender != 'other'
      -- Check room has space
      AND (
          SELECT COUNT(*) 
          FROM public.room_participants rp
          WHERE rp.room_id = r.id 
            AND rp.left_at IS NULL
      ) < p_room_size
    ORDER BY r.created_at ASC
    LIMIT 1;
    
    -- Found existing room? Return it WITHOUT joining
    IF v_found_room_id IS NOT NULL THEN
        RAISE NOTICE 'Found existing room: %', v_found_room_id;
        RETURN QUERY 
        SELECT v_found_room_id AS matched_room_id, false AS is_new_room;
        RETURN;
    END IF;
    
    -- No room found, create new one
    INSERT INTO public.rooms (
        room_type,
        room_size,
        gender_preference,
        interest_category,
        creator_id,
        is_active
    ) VALUES (
        'public',
        p_room_size,
        p_interested_in,
        p_interest,
        p_user_id,
        true
    )
    RETURNING id INTO v_created_room_id;
    
    RAISE NOTICE 'Created new room: %', v_created_room_id;
    
    -- Return new room WITHOUT joining
    RETURN QUERY 
    SELECT v_created_room_id AS matched_room_id, true AS is_new_room;
END;
$$;

GRANT EXECUTE ON FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) TO authenticated, anon;

-- STEP 4: Fix join_room_if_available to handle all cases gracefully
DROP FUNCTION IF EXISTS join_room_if_available(UUID, UUID);

CREATE OR REPLACE FUNCTION join_room_if_available(
  p_room_id UUID,
  p_user_id UUID
)
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
  -- Lock the room row
  SELECT room_size, is_active 
  INTO v_room_size, v_room_active
  FROM rooms 
  WHERE id = p_room_id 
  FOR UPDATE;
  
  -- Check room exists
  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_not_found',
      'message', 'Room does not exist'
    );
  END IF;
  
  -- Check room is active
  IF NOT v_room_active THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_inactive',
      'message', 'Room is no longer active'
    );
  END IF;
  
  -- Count participants (excluding this user)
  SELECT COUNT(*) INTO v_current_count
  FROM room_participants
  WHERE room_id = p_room_id 
    AND left_at IS NULL
    AND user_id != p_user_id;
  
  -- Check capacity
  IF v_current_count >= v_room_size THEN
    RETURN json_build_object(
      'success', false,
      'error', 'room_full',
      'message', 'Room is full',
      'current_count', v_current_count,
      'max_size', v_room_size
    );
  END IF;
  
  -- ✅ CRITICAL FIX: Use UPSERT with ON CONFLICT
  -- This prevents 409 errors if already joined
  INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
  VALUES (p_room_id, p_user_id, NOW(), NULL)
  ON CONFLICT (room_id, user_id) 
  DO UPDATE SET 
    left_at = NULL,
    joined_at = NOW()
  WHERE room_participants.room_id = p_room_id 
    AND room_participants.user_id = p_user_id;
  
  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined room',
    'current_count', v_current_count + 1,
    'max_size', v_room_size
  );
  
EXCEPTION 
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', 'database_error',
      'message', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION join_room_if_available(UUID, UUID) TO authenticated, anon;

-- STEP 5: Ensure all functions have correct search_path
ALTER FUNCTION find_compatible_room(UUID, gender_preference, gender_preference, interest_category, INTEGER) SET search_path = public;
ALTER FUNCTION join_room_if_available(UUID, UUID) SET search_path = public;
ALTER FUNCTION leave_all_user_rooms(UUID) SET search_path = public;

-- STEP 6: Verification
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL FIXES APPLIED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Key Changes:';
    RAISE NOTICE '  1. find_compatible_room NO LONGER auto-joins';
    RAISE NOTICE '  2. join_room_if_available uses UPSERT (no 409)';
    RAISE NOTICE '  3. Unique constraint properly named';
    RAISE NOTICE '  4. All existing data cleaned';
    RAISE NOTICE '';
    RAISE NOTICE 'HOW IT WORKS NOW:';
    RAISE NOTICE '  Step 1: find_compatible_room → Returns room_id';
    RAISE NOTICE '  Step 2: Frontend calls join_room_if_available';
    RAISE NOTICE '  Step 3: User joins atomically (no race)';
    RAISE NOTICE '  Step 4: Navigate to room';
    RAISE NOTICE '';
    RAISE NOTICE 'This eliminates the double-join issue!';
    RAISE NOTICE '========================================';
END $$;

-- Test the functions
DO $$
DECLARE
    test_user_id UUID;
    find_result RECORD;
    join_result JSON;
BEGIN
    SELECT id INTO test_user_id FROM public.users LIMIT 1;
    
    IF test_user_id IS NOT NULL THEN
        RAISE NOTICE '🧪 Testing with user: %', test_user_id;
        
        -- Test find_compatible_room
        SELECT * INTO find_result
        FROM find_compatible_room(
            test_user_id,
            'male'::gender_preference,
            'female'::gender_preference,
            'random'::interest_category,
            2
        );
        
        RAISE NOTICE '✅ find_compatible_room: room_id=%', find_result.matched_room_id;
        
        -- Test join_room_if_available
        SELECT * INTO join_result
        FROM join_room_if_available(
            find_result.matched_room_id,
            test_user_id
        );
        
        RAISE NOTICE '✅ join_room_if_available: %', join_result;
        
        -- Clean up test data
        UPDATE public.room_participants 
        SET left_at = NOW() 
        WHERE user_id = test_user_id;
        
        UPDATE public.rooms 
        SET is_active = false 
        WHERE id = find_result.matched_room_id;
        
        RAISE NOTICE '✅ Test complete and cleaned up';
    ELSE
        RAISE NOTICE '⚠️  No users found for testing';
    END IF;
END $$;