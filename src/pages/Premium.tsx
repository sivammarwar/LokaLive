import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { useUserStore } from '@/lib/userStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import {
  Crown,
  Sparkles,
  Check,
  ArrowLeft,
  Shield,
  Zap,
  Star,
  Heart,
} from 'lucide-react';
import { cn } from '@/lib/utils';

type MembershipTier = 'free' | 'premium' | 'premium_plus';

interface PricingPlan {
  tier: MembershipTier;
  name: string;
  price: number;
  icon: React.ElementType;
  color: string;
  bgColor: string;
  borderColor: string;
  features: string[];
  popular?: boolean;
}

const pricingPlans: PricingPlan[] = [
  {
    tier: 'premium',
    name: 'Premium',
    price: 99,
    icon: Crown,
    color: 'text-blue-500',
    bgColor: 'bg-blue-500/10',
    borderColor: 'border-blue-500',
    features: [
      'Blue username & health hearts',
      'Premium badge display',
      'Reports reduce health by 1.5x',
      'Priority matching',
      'Ad-free experience',
    ],
  },
  {
    tier: 'premium_plus',
    name: 'Premium Plus',
    price: 199,
    icon: Sparkles,
    color: 'text-yellow-500',
    bgColor: 'bg-yellow-500/10',
    borderColor: 'border-yellow-500',
    popular: true,
    features: [
      'Golden username & health hearts',
      'Premium Plus badge display',
      'Reports reduce health by 1.5x',
      'Highest priority matching',
      'Ad-free experience',
      'Priority support',
      'Exclusive features (coming soon)',
    ],
  },
];

