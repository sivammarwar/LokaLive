// Optional: Add this component to show batching performance
// Place this in src/components/SignalingIndicator.tsx

import { Activity } from 'lucide-react';
import { cn } from '@/lib/utils';

interface SignalingIndicatorProps {
  className?: string;
}

export function SignalingIndicator({ className }: SignalingIndicatorProps) {
  return (
    <div
      className={cn(
        "flex items-center gap-2 glass rounded-full px-3 py-1.5 text-xs",
        className
      )}
      title="Optimized batched signaling active"
    >
      <Activity className="h-3 w-3 text-green-500 animate-pulse" />
      <span className="text-muted-foreground hidden sm:inline">
        Optimized
      </span>
    </div>
  );
}

// Then in Room.tsx header section, add:
// <SignalingIndicator />