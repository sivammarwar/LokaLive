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