export default function Premium() {
  const navigate = useNavigate();
  const { id: userId } = useUserStore();
  const [isLoading, setIsLoading] = useState(false);
  const [currentTier, setCurrentTier] = useState<MembershipTier>('free');
  const [expiryDate, setExpiryDate] = useState<string | null>(null);

  // Redirect if not logged in
  useEffect(() => {
    if (!userId) {
      navigate('/');
      return;
    }

    // Fetch current membership
    const fetchMembership = async () => {
      const { data } = await supabase
        .from('users')
        .select('membership_tier, membership_expires_at')
        .eq('id', userId)
        .single();

      if (data) {
        setCurrentTier(data.membership_tier as MembershipTier);
        setExpiryDate(data.membership_expires_at);
      }
    };

    fetchMembership();
  }, [userId, navigate]);

  const handlePurchase = async (tier: MembershipTier, price: number) => {
    if (!userId) {
      toast.error('Please login to purchase');
      navigate('/');
      return;
    }

    setIsLoading(true);

    try {
      // Create a transaction record
      const { data: transaction, error: txError } = await supabase
        .from('transactions')
        .insert({
          user_id: userId,
          membership_tier: tier,
          amount: price,
          currency: 'INR',
          payment_status: 'pending',
        })
        .select()
        .single();

      if (txError) throw txError;

      // Initialize Razorpay
      const options = {
        key: import.meta.env.VITE_RAZORPAY_KEY_ID || 'rzp_test_placeholder', // Add your Razorpay key
        amount: price * 100, // Razorpay expects amount in paise
        currency: 'INR',
        name: 'Loka',
        description: `${tier === 'premium' ? 'Premium' : 'Premium Plus'} Membership (1 Month)`,
        handler: async function (response: any) {
          // Payment successful
          try {
            // Update transaction with payment details
            await supabase
              .from('transactions')
              .update({
                payment_status: 'completed',
                razorpay_payment_id: response.razorpay_payment_id,
                razorpay_order_id: response.razorpay_order_id,
                razorpay_signature: response.razorpay_signature,
              })
              .eq('id', transaction.id);

            toast.success('Payment successful! Your membership is now active.');
            
            // Refresh page to show updated status
            window.location.reload();
          } catch (error) {
            console.error('Error updating transaction:', error);
            toast.error('Payment successful but failed to update membership. Please contact support.');
          }
        },
        prefill: {
          name: useUserStore.getState().displayName || '',
          email: '', // You can add email from user profile if available
        },
        theme: {
          color: tier === 'premium' ? '#3b82f6' : '#eab308',
        },
        modal: {
          ondismiss: async function() {
            // Payment cancelled
            await supabase
              .from('transactions')
              .update({ payment_status: 'failed' })
              .eq('id', transaction.id);
            
            toast.info('Payment cancelled');
            setIsLoading(false);
          }
        }
      };

      // Check if Razorpay is loaded
      if (typeof (window as any).Razorpay !== 'undefined') {
        const razorpay = new (window as any).Razorpay(options);
        razorpay.open();
      } else {
        toast.error('Payment gateway not loaded. Please refresh the page.');
        setIsLoading(false);
      }
    } catch (error) {
      console.error('Purchase error:', error);
      toast.error('Failed to initiate payment. Please try again.');
      setIsLoading(false);
    }
  };

  const formatExpiryDate = (date: string | null) => {
    if (!date) return '';
    return new Date(date).toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
  };

  return (
    <>
      {/* Razorpay Script */}
      <script src="https://checkout.razorpay.com/v1/checkout.js"></script>

      <div className="min-h-screen flex flex-col p-4 relative overflow-hidden">
        {/* Background */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/10 rounded-full blur-[150px]" />
          <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-yellow-500/10 rounded-full blur-[150px]" />
        </div>

        {/* Header */}
        <header className="flex items-center justify-between mb-8 relative z-10">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate('/create-room')}
          >
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <Logo size="sm" />
          <div className="w-10" /> {/* Spacer for alignment */}
        </header>

        {/* Main Content */}
        <main className="flex-1 flex items-center justify-center relative z-10">
          <div className="w-full max-w-5xl space-y-8 animate-slide-up">
            {/* Header Section */}
            <div className="text-center space-y-4">
              <h1 className="text-4xl md:text-5xl font-bold">
                Upgrade Your Experience
              </h1>
              <p className="text-muted-foreground text-lg max-w-2xl mx-auto">
                Stand out with premium badges and colored hearts. Help keep the community safe with powerful reports.
              </p>

              {/* Current Membership Status */}
              {currentTier !== 'free' && expiryDate && (
                <div className="inline-flex items-center gap-2 glass rounded-full px-6 py-3 mt-4">
                  <Shield className="h-5 w-5 text-green-500" />
                  <span className="text-sm">
                    Active until <strong>{formatExpiryDate(expiryDate)}</strong>
                  </span>
                </div>
              )}
            </div>

            {/* Pricing Cards */}
            <div className="grid md:grid-cols-2 gap-6 max-w-4xl mx-auto">
              {pricingPlans.map((plan) => {
                const Icon = plan.icon;
                const isCurrentPlan = currentTier === plan.tier;
                
                return (
                  <div
                    key={plan.tier}
                    className={cn(
                      'relative glass-strong rounded-2xl p-8 space-y-6 transition-all duration-300',
                      plan.popular && 'ring-2 ring-yellow-500 scale-105',
                      isCurrentPlan && 'opacity-60'
                    )}
                  >
                    {/* Popular Badge */}
                    {plan.popular && (
                      <div className="absolute -top-4 left-1/2 -translate-x-1/2">
                        <div className="bg-yellow-500 text-yellow-950 px-4 py-1 rounded-full text-sm font-bold flex items-center gap-1">
                          <Star className="h-4 w-4 fill-yellow-950" />
                          Most Popular
                        </div>
                      </div>
                    )}

                    {/* Current Plan Badge */}
                    {isCurrentPlan && (
                      <div className="absolute top-4 right-4">
                        <div className="bg-green-500 text-green-950 px-3 py-1 rounded-full text-xs font-bold flex items-center gap-1">
                          <Check className="h-3 w-3" />
                          Active
                        </div>
                      </div>
                    )}

                    {/* Header */}
                    <div className="space-y-4">
                      <div className={cn(
                        'inline-flex items-center gap-3 px-4 py-2 rounded-full',
                        plan.bgColor,
                        plan.borderColor,
                        'border-2'
                      )}>
                        <Icon className={cn('h-6 w-6', plan.color)} />
                        <span className={cn('text-xl font-bold', plan.color)}>
                          {plan.name}
                        </span>
                      </div>
                      
                      <div className="flex items-baseline gap-2">
                        <span className="text-5xl font-bold">₹{plan.price}</span>
                        <span className="text-muted-foreground">/month</span>
                      </div>
                    </div>

                    {/* Features */}
                    <ul className="space-y-3">
                      {plan.features.map((feature, index) => (
                        <li key={index} className="flex items-start gap-3">
                          <div className={cn(
                            'rounded-full p-1 mt-0.5',
                            plan.bgColor
                          )}>
                            <Check className={cn('h-4 w-4', plan.color)} />
                          </div>
                          <span className="text-sm">{feature}</span>
                        </li>
                      ))}
                    </ul>

                    {/* CTA Button */}
                    <Button
                      variant={plan.popular ? 'default' : 'outline'}
                      size="lg"
                      className={cn(
                        'w-full',
                        plan.popular && 'bg-yellow-500 hover:bg-yellow-600 text-yellow-950'
                      )}
                      onClick={() => handlePurchase(plan.tier, plan.price)}
                      disabled={isLoading || isCurrentPlan}
                    >
                      {isLoading ? (
                        <div className="flex items-center gap-2">
                          <div className="w-5 h-5 border-2 border-current/30 border-t-current rounded-full animate-spin" />
                          Processing...
                        </div>
                      ) : isCurrentPlan ? (
                        'Current Plan'
                      ) : (
                        <>
                          <Zap className="h-5 w-5" />
                          Upgrade Now
                        </>
                      )}
                    </Button>
                  </div>
                );
              })}
            </div>

            {/* Benefits Section */}
            <div className="glass rounded-2xl p-8 max-w-3xl mx-auto">
              <h3 className="text-2xl font-bold text-center mb-6">
                Why Go Premium?
              </h3>
              <div className="grid md:grid-cols-3 gap-6">
                <div className="text-center space-y-2">
                  <div className="w-12 h-12 mx-auto rounded-full bg-blue-500/10 flex items-center justify-center">
                    <Heart className="h-6 w-6 text-blue-500" />
                  </div>
                  <h4 className="font-semibold">Stand Out</h4>
                  <p className="text-sm text-muted-foreground">
                    Premium colored names and hearts make you instantly recognizable
                  </p>
                </div>
                <div className="text-center space-y-2">
                  <div className="w-12 h-12 mx-auto rounded-full bg-yellow-500/10 flex items-center justify-center">
                    <Shield className="h-6 w-6 text-yellow-500" />
                  </div>
                  <h4 className="font-semibold">Stronger Reports</h4>
                  <p className="text-sm text-muted-foreground">
                    Your reports carry more weight (1.5x health reduction)
                  </p>
                </div>
                <div className="text-center space-y-2">
                  <div className="w-12 h-12 mx-auto rounded-full bg-green-500/10 flex items-center justify-center">
                    <Zap className="h-6 w-6 text-green-500" />
                  </div>
                  <h4 className="font-semibold">Priority Access</h4>
                  <p className="text-sm text-muted-foreground">
                    Get matched faster with priority queue placement
                  </p>
                </div>
              </div>
            </div>

            {/* FAQ or Additional Info */}
            <p className="text-center text-sm text-muted-foreground">
              All plans are valid for 30 days from purchase. 
              <br />
              Safe and secure payments powered by Razorpay.
            </p>
          </div>
        </main>
      </div>
    </>
  );
}