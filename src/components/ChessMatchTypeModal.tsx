// src/components/ChessMatchTypeModal.tsx
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { useDiamondStore, MAX_BET_DIAMONDS } from '@/lib/diamondStore';
import { Swords, Gem, Trophy, X } from 'lucide-react';
import { cn } from '@/lib/utils';

interface ChessMatchTypeModalProps {
  opponentId: string;
  opponentName: string;
  opponentDiamonds: number;
  myDiamonds: number;
  onSelectNormal: () => void;
  onSelectBet: (betAmount: number) => void;
  onClose: () => void;
}

export function ChessMatchTypeModal({
  opponentId,
  opponentName,
  opponentDiamonds,
  myDiamonds,
  onSelectNormal,
  onSelectBet,
  onClose,
}: ChessMatchTypeModalProps) {
  const [showBetInput, setShowBetInput] = useState(false);
  const [betAmount, setBetAmount] = useState<string>('');
  const [error, setError] = useState<string>('');

  const maxBet = Math.min(myDiamonds, opponentDiamonds, MAX_BET_DIAMONDS);

  const handleBetChange = (value: string) => {
    setError('');
    setBetAmount(value);
    
    const amount = parseInt(value);
    
    if (isNaN(amount) || amount <= 0) {
      setError('Enter a valid bet amount');
      return;
    }
    
    if (amount > myDiamonds) {
      setError(`You only have ${myDiamonds} diamonds`);
      return;
    }
    
    if (amount > opponentDiamonds) {
      setError(`${opponentName} only has ${opponentDiamonds} diamonds`);
      return;
    }
    
    if (amount > MAX_BET_DIAMONDS) {
      setError(`Maximum bet is ${MAX_BET_DIAMONDS} diamonds`);
      return;
    }
  };

  const handleConfirmBet = () => {
    const amount = parseInt(betAmount);
    if (!isNaN(amount) && amount > 0 && !error) {
      onSelectBet(amount);
    }
  };

  if (showBetInput) {
    return (
      <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
        <div className="glass-strong rounded-2xl p-6 max-w-md w-full space-y-6 animate-slide-up">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Gem className="h-6 w-6 text-blue-500" />
              <h3 className="text-xl font-bold">Set Bet Amount</h3>
            </div>
            <button
              onClick={onClose}
              className="rounded-full p-2 hover:bg-muted transition-colors"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="space-y-4">
            <div className="glass rounded-xl p-4 space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Your Balance:</span>
                <span className="font-medium flex items-center gap-1">
                  {myDiamonds} <Gem className="h-3 w-3 text-blue-500" />
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">{opponentName}'s Balance:</span>
                <span className="font-medium flex items-center gap-1">
                  {opponentDiamonds} <Gem className="h-3 w-3 text-blue-500" />
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Max Bet:</span>
                <span className="font-medium flex items-center gap-1">
                  {maxBet} <Gem className="h-3 w-3 text-blue-500" />
                </span>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Bet Amount</label>
              <div className="relative">
                <input
                  type="number"
                  value={betAmount}
                  onChange={(e) => handleBetChange(e.target.value)}
                  placeholder="Enter bet amount"
                  min="1"
                  max={maxBet}
                  className="w-full px-4 py-3 rounded-xl bg-background border-2 border-border focus:border-primary outline-none transition-colors"
                />
                <Gem className="absolute right-3 top-1/2 -translate-y-1/2 h-5 w-5 text-blue-500" />
              </div>
              {error && (
                <p className="text-sm text-destructive">{error}</p>
              )}
              {betAmount && !error && (
                <p className="text-sm text-muted-foreground">
                  Winner gets: {parseInt(betAmount) * 2} diamonds
                </p>
              )}
            </div>

            <div className="grid grid-cols-3 gap-2">
              {[50, 100, 200].map((amount) => (
                <Button
                  key={amount}
                  variant="outline"
                  size="sm"
                  onClick={() => handleBetChange(amount.toString())}
                  disabled={amount > maxBet}
                  className="text-xs"
                >
                  {amount}
                </Button>
              ))}
            </div>
          </div>

          <div className="flex gap-3">
            <Button
              variant="outline"
              className="flex-1"
              onClick={() => setShowBetInput(false)}
            >
              Back
            </Button>
            <Button
              variant="hero"
              className="flex-1"
              onClick={handleConfirmBet}
              disabled={!betAmount || !!error}
            >
              Send Challenge
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="glass-strong rounded-2xl p-6 max-w-md w-full space-y-6 animate-slide-up">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Swords className="h-6 w-6 text-primary" />
            <h3 className="text-xl font-bold">Chess Challenge</h3>
          </div>
          <button
            onClick={onClose}
            className="rounded-full p-2 hover:bg-muted transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <p className="text-center text-muted-foreground">
          Challenge <span className="font-semibold text-foreground">{opponentName}</span> to a chess match
        </p>

        <div className="space-y-3">
          {/* Normal Match */}
          <button
            onClick={onSelectNormal}
            className="w-full glass hover:bg-muted/50 rounded-xl p-4 transition-all hover:scale-[1.02] active:scale-[0.98] text-left"
          >
            <div className="flex items-start gap-3">
              <div className="p-2 rounded-lg bg-primary/10">
                <Swords className="h-5 w-5 text-primary" />
              </div>
              <div className="flex-1">
                <h4 className="font-semibold mb-1">Normal Match</h4>
                <p className="text-sm text-muted-foreground">
                  Play for fun, no diamonds at stake
                </p>
              </div>
            </div>
          </button>

          {/* Bet Match */}
          <button
            onClick={() => setShowBetInput(true)}
            className={cn(
              "w-full rounded-xl p-4 transition-all hover:scale-[1.02] active:scale-[0.98] text-left",
              "bg-gradient-to-br from-amber-500/20 to-orange-500/20 hover:from-amber-500/30 hover:to-orange-500/30",
              "border-2 border-amber-500/30 hover:border-amber-500/50"
            )}
          >
            <div className="flex items-start gap-3">
              <div className="p-2 rounded-lg bg-amber-500/20">
                <Trophy className="h-5 w-5 text-amber-500" />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <h4 className="font-semibold">Bet Match</h4>
                  <Gem className="h-4 w-4 text-blue-500" />
                </div>
                <p className="text-sm text-muted-foreground mb-2">
                  Play for diamonds, winner takes all
                </p>
                <div className="flex items-center gap-2 text-xs">
                  <span className="px-2 py-1 rounded-full bg-background/50">
                    Your: {myDiamonds} 💎
                  </span>
                  <span className="px-2 py-1 rounded-full bg-background/50">
                    {opponentName}: {opponentDiamonds} 💎
                  </span>
                </div>
              </div>
            </div>
          </button>
        </div>

        <div className="text-xs text-center text-muted-foreground space-y-1">
          <p>• Max bet: {MAX_BET_DIAMONDS} diamonds per match</p>
          <p>• Winner receives 2x the bet amount</p>
        </div>
      </div>
    </div>
  );
}