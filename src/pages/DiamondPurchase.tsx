// src/pages/DiamondPurchase.tsx - FIXED VERSION
import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { useUserStore } from '@/lib/userStore';
import { useDiamondStore, DIAMOND_PACKAGES } from '@/lib/diamondStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Gem, ArrowLeft, CheckCircle, Sparkles, Shield, CreditCard, Building2 } from 'lucide-react';
import { cn } from '@/lib/utils';

// Declare Razorpay type for TypeScript
declare global {
  interface Window {
    Razorpay: any;
  }
}

export default function DiamondPurchase() {
  const { id: userId, displayName } = useUserStore();
  const { diamonds, refreshDiamonds } = useDiamondStore();
  const [selectedPackage, setSelectedPackage] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [showPaymentMethods, setShowPaymentMethods] = useState(false);
  const [razorpayLoaded, setRazorpayLoaded] = useState(false);

  // Load Razorpay script with proper error handling
  useEffect(() => {
    // Check if already loaded
    if (window.Razorpay) {
      setRazorpayLoaded(true);
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    
    script.onload = () => {
      setRazorpayLoaded(true);
    };
    
    script.onerror = () => {
      toast.error('Failed to load payment gateway. Please refresh the page.');
    };
    
    document.body.appendChild(script);
    
    return () => {
      // Only remove if we added it
      if (document.body.contains(script)) {
        document.body.removeChild(script);
      }
    };
  }, []);

  const handlePackageSelect = (packageId: string) => {
    setSelectedPackage(packageId);
    setShowPaymentMethods(true);
  };

  const handleRazorpayPayment = async (packageId: string) => {
    if (!userId) {
      toast.error('Please login first');
      return;
    }

    if (!razorpayLoaded) {
      toast.error('Payment gateway is loading. Please wait...');
      return;
    }

    const pkg = DIAMOND_PACKAGES.find(p => p.id === packageId);
    if (!pkg) return;

    // Check if Razorpay key is configured
    const razorpayKey = import.meta.env.VITE_RAZORPAY_KEY_ID;
    if (!razorpayKey) {
      toast.error('Payment gateway not configured. Please contact support.');
      console.error('VITE_RAZORPAY_KEY_ID not found in environment variables');
      return;
    }

    setIsProcessing(true);

    try {
      // Step 1: Create order on backend
      const { data: orderData, error: orderError } = await supabase.functions.invoke('create-diamond-order', {
        body: {
          amount: pkg.price,
          diamonds: pkg.diamonds,
          userId: userId,
        },
      });

      if (orderError) {
        console.error('Order creation error:', orderError);
        throw new Error(orderError.message || 'Failed to create order');
      }

      if (!orderData?.orderId) {
        throw new Error('Invalid order response');
      }

      // Step 2: Initialize Razorpay
      const options = {
        key: razorpayKey,
        amount: pkg.price * 100, // Razorpay expects amount in paise
        currency: 'INR',
        name: 'Your App Name',
        description: `Purchase ${pkg.diamonds} Diamonds`,
        order_id: orderData.orderId,
        handler: async function (response: any) {
          // Step 3: Verify payment on backend
          try {
            const { data: verifyData, error: verifyError } = await supabase.functions.invoke('verify-diamond-payment', {
              body: {
                razorpay_order_id: response.razorpay_order_id,
                razorpay_payment_id: response.razorpay_payment_id,
                razorpay_signature: response.razorpay_signature,
                userId: userId,
                diamonds: pkg.diamonds,
                amount: pkg.price,
              },
            });

            if (verifyError) {
              console.error('Verification error:', verifyError);
              throw new Error(verifyError.message || 'Payment verification failed');
            }

            if (verifyData?.success) {
              // Payment verified, refresh diamonds
              await refreshDiamonds(userId);
              toast.success(`Successfully purchased ${pkg.diamonds} diamonds! 💎`);
              setShowPaymentMethods(false);
              setSelectedPackage(null);
            } else {
              throw new Error('Payment verification failed');
            }
          } catch (error: any) {
            console.error('Payment verification error:', error);
            toast.error(error.message || 'Payment verification failed. Contact support if amount was deducted.');
          } finally {
            setIsProcessing(false);
          }
        },
        prefill: {
          name: displayName || 'User',
          email: '', // Add user email if available
          contact: '', // Add user phone if available
        },
        notes: {
          user_id: userId,
          diamonds: pkg.diamonds,
        },
        theme: {
          color: '#3b82f6',
        },
        modal: {
          ondismiss: function() {
            setIsProcessing(false);
            toast.info('Payment cancelled');
          }
        }
      };

      const razorpay = new window.Razorpay(options);
      razorpay.open();

    } catch (error: any) {
      console.error('Payment error:', error);
      toast.error(error.message || 'Failed to initiate payment. Please try again.');
      setIsProcessing(false);
    }
  };

  // For demo/testing - remove in production
  const handleTestPurchase = async (packageId: string) => {
    if (!userId) {
      toast.error('Please login first');
      return;
    }
    
    const pkg = DIAMOND_PACKAGES.find(p => p.id === packageId);
    if (!pkg) return;

    setIsProcessing(true);

    try {
      // Use the add_diamonds function
      const { error: addError } = await supabase.rpc('add_diamonds', {
        p_user_id: userId,
        p_amount: pkg.diamonds
      });

      if (addError) {
        console.error('Add diamonds error:', addError);
        throw addError;
      }

      // Add transaction record
      const { error: txError } = await supabase.from('diamond_transactions').insert({
        user_id: userId,
        type: 'purchase',
        amount: pkg.diamonds,
        description: `TEST PURCHASE: ${pkg.diamonds} diamonds`,
        status: 'completed',
      });

      if (txError) {
        console.error('Transaction record error:', txError);
      }

      // Refresh diamonds display
      await refreshDiamonds(userId);
      toast.success(`TEST: Added ${pkg.diamonds} diamonds!`);
      setShowPaymentMethods(false);
      setSelectedPackage(null);
    } catch (error: any) {
      console.error('Test purchase error:', error);
      toast.error(error.message || 'Failed to add diamonds');
    } finally {
      setIsProcessing(false);
    }
  };

  const goBack = () => {
    window.history.back();
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-background via-background to-muted/20 p-4">
      <div className="max-w-4xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <Button variant="ghost" onClick={goBack} className="gap-2">
            <ArrowLeft className="h-4 w-4" />
            Back
          </Button>
          <Logo size="sm" />
        </div>

        {/* Current Balance */}
        <div className="glass-strong rounded-3xl p-6 text-center relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-blue-500/5 to-purple-500/5" />
          <div className="relative">
            <div className="flex items-center justify-center gap-3 mb-2">
              <Gem className="h-8 w-8 text-blue-500" />
              <h2 className="text-4xl font-bold">{diamonds}</h2>
            </div>
            <p className="text-muted-foreground">Your Diamond Balance</p>
            <p className="text-sm text-muted-foreground mt-1">
              ≈ ₹{(diamonds * 5).toFixed(0)}
            </p>
          </div>
        </div>

        {/* Title */}
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold flex items-center justify-center gap-2">
            <Sparkles className="h-8 w-8 text-yellow-500" />
            Buy Diamonds
          </h1>
          <p className="text-muted-foreground">
            Secure payment powered by Razorpay | 1 Diamond = ₹5
          </p>
        </div>

        {/* Payment Method Modal */}
        {showPaymentMethods && selectedPackage && (
          <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
            <div className="glass-strong rounded-2xl p-6 max-w-md w-full space-y-6 animate-slide-up">
              <div className="flex items-center justify-between">
                <h3 className="text-xl font-bold">Select Payment Method</h3>
                <button
                  onClick={() => {
                    setShowPaymentMethods(false);
                    setSelectedPackage(null);
                  }}
                  className="rounded-full p-2 hover:bg-muted"
                >
                  ✕
                </button>
              </div>

              <div className="glass rounded-xl p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-muted-foreground">Selected Package:</span>
                  <span className="font-bold">
                    {DIAMOND_PACKAGES.find(p => p.id === selectedPackage)?.diamonds} 💎
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Amount:</span>
                  <span className="font-bold text-2xl">
                    ₹{DIAMOND_PACKAGES.find(p => p.id === selectedPackage)?.price}
                  </span>
                </div>
              </div>

              <div className="space-y-3">
                {/* Razorpay Payment */}
                <button
                  onClick={() => handleRazorpayPayment(selectedPackage)}
                  disabled={isProcessing || !razorpayLoaded}
                  className="w-full glass hover:bg-muted/50 rounded-xl p-4 transition-all text-left flex items-center gap-3 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <div className="p-2 rounded-lg bg-blue-500/10">
                    <CreditCard className="h-6 w-6 text-blue-500" />
                  </div>
                  <div className="flex-1">
                    <h4 className="font-semibold">Pay with Razorpay</h4>
                    <p className="text-xs text-muted-foreground">
                      {razorpayLoaded ? 'UPI, Cards, Net Banking & more' : 'Loading...'}
                    </p>
                  </div>
                  <Shield className="h-5 w-5 text-green-500" />
                </button>

                {/* Test Payment - REMOVE IN PRODUCTION */}
                <button
                  onClick={() => handleTestPurchase(selectedPackage)}
                  disabled={isProcessing}
                  className="w-full glass hover:bg-muted/50 rounded-xl p-4 transition-all text-left flex items-center gap-3 border-2 border-yellow-500/30 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <div className="p-2 rounded-lg bg-yellow-500/10">
                    <Building2 className="h-6 w-6 text-yellow-500" />
                  </div>
                  <div className="flex-1">
                    <h4 className="font-semibold text-yellow-500">Test Purchase</h4>
                    <p className="text-xs text-muted-foreground">
                      For testing only - Remove in production
                    </p>
                  </div>
                </button>
              </div>

              {isProcessing && (
                <div className="text-center text-sm text-muted-foreground">
                  Processing payment...
                </div>
              )}
            </div>
          </div>
        )}

        {/* Packages */}
        <div className="grid gap-4 md:grid-cols-3">
          {DIAMOND_PACKAGES.map((pkg) => (
            <div
              key={pkg.id}
              className={cn(
                "glass-strong rounded-2xl p-6 relative overflow-hidden transition-all hover:scale-[1.02]",
                pkg.popular && "ring-2 ring-primary shadow-xl md:scale-105"
              )}
            >
              {pkg.popular && (
                <div className="absolute top-0 right-0 bg-primary text-primary-foreground px-3 py-1 text-xs font-bold rounded-bl-lg">
                  POPULAR
                </div>
              )}
              
              <div className="text-center space-y-4">
                <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-gradient-to-br from-blue-500/20 to-purple-500/20">
                  <Gem className={cn(
                    "h-8 w-8",
                    pkg.popular ? "text-primary" : "text-blue-500"
                  )} />
                </div>

                <div>
                  <div className="flex items-center justify-center gap-2 mb-1">
                    <h3 className="text-3xl font-bold">{pkg.diamonds}</h3>
                    <Gem className="h-5 w-5 text-blue-500" />
                  </div>
                  {pkg.bonus && (
                    <p className="text-xs text-green-500 font-medium">
                      +{pkg.bonus} bonus diamonds
                    </p>
                  )}
                </div>

                <div className="space-y-1">
                  <p className="text-2xl font-bold">₹{pkg.price}</p>
                  <p className="text-xs text-muted-foreground">
                    ₹{(pkg.price / pkg.diamonds).toFixed(1)} per diamond
                  </p>
                </div>

                <Button
                  variant={pkg.popular ? "hero" : "default"}
                  className="w-full"
                  onClick={() => handlePackageSelect(pkg.id)}
                  disabled={isProcessing}
                >
                  Buy Now
                </Button>
              </div>
            </div>
          ))}
        </div>

        {/* Payment Features */}
        <div className="glass rounded-2xl p-6 space-y-4">
          <h3 className="font-bold flex items-center gap-2">
            <Shield className="h-5 w-5 text-green-500" />
            Secure Payment
          </h3>
          <div className="grid md:grid-cols-2 gap-4 text-sm">
            <div className="flex items-start gap-2">
              <CheckCircle className="h-4 w-4 text-green-500 mt-0.5" />
              <div>
                <p className="font-medium">100% Secure</p>
                <p className="text-muted-foreground text-xs">Encrypted transactions via Razorpay</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle className="h-4 w-4 text-green-500 mt-0.5" />
              <div>
                <p className="font-medium">Multiple Payment Options</p>
                <p className="text-muted-foreground text-xs">UPI, Cards, Net Banking, Wallets</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle className="h-4 w-4 text-green-500 mt-0.5" />
              <div>
                <p className="font-medium">Instant Delivery</p>
                <p className="text-muted-foreground text-xs">Diamonds added immediately after payment</p>
              </div>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle className="h-4 w-4 text-green-500 mt-0.5" />
              <div>
                <p className="font-medium">24/7 Support</p>
                <p className="text-muted-foreground text-xs">Help with any payment issues</p>
              </div>
            </div>
          </div>
        </div>

        {/* Info Section */}
        <div className="glass rounded-2xl p-6 space-y-4">
          <h3 className="font-bold flex items-center gap-2">
            <CheckCircle className="h-5 w-5 text-blue-500" />
            How it works
          </h3>
          <ul className="space-y-2 text-sm text-muted-foreground">
            <li>• Select a diamond package that suits your needs</li>
            <li>• Choose your preferred payment method</li>
            <li>• Complete payment securely via Razorpay</li>
            <li>• Diamonds are added to your account instantly</li>
            <li>• Use diamonds to place bets in chess matches</li>
            <li>• Win matches to earn more diamonds</li>
            <li>• Withdraw diamonds anytime (minimum 15 diamonds = ₹75)</li>
          </ul>
        </div>
      </div>
    </div>
  );
}