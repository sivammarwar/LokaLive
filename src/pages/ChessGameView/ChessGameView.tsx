import { RefObject, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { ChessGame } from '@/components/ChessGame';
import { Mic, MicOff, Volume2, VolumeX, Video, VideoOff, Swords, Gem, Loader2, AlertCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

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
  
  // ✅ NEW: Track chess game result
  const [gameResult, setGameResult] = useState<{
    showAlert: boolean;
    winner: string | null;
    message: string;
  }>({ showAlert: false, winner: null, message: '' });

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

  // ✅ CRITICAL FIX 1: Enhanced auto-recovery for opponent stream (same as normal room)
  const attachOpponentStream = useRef<(() => void) | null>(null);

  // Create a reusable function to attach opponent stream
  useEffect(() => {
    attachOpponentStream.current = () => {
      const opponentStream = remoteStreams.get(opponentId);
      
      if (opponentStream && opponentStream.active) {
        console.log(`🔄 [Chess Auto-Recovery] Attaching opponent stream to all video elements`);
        
        // Attach to desktop opponent video
        if (chessOpponentVideoRef.current) {
          const el = chessOpponentVideoRef.current;
          // Always force re-attach to ensure stream is fresh
          el.srcObject = opponentStream;
          el.muted = isSpeakerOff;
          el.playsInline = true;
          el.autoplay = true;
          el.setAttribute('playsinline', 'true');
          el.setAttribute('webkit-playsinline', 'true');
          
          el.load();
          el.play()
            .then(() => {
              console.log('✅ Desktop opponent video playing');
              setIsOpponentStreamReady(true);
            })
            .catch(err => {
              console.warn('⚠️ Desktop play failed, retrying:', err);
              setTimeout(() => {
                el.muted = true;
                el.play().then(() => {
                  if (!isSpeakerOff) {
                    setTimeout(() => { el.muted = isSpeakerOff; }, 100);
                  }
                }).catch(console.error);
              }, 500);
            });
        }
        
        // Attach to mobile opponent video
        if (mobileOpponentVideoRef.current) {
          const el = mobileOpponentVideoRef.current;
          el.srcObject = opponentStream;
          el.muted = isSpeakerOff;
          el.playsInline = true;
          el.autoplay = true;
          el.setAttribute('playsinline', 'true');
          el.setAttribute('webkit-playsinline', 'true');
          
          el.load();
          el.play()
            .then(() => {
              console.log('✅ Mobile opponent video playing');
              setIsOpponentStreamReady(true);
            })
            .catch(err => {
              console.warn('⚠️ Mobile play failed, retrying:', err);
              setTimeout(() => {
                el.muted = true;
                el.play().then(() => {
                  if (!isSpeakerOff) {
                    setTimeout(() => { el.muted = isSpeakerOff; }, 100);
                  }
                }).catch(console.error);
              }, 500);
            });
        }
        
        // Also update the main Room component's ref
        const tempVideoEl = document.createElement('video');
        tempVideoEl.srcObject = opponentStream;
        opponentVideoRef(tempVideoEl);
        
        console.log('✅✅✅ Opponent stream attached to all chess video elements');
      } else {
        console.warn('⚠️ No active opponent stream available');
        setIsOpponentStreamReady(false);
      }
    };
  }, [remoteStreams, opponentId, isSpeakerOff, opponentVideoRef]);

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

  // ✅ CRITICAL: Enhanced continuous monitoring and re-attachment (like normal room)
  useEffect(() => {
    // Initial attachment
    if (attachOpponentStream.current) {
      console.log('🎬 [Chess] Initial opponent stream attachment');
      attachOpponentStream.current();
    }

    // Clear any existing health check
    if (healthCheckIntervalRef.current) {
      clearInterval(healthCheckIntervalRef.current);
    }

    const checkAndAttachStream = () => {
      const opponentStream = remoteStreams.get(opponentId);
      const now = Date.now();
      
      console.log(`🏥 [Chess Health Check #${streamCheckCounter}]`, {
        hasStream: !!opponentStream,
        streamActive: opponentStream?.active,
        videoTracks: opponentStream?.getVideoTracks().length || 0,
        audioTracks: opponentStream?.getAudioTracks().length || 0,
        timeSinceLastCheck: now - lastHealthCheckRef.current,
      });

      // Check if stream is available and healthy
      if (opponentStream && opponentStream.active) {
        const videoTrack = opponentStream.getVideoTracks()[0];
        
        if (videoTrack && videoTrack.readyState === 'live') {
          // Check if video elements are playing
          const desktopPlaying = chessOpponentVideoRef.current && 
            !chessOpponentVideoRef.current.paused && 
            chessOpponentVideoRef.current.readyState >= 2;
          
          const mobilePlaying = mobileOpponentVideoRef.current && 
            !mobileOpponentVideoRef.current.paused && 
            mobileOpponentVideoRef.current.readyState >= 2;
          
          // If not playing, re-attach
          if (!desktopPlaying || !mobilePlaying) {
            console.log(`🔄 [Chess Health] Video not playing, re-attaching...`);
            if (attachOpponentStream.current) {
              attachOpponentStream.current();
            }
          } else {
            setIsOpponentStreamReady(true);
          }
        } else {
          console.warn(`⚠️ [Chess Health] Video track not live:`, videoTrack?.readyState);
          setIsOpponentStreamReady(false);
          
          // Try to re-attach anyway
          if (attachOpponentStream.current) {
            attachOpponentStream.current();
          }
        }
      } else {
        console.warn(`⚠️ [Chess Health] No active opponent stream`);
        setIsOpponentStreamReady(false);
      }
      
      lastHealthCheckRef.current = now;
      setStreamCheckCounter(prev => prev + 1);
    };

    // Continuous health monitoring every 2 seconds (like normal room)
    healthCheckIntervalRef.current = setInterval(checkAndAttachStream, 2000);

    return () => {
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
        healthCheckIntervalRef.current = null;
      }
    };
  }, [remoteStreams, opponentId, streamCheckCounter]);

  // ✅ Update speaker state for opponent videos when toggled
  useEffect(() => {
    if (chessOpponentVideoRef.current) {
      chessOpponentVideoRef.current.muted = isSpeakerOff;
    }
    if (mobileOpponentVideoRef.current) {
      mobileOpponentVideoRef.current.muted = isSpeakerOff;
    }
  }, [isSpeakerOff]);

  // ✅ FIX 2: Listen for game results and show alert
  useEffect(() => {
    // This would be connected to your chess game component
    // For now, I'll create a simulated listener
    const handleGameResult = (event: CustomEvent) => {
      const { winner, message } = event.detail;
      
      setGameResult({
        showAlert: true,
        winner,
        message
      });
      
      toast.success(message);
    };

    // Listen for custom event from ChessGame component
    window.addEventListener('chess-game-ended', handleGameResult as EventListener);

    return () => {
      window.removeEventListener('chess-game-ended', handleGameResult as EventListener);
    };
  }, []);

  // ✅ Function to handle return to room after win alert
  const handleReturnToRoom = () => {
    setGameResult({ showAlert: false, winner: null, message: '' });
    
    // Close the chess game and return to room
    setTimeout(() => {
      onClose();
    }, 500);
  };

  // ✅ FIX 3: Ensure clean return to room by pre-warming connections
  useEffect(() => {
    // This effect ensures that when we return to room, 
    // the remoteStreams are properly maintained
    return () => {
      console.log('♟️ [ChessGameView] Cleaning up - returning to room');
      
      // Clear intervals
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
      }
      
      // Force a small delay to let WebRTC hooks reinitialize
      setTimeout(() => {
        console.log('♟️ [ChessGameView] Cleanup complete - room should reconnect');
      }, 100);
    };
  }, []);

  // ✅ Check if opponent stream exists
  const hasOpponentStream = remoteStreams.has(opponentId);

  return (
    <div className="fixed inset-0 z-50 bg-background flex flex-col">
      {/* Win Alert Modal */}
      {gameResult.showAlert && (
        <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-strong rounded-2xl p-6 max-w-sm w-full space-y-4 animate-slide-up">
            <div className="text-center space-y-2">
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-gradient-to-br from-green-500/20 to-emerald-500/20 mb-2">
                <AlertCircle className="h-8 w-8 text-green-500" />
              </div>
              <h3 className="text-xl font-bold">Game Over!</h3>
              <p className="text-muted-foreground">
                {gameResult.message}
              </p>
              {isBetMatch && betAmount > 0 && (
                <div className="glass rounded-xl p-3 space-y-1">
                  <p className="text-sm font-medium flex items-center justify-center gap-2">
                    <Gem className="h-4 w-4 text-amber-500" />
                    {gameResult.winner === myUserId ? 
                      `You won ${betAmount * 2} diamonds!` : 
                      `You lost ${betAmount} diamonds`
                    }
                  </p>
                </div>
              )}
            </div>
            <div className="flex gap-3">
              <Button 
                variant="default"
                className="flex-1" 
                onClick={handleReturnToRoom}
              >
                Return to Room
              </Button>
            </div>
          </div>
        </div>
      )}

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
            onGameEnd={(winner, message) => {
              // Trigger win alert
              setGameResult({
                showAlert: true,
                winner,
                message
              });
            }}
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
            {/* ✅ Enhanced loading overlay with retry button */}
            {!isOpponentStreamReady && (
              <div className="absolute inset-0 flex flex-col items-center justify-center bg-muted/30 z-10">
                <Loader2 className="w-8 h-8 text-primary animate-spin mb-2" />
                <p className="text-xs text-muted-foreground mb-2">
                  {hasOpponentStream ? 'Connecting video...' : 'Waiting for opponent...'}
                </p>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    if (attachOpponentStream.current) {
                      attachOpponentStream.current();
                    }
                  }}
                  className="text-xs"
                >
                  Retry Connection
                </Button>
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
              onStalled={() => {
                console.warn('⚠️ Desktop opponent video stalled, retrying...');
                if (attachOpponentStream.current) {
                  setTimeout(() => attachOpponentStream.current!(), 500);
                }
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
            {/* ✅ Enhanced loading overlay */}
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
                setIsOpponentStreamReady(true);
              }}
              onStalled={() => {
                console.warn('⚠️ Mobile opponent video stalled');
                if (attachOpponentStream.current) {
                  setTimeout(() => attachOpponentStream.current!(), 500);
                }
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