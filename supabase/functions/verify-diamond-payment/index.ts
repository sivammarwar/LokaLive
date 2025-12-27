// supabase/functions/verify-diamond-payment/index.ts - CORRECTED
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createHmac } from "https://deno.land/std@0.160.0/node/crypto.ts";

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
    console.log('🔐 Starting payment verification');

    const { 
      razorpay_order_id, 
      razorpay_payment_id, 
      razorpay_signature,
      userId,
      diamonds,
      amount,
    } = await req.json();

    console.log('📦 Received data:', { razorpay_order_id, razorpay_payment_id, userId, diamonds, amount });

    // Validate input
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature || !userId || !diamonds) {
      console.error('❌ Missing required fields');
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify signature
    console.log('🔍 Verifying signature...');
    const text = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expectedSignature = createHmac('sha256', RAZORPAY_KEY_SECRET)
      .update(text)
      .digest('hex');

    if (expectedSignature !== razorpay_signature) {
      console.error('❌ Signature verification failed');
      console.error('Expected:', expectedSignature);
      console.error('Received:', razorpay_signature);
      return new Response(
        JSON.stringify({ error: 'Invalid signature', success: false }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ Signature verified');

    // Initialize Supabase with service role
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Check if payment already processed (prevent double processing)
    console.log('🔍 Checking for duplicate payment...');
    const { data: existingTransaction } = await supabaseClient
      .from('diamond_transactions')
      .select('id')
      .eq('payment_reference', razorpay_payment_id)
      .eq('status', 'completed')
      .maybeSingle();

    if (existingTransaction) {
      console.log('⚠️ Payment already processed:', razorpay_payment_id);
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Payment already processed',
          alreadyProcessed: true,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // ✅ FIX: Use correct parameter names: p_user_id and p_amount
    console.log('💎 Adding diamonds to user...');
    const { error: addDiamondsError } = await supabaseClient.rpc('add_diamonds', {
      p_user_id: userId,  // ✅ Correct parameter name
      p_amount: diamonds,  // ✅ Correct parameter name
    });

    if (addDiamondsError) {
      console.error('❌ Error adding diamonds:', addDiamondsError);
      throw new Error('Failed to add diamonds: ' + addDiamondsError.message);
    }

    console.log('✅ Diamonds added successfully');

    // Update transaction record - first try to update pending transaction
    console.log('📝 Updating transaction record...');
    const { error: updateError } = await supabaseClient
      .from('diamond_transactions')
      .update({
        status: 'completed',
        payment_reference: razorpay_payment_id,
        description: `Successfully purchased ${diamonds} diamonds for ₹${amount} (Payment ID: ${razorpay_payment_id})`,
        updated_at: new Date().toISOString(),
      })
      .eq('payment_reference', razorpay_order_id)
      .eq('status', 'pending');

    // If no pending transaction found, create a new completed one
    if (updateError) {
      console.log('⚠️ No pending transaction found, creating new record...');
      const { error: insertError } = await supabaseClient
        .from('diamond_transactions')
        .insert({
          user_id: userId,
          type: 'purchase',
          amount: diamonds,
          description: `Successfully purchased ${diamonds} diamonds for ₹${amount} (Payment ID: ${razorpay_payment_id})`,
          status: 'completed',
          payment_reference: razorpay_payment_id,
        });

      if (insertError) {
        console.error('⚠️ Failed to create transaction record:', insertError);
        // Don't throw - diamonds are already added
      }
    }

    console.log('🎉 Payment verification complete');

    return new Response(
      JSON.stringify({ 
        success: true,
        diamonds: diamonds,
        message: 'Payment verified and diamonds added successfully'
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('💥 Error:', error);
    return new Response(
      JSON.stringify({ error: error.message, success: false }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});