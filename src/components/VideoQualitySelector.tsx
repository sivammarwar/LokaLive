import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Sparkles, Crown, Lock } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

type VideoQuality = 'sd' | 'hd' | 'fullhd';
type MembershipTier = 'free' | 'premium' | 'premium_plus';

interface VideoQualitySelectorProps {
  currentQuality: VideoQuality;
  membershipTier: MembershipTier;
  onQualityChange: (quality: VideoQuality) => void;
  disabled?: boolean;
}

const qualityConfig = {
  sd: {
    label: 'SD',
    resolution: '480p',
    icon: null,
    requiredTier: 'free' as MembershipTier,
  },
  hd: {
    label: 'HD',
    resolution: '720p',
    icon: Crown,
    requiredTier: 'premium' as MembershipTier,
  },
  fullhd: {
    label: 'Full HD',
    resolution: '1080p',
    icon: Sparkles,
    requiredTier: 'premium_plus' as MembershipTier,
  },
};

const tierHierarchy = {
  free: 0,
  premium: 1,
  premium_plus: 2,
};

export function VideoQualitySelector({
  currentQuality,
  membershipTier,
  onQualityChange,
  disabled = false,
}: VideoQualitySelectorProps) {
  const [hoveredQuality, setHoveredQuality] = useState<VideoQuality | null>(null);

  const canAccessQuality = (quality: VideoQuality): boolean => {
    const required = qualityConfig[quality].requiredTier;
    return tierHierarchy[membershipTier] >= tierHierarchy[required];
  };

  const handleQualityClick = (quality: VideoQuality) => {
    if (disabled) return;

    if (!canAccessQuality(quality)) {
      const config = qualityConfig[quality];
      const tierName = config.requiredTier === 'premium_plus' ? 'Premium+' : 'Premium';
      toast.error(`${config.label} quality requires ${tierName} membership`);
      return;
    }

    if (quality !== currentQuality) {
      onQualityChange(quality);
      toast.success(`Video quality changed to ${qualityConfig[quality].label}`);
    }
  };

  return (
    <div className="flex items-center gap-2 glass rounded-full px-3 py-2">
      {(Object.keys(qualityConfig) as VideoQuality[]).map((quality) => {
        const config = qualityConfig[quality];
        const hasAccess = canAccessQuality(quality);
        const isActive = currentQuality === quality;
        const isHovered = hoveredQuality === quality;
        const Icon = config.icon;

        return (
          <div key={quality} className="relative">
            <Button
              variant={isActive ? 'default' : 'ghost'}
              size="sm"
              onClick={() => handleQualityClick(quality)}
              onMouseEnter={() => setHoveredQuality(quality)}
              onMouseLeave={() => setHoveredQuality(null)}
              disabled={disabled}
              className={cn(
                'relative rounded-full px-3 py-1.5 text-xs font-medium transition-all',
                isActive && hasAccess && 'bg-primary text-primary-foreground',
                isActive && !hasAccess && 'bg-muted text-muted-foreground cursor-not-allowed',
                !isActive && hasAccess && 'hover:bg-muted',
                !isActive && !hasAccess && 'text-muted-foreground/50 cursor-not-allowed',
                membershipTier === 'premium_plus' && quality === 'fullhd' && isActive && 
                  'bg-gradient-to-r from-amber-500 to-yellow-500 hover:from-amber-600 hover:to-yellow-600',
                membershipTier === 'premium' && quality === 'hd' && isActive && 
                  'bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700'
              )}
            >
              <span className="flex items-center gap-1.5">
                {Icon && <Icon className="h-3 w-3" />}
                {config.label}
              </span>
              
              {!hasAccess && (
                <span className="absolute -top-1 -right-1 flex items-center justify-center w-4 h-4 rounded-full bg-red-500 text-white text-[10px] font-bold">
                  P
                </span>
              )}
            </Button>

            {/* Tooltip */}
            {isHovered && !hasAccess && (
              <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 bg-popover border border-border rounded-lg shadow-lg whitespace-nowrap z-50 animate-in fade-in-0 zoom-in-95">
                <div className="flex items-center gap-2">
                  <Lock className="h-3 w-3 text-muted-foreground" />
                  <span className="text-xs font-medium">
                    {config.requiredTier === 'premium_plus' 
                      ? 'Buy Premium+ to unlock' 
                      : 'Buy Premium to unlock'}
                  </span>
                </div>
                <div className="absolute top-full left-1/2 -translate-x-1/2 -mt-px">
                  <div className="border-4 border-transparent border-t-popover" />
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}