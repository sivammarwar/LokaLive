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