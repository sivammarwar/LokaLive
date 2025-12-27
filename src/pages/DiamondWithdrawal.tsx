// src/pages/DiamondWithdrawal.tsx
import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { useUserStore } from '@/lib/userStore';
import { useDiamondStore, MIN_WITHDRAWAL_DIAMONDS } from '@/lib/diamondStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { 
  Gem, 
  ArrowLeft, 
  Wallet, 
  Building2, 
  AlertCircle,
  CheckCircle,
  IndianRupee,
  CreditCard,
  Clock,
  Loader2,
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface WithdrawalMethod {
  id: string;
  type: 'upi' | 'bank';
  accountName?: string;
  accountNumber?: string;
  ifscCode?: string;
  upiId?: string;
  isVerified: boolean;
}

export default function DiamondWithdrawal() {
  const { id: userId, displayName } = useUserStore();
  const { diamonds, refreshDiamonds, isLoading } = useDiamondStore();
  
  const [withdrawalAmount, setWithdrawalAmount] = useState<string>('');
  const [selectedMethod, setSelectedMethod] = useState<WithdrawalMethod | null>(null);
  const [withdrawalMethods, setWithdrawalMethods] = useState<WithdrawalMethod[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [showAddMethod, setShowAddMethod] = useState(false);
  const [pendingWithdrawals, setPendingWithdrawals] = useState<any[]>([]);
  
  // New payment method form
  const [methodType, setMethodType] = useState<'upi' | 'bank'>('upi');
  const [upiId, setUpiId] = useState('');
  const [accountName, setAccountName] = useState('');
  const [accountNumber, setAccountNumber] = useState('');
  const [ifscCode, setIfscCode] = useState('');

  const rupeesAmount = parseInt(withdrawalAmount) * 5;
  const isValidAmount = parseInt(withdrawalAmount) >= MIN_WITHDRAWAL_DIAMONDS && parseInt(withdrawalAmount) <= diamonds;

  // ✅ FIX #1: Fetch diamond balance on page load
  useEffect(() => {
    if (!userId) return;

    console.log('🔄 Refreshing diamonds for user:', userId);
    refreshDiamonds(userId);
  }, [userId, refreshDiamonds]);

  // Fetch withdrawal methods and pending withdrawals
  useEffect(() => {
    if (!userId) return;

    const fetchData = async () => {
      // Fetch saved payment methods
      const { data: methods } = await supabase
        .from('withdrawal_methods')
        .select('*')
        .eq('user_id', userId);

      if (methods) {
        setWithdrawalMethods(methods);
      }

      // Fetch pending withdrawals
      const { data: withdrawals } = await supabase
        .from('diamond_transactions')
        .select('*')
        .eq('user_id', userId)
        .eq('type', 'withdrawal')
        .eq('status', 'pending')
        .order('created_at', { ascending: false });

      if (withdrawals) {
        setPendingWithdrawals(withdrawals);
      }
    };

    fetchData();
  }, [userId]);

  const handleAddPaymentMethod = async () => {
    if (!userId) return;

    try {
      setIsProcessing(true);

      const newMethod = {
        user_id: userId,
        type: methodType,
        upi_id: methodType === 'upi' ? upiId : null,
        account_name: methodType === 'bank' ? accountName : null,
        account_number: methodType === 'bank' ? accountNumber : null,
        ifsc_code: methodType === 'bank' ? ifscCode : null,
        is_verified: false,
      };

      const { data, error } = await supabase
        .from('withdrawal_methods')
        .insert(newMethod)
        .select()
        .single();

      if (error) throw error;

      setWithdrawalMethods([...withdrawalMethods, data]);
      toast.success('Payment method added successfully');
      setShowAddMethod(false);
      
      // Reset form
      setUpiId('');
      setAccountName('');
      setAccountNumber('');
      setIfscCode('');
    } catch (error) {
      console.error('Error adding payment method:', error);
      toast.error('Failed to add payment method');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleWithdrawal = async () => {
    if (!userId || !selectedMethod || !isValidAmount) return;

    try {
      setIsProcessing(true);

      const diamondsToWithdraw = parseInt(withdrawalAmount);
      const rupeesToTransfer = diamondsToWithdraw * 5;

      // Deduct diamonds first
      const { error: deductError } = await supabase.rpc('deduct_diamonds', {
        p_user_id: userId,
        p_amount: diamondsToWithdraw,
      });

      if (deductError) throw deductError;

      // Create withdrawal request
      const { error: transactionError } = await supabase
        .from('diamond_transactions')
        .insert({
          user_id: userId,
          type: 'withdrawal',
          amount: -diamondsToWithdraw, // Negative for withdrawal
          description: `Withdrawal request: ${diamondsToWithdraw} diamonds (₹${rupeesToTransfer}) via ${selectedMethod.type === 'upi' ? 'UPI' : 'Bank Transfer'}`,
          status: 'pending',
          payment_reference: `WD_${Date.now()}`,
        });

      if (transactionError) throw transactionError;

      // Call backend to process withdrawal
      const { error: withdrawalError } = await supabase.functions.invoke('process-withdrawal', {
        body: {
          userId,
          amount: rupeesToTransfer,
          diamonds: diamondsToWithdraw,
          method: selectedMethod,
        },
      });

      if (withdrawalError) {
        console.error('Withdrawal processing error:', withdrawalError);
        // Don't throw - withdrawal is queued even if immediate processing fails
      }

      // ✅ FIX #2: Refresh diamonds after withdrawal
      await refreshDiamonds(userId);
      
      toast.success(`Withdrawal request submitted! ₹${rupeesToTransfer} will be transferred within 24-48 hours.`);
      
      setWithdrawalAmount('');
      setSelectedMethod(null);
      
      // Refresh pending withdrawals
      const { data: withdrawals } = await supabase
        .from('diamond_transactions')
        .select('*')
        .eq('user_id', userId)
        .eq('type', 'withdrawal')
        .eq('status', 'pending')
        .order('created_at', { ascending: false });

      if (withdrawals) {
        setPendingWithdrawals(withdrawals);
      }

    } catch (error) {
      console.error('Withdrawal error:', error);
      toast.error('Failed to process withdrawal. Please try again.');
      
      // Refund diamonds if transaction failed
      if (parseInt(withdrawalAmount) > 0) {
        await supabase.rpc('add_diamonds', {
          p_user_id: userId,
          p_amount: parseInt(withdrawalAmount),
        });
        await refreshDiamonds(userId);
      }
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
        <div className="glass-strong rounded-3xl p-6 text-center">
          <div className="flex items-center justify-center gap-3 mb-2">
            <Gem className="h-8 w-8 text-blue-500" />
            {/* ✅ FIX #3: Show loading state while fetching */}
            {isLoading ? (
              <div className="flex items-center gap-2">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
                <span className="text-2xl text-muted-foreground">Loading...</span>
              </div>
            ) : (
              <h2 className="text-4xl font-bold">{diamonds}</h2>
            )}
          </div>
          <p className="text-muted-foreground">Available for Withdrawal</p>
          <p className="text-sm text-muted-foreground mt-1">
            ≈ ₹{(diamonds * 5).toFixed(0)}
          </p>
        </div>

        {/* Title */}
        <div className="text-center space-y-2">
          <h1 className="text-4xl font-bold flex items-center justify-center gap-2">
            <Wallet className="h-8 w-8 text-green-500" />
            Withdraw Diamonds
          </h1>
          <p className="text-muted-foreground">
            Convert your diamonds to real money | Minimum: {MIN_WITHDRAWAL_DIAMONDS} diamonds (₹{MIN_WITHDRAWAL_DIAMONDS * 5})
          </p>
        </div>

        {/* Withdrawal Form */}
        <div className="glass-strong rounded-2xl p-6 space-y-6">
          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-2 block">Withdrawal Amount</label>
              <div className="relative">
                <input
                  type="number"
                  value={withdrawalAmount}
                  onChange={(e) => setWithdrawalAmount(e.target.value)}
                  placeholder={`Minimum ${MIN_WITHDRAWAL_DIAMONDS} diamonds`}
                  min={MIN_WITHDRAWAL_DIAMONDS}
                  max={diamonds}
                  className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none transition-colors pr-12"
                  disabled={isLoading}
                />
                <Gem className="absolute right-3 top-1/2 -translate-y-1/2 h-5 w-5 text-blue-500" />
              </div>
              {withdrawalAmount && (
                <div className="mt-2 flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">You will receive:</span>
                  <span className="font-bold text-lg flex items-center gap-1">
                    <IndianRupee className="h-4 w-4" />
                    {rupeesAmount}
                  </span>
                </div>
              )}
              {withdrawalAmount && !isValidAmount && (
                <p className="text-sm text-destructive mt-2 flex items-center gap-1">
                  <AlertCircle className="h-4 w-4" />
                  {parseInt(withdrawalAmount) < MIN_WITHDRAWAL_DIAMONDS 
                    ? `Minimum withdrawal is ${MIN_WITHDRAWAL_DIAMONDS} diamonds`
                    : 'Insufficient balance'}
                </p>
              )}
            </div>

            {/* Quick amounts */}
            <div className="flex gap-2 flex-wrap">
              {[MIN_WITHDRAWAL_DIAMONDS, 50, 100, 200].map((amount) => (
                <Button
                  key={amount}
                  variant="outline"
                  size="sm"
                  onClick={() => setWithdrawalAmount(amount.toString())}
                  disabled={amount > diamonds || isLoading}
                >
                  {amount} 💎 (₹{amount * 5})
                </Button>
              ))}
            </div>
          </div>

          {/* Payment Methods */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <label className="text-sm font-medium">Select Payment Method</label>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setShowAddMethod(true)}
              >
                + Add Method
              </Button>
            </div>

            {withdrawalMethods.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">
                <Wallet className="h-12 w-12 mx-auto mb-2 opacity-50" />
                <p>No payment methods added yet</p>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAddMethod(true)}
                  className="mt-3"
                >
                  Add Payment Method
                </Button>
              </div>
            ) : (
              <div className="space-y-2">
                {withdrawalMethods.map((method) => (
                  <button
                    key={method.id}
                    onClick={() => setSelectedMethod(method)}
                    className={cn(
                      "w-full glass rounded-xl p-4 text-left transition-all",
                      selectedMethod?.id === method.id 
                        ? "ring-2 ring-primary bg-primary/10" 
                        : "hover:bg-muted/50"
                    )}
                  >
                    <div className="flex items-center gap-3">
                      {method.type === 'upi' ? (
                        <div className="p-2 rounded-lg bg-purple-500/10">
                          <CreditCard className="h-5 w-5 text-purple-500" />
                        </div>
                      ) : (
                        <div className="p-2 rounded-lg bg-blue-500/10">
                          <Building2 className="h-5 w-5 text-blue-500" />
                        </div>
                      )}
                      <div className="flex-1">
                        <p className="font-medium">
                          {method.type === 'upi' ? 'UPI' : 'Bank Account'}
                        </p>
                        <p className="text-sm text-muted-foreground">
                          {method.type === 'upi' 
                            ? method.upiId 
                            : `${method.accountName} - ${method.accountNumber?.slice(-4)}`}
                        </p>
                      </div>
                      {method.isVerified ? (
                        <CheckCircle className="h-5 w-5 text-green-500" />
                      ) : (
                        <Clock className="h-5 w-5 text-yellow-500" />
                      )}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>

          <Button
            variant="hero"
            className="w-full"
            onClick={handleWithdrawal}
            disabled={!isValidAmount || !selectedMethod || isProcessing || isLoading}
          >
            {isProcessing ? 'Processing...' : `Withdraw ₹${rupeesAmount || 0}`}
          </Button>
        </div>

        {/* Pending Withdrawals */}
        {pendingWithdrawals.length > 0 && (
          <div className="glass rounded-2xl p-6 space-y-4">
            <h3 className="font-bold flex items-center gap-2">
              <Clock className="h-5 w-5 text-yellow-500" />
              Pending Withdrawals
            </h3>
            <div className="space-y-2">
              {pendingWithdrawals.map((withdrawal) => (
                <div key={withdrawal.id} className="glass rounded-xl p-4 flex items-center justify-between">
                  <div>
                    <p className="font-medium">₹{Math.abs(withdrawal.amount) * 5}</p>
                    <p className="text-xs text-muted-foreground">
                      {new Date(withdrawal.created_at).toLocaleDateString()}
                    </p>
                  </div>
                  <span className="px-3 py-1 rounded-full text-xs bg-yellow-500/20 text-yellow-500">
                    Processing
                  </span>
                </div>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">
              * Withdrawals are processed within 24-48 hours
            </p>
          </div>
        )}

        {/* Info */}
        <div className="glass rounded-2xl p-6 space-y-4">
          <h3 className="font-bold flex items-center gap-2">
            <AlertCircle className="h-5 w-5 text-blue-500" />
            Withdrawal Information
          </h3>
          <ul className="space-y-2 text-sm text-muted-foreground">
            <li>• Minimum withdrawal: {MIN_WITHDRAWAL_DIAMONDS} diamonds (₹{MIN_WITHDRAWAL_DIAMONDS * 5})</li>
            <li>• Processing time: 24-48 hours</li>
            <li>• No withdrawal fees</li>
            <li>• Withdrawals are processed on business days only</li>
            <li>• Make sure your payment details are correct</li>
            <li>• Contact support if withdrawal takes longer than 48 hours</li>
          </ul>
        </div>
      </div>

      {/* Add Payment Method Modal */}
      {showAddMethod && (
        <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-strong rounded-2xl p-6 max-w-md w-full space-y-6">
            <div className="flex items-center justify-between">
              <h3 className="text-xl font-bold">Add Payment Method</h3>
              <button
                onClick={() => setShowAddMethod(false)}
                className="rounded-full p-2 hover:bg-muted"
              >
                ✕
              </button>
            </div>

            <div className="flex gap-2">
              <Button
                variant={methodType === 'upi' ? 'default' : 'outline'}
                className="flex-1"
                onClick={() => setMethodType('upi')}
              >
                UPI
              </Button>
              <Button
                variant={methodType === 'bank' ? 'default' : 'outline'}
                className="flex-1"
                onClick={() => setMethodType('bank')}
              >
                Bank Account
              </Button>
            </div>

            {methodType === 'upi' ? (
              <div className="space-y-4">
                <div>
                  <label className="text-sm font-medium mb-2 block">UPI ID</label>
                  <input
                    type="text"
                    value={upiId}
                    onChange={(e) => setUpiId(e.target.value)}
                    placeholder="yourname@paytm"
                    className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none"
                  />
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div>
                  <label className="text-sm font-medium mb-2 block">Account Holder Name</label>
                  <input
                    type="text"
                    value={accountName}
                    onChange={(e) => setAccountName(e.target.value)}
                    placeholder="John Doe"
                    className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none"
                  />
                </div>
                <div>
                  <label className="text-sm font-medium mb-2 block">Account Number</label>
                  <input
                    type="text"
                    value={accountNumber}
                    onChange={(e) => setAccountNumber(e.target.value)}
                    placeholder="1234567890"
                    className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none"
                  />
                </div>
                <div>
                  <label className="text-sm font-medium mb-2 block">IFSC Code</label>
                  <input
                    type="text"
                    value={ifscCode}
                    onChange={(e) => setIfscCode(e.target.value.toUpperCase())}
                    placeholder="SBIN0001234"
                    className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none"
                  />
                </div>
              </div>
            )}

            <Button
              variant="hero"
              className="w-full"
              onClick={handleAddPaymentMethod}
              disabled={
                isProcessing || 
                (methodType === 'upi' ? !upiId : (!accountName || !accountNumber || !ifscCode))
              }
            >
              {isProcessing ? 'Adding...' : 'Add Payment Method'}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}