import { Heart } from 'lucide-react';
import { cn } from '@/lib/utils';

type MembershipTier = 'free' | 'premium' | 'premium_plus';

interface HealthTokensProps {
  tokens: number;
  maxTokens?: number;
  size?: 'sm' | 'md' | 'lg';
  membershipTier?: MembershipTier;
}

export function HealthTokens({ 
  tokens, 
  maxTokens = 5, 
  size = 'md',
  membershipTier = 'free'
}: HealthTokensProps) {
  const sizeClasses = {
    sm: 'h-4 w-4',
    md: 'h-5 w-5',
    lg: 'h-6 w-6',
  };

  // Get heart color based on membership tier
  const getHeartColor = () => {
    switch (membershipTier) {
      case 'premium':
        return {
          fill: 'fill-blue-500',
          text: 'text-blue-500',
          glow: 'drop-shadow-[0_0_8px_rgb(59,130,246)]'
        };
      case 'premium_plus':
        return {
          fill: 'fill-yellow-500',
          text: 'text-yellow-500',
          glow: 'drop-shadow-[0_0_8px_rgb(234,179,8)]'
        };
      default:
        return {
          fill: 'fill-health',
          text: 'text-health',
          glow: 'drop-shadow-[0_0_8px_hsl(var(--health))]'
        };
    }
  };

  const heartColor = getHeartColor();

  return (
    <div className="flex items-center gap-1">
      {Array.from({ length: maxTokens }).map((_, i) => (
        <Heart
          key={i}
          className={cn(
            sizeClasses[size],
            'transition-all duration-300',
            i < tokens
              ? `${heartColor.fill} ${heartColor.text} ${heartColor.glow}`
              : 'text-muted-foreground/30'
          )}
        />
      ))}
    </div>
  );
}