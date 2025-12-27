import { RefObject, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { ChessGame } from '@/components/ChessGame';
import { Mic, MicOff, Volume2, VolumeX, Video, VideoOff, Swords, Gem, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface ChessGameViewProps {
  gameId: string;
  myUserId: string;
  myColor: 'white' | 'black';
  opponentId: string;
  opponentName: string;
  displayName: string;
  localVideoRef: RefObject<HTMLVideoElement>;
  localStream: MediaStream | null;
  opponentVideoRef: (el: HTMLVideoElement | null) => void;
  remoteStreams: Map<string, MediaStream>;
  isVideoOff: boolean;
  isSpeakerOff: boolean;
  isMuted: boolean;
  onClose: () => void;
  onToggleMute: () => void;
  onToggleVideo: () => void;
  onToggleSpeaker: () => void;
  originalRoomId: string;
  isBetMatch?: boolean;
  betAmount?: number;
}

export function ChessGameView({
  gameId,
  myUserId,
  myColor,
  opponentId,
  opponentName,
  displayName,
  localVideoRef,
  localStream,
  opponentVideoRef,
  remoteStreams,
  isVideoOff,
  isSpeakerOff,
  isMuted,
  onClose,
  onToggleMute,
  onToggleVideo,
  onToggleSpeaker,
  originalRoomId,
  isBetMatch = false,
  betAmount = 0,
}: ChessGameViewProps) {
  const chessLocalVideoRef = useRef<HTMLVideoElement>(null);
  const chessOpponentVideoRef = useRef<HTMLVideoElement>(null);
  const mobileLocalVideoRef = useRef<HTMLVideoElement>(null);
  const mobileOpponentVideoRef = useRef<HTMLVideoElement>(null);

  // ✅ Track opponent stream health
  const [isOpponentStreamReady, setIsOpponentStreamReady] = useState(false);
  const [streamCheckCounter, setStreamCheckCounter] = useState(0);
  const healthCheckIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const lastHealthCheckRef = useRef<number>(Date.now());

  // ✅ FIX: Prevent refresh/navigation from leaving chess room
  useEffect(() => {
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = 'Chess game in progress. Are you sure you want to leave?';
      return e.returnValue;
    };

    window.addEventListener('beforeunload', handleBeforeUnload);

    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  }, []);

  // ✅ Attach local stream to ALL chess video elements
  useEffect(() => {
    if (localStream) {
      console.log('♟️ Attaching local stream to chess video elements');
      
      // Desktop local video
      if (chessLocalVideoRef.current) {
        const el = chessLocalVideoRef.current;
        if (el.srcObject !== localStream) {
          console.log('🎥 [Desktop Local] Attaching stream');
          el.srcObject = localStream;
          el.muted = true;
          el.playsInline = true;
          el.autoplay = true;
          el.setAttribute('playsinline', 'true');
          el.setAttribute('webkit-playsinline', 'true');
          el.load();
          el.play().catch(console.error);
        }
      }

      // Mobile local video
      if (mobileLocalVideoRef.current) {
        const el = mobileLocalVideoRef.current;
        if (el.srcObject !== localStream) {
          console.log('🎥 [Mobile Local] Attaching stream');
          el.srcObject = localStream;
          el.muted = true;
          el.playsInline = true;
          el.autoplay = true;
          el.setAttribute('playsinline', 'true');
          el.setAttribute('webkit-playsinline', 'true');
          el.load();
          el.play().catch(console.error);
        }
      }
    }
  }, [localStream]);

  // ✅ CRITICAL: Continuously monitor and re-attach opponent stream (like normal room)
  useEffect(() => {
    // Clear any existing health check
    if (healthCheckIntervalRef.current) {
      clearInterval(healthCheckIntervalRef.current);
    }

    const checkAndAttachStream = () => {
      const opponentStream = remoteStreams.get(opponentId);
      const now = Date.now();
      
      console.log(`🏥 [Chess Health Check #${streamCheckCounter}] Opponent stream:`, {
        hasStream: !!opponentStream,
        streamActive: opponentStream?.active,
        videoTracks: opponentStream?.getVideoTracks().length || 0,
        audioTracks: opponentStream?.getAudioTracks().length || 0,
        timeSinceLastCheck: now - lastHealthCheckRef.current,
      });

      if (opponentStream && opponentStream.active) {
        const videoTrack = opponentStream.getVideoTracks()[0];
        
        // Check track health
        if (videoTrack && videoTrack.readyState === 'live') {
          console.log(`✅ [Chess Health] Stream is healthy, re-attaching if needed`);
          
          // Re-attach to all video elements
          [
            { ref: chessOpponentVideoRef.current, label: 'Desktop' },
            { ref: mobileOpponentVideoRef.current, label: 'Mobile' }
          ].forEach(({ ref: el, label }) => {
            if (el) {
              // Always re-attach to ensure freshness
              const needsAttach = el.srcObject !== opponentStream || el.paused;
              
              if (needsAttach) {
                console.log(`🔄 [Chess Health] Re-attaching to ${label} opponent video`);
                
                el.srcObject = opponentStream;
                el.muted = isSpeakerOff;
                el.playsInline = true;
                el.autoplay = true;
                el.setAttribute('playsinline', 'true');
                el.setAttribute('webkit-playsinline', 'true');
                
                el.load();
                el.play()
                  .then(() => {
                    console.log(`✅ [Chess Health] ${label} opponent video playing`);
                    setIsOpponentStreamReady(true);
                  })
                  .catch(err => {
                    console.warn(`⚠️ [Chess Health] ${label} play failed:`, err);
                    // Try user interaction workaround
                    setTimeout(() => {
                      el.muted = true;
                      el.play().then(() => {
                        if (!isSpeakerOff) {
                          setTimeout(() => { el.muted = isSpeakerOff; }, 100);
                        }
                      }).catch(console.error);
                    }, 500);
                  });
              } else if (el.srcObject === opponentStream && !el.paused) {
                // Already playing, mark as ready
                setIsOpponentStreamReady(true);
              }
            }
          });
        } else {
          console.warn(`⚠️ [Chess Health] Video track not live:`, videoTrack?.readyState);
          setIsOpponentStreamReady(false);
        }
      } else {
        console.warn(`⚠️ [Chess Health] No active opponent stream`);
        setIsOpponentStreamReady(false);
      }
      
      lastHealthCheckRef.current = now;
      setStreamCheckCounter(prev => prev + 1);
    };

    // Initial check immediately
    checkAndAttachStream();

    // Continuous health monitoring every 2 seconds (like normal room)
    healthCheckIntervalRef.current = setInterval(checkAndAttachStream, 2000);

    return () => {
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
        healthCheckIntervalRef.current = null;
      }
    };
  }, [remoteStreams, opponentId, isSpeakerOff, streamCheckCounter]);

  // ✅ Update speaker state for opponent videos when toggled
  useEffect(() => {
    if (chessOpponentVideoRef.current) {
      chessOpponentVideoRef.current.muted = isSpeakerOff;
    }
    if (mobileOpponentVideoRef.current) {
      mobileOpponentVideoRef.current.muted = isSpeakerOff;
    }
  }, [isSpeakerOff]);

  // ✅ Check if opponent stream exists
  const hasOpponentStream = remoteStreams.has(opponentId);

  return (
    <div className="fixed inset-0 z-50 bg-background flex flex-col">
      {/* Header - ✅ REMOVED BACK BUTTON */}
      <header className="flex items-center justify-between p-2 md:p-4 border-b border-border">
        <Logo size="sm" />
        <div className="flex items-center gap-2 md:gap-4">
          <div className="flex items-center gap-2 glass rounded-full px-3 py-1.5 md:px-4 md:py-2">
            {isBetMatch ? (
              <>
                <Gem className="h-3 w-3 md:h-4 md:w-4 text-amber-500" />
                <span className="text-xs md:text-sm font-medium">
                  Bet Match
                </span>
                {betAmount > 0 && (
                  <span className="text-xs font-bold text-amber-500">
                    {betAmount * 2}💎
                  </span>
                )}
              </>
            ) : (
              <>
                <Swords className="h-3 w-3 md:h-4 md:w-4 text-primary" />
                <span className="text-xs md:text-sm font-medium">Chess Match</span>
              </>
            )}
          </div>
        </div>
      </header>

      {/* Main Content: Chess Board + Videos */}
      <div className="flex-1 flex flex-col lg:flex-row gap-4 p-2 md:p-4 overflow-hidden">
        {/* Chess Board Section */}
        <div className="flex-1 flex items-center justify-center min-w-0 max-w-[600px] lg:ml-[60px]">
          <ChessGame
            gameId={gameId}
            myUserId={myUserId}
            myColor={myColor}
            opponentName={opponentName}
            onClose={onClose}
            isEmbedded={true}
            originalRoomId={originalRoomId}
            isBetMatch={isBetMatch}
            betAmount={betAmount}
          />
        </div>

        {/* Desktop Video Section - Side Panel */}
        <div className="hidden lg:flex lg:flex-col gap-3 w-[450px] ml-[150px] shrink-0">
          {/* Bet Info Banner (Desktop) */}
          {isBetMatch && betAmount > 0 && (
            <div className="glass-strong rounded-xl p-4 bg-gradient-to-r from-amber-500/10 to-orange-500/10 border border-amber-500/30">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="p-2 rounded-lg bg-amber-500/20">
                    <Gem className="h-5 w-5 text-amber-500" />
                  </div>
                  <div>
                    <p className="text-sm font-bold">Prize Pool</p>
                    <p className="text-xs text-muted-foreground">Winner takes all</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-2xl font-bold text-amber-500">{betAmount * 2}</p>
                  <p className="text-xs text-muted-foreground">diamonds</p>
                </div>
              </div>
            </div>
          )}

          {/* Opponent Video - DESKTOP */}
          <div className={cn(
            "relative rounded-xl overflow-hidden bg-card shadow-lg aspect-video",
            isBetMatch && "ring-2 ring-amber-500/30"
          )}>
            {/* ✅ Loading overlay if no stream */}
            {!isOpponentStreamReady && (
              <div className="absolute inset-0 flex flex-col items-center justify-center bg-muted/20 z-10">
                <Loader2 className="w-8 h-8 text-primary animate-spin mb-2" />
                <p className="text-xs text-muted-foreground">
                  {hasOpponentStream ? 'Loading video...' : 'Connecting to opponent...'}
                </p>
              </div>
            )}
            
            <video
              ref={chessOpponentVideoRef}
              autoPlay
              playsInline
              muted={isSpeakerOff}
              className="w-full h-full object-cover"
              onLoadedMetadata={() => {
                console.log('✅ Desktop opponent video metadata loaded');
              }}
              onPlay={() => {
                console.log('✅ Desktop opponent video playing');
                setIsOpponentStreamReady(true);
              }}
              onPause={() => {
                console.log('⏸️ Desktop opponent video paused');
              }}
            />
            <div className="absolute bottom-2 left-2 glass rounded-full px-3 py-1">
              <span className="text-xs font-medium">{opponentName}</span>
            </div>
          </div>

          {/* Local Video - DESKTOP */}
          <div className={cn(
            "relative rounded-xl overflow-hidden bg-card shadow-lg aspect-video",
            isBetMatch && "ring-2 ring-amber-500/30"
          )}>
            <video
              ref={chessLocalVideoRef}
              autoPlay
              muted
              playsInline
              className={cn(
                'w-full h-full object-cover',
                isVideoOff && 'opacity-0'
              )}
            />
            {isVideoOff && (
              <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-muted to-card">
                <div className="w-16 h-16 rounded-full bg-primary/20 flex items-center justify-center">
                  <span className="text-2xl font-bold text-primary">
                    {displayName?.[0]?.toUpperCase()}
                  </span>
                </div>
              </div>
            )}
            <div className="absolute bottom-2 left-2 glass rounded-full px-3 py-1">
              <span className="text-xs font-medium">{displayName} (You)</span>
            </div>
            <div className="absolute top-2 right-2 flex gap-1">
              {isMuted && (
                <div className="bg-destructive rounded-full p-1.5">
                  <MicOff className="h-3 w-3" />
                </div>
              )}
              {isVideoOff && (
                <div className="bg-destructive rounded-full p-1.5">
                  <VideoOff className="h-3 w-3" />
                </div>
              )}
            </div>
          </div>

          {/* Desktop Controls */}
          <div className="flex items-center justify-center gap-2">
            <Button
              variant={isMuted ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleMute}
              className="rounded-full flex-1"
            >
              {isMuted ? <MicOff className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
            </Button>
            <Button
              variant={isVideoOff ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleVideo}
              className="rounded-full flex-1"
            >
              {isVideoOff ? <VideoOff className="h-4 w-4" /> : <Video className="h-4 w-4" />}
            </Button>
            <Button
              variant={isSpeakerOff ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleSpeaker}
              className="rounded-full flex-1"
            >
              {isSpeakerOff ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
            </Button>
          </div>
        </div>
      </div>

      {/* Mobile Bet Info Banner */}
      {isBetMatch && betAmount > 0 && (
        <div className="lg:hidden fixed top-14 left-1/2 -translate-x-1/2 z-20 pointer-events-none">
          <div className="glass-strong rounded-full px-4 py-2 bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-500/40 shadow-xl">
            <div className="flex items-center gap-2">
              <Gem className="h-4 w-4 text-amber-500" />
              <span className="text-sm font-bold text-amber-500">
                {betAmount * 2} diamonds at stake
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Mobile Video Overlays - Circular */}
      <div className="lg:hidden fixed inset-0 pointer-events-none z-10">
        {/* Opponent Video - Top Right - MOBILE */}
        <div className="absolute top-16 right-3 w-[150px] h-[100px] sm:w-[140px] sm:h-[140px] pointer-events-auto">
          <div className={cn(
            "relative w-full h-full rounded-full overflow-hidden bg-card/90 backdrop-blur-md shadow-2xl",
            isBetMatch 
              ? "ring-2 ring-amber-500/50" 
              : "ring-2 ring-primary/30"
          )}>
            {/* ✅ Loading overlay if no stream */}
            {!isOpponentStreamReady && (
              <div className="absolute inset-0 flex items-center justify-center bg-muted/40 z-10">
                <Loader2 className="w-6 h-6 text-primary animate-spin" />
              </div>
            )}
            
            <video
              ref={mobileOpponentVideoRef}
              autoPlay
              playsInline
              muted={isSpeakerOff}
              className="w-full h-full object-cover scale-150"
              onPlay={() => {
                console.log('✅ Mobile opponent video playing');
              }}
            />
            <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent pointer-events-none" />
            <div className="absolute bottom-0.5 left-1/2 -translate-x-1/2 bg-black/80 backdrop-blur-sm rounded-full px-1.5 py-0.5">
              <span className="text-[9px] sm:text-[10px] font-medium text-white whitespace-nowrap">
                {opponentName.length > 8 ? opponentName.split(' ')[0] : opponentName}
              </span>
            </div>
            {isBetMatch && (
              <div className="absolute top-0 right-0 bg-amber-500 rounded-full p-1">
                <Gem className="h-2 w-2 text-white" />
              </div>
            )}
          </div>
        </div>

        {/* Local Video - Bottom Right - MOBILE */}
        <div className="absolute bottom-20 sm:bottom-24 right-3 w-[150px] h-[100px] sm:w-[140px] sm:h-[140px] pointer-events-auto">
          <div className={cn(
            "relative w-full h-full rounded-full overflow-hidden bg-card/90 backdrop-blur-md shadow-2xl",
            isBetMatch 
              ? "ring-2 ring-amber-500/50" 
              : "ring-2 ring-primary/30"
          )}>
            <video
              ref={mobileLocalVideoRef}
              autoPlay
              muted
              playsInline
              className={cn(
                'w-full h-full object-cover scale-150',
                isVideoOff && 'opacity-0'
              )}
            />
            {isVideoOff && (
              <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/20 to-muted">
                <span className="text-xl sm:text-2xl font-bold text-primary">
                  {displayName?.[0]?.toUpperCase()}
                </span>
              </div>
            )}
            <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent pointer-events-none" />
            <div className="absolute bottom-0.5 left-1/2 -translate-x-1/2 bg-black/80 backdrop-blur-sm rounded-full px-1.5 py-0.5">
              <span className="text-[9px] sm:text-[10px] font-medium text-white">You</span>
            </div>
            
            {/* Status Indicators */}
            <div className="absolute top-0.5 right-0.5 flex flex-col gap-0.5">
              {isMuted && (
                <div className="bg-destructive/95 rounded-full p-1">
                  <MicOff className="h-2.5 w-2.5 sm:h-3 sm:w-3 text-white" />
                </div>
              )}
              {isVideoOff && (
                <div className="bg-destructive/95 rounded-full p-1">
                  <VideoOff className="h-2.5 w-2.5 sm:h-3 sm:w-3 text-white" />
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Mobile Controls - Bottom Center */}
        <div className="absolute bottom-3 sm:bottom-4 left-1/2 -translate-x-1/2 pointer-events-auto">
          <div className="flex items-center gap-1.5 sm:gap-2 bg-card/95 backdrop-blur-md rounded-full p-1.5 sm:p-2 shadow-2xl ring-1 ring-border/50">
            <Button
              variant={isMuted ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleMute}
              className="rounded-full h-9 w-9 sm:h-10 sm:w-10 p-0"
            >
              {isMuted ? <MicOff className="h-3.5 w-3.5 sm:h-4 sm:w-4" /> : <Mic className="h-3.5 w-3.5 sm:h-4 sm:w-4" />}
            </Button>
            <Button
              variant={isVideoOff ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleVideo}
              className="rounded-full h-9 w-9 sm:h-10 sm:w-10 p-0"
            >
              {isVideoOff ? <VideoOff className="h-3.5 w-3.5 sm:h-4 sm:w-4" /> : <Video className="h-3.5 w-3.5 sm:h-4 sm:w-4" />}
            </Button>
            <Button
              variant={isSpeakerOff ? 'destructive' : 'secondary'}
              size="sm"
              onClick={onToggleSpeaker}
              className="rounded-full h-9 w-9 sm:h-10 sm:w-10 p-0"
            >
              {isSpeakerOff ? <VolumeX className="h-3.5 w-3.5 sm:h-4 sm:w-4" /> : <Volume2 className="h-3.5 w-3.5 sm:h-4 sm:w-4" />}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}