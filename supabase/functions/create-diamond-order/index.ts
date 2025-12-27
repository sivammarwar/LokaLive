// supabase/functions/create-diamond-order/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    console.log('🚀 Starting create-diamond-order function');

    // Get environment variables
    const RAZORPAY_KEY_ID = Deno.env.get('RAZORPAY_KEY_ID');
    const RAZORPAY_KEY_SECRET = Deno.env.get('RAZORPAY_KEY_SECRET');

    console.log('🔑 Razorpay Key ID:', RAZORPAY_KEY_ID ? 'Present' : 'Missing');
    console.log('🔑 Razorpay Secret:', RAZORPAY_KEY_SECRET ? 'Present' : 'Missing');

    if (!RAZORPAY_KEY_ID || !RAZORPAY_KEY_SECRET) {
      console.error('❌ Razorpay credentials not found');
      return new Response(
        JSON.stringify({ 
          error: 'Razorpay credentials not configured. Please contact support.' 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const requestBody = await req.json();
    console.log('📦 Request body:', requestBody);

    const { amount, diamonds, userId } = requestBody;

    // Validate input
    if (!amount || !diamonds || !userId) {
      console.error('❌ Missing required fields');
      return new Response(
        JSON.stringify({ 
          error: 'Missing required fields',
          received: { amount, diamonds, userId }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create Razorpay order
    console.log('💳 Creating Razorpay order...');
    const auth = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`);
    
    // Generate short receipt (max 40 chars)
    const timestamp = Date.now().toString().slice(-8); // Last 8 digits
    const userIdShort = userId.slice(0, 8); // First 8 chars of user ID
    const receipt = `DIA_${userIdShort}_${timestamp}`; // Total ~25 chars
    
    const orderPayload = {
      amount: amount * 100, // Convert to paise
      currency: 'INR',
      receipt: receipt,
      notes: {
        user_id: userId,
        diamonds: diamonds,
      },
    };

    console.log('📤 Sending to Razorpay:', orderPayload);

    const orderResponse = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(orderPayload),
    });

    console.log('📥 Razorpay response status:', orderResponse.status);

    if (!orderResponse.ok) {
      const errorData = await orderResponse.json();
      console.error('❌ Razorpay error:', errorData);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to create Razorpay order',
          details: errorData 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const orderData = await orderResponse.json();
    console.log('✅ Razorpay order created:', orderData.id);

    // Log order creation in database
    try {
      const supabaseClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );

      const { error: dbError } = await supabaseClient.from('diamond_transactions').insert({
        user_id: userId,
        type: 'purchase',
        amount: diamonds,
        description: `Razorpay order created: ${orderData.id}`,
        status: 'pending',
        payment_reference: orderData.id,
      });

      if (dbError) {
        console.error('⚠️ Database error (non-critical):', dbError);
      } else {
        console.log('✅ Transaction logged in database');
      }
    } catch (dbError) {
      console.error('⚠️ Failed to log transaction:', dbError);
      // Continue anyway - order is created
    }

    console.log('🎉 Order creation successful');

    return new Response(
      JSON.stringify({ 
        orderId: orderData.id,
        amount: orderData.amount,
        currency: orderData.currency,
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('💥 Unhandled error:', error);
    return new Response(
      JSON.stringify({ 
        error: error.message || 'Internal server error',
        stack: error.stack
      }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});