// src/lib/premiumStyles.ts

export type MembershipTier = 'free' | 'premium' | 'premium_plus';

export interface MembershipStyle {
  textColor: string;
  bgColor: string;
  borderColor: string;
  gradientFrom: string;
  gradientTo: string;
  glowColor: string;
  iconColor: string;
  label: string;
  videoFrame: string;
  videoGlow: string;
  videoBorder: string;
  nameTag: string;
  nameTagText: string;
  controlsBg: string;
  buttonHover: string;
  accentColor: string;
}

export const getMembershipStyle = (tier: MembershipTier): MembershipStyle => {
  switch (tier) {
    case 'premium':
      return {
        textColor: 'text-blue-400',
        bgColor: 'bg-blue-950/40',
        borderColor: 'border-blue-500/60',
        gradientFrom: 'from-blue-900/30',
        gradientTo: 'to-blue-950/50',
        glowColor: 'shadow-blue-500/30',
        iconColor: 'text-blue-400',
        label: 'Premium',
        videoFrame: 'border-blue-500/70',
        videoGlow: 'shadow-lg shadow-blue-500/40',
        videoBorder: 'border-2',
        nameTag: 'bg-gradient-to-r from-blue-950/90 to-blue-900/80 backdrop-blur-md border border-blue-500/40',
        nameTagText: 'text-blue-300',
        controlsBg: 'bg-blue-950/60',
        buttonHover: 'hover:bg-blue-500/30',
        accentColor: '#3b82f6',
      };
    
    case 'premium_plus':
      return {
        textColor: 'text-transparent bg-clip-text bg-gradient-to-r from-amber-200 via-yellow-400 to-amber-200',
        bgColor: 'bg-gradient-to-br from-amber-950/40 via-yellow-950/30 to-amber-950/40',
        borderColor: 'border-yellow-500/70',
        gradientFrom: 'from-amber-900/40',
        gradientTo: 'to-yellow-900/40',
        glowColor: 'shadow-yellow-500/50',
        iconColor: 'text-yellow-400',
        label: 'Premium+',
        videoFrame: 'border-yellow-500/90 border-[3px]',
        videoGlow: 'shadow-2xl shadow-yellow-500/60 ring-2 ring-yellow-400/30',
        videoBorder: 'border-[3px]',
        nameTag: 'bg-gradient-to-r from-amber-950/95 via-yellow-950/90 to-amber-950/95 backdrop-blur-xl border-2 border-yellow-500/60 shadow-lg shadow-yellow-500/30',
        nameTagText: 'text-transparent bg-clip-text bg-gradient-to-r from-amber-300 via-yellow-300 to-amber-300 font-semibold',
        controlsBg: 'bg-gradient-to-r from-amber-950/80 via-yellow-950/70 to-amber-950/80',
        buttonHover: 'hover:bg-yellow-500/40 hover:shadow-lg hover:shadow-yellow-500/50',
        accentColor: '#eab308',
      };
    
    default:
      return {
        textColor: 'text-foreground',
        bgColor: 'bg-muted/30',
        borderColor: 'border-border',
        gradientFrom: 'from-muted/20',
        gradientTo: 'to-card/20',
        glowColor: 'shadow-none',
        iconColor: 'text-muted-foreground',
        label: '',
        videoFrame: 'border-border',
        videoGlow: 'shadow-none',
        videoBorder: 'border-2',
        nameTag: 'bg-background/80 backdrop-blur-sm border border-border/60',
        nameTagText: 'text-foreground',
        controlsBg: 'bg-background/70',
        buttonHover: 'hover:bg-muted/50',
        accentColor: '#6b7280',
      };
  }
};

// Animated gradient for Premium Plus
export const premiumPlusGradient = `
  @keyframes shimmer {
    0% {
      background-position: 0% 50%;
    }
    50% {
      background-position: 100% 50%;
    }
    100% {
      background-position: 0% 50%;
    }
  }
  
  .premium-plus-shimmer {
    background: linear-gradient(
      90deg,
      rgba(251, 191, 36, 0.3) 0%,
      rgba(234, 179, 8, 0.5) 25%,
      rgba(253, 224, 71, 0.4) 50%,
      rgba(234, 179, 8, 0.5) 75%,
      rgba(251, 191, 36, 0.3) 100%
    );
    background-size: 200% 200%;
    animation: shimmer 3s ease-in-out infinite;
  }
  
  .premium-plus-glow {
    box-shadow: 
      0 0 20px rgba(234, 179, 8, 0.3),
      0 0 40px rgba(234, 179, 8, 0.2),
      inset 0 0 20px rgba(234, 179, 8, 0.1);
  }
  
  .premium-glow {
    box-shadow: 
      0 0 15px rgba(59, 130, 246, 0.2),
      0 0 30px rgba(59, 130, 246, 0.15);
  }
`;

// Video container wrapper component props
export interface PremiumVideoWrapperProps {
  tier: MembershipTier;
  children: React.ReactNode;
  className?: string;
  isFullscreen?: boolean;
}

export const getPremiumVideoClasses = (tier: MembershipTier, isFullscreen = false) => {
  const style = getMembershipStyle(tier);
  
  if (tier === 'premium_plus') {
    return {
      container: `${style.videoFrame} ${style.videoGlow} ${style.videoBorder} ${
        isFullscreen ? 'premium-plus-glow' : ''
      }`,
      overlay: 'premium-plus-shimmer',
      particles: true,
    };
  }
  
  if (tier === 'premium') {
    return {
      container: `${style.videoFrame} ${style.videoGlow} ${style.videoBorder} ${
        isFullscreen ? 'premium-glow' : ''
      }`,
      overlay: '',
      particles: false,
    };
  }
  
  return {
    container: `${style.videoFrame} ${style.videoBorder}`,
    overlay: '',
    particles: false,
  };
};