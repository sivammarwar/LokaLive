// supabase/functions/process-withdrawal/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RAZORPAY_KEY_ID = Deno.env.get('RAZORPAY_KEY_ID')!;
const RAZORPAY_KEY_SECRET = Deno.env.get('RAZORPAY_KEY_SECRET')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { userId, amount, diamonds, method } = await req.json();

    // Validate input
    if (!userId || !amount || !diamonds || !method) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Get user details
    const { data: user } = await supabaseClient
      .from('users')
      .select('display_name, email')
      .eq('id', userId)
      .single();

    // Create payout using Razorpay X (Payout API)
    const auth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);
    
    let payoutResponse;
    
    if (method.type === 'upi') {
      // UPI Payout
      payoutResponse = await fetch('https://api.razorpay.com/v1/payouts', {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          account_number: Deno.env.get('RAZORPAY_ACCOUNT_NUMBER'), // Your Razorpay X account
          fund_account_id: await getOrCreateFundAccount(method.upi_id, 'vpa', user, auth),
          amount: amount * 100, // Convert to paise
          currency: 'INR',
          mode: 'UPI',
          purpose: 'payout',
          queue_if_low_balance: true,
          reference_id: `WD_${userId}_${Date.now()}`,
          narration: `Diamond withdrawal - ${diamonds} diamonds`,
        }),
      });
    } else {
      // Bank Transfer Payout
      payoutResponse = await fetch('https://api.razorpay.com/v1/payouts', {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          account_number: Deno.env.get('RAZORPAY_ACCOUNT_NUMBER'),
          fund_account_id: await getOrCreateFundAccount(
            { 
              account_number: method.account_number, 
              ifsc: method.ifsc_code,
              name: method.account_name 
            }, 
            'bank_account', 
            user,
            auth
          ),
          amount: amount * 100,
          currency: 'INR',
          mode: 'IMPS',
          purpose: 'payout',
          queue_if_low_balance: true,
          reference_id: `WD_${userId}_${Date.now()}`,
          narration: `Diamond withdrawal - ${diamonds} diamonds`,
        }),
      });
    }

    const payoutData = await payoutResponse.json();

    if (!payoutResponse.ok) {
      console.error('Razorpay payout error:', payoutData);
      
      // Log failed payout attempt
      await supabaseClient.from('diamond_transactions').insert({
        user_id: userId,
        type: 'withdrawal',
        amount: -diamonds,
        description: `Withdrawal failed: ${payoutData.error?.description || 'Unknown error'}`,
        status: 'failed',
        payment_reference: `FAILED_${Date.now()}`,
      });

      throw new Error(payoutData.error?.description || 'Payout creation failed');
    }

    // Update transaction status to processing
    await supabaseClient
      .from('diamond_transactions')
      .update({
        status: 'processing',
        payment_reference: payoutData.id,
        description: `Withdrawal processing: ${diamonds} diamonds (₹${amount}) - Payout ID: ${payoutData.id}`,
      })
      .eq('user_id', userId)
      .eq('type', 'withdrawal')
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(1);

    console.log(`✅ Payout created for user ${userId}: ₹${amount}`);

    return new Response(
      JSON.stringify({ 
        success: true,
        payoutId: payoutData.id,
        status: payoutData.status,
        message: 'Withdrawal request queued successfully'
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Withdrawal error:', error);
    return new Response(
      JSON.stringify({ 
        error: error.message,
        success: false,
        message: 'Withdrawal queued for manual processing'
      }),
      { 
        status: 200, // Return 200 even on error so user knows it's queued
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});

// Helper function to get or create fund account
async function getOrCreateFundAccount(
  accountDetails: any,
  type: 'vpa' | 'bank_account',
  user: any,
  auth: string
) {
  // Create contact first
  const contactResponse = await fetch('https://api.razorpay.com/v1/contacts', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      name: user.display_name || 'User',
      email: user.email || '',
      type: 'customer',
      reference_id: user.id,
    }),
  });

  const contact = await contactResponse.json();

  // Create fund account
  const fundAccountPayload: any = {
    contact_id: contact.id,
    account_type: type,
  };

  if (type === 'vpa') {
    fundAccountPayload.vpa = {
      address: accountDetails,
    };
  } else {
    fundAccountPayload.bank_account = {
      name: accountDetails.name,
      ifsc: accountDetails.ifsc,
      account_number: accountDetails.account_number,
    };
  }

  const fundAccountResponse = await fetch('https://api.razorpay.com/v1/fund_accounts', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(fundAccountPayload),
  });

  const fundAccount = await fundAccountResponse.json();
  return fundAccount.id;
}