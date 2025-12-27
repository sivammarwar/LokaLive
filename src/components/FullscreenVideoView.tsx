import { useEffect, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { X, Maximize2, Crown, Sparkles } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useThumbnailVideoManager } from '@/hooks/useVideoStreamManager';

interface FullscreenVideoViewProps {
  fullscreenUserId: string;
  localUserId: string;
  localStream: MediaStream | null;
  remoteStreams: Map<string, MediaStream>;
  participants: Array<{
    user_id: string;
    display_name: string;
    membership_tier: string;
  }>;
  isSpeakerOff: boolean;
  isVideoOff: boolean;
  myDisplayName: string;
  myMembershipTier: string;
  onExitFullscreen: () => void;
  onSwitchFullscreen: (userId: string) => void;
}

const getMembershipIcon = (tier: string) => {
  switch (tier) {
    case 'premium': return Crown;
    case 'premium_plus': return Sparkles;
    default: return null;
  }
};

const getMembershipColor = (tier: string) => {
  switch (tier) {
    case 'premium': return 'text-blue-500 border-blue-500/30';
    case 'premium_plus': return 'text-yellow-500 border-yellow-500/30';
    default: return 'text-muted-foreground border-border';
  }
};

export function FullscreenVideoView({
  fullscreenUserId,
  localUserId,
  localStream,
  remoteStreams,
  participants,
  isSpeakerOff,
  isVideoOff,
  myDisplayName,
  myMembershipTier,
  onExitFullscreen,
  onSwitchFullscreen,
}: FullscreenVideoViewProps) {
  const mainVideoRef = useRef<HTMLVideoElement>(null);
  const attachedStreamRef = useRef<MediaStream | null>(null);

  const isLocalUserFullscreen = fullscreenUserId === localUserId;
  const fullscreenStream = isLocalUserFullscreen 
    ? localStream 
    : remoteStreams.get(fullscreenUserId);

  const fullscreenParticipant = participants.find(p => p.user_id === fullscreenUserId);
  const fullscreenName = isLocalUserFullscreen 
    ? myDisplayName 
    : (fullscreenParticipant?.display_name || 'Unknown');
  const fullscreenTier = isLocalUserFullscreen 
    ? myMembershipTier 
    : (fullscreenParticipant?.membership_tier || 'free');

  const MembershipIcon = getMembershipIcon(fullscreenTier);

  // Attach fullscreen video
  useEffect(() => {
    if (!mainVideoRef.current || !fullscreenStream) return;

    const videoElement = mainVideoRef.current;

    if (attachedStreamRef.current === fullscreenStream && videoElement.srcObject === fullscreenStream) {
      videoElement.muted = isLocalUserFullscreen || isSpeakerOff;
      return;
    }

    console.log('🖼️ [Fullscreen] Attaching stream for', fullscreenName);

    const attachStream = async () => {
      if (videoElement.srcObject && videoElement.srcObject !== fullscreenStream) {
        videoElement.pause();
        videoElement.srcObject = null;
        await new Promise(r => setTimeout(r, 50));
      }

      videoElement.srcObject = fullscreenStream;
      videoElement.muted = isLocalUserFullscreen || isSpeakerOff;
      videoElement.playsInline = true;
      videoElement.autoplay = true;
      videoElement.setAttribute('playsinline', 'true');
      videoElement.setAttribute('webkit-playsinline', 'true');

      attachedStreamRef.current = fullscreenStream;

      try {
        await videoElement.play();
        console.log('✅ [Fullscreen] Playing');
      } catch (error) {
        console.error('❌ [Fullscreen] Play error:', error);
        setTimeout(() => videoElement.play().catch(console.error), 500);
      }
    };

    attachStream();
  }, [fullscreenStream, isLocalUserFullscreen, isSpeakerOff, fullscreenName]);

  // Get other participants for bottom bar
  const otherParticipants = [
    { userId: localUserId, name: myDisplayName, tier: myMembershipTier, isLocal: true },
    ...Array.from(remoteStreams.entries()).map(([userId]) => {
      const participant = participants.find(p => p.user_id === userId);
      return {
        userId,
        name: participant?.display_name || 'Unknown',
        tier: participant?.membership_tier || 'free',
        isLocal: false,
      };
    }),
  ].filter(p => p.userId !== fullscreenUserId);

  return (
    <div className="fixed inset-0 z-40 bg-background flex flex-col">
      {/* Main Fullscreen Video - 80% height */}
      <div className="flex-1 relative bg-black">
        <video
          ref={mainVideoRef}
          autoPlay
          muted={isLocalUserFullscreen || isSpeakerOff}
          playsInline
          className={cn(
            'w-full h-full object-contain',
            isLocalUserFullscreen && isVideoOff && 'opacity-0'
          )}
        />

        {/* Placeholder when video is off */}
        {isLocalUserFullscreen && isVideoOff && (
          <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-muted to-card">
            <div className={cn(
              "w-32 h-32 rounded-full flex items-center justify-center",
              fullscreenTier === 'premium_plus'
                ? "bg-gradient-to-br from-yellow-500/40 to-amber-600/40 ring-4 ring-yellow-500/60"
                : fullscreenTier === 'premium'
                  ? "bg-gradient-to-br from-blue-500/30 to-blue-600/30 ring-4 ring-blue-500/50"
                  : "bg-primary/20"
            )}>
              <span className={cn(
                "text-5xl font-bold",
                fullscreenTier === 'premium_plus'
                  ? "text-yellow-400"
                  : fullscreenTier === 'premium'
                    ? "text-blue-300"
                    : "text-primary"
              )}>
                {fullscreenName?.[0]?.toUpperCase()}
              </span>
            </div>
          </div>
        )}

        {/* Top overlay - User info and controls */}
        <div className="absolute top-0 left-0 right-0 p-4 bg-gradient-to-b from-black/60 to-transparent">
          <div className="flex items-center justify-between">
            <div className={cn(
              "flex items-center gap-3 rounded-full px-4 py-2 backdrop-blur-xl border",
              getMembershipColor(fullscreenTier),
              fullscreenTier === 'premium_plus' && "bg-gradient-to-r from-yellow-500/20 to-amber-500/20",
              fullscreenTier === 'premium' && "bg-gradient-to-r from-blue-500/20 to-blue-600/20",
              fullscreenTier === 'free' && "bg-black/40"
            )}>
              {MembershipIcon && (
                <MembershipIcon className={cn(
                  "h-5 w-5",
                  fullscreenTier === 'premium_plus' && "text-yellow-500",
                  fullscreenTier === 'premium' && "text-blue-500"
                )} />
              )}
              <span className="text-white font-semibold">
                {fullscreenName} {isLocalUserFullscreen && '(You)'}
              </span>
            </div>

            <Button
              variant="ghost"
              size="icon"
              onClick={onExitFullscreen}
              className="rounded-full bg-black/40 backdrop-blur-xl hover:bg-black/60 text-white"
            >
              <X className="h-5 w-5" />
            </Button>
          </div>
        </div>

        {/* Bottom gradient for better visibility */}
        <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-black/60 to-transparent pointer-events-none" />
      </div>

      {/* Bottom Bar - Other Participants - 20% height */}
      <div className="h-[20vh] min-h-[120px] bg-gradient-to-b from-black/90 to-black border-t border-white/10 p-4">
        <div className="h-full flex items-center justify-center gap-4 overflow-x-auto">
          {otherParticipants.map((participant) => (
            <ParticipantCircle
              key={participant.userId}
              userId={participant.userId}
              name={participant.name}
              tier={participant.tier}
              isLocal={participant.isLocal}
              localStream={localStream}
              remoteStreams={remoteStreams}
              isVideoOff={participant.isLocal && isVideoOff}
              onClick={() => onSwitchFullscreen(participant.userId)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

// Participant Circle Component
interface ParticipantCircleProps {
  userId: string;
  name: string;
  tier: string;
  isLocal: boolean;
  localStream: MediaStream | null;
  remoteStreams: Map<string, MediaStream>;
  isVideoOff: boolean;
  onClick: () => void;
}

function ParticipantCircle({
  userId,
  name,
  tier,
  isLocal,
  localStream,
  remoteStreams,
  isVideoOff,
  onClick,
}: ParticipantCircleProps) {
  const { videoRef } = useThumbnailVideoManager(userId, isLocal, localStream, remoteStreams);
  const MembershipIcon = getMembershipIcon(tier);

  return (
    <button
      onClick={onClick}
      className="group relative flex-shrink-0 transition-transform hover:scale-110 active:scale-95"
    >
      {/* Circle Container */}
      <div className={cn(
        "w-24 h-24 md:w-28 md:h-28 rounded-full overflow-hidden border-4 transition-all",
        "bg-gradient-to-br from-muted to-card",
        tier === 'premium_plus' && "border-yellow-500 shadow-lg shadow-yellow-500/50",
        tier === 'premium' && "border-blue-500 shadow-lg shadow-blue-500/50",
        tier === 'free' && "border-white/30",
        "group-hover:border-white"
      )}>
        {/* Video */}
        <video
          ref={videoRef}
          autoPlay
          muted
          playsInline
          className={cn(
            'w-full h-full object-cover scale-150',
            isVideoOff && 'opacity-0'
          )}
        />

        {/* Placeholder when video off */}
        {isVideoOff && (
          <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-muted to-card">
            <span className={cn(
              "text-2xl font-bold",
              tier === 'premium_plus' && "text-yellow-400",
              tier === 'premium' && "text-blue-300",
              tier === 'free' && "text-primary"
            )}>
              {name?.[0]?.toUpperCase()}
            </span>
          </div>
        )}

        {/* Hover overlay with expand icon */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center">
          <Maximize2 className="h-6 w-6 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
        </div>
      </div>

      {/* Name tag below circle */}
      <div className={cn(
        "mt-2 px-3 py-1 rounded-full backdrop-blur-md border text-xs font-medium transition-all",
        tier === 'premium_plus' && "bg-yellow-500/20 border-yellow-500/40 text-yellow-300",
        tier === 'premium' && "bg-blue-500/20 border-blue-500/40 text-blue-300",
        tier === 'free' && "bg-white/10 border-white/20 text-white/80",
        "group-hover:bg-white/20"
      )}>
        <div className="flex items-center gap-1 justify-center">
          {MembershipIcon && (
            <MembershipIcon className="h-3 w-3" />
          )}
          <span className="max-w-[80px] truncate">
            {name} {isLocal && '(You)'}
          </span>
        </div>
      </div>
    </button>
  );
}