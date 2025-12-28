// src/components/ChessGameView.tsx - FIXED: With auto-reconnect on return
import { RefObject, useEffect, useRef, useState, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { ChessGame } from '@/components/ChessGame';
import { Mic, MicOff, Volume2, VolumeX, Video, VideoOff, Swords, Gem, Loader2, AlertCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

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
  
  const [isOpponentConnected, setIsOpponentConnected] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState('Connecting...');
  const [retryCount, setRetryCount] = useState(0);
  
  const peerConnectionRef = useRef<RTCPeerConnection | null>(null);
  const retryTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const connectionCheckRef = useRef<NodeJS.Timeout | null>(null);
  const opponentStreamRef = useRef<MediaStream | null>(null);
  
  const [gameResult, setGameResult] = useState<{
    showAlert: boolean;
    winner: string | null;
    message: string;
  }>({ showAlert: false, winner: null, message: '' });

  // ✅ NEW: Track if returning from chess to trigger reconnection
  const [isReturning, setIsReturning] = useState(false);

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

  const cleanupTimeouts = () => {
    if (retryTimeoutRef.current) {
      clearTimeout(retryTimeoutRef.current);
      retryTimeoutRef.current = null;
    }
    if (connectionCheckRef.current) {
      clearInterval(connectionCheckRef.current);
      connectionCheckRef.current = null;
    }
  };

  const setupWebRTC = useCallback(async (isInitiator: boolean) => {
    if (!myUserId || !opponentId || !localStream) return;

    setConnectionStatus('Setting up connection...');
    console.log('♟️ [Chess WebRTC] Setting up, initiator:', isInitiator);

    if (peerConnectionRef.current) {
      peerConnectionRef.current.close();
    }

    cleanupTimeouts();

    try {
      const pc = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' },
          { urls: 'stun:stun2.l.google.com:19302' },
          { urls: 'stun:stun3.l.google.com:19302' },
        ]
      });
      peerConnectionRef.current = pc;

      localStream.getTracks().forEach(track => {
        pc.addTrack(track, localStream);
      });

      pc.ontrack = (event) => {
        console.log('♟️ [Chess WebRTC] Remote track received:', event.track.kind);
        if (event.streams[0]) {
          const stream = event.streams[0];
          opponentStreamRef.current = stream;
          
          if (chessOpponentVideoRef.current) {
            chessOpponentVideoRef.current.srcObject = stream;
            chessOpponentVideoRef.current.play()
              .then(() => {
                console.log('✅ Desktop chess video playing');
                setConnectionStatus('Connected');
                setIsOpponentConnected(true);
                setRetryCount(0);
              })
              .catch(() => {
                setConnectionStatus('Connected (click to play)');
                setIsOpponentConnected(true);
                setRetryCount(0);
              });
          }
          
          if (mobileOpponentVideoRef.current) {
            mobileOpponentVideoRef.current.srcObject = stream;
            mobileOpponentVideoRef.current.play()
              .then(() => console.log('✅ Mobile chess video playing'))
              .catch(console.error);
          }
          
          const tempVideoEl = document.createElement('video');
          tempVideoEl.srcObject = stream;
          opponentVideoRef(tempVideoEl);
        }
      };

      pc.oniceconnectionstatechange = () => {
        const state = pc.iceConnectionState;
        console.log('♟️ [Chess WebRTC] ICE state:', state);
        
        if (state === 'connected' || state === 'completed') {
          setConnectionStatus('Connected');
          setIsOpponentConnected(true);
          setRetryCount(0);
        } else if (state === 'failed') {
          setConnectionStatus('Connection failed - Reconnecting...');
          console.log('♟️ Connection failed, will retry...');
          
          retryTimeoutRef.current = setTimeout(() => {
            console.log('♟️ Auto-retrying connection...');
            setRetryCount(prev => prev + 1);
            if (retryCount < 3) {
              setupWebRTC(isInitiator);
            } else {
              setConnectionStatus('Failed to connect after multiple attempts');
              toast.error('Unable to establish connection. Please try again.');
            }
          }, 3000);
        } else if (state === 'disconnected') {
          setConnectionStatus('Disconnected - Reconnecting...');
          retryTimeoutRef.current = setTimeout(() => {
            console.log('♟️ Auto-reconnecting after disconnect...');
            setupWebRTC(isInitiator);
          }, 2000);
        }
      };

      pc.onicecandidate = async (event) => {
        if (event.candidate && opponentId) {
          try {
            await supabase.from('chess_signaling').insert({
              chess_game_id: gameId,
              from_user: myUserId,
              to_user: opponentId,
              signal_type: 'ice-candidate',
              signal_data: { candidate: event.candidate }
            });
          } catch (error) {
            console.error('♟️ Error sending ICE candidate:', error);
          }
        }
      };

      if (isInitiator) {
        console.log('♟️ Creating offer as initiator');
        try {
          const offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          
          await supabase.from('chess_signaling').insert({
            chess_game_id: gameId,
            from_user: myUserId,
            to_user: opponentId,
            signal_type: 'offer',
            signal_data: { sdp: offer }
          });
          
          console.log('♟️ Offer sent');
          
          connectionCheckRef.current = setInterval(() => {
            if (pc.iceConnectionState === 'checking' || pc.iceConnectionState === 'new') {
              console.log('♟️ Connection stuck in checking state, will retry...');
              setupWebRTC(isInitiator);
            }
          }, 10000);
          
        } catch (error) {
          console.error('♟️ Error creating offer:', error);
          setTimeout(() => setupWebRTC(isInitiator), 2000);
        }
      }

    } catch (error) {
      console.error('♟️ WebRTC setup error:', error);
      setConnectionStatus('Setup failed - Retrying...');
      retryTimeoutRef.current = setTimeout(() => {
        setupWebRTC(isInitiator);
      }, 3000);
    }
  }, [myUserId, opponentId, localStream, gameId, retryCount, opponentVideoRef]);

  // ✅ NEW: Listen for chess end signals from opponent
  useEffect(() => {
    if (!myUserId || !opponentId || !gameId) return;

    console.log('♟️ Setting up chess end signal listener');

    const channel = supabase
      .channel(`chess-end-signaling-${myUserId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'chess_signaling',
          filter: `to_user=eq.${myUserId}`,
        },
        async (payload) => {
          const signal = payload.new as any;
          if (signal.from_user !== opponentId) return;

          console.log('♟️ Received chess end signal:', signal.signal_type);

          if (signal.signal_type === 'game-over' || signal.signal_type === 'resigned') {
            console.log('♟️ Opponent ended chess, preparing to return...');
            // Opponent ended the game, prepare for return
            setIsReturning(true);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [myUserId, opponentId, gameId]);

  useEffect(() => {
    if (!myUserId || !opponentId || !gameId) return;

    console.log('♟️ Setting up chess signaling listener for opponent:', opponentId);

    const channel = supabase
      .channel(`chess-signaling-${opponentId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'chess_signaling',
          filter: `to_user=eq.${myUserId}`,
        },
        async (payload) => {
          const signal = payload.new as any;
          const pc = peerConnectionRef.current;
          
          if (!pc || signal.from_user !== opponentId) return;

          console.log('♟️ Received chess signal:', signal.signal_type);

          try {
            switch (signal.signal_type) {
              case 'offer':
                console.log('♟️ Processing chess offer from opponent');
                await pc.setRemoteDescription(new RTCSessionDescription(signal.signal_data.sdp));
                
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                
                await supabase.from('chess_signaling').insert({
                  chess_game_id: gameId,
                  from_user: myUserId,
                  to_user: opponentId,
                  signal_type: 'answer',
                  signal_data: { sdp: answer }
                });
                break;

              case 'answer':
                console.log('♟️ Processing chess answer from opponent');
                if (signal.from_user === opponentId) {
                  await pc.setRemoteDescription(new RTCSessionDescription(signal.signal_data.sdp));
                }
                break;

              case 'ice-candidate':
                if (signal.signal_data.candidate) {
                  await pc.addIceCandidate(new RTCIceCandidate(signal.signal_data.candidate));
                }
                break;
            }
          } catch (error) {
            console.error('♟️ Signal processing error:', error);
            if (error.toString().includes('wrong state') || error.toString().includes('stable')) {
              console.log('♟️ WebRTC state error, restarting connection...');
              setTimeout(() => setupWebRTC(false), 2000);
            }
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [myUserId, opponentId, gameId, setupWebRTC]);

  // ✅ NEW: Enhanced cleanup with reconnection trigger
  useEffect(() => {
    return () => {
      console.log('♟️ ChessGameView unmounting, triggering reconnection...');
      cleanupTimeouts();
      
      if (peerConnectionRef.current) {
        peerConnectionRef.current.close();
      }
      if (opponentStreamRef.current) {
        opponentStreamRef.current.getTracks().forEach(track => track.stop());
      }
      
      // Trigger reconnection in main room when chess ends
      if (!isReturning) {
        console.log('♟️ Sending return-from-chess event');
        window.dispatchEvent(new CustomEvent('return-from-chess', {
          detail: { gameId, opponentId }
        }));
      }
    };
  }, [isReturning, gameId, opponentId]);

  useEffect(() => {
    if (!myUserId || !opponentId || !localStream) return;

    const initTimer = setTimeout(() => {
      const isInitiator = myColor === 'white';
      console.log(`♟️ Starting chess WebRTC, initiator: ${isInitiator} (I'm ${myColor})`);
      setupWebRTC(isInitiator);
    }, 1000);

    return () => {
      clearTimeout(initTimer);
    };
  }, [myUserId, opponentId, localStream, myColor, setupWebRTC]);

  useEffect(() => {
    if (localStream) {
      console.log('♟️ Attaching local stream to chess video elements');
      
      if (chessLocalVideoRef.current) {
        const el = chessLocalVideoRef.current;
        if (el.srcObject !== localStream) {
          console.log('🎥 [Desktop Local] Attaching stream');
          el.srcObject = localStream;
          el.muted = true;
          el.playsInline = true;
          el.autoplay = true;
          el.load();
          el.play().catch(console.error);
        }
      }

      if (mobileLocalVideoRef.current) {
        const el = mobileLocalVideoRef.current;
        if (el.srcObject !== localStream) {
          console.log('🎥 [Mobile Local] Attaching stream');
          el.srcObject = localStream;
          el.muted = true;
          el.playsInline = true;
          el.autoplay = true;
          el.load();
          el.play().catch(console.error);
        }
      }
    }
  }, [localStream]);

  useEffect(() => {
    if (chessOpponentVideoRef.current) {
      chessOpponentVideoRef.current.muted = isSpeakerOff;
    }
    if (mobileOpponentVideoRef.current) {
      mobileOpponentVideoRef.current.muted = isSpeakerOff;
    }
  }, [isSpeakerOff]);

  // ✅ NEW: Listen for return events from chess game
  useEffect(() => {
    const handleGameResult = (event: CustomEvent) => {
      const { winner, message } = event.detail;
      
      setGameResult({
        showAlert: true,
        winner,
        message
      });
      
      toast.success(message, { duration: 3000 });
    };

    window.addEventListener('chess-game-ended', handleGameResult as EventListener);

    return () => {
      window.removeEventListener('chess-game-ended', handleGameResult as EventListener);
    };
  }, []);

  // ✅ NEW: Enhanced return to room with reconnection trigger
  // ✅ NEW: Listen for opponent returning from chess
useEffect(() => {
  if (!gameId) return;

  console.log('♟️ Setting up opponent return listener');

  const channel = supabase
    .channel(`chess-end-${gameId}`)
    .on('broadcast', { event: 'player-returning' }, (payload) => {
      const { userId, newRoomId } = payload.payload;
      
      if (userId === opponentId) {
        console.log('♟️ Opponent is returning to room:', newRoomId);
        toast.info(`${opponentName} returned to room`, { duration: 2000 });
        
        // If opponent returns first, we should also return
        setTimeout(() => {
          handleReturnToRoom();
        }, 1000);
      }
    })
    .subscribe();

  return () => {
    supabase.removeChannel(channel);
  };
}, [gameId, opponentId, opponentName]); // Don't include handleReturnToRoom in deps

// ✅ UPDATED: Enhanced return with database logic
const handleReturnToRoom = useCallback(async () => {
  console.log('🏁 Returning to room from chess...');
  
  setIsReturning(true);
  setGameResult({ showAlert: false, winner: null, message: '' });
  
  try {
    // Call database function to handle room logic
    const { data: returnData, error: returnError } = await supabase.rpc(
      'return_from_chess_to_appropriate_room',
      {
        p_game_id: gameId,
        p_user_id: myUserId
      }
    );
    
    if (returnError) {
      console.error('❌ Error returning from chess:', returnError);
      toast.error('Error returning to room');
      onClose();
      return;
    }
    
    const result = returnData as {
      success: boolean;
      new_room_id?: string;
      room_size?: number;
      is_new_room?: boolean;
      message?: string;
      error?: string;
    };
    
    if (!result.success) {
      console.error('❌ Return failed:', result.error);
      toast.error('Could not return to room');
      onClose();
      return;
    }
    
    console.log('✅ Chess return result:', result);
    
    // Broadcast to opponent that we're returning
    const chessChannel = supabase.channel(`chess-end-${gameId}`);
    await chessChannel.send({
      type: 'broadcast',
      event: 'player-returning',
      payload: {
        gameId,
        userId: myUserId,
        newRoomId: result.new_room_id
      }
    });
    
    // Trigger reconnection event with new room info
    window.dispatchEvent(new CustomEvent('return-from-chess', {
      detail: { 
        gameId, 
        opponentId,
        newRoomId: result.new_room_id,
        roomSize: result.room_size,
        isNewRoom: result.is_new_room,
        triggeredBy: 'user-click'
      }
    }));
    
    // Show appropriate message
    if (result.is_new_room && result.room_size === 2) {
      toast.success('Moving to new 2-person room...', { duration: 2000 });
    } else if (!result.is_new_room) {
      toast.success('Returning to room...', { duration: 2000 });
    }
    
    // Navigate to the new/original room
    if (result.new_room_id) {
      setTimeout(() => {
        window.location.href = `/room/${result.new_room_id}`;
      }, 500);
    } else {
      onClose();
    }
    
  } catch (error) {
    console.error('❌ Error in handleReturnToRoom:', error);
    toast.error('Error returning to room');
    onClose();
  }
}, [onClose, gameId, opponentId, myUserId]);

  const restartChessConnection = () => {
    cleanupTimeouts();
    setRetryCount(0);
    const isInitiator = myColor === 'white';
    setupWebRTC(isInitiator);
  };

  const forcePlayVideo = () => {
    if (chessOpponentVideoRef.current) {
      chessOpponentVideoRef.current.play();
    }
  };

  const hasOpponentStream = opponentStreamRef.current !== null;

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

      {/* Header */}
      <header className="flex items-center justify-between p-2 md:p-4 border-b border-border">
        <Logo size="sm" />
        <div className="flex items-center gap-2 md:gap-4">
          <div className={cn(
            "flex items-center gap-2 glass rounded-full px-3 py-1.5 md:px-4 md:py-2",
            isOpponentConnected 
              ? "bg-green-500/20 text-green-600" 
              : "bg-yellow-500/20 text-yellow-600"
          )}>
            {isOpponentConnected ? (
              <>
                <div className="w-2 h-2 rounded-full bg-green-500" />
                <span className="text-xs md:text-sm font-medium">Connected</span>
              </>
            ) : (
              <>
                <Loader2 className="w-3 h-3 md:w-4 md:h-4 animate-spin" />
                <span className="text-xs md:text-sm font-medium">{connectionStatus}</span>
              </>
            )}
            {retryCount > 0 && (
              <span className="text-[10px] text-muted-foreground">
                ({retryCount}/3)
              </span>
            )}
          </div>
          
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
            opponentId={opponentId} // ✅ Pass opponentId
            onClose={onClose}
            isEmbedded={true}
            originalRoomId={originalRoomId}
            isBetMatch={isBetMatch}
            betAmount={betAmount}
            onGameEnd={(winner, message) => {
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
            {!isOpponentConnected && (
              <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center z-10">
                <div className="text-center p-6">
                  <div className="w-16 h-16 border-4 border-blue-500 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
                  <p className="text-white text-lg mb-2">{connectionStatus}</p>
                  <p className="text-gray-400">
                    {myColor === 'white' ? 'Initiating connection...' : 'Waiting for connection...'}
                  </p>
                  {retryCount > 0 && (
                    <p className="text-yellow-400 text-sm mt-2">
                      Auto-retrying... ({retryCount}/3)
                    </p>
                  )}
                  <Button 
                    variant="outline" 
                    size="sm"
                    className="mt-4 text-white border-gray-600"
                    onClick={restartChessConnection}
                  >
                    Retry Connection
                  </Button>
                </div>
              </div>
            )}
            
            <video
              ref={chessOpponentVideoRef}
              autoPlay
              playsInline
              muted={isSpeakerOff}
              className="w-full h-full object-cover bg-gray-800"
              onClick={forcePlayVideo}
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
            {!isOpponentConnected && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/60 z-10 rounded-full">
                <Loader2 className="w-6 h-6 text-white animate-spin" />
              </div>
            )}
            
            <video
              ref={mobileOpponentVideoRef}
              autoPlay
              playsInline
              muted={isSpeakerOff}
              className="w-full h-full object-cover scale-150"
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
              <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/20 to-muted rounded-full">
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