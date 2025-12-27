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