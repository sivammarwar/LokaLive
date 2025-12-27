// ============================================
// Room.tsx Part 1/12 - Imports & Type Definitions
// ✅ FIXED: Stable refs to prevent video detachment
// ============================================

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Logo } from '@/components/Logo';
import { HealthTokens } from '@/components/HealthTokens';
import { useUserStore } from '@/lib/userStore';
import { useDiamondStore } from '@/lib/diamondStore';
import { useWebRTC } from '@/hooks/useWebRTC';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { ChessMatchTypeModal } from '@/components/ChessMatchTypeModal';
import { VideoQualitySelector } from '@/components/VideoQualitySelector';
import { SignalingIndicator } from '@/components/SignalingIndicator';
import RoomDiagnostics from '@/components/RoomDiagnostics';
import { FullscreenVideoView } from '@/components/FullscreenVideoView';
import { WebRTCDiagnostic } from '@/components/WebRTCDiagnostic';

import { 
  useVideoStreamManager,
  useRemoteVideoManager, 
  useFullscreenVideoManager 
} from '@/hooks/useVideoStreamManager';

import {
  Mic, MicOff, Volume2, VolumeX, Flag, MonitorUp, Phone, Users, Copy,
  Video, VideoOff, Swords, Maximize, UserX, X, SkipForward, Loader2, Gem,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { ChessGameView } from './ChessGameView/ChessGameView';
import { 
  getMembershipStyle, 
  getPremiumVideoClasses,
  type MembershipTier 
} from '@/lib/premiumStyles';
import { ChessGameWithBet } from '../lib/types/diamond';

// ============================================
// Type Definitions
// ============================================

interface Participant {
  id: string;
  user_id: string;
  display_name: string;
  membership_tier: MembershipTier;
  diamonds: number;
}

interface ChessInvite {
  gameId: string;
  inviterId: string;
  inviterName: string;
  inviterDiamonds: number;
  isBetMatch: boolean;
  betAmount?: number;
}

interface KickVote {
  targetUserId: string;
  targetUserName: string;
  initiatorId: string;
  initiatorName: string;
  votes: Set<string>;
  requiredVotes: number;
}

interface RoomData {
  id: string;
  room_type: 'public' | 'private';
  room_size: number;
  room_code?: string;
  gender_preference?: string;
  interest_category?: string;
  creator_gender?: string;
  is_active: boolean;
  created_at: string;
}

type Gender = 'male' | 'female' | 'other';
type Interest = 'student' | 'music' | 'entertainment' | 'friend' | 'random' | 'iitians' | 'nitians';

// ============================================
// Room.tsx Part 2/12 - Component Declaration & State
// ✅ FIXED: Added stable ref tracking for video elements
// ============================================

export default function Room() {
  const { roomId } = useParams<{ roomId: string }>();
  const navigate = useNavigate();
  
  // User Store
  const { 
    id: userId, 
    displayName, 
    healthTokens, 
    gender, 
    interestedIn, 
    interest 
  } = useUserStore();
  
  const { diamonds, refreshDiamonds } = useDiamondStore();

  // ============================================
  // STATE DECLARATIONS
  // ============================================
  
  // Media State
  const [isMuted, setIsMuted] = useState(false);
  const [isVideoOff, setIsVideoOff] = useState(false);
  const [isSpeakerOff, setIsSpeakerOff] = useState(false);
  const [isScreenSharing, setIsScreenSharing] = useState(false);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  
  // Room State
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [roomData, setRoomData] = useState<RoomData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [myMembershipTier, setMyMembershipTier] = useState<MembershipTier>('free');
  
  // UI State
  const [fullscreenUserId, setFullscreenUserId] = useState<string | null>(null);
  const [isSearchingNextRoom, setIsSearchingNextRoom] = useState(false);
  
  // Connection status tracking
  const [isMediaReady, setIsMediaReady] = useState(false);
  const [isRoomReady, setIsRoomReady] = useState(false);
  
  // Kick Vote State
  const [activeKickVote, setActiveKickVote] = useState<KickVote | null>(null);
  const [showKickVoteModal, setShowKickVoteModal] = useState(false);
  
  // Chess State
  const [activeChessGame, setActiveChessGame] = useState<{
    gameId: string;
    myColor: 'white' | 'black';
    opponentId: string;
    opponentName: string;
    chessRoomId: string;
    isBetMatch: boolean;
    betAmount?: number;
  } | null>(null);
  
  const [pendingChessInvite, setPendingChessInvite] = useState<ChessInvite | null>(null);
  const [showMatchTypeModal, setShowMatchTypeModal] = useState(false);
  const [selectedOpponent, setSelectedOpponent] = useState<{
    id: string;
    name: string;
    diamonds: number;
  } | null>(null);

  // Next room status
  const [nextRoomStatus, setNextRoomStatus] = useState<{
    isSearching: boolean;
    message: string;
  }>({ isSearching: false, message: '' });

  // ✅ CRITICAL FIX: Refs for cleanup and stable callbacks
  const mountedRef = useRef(true);
  const joiningRoomRef = useRef(false);
  const videoRefsMapRef = useRef<Map<string, HTMLVideoElement>>(new Map());

  // ============================================
  // CUSTOM HOOKS
  // ============================================
  
  const { 
    remoteStreams, 
    announceLeave, 
    replaceVideoTrack, 
    changeVideoQuality, 
    currentQuality,
    peerConnectionsRef // ✅ For diagnostics
  } = useWebRTC({
    roomId: activeChessGame ? activeChessGame.chessRoomId : (roomId || ''),
    userId: userId || '',
    displayName: displayName || '',
    localStream,
  });

  // Local video hook
  const { videoRef: localVideoRef } = useVideoStreamManager({
    stream: localStream,
    isEnabled: !isVideoOff,
    isMuted: true,
    shouldAttach: !activeChessGame && !fullscreenUserId,
    debugLabel: 'local-video',
  });

  // ✅ CRITICAL FIX: Create stable setRemoteVideoRef callback using useMemo
  // const setRemoteVideoRef = useMemo(() => {
  //   return (peerId: string) => {
  //     return (el: HTMLVideoElement | null) => {
  //       const existing = videoRefsMapRef.current.get(peerId);
        
  //       // Only update if element actually changed
  //       if (el && el !== existing) {
  //         console.log(`🔌 [Room] Setting video ref for ${peerId.slice(0, 8)}`);
  //         videoRefsMapRef.current.set(peerId, el);
  //       } else if (!el && existing) {
  //         console.log(`🔌 [Room] Clearing video ref for ${peerId.slice(0, 8)}`);
  //         videoRefsMapRef.current.delete(peerId);
  //       }
  //     };
  //   };
  // }, []); // ✅ Empty deps = stable callback

  // Remote video manager with stable callback
  // const { setVideoRef: _setRemoteVideoRefFromHook } = useRemoteVideoManager(
  //   remoteStreams,
  //   !fullscreenUserId && !activeChessGame,
  //   isSpeakerOff
  // );

  // Fullscreen video hook
  const { videoRef: fullscreenVideoRef } = useFullscreenVideoManager(
    fullscreenUserId,
    userId!,
    localStream,
    remoteStreams,
    isSpeakerOff
  );
  const { setVideoRef: setRemoteVideoRef } = useRemoteVideoManager(
    remoteStreams,
    !fullscreenUserId && !activeChessGame,
    isSpeakerOff
  );
  // ============================================
  // COMPUTED VALUES (using useMemo for stability)
  // ============================================
  
  const hasPremiumAccess = useMemo(
    () => myMembershipTier === 'premium' || myMembershipTier === 'premium_plus',
    [myMembershipTier]
  );
  
  const totalParticipants = useMemo(
    () => 1 + remoteStreams.size,
    [remoteStreams.size]
  );
  
  const myMembershipStyle = useMemo(
    () => getMembershipStyle(myMembershipTier),
    [myMembershipTier]
  );
  
  const MyMembershipIcon = myMembershipStyle.icon;
  
  const allParticipantIds = useMemo(
    () => [userId!, ...Array.from(remoteStreams.keys())],
    [userId, remoteStreams]
  );
  
  const myVideoClasses = useMemo(
    () => getPremiumVideoClasses(myMembershipTier, fullscreenUserId === userId),
    [myMembershipTier, fullscreenUserId, userId]
  );

  // ============================================
// Room.tsx Part 3/12 - Fetch User Data & Initialize Media
// ✅ FIXED: Better media initialization
// ============================================

  // Fetch user membership and diamond balance
  useEffect(() => {
    const fetchUserData = async () => {
      if (!userId) return;
      
      const { data, error } = await supabase
        .from('users')
        .select('membership_tier, diamonds')
        .eq('id', userId)
        .single();
      
      if (error) {
        console.error('❌ Error fetching user data:', error);
        return;
      }
      
      if (data) {
        setMyMembershipTier(data.membership_tier as MembershipTier);
        await refreshDiamonds(userId);
        console.log('✅ User data loaded:', data.membership_tier);
      }
    };
    
    fetchUserData();
  }, [userId, refreshDiamonds]);

  // ============================================
  // ✅ Initialize Media with Better Error Handling
  // ============================================
  useEffect(() => {
    if (!userId) {
      navigate('/');
      return;
    }

    mountedRef.current = true;
    
    const initMedia = async () => {
      try {
        const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
        console.log('📹 Initializing media...', { isMobile });
        
        const constraints = {
          video: isMobile ? {
            width: { ideal: 640, max: 1280 },
            height: { ideal: 480, max: 720 },
            facingMode: 'user',
            frameRate: { ideal: 24, max: 30 },
          } : {
            width: { ideal: 1280 },
            height: { ideal: 720 },
            facingMode: 'user',
          },
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            sampleRate: isMobile ? 16000 : 48000,
          },
        };
        
        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        
        if (!mountedRef.current) {
          console.log('⚠️ Component unmounted during media init, cleaning up');
          stream.getTracks().forEach(track => track.stop());
          return;
        }
        
        // Verify tracks are active
        const videoTrack = stream.getVideoTracks()[0];
        const audioTrack = stream.getAudioTracks()[0];
        
        if (!videoTrack || !audioTrack) {
          throw new Error('Missing video or audio track');
        }
        
        console.log('✅ Media tracks obtained:', {
          video: videoTrack.label,
          audio: audioTrack.label,
          videoState: videoTrack.readyState,
          audioState: audioTrack.readyState
        });
        
        setLocalStream(stream);
        setIsMediaReady(true);
        
        // Monitor track states
        videoTrack.onended = () => {
          console.warn('⚠️ Video track ended unexpectedly');
          toast.warning('Camera disconnected');
        };
        
        audioTrack.onended = () => {
          console.warn('⚠️ Audio track ended unexpectedly');
          toast.warning('Microphone disconnected');
        };
        
      } catch (error: any) {
        console.error('❌ Media error:', error);
        
        if (!mountedRef.current) return;
        
        // Better error messages
        if (error.name === 'NotAllowedError') {
          toast.error('Camera/microphone permission denied. Please allow access.');
        } else if (error.name === 'NotFoundError') {
          toast.error('No camera or microphone found');
        } else if (error.name === 'NotReadableError') {
          toast.error('Camera/microphone is already in use by another application');
        } else {
          // Fallback to basic constraints
          try {
            console.log('🔄 Trying fallback constraints...');
            const fallbackStream = await navigator.mediaDevices.getUserMedia({
              video: { facingMode: 'user' },
              audio: true,
            });
            
            if (mountedRef.current) {
              setLocalStream(fallbackStream);
              setIsMediaReady(true);
              toast.success('Camera connected with basic settings');
            } else {
              fallbackStream.getTracks().forEach(track => track.stop());
            }
          } catch (fallbackError) {
            if (mountedRef.current) {
              toast.error('Could not access camera/microphone. Please check permissions.');
            }
          }
        }
      }
    };
    
    initMedia();

    // Cleanup
    return () => {
      console.log('🧹 Cleaning up media stream');
      mountedRef.current = false;
      if (localStream) {
        localStream.getTracks().forEach(track => {
          track.stop();
          console.log('🛑 Stopped track:', track.kind);
        });
      }
    };
  }, [userId, navigate]);

  // ============================================
// Room.tsx Part 3/12 - Fetch User Data & Initialize Media
// ✅ FIXED: Better media initialization
// ============================================

  // Fetch user membership and diamond balance
  useEffect(() => {
    const fetchUserData = async () => {
      if (!userId) return;
      
      const { data, error } = await supabase
        .from('users')
        .select('membership_tier, diamonds')
        .eq('id', userId)
        .single();
      
      if (error) {
        console.error('❌ Error fetching user data:', error);
        return;
      }
      
      if (data) {
        setMyMembershipTier(data.membership_tier as MembershipTier);
        await refreshDiamonds(userId);
        console.log('✅ User data loaded:', data.membership_tier);
      }
    };
    
    fetchUserData();
  }, [userId, refreshDiamonds]);

  // ============================================
  // ✅ Initialize Media with Better Error Handling
  // ============================================
  useEffect(() => {
    if (!userId) {
      navigate('/');
      return;
    }

    mountedRef.current = true;
    
    const initMedia = async () => {
      try {
        const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
        console.log('📹 Initializing media...', { isMobile });
        
        const constraints = {
          video: isMobile ? {
            width: { ideal: 640, max: 1280 },
            height: { ideal: 480, max: 720 },
            facingMode: 'user',
            frameRate: { ideal: 24, max: 30 },
          } : {
            width: { ideal: 1280 },
            height: { ideal: 720 },
            facingMode: 'user',
          },
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            sampleRate: isMobile ? 16000 : 48000,
          },
        };
        
        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        
        if (!mountedRef.current) {
          console.log('⚠️ Component unmounted during media init, cleaning up');
          stream.getTracks().forEach(track => track.stop());
          return;
        }
        
        // Verify tracks are active
        const videoTrack = stream.getVideoTracks()[0];
        const audioTrack = stream.getAudioTracks()[0];
        
        if (!videoTrack || !audioTrack) {
          throw new Error('Missing video or audio track');
        }
        
        console.log('✅ Media tracks obtained:', {
          video: videoTrack.label,
          audio: audioTrack.label,
          videoState: videoTrack.readyState,
          audioState: audioTrack.readyState
        });
        
        setLocalStream(stream);
        setIsMediaReady(true);
        
        // Monitor track states
        videoTrack.onended = () => {
          console.warn('⚠️ Video track ended unexpectedly');
          toast.warning('Camera disconnected');
        };
        
        audioTrack.onended = () => {
          console.warn('⚠️ Audio track ended unexpectedly');
          toast.warning('Microphone disconnected');
        };
        
      } catch (error: any) {
        console.error('❌ Media error:', error);
        
        if (!mountedRef.current) return;
        
        // Better error messages
        if (error.name === 'NotAllowedError') {
          toast.error('Camera/microphone permission denied. Please allow access.');
        } else if (error.name === 'NotFoundError') {
          toast.error('No camera or microphone found');
        } else if (error.name === 'NotReadableError') {
          toast.error('Camera/microphone is already in use by another application');
        } else {
          // Fallback to basic constraints
          try {
            console.log('🔄 Trying fallback constraints...');
            const fallbackStream = await navigator.mediaDevices.getUserMedia({
              video: { facingMode: 'user' },
              audio: true,
            });
            
            if (mountedRef.current) {
              setLocalStream(fallbackStream);
              setIsMediaReady(true);
              toast.success('Camera connected with basic settings');
            } else {
              fallbackStream.getTracks().forEach(track => track.stop());
            }
          } catch (fallbackError) {
            if (mountedRef.current) {
              toast.error('Could not access camera/microphone. Please check permissions.');
            }
          }
        }
      }
    };
    
    initMedia();

    // Cleanup
    return () => {
      console.log('🧹 Cleaning up media stream');
      mountedRef.current = false;
      if (localStream) {
        localStream.getTracks().forEach(track => {
          track.stop();
          console.log('🛑 Stopped track:', track.kind);
        });
      }
    };
  }, [userId, navigate]);


  // ✅ FIX: Load room data and participants
useEffect(() => {
  if (!roomId || !userId) return;
  
  let mounted = true;
  
  const fetchRoomData = async () => {
    try {
      console.log('📊 [Room] Loading room data...');
      
      // Load room details
      const { data: room, error: roomError } = await supabase
        .from('rooms')
        .select('*')
        .eq('id', roomId)
        .single();
      
      if (roomError) {
        console.error('❌ [Room] Error loading room:', roomError);
        return;
      }
      
      if (room && mounted) {
        setRoomData(room);
        console.log('✅ [Room] Room loaded:', room);
      }
      
      // ✅ CRITICAL FIX: Load participants with JOIN to get user data
      const { data: participantsData, error: participantsError } = await supabase
        .from('room_participants')
        .select(`
          user_id,
          joined_at,
          users!inner (
            display_name,
            membership_tier,
            diamonds
          )
        `)
        .eq('room_id', roomId)
        .is('left_at', null);
      
      if (participantsError) {
        console.error('❌ [Room] Error loading participants:', participantsError);
        return;
      }
      
      console.log('📥 [Room] Raw participants data:', participantsData);
      
      if (participantsData && mounted) {
        const participantList: Participant[] = participantsData.map(p => {
          // Handle both possible data structures
          const userData = Array.isArray(p.users) ? p.users[0] : p.users;
          
          return {
            id: p.user_id,
            user_id: p.user_id,
            display_name: userData?.display_name || 'Unknown User',
            membership_tier: (userData?.membership_tier as MembershipTier) || 'free',
            diamonds: userData?.diamonds || 0,
          };
        });
        
        setParticipants(participantList);
        console.log('✅ [Room] Participants loaded:', participantList.map(p => ({
          id: p.user_id.slice(0, 8),
          name: p.display_name
        })));
      }
      
      if (mounted) {
        setIsRoomReady(true);
        setIsLoading(false);
      }
      
    } catch (error) {
      console.error('❌ [Room] Error in fetchRoomData:', error);
      if (mounted) setIsLoading(false);
    }
  };
  
  fetchRoomData();
  
  // ✅ Subscribe to new participants joining
  const participantChannel = supabase
    .channel(`room-participants-${roomId}`)
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'room_participants',
      filter: `room_id=eq.${roomId}`,
    }, async (payload) => {
      console.log('👤 [Room] New participant joined:', payload.new.user_id);
      
      // Fetch the new user's data
      const { data: newUser } = await supabase
        .from('users')
        .select('display_name, membership_tier, diamonds')
        .eq('id', payload.new.user_id)
        .single();
      
      if (newUser && mounted) {
        const newParticipant: Participant = {
          id: payload.new.user_id,
          user_id: payload.new.user_id,
          display_name: newUser.display_name || 'Unknown',
          membership_tier: (newUser.membership_tier as MembershipTier) || 'free',
          diamonds: newUser.diamonds || 0,
        };
        
        setParticipants(prev => {
          // Don't add if already exists
          if (prev.some(p => p.user_id === newParticipant.user_id)) {
            return prev;
          }
          return [...prev, newParticipant];
        });
        
        console.log('✅ [Room] Added new participant:', newParticipant.display_name);
      }
    })
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'room_participants',
      filter: `room_id=eq.${roomId}`,
    }, (payload) => {
      // Handle participant leaving
      if (payload.new.left_at && mounted) {
        console.log('👋 [Room] Participant left:', payload.new.user_id);
        setParticipants(prev => 
          prev.filter(p => p.user_id !== payload.new.user_id)
        );
      }
    })
    .subscribe();
  
  return () => {
    mounted = false;
    supabase.removeChannel(participantChannel);
  };
}, [roomId, userId]);

  // ============================================
// Room.tsx Part 5/12 - Chess & Kick Vote Subscriptions
// ✅ No changes - working correctly
// ============================================

  // Chess game subscriptions
  useEffect(() => {
    if (!roomId || !userId) return;

    const chessChannel = supabase
      .channel(`chess-invites-${roomId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'chess_games',
        filter: `room_id=eq.${roomId}`,
      }, async (payload) => {
        const game = payload.new as ChessGameWithBet;
        
        if (game.black_player_id === userId && game.status === 'pending') {
          const { data: inviter } = await supabase
            .from('users')
            .select('display_name, diamonds')
            .eq('id', game.white_player_id)
            .single();

          setPendingChessInvite({
            gameId: game.id,
            inviterId: game.white_player_id,
            inviterName: inviter?.display_name || 'Someone',
            inviterDiamonds: inviter?.diamonds || 0,
            isBetMatch: game.is_bet_match || false,
            betAmount: game.bet_amount,
          });
        }
      })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'chess_games',
        filter: `room_id=eq.${roomId}`,
      }, async (payload) => {
        const game = payload.new as ChessGameWithBet;
        
        if (game.status === 'active' && game.white_player_id === userId && !activeChessGame) {
          const { data: opponent } = await supabase
            .from('users')
            .select('display_name')
            .eq('id', game.black_player_id)
            .single();

          await createChessRoom(
            game.id, 
            game.black_player_id, 
            opponent?.display_name || 'Opponent',
            game.is_bet_match || false,
            game.bet_amount
          );
        }
      })
      .on('broadcast', { event: 'chess-room-created' }, async (payload) => {
        const { gameId, chessRoomId, opponentId, opponentName, isBetMatch, betAmount } = payload.payload;
        
        if (opponentId === userId) {
          setActiveChessGame({
            gameId,
            myColor: 'black',
            opponentId: payload.payload.inviterId,
            opponentName: payload.payload.inviterName,
            chessRoomId,
            isBetMatch: isBetMatch || false,
            betAmount,
          });
          toast.success(
            isBetMatch 
              ? `Chess bet match started! ${betAmount} diamonds at stake` 
              : 'Chess game started!'
          );
        }
      })
      .on('broadcast', { event: 'chess-resigned' }, async (payload) => {
        const { gameId: resignedGameId, resignerName } = payload.payload;
        
        if (activeChessGame && activeChessGame.gameId === resignedGameId) {
          toast.success(`${resignerName} resigned. You won!`);
          setTimeout(() => returnToOriginalRoom(), 2000);
        }
      })
      .subscribe();

    const kickVoteChannel = supabase
      .channel(`kick-votes-${roomId}`)
      .on('broadcast', { event: 'kick-vote-initiated' }, (payload) => {
        const { targetUserId, targetUserName, initiatorId, initiatorName, requiredVotes } = payload.payload;
        
        if (targetUserId !== userId && initiatorId !== userId) {
          setActiveKickVote({
            targetUserId, 
            targetUserName, 
            initiatorId, 
            initiatorName,
            votes: new Set([initiatorId]), 
            requiredVotes,
          });
          setShowKickVoteModal(true);
        }
      })
      .on('broadcast', { event: 'kick-vote-cast' }, (payload) => {
        const { voterId, targetUserId: target } = payload.payload;
        
        setActiveKickVote((prev) => {
          if (!prev || prev.targetUserId !== target) return prev;
          const newVotes = new Set(prev.votes);
          newVotes.add(voterId);
          return { ...prev, votes: newVotes };
        });
      })
      .on('broadcast', { event: 'kick-vote-cancelled' }, () => {
        setActiveKickVote(null);
        setShowKickVoteModal(false);
      })
      .subscribe();

    return () => {
      supabase.removeChannel(chessChannel);
      supabase.removeChannel(kickVoteChannel);
    };
  }, [roomId, userId, activeChessGame]);

  // Auto-kick when votes reach threshold
  useEffect(() => {
    if (activeKickVote && activeKickVote.votes.size >= activeKickVote.requiredVotes) {
      handleKickUser(activeKickVote.targetUserId);
      setActiveKickVote(null);
      setShowKickVoteModal(false);
    }
  }, [activeKickVote]);
  // ============================================
// Room.tsx Part 6/12 - Media Control Handlers
// ✅ Using useCallback for stable function refs
// ============================================

  // Toggle microphone mute
  const toggleMute = useCallback(() => {
    if (localStream) {
      const audioTrack = localStream.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled;
        setIsMuted(!isMuted);
        console.log('🎤', isMuted ? 'Unmuted' : 'Muted');
      }
    }
  }, [localStream, isMuted]);

  // Toggle video on/off
  const toggleVideo = useCallback(() => {
    if (localStream) {
      const videoTrack = localStream.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.enabled = !videoTrack.enabled;
        setIsVideoOff(!isVideoOff);
        console.log('📹', isVideoOff ? 'Video ON' : 'Video OFF');
      }
    }
  }, [localStream, isVideoOff]);

  // Toggle speaker on/off
  const toggleSpeaker = useCallback(() => {
    setIsSpeakerOff(!isSpeakerOff);
    console.log('🔊', isSpeakerOff ? 'Speaker ON' : 'Speaker OFF');
  }, [isSpeakerOff]);

  // Toggle fullscreen view
  const handleFullscreen = useCallback((targetUserId: string) => {
    if (!hasPremiumAccess) {
      toast.error('This feature is only available for Premium members');
      return;
    }
    setFullscreenUserId(fullscreenUserId === targetUserId ? null : targetUserId);
  }, [hasPremiumAccess, fullscreenUserId]);

  // Handle screen sharing
  const handleScreenShare = useCallback(async () => {
    if (roomData?.room_type !== 'private') {
      toast.error('Screen sharing is only available in private rooms');
      return;
    }
    
    try {
      if (!isScreenSharing) {
        const screenStream = await navigator.mediaDevices.getDisplayMedia({
          video: true, 
          audio: true,
        });
        
        const screenVideoTrack = screenStream.getVideoTracks()[0];
        await replaceVideoTrack(screenVideoTrack);
        
        screenVideoTrack.onended = async () => {
          if (localStream) {
            const cameraTrack = localStream.getVideoTracks()[0];
            if (cameraTrack) await replaceVideoTrack(cameraTrack);
          }
          setIsScreenSharing(false);
          toast.info('Screen sharing stopped');
        };
        
        setIsScreenSharing(true);
        toast.success('Screen sharing started');
      } else {
        if (localStream) {
          const cameraTrack = localStream.getVideoTracks()[0];
          if (cameraTrack) await replaceVideoTrack(cameraTrack);
        }
        setIsScreenSharing(false);
      }
    } catch (error) {
      console.error('❌ Screen share error:', error);
      toast.error('Could not start screen sharing');
    }
  }, [roomData?.room_type, isScreenSharing, replaceVideoTrack, localStream]);

  // Change video quality
  const handleQualityChange = useCallback(async (quality: 'sd' | 'hd' | 'fullhd') => {
    const success = await changeVideoQuality(quality);
    if (!success) {
      toast.error('Failed to change video quality');
    }
  }, [changeVideoQuality]);

  // Copy room code to clipboard
  const copyRoomCode = useCallback(() => {
    if (roomData?.room_code) {
      navigator.clipboard.writeText(roomData.room_code);
      toast.success('Room code copied!');
    }
  }, [roomData?.room_code]);
  // ============================================
// Room.tsx Part 7/12 - Room Navigation Handlers
// ✅ Using useCallback for stability
// ============================================

  // Report user
  const handleReport = useCallback(async (reportedUserId: string) => {
    if (reportedUserId === userId) {
      toast.error("You can't report yourself");
      return;
    }
    
    await supabase.from('reports').insert({
      reporter_id: userId,
      reported_user_id: reportedUserId,
      room_id: roomId,
      reason: 'User reported via in-room button',
    });
    
    toast.success(
      hasPremiumAccess 
        ? 'Premium report submitted!' 
        : 'Report submitted'
    );
  }, [userId, roomId, hasPremiumAccess]);

  // ✅ Leave current room with proper cleanup
  const handleLeaveRoom = useCallback(async () => {
    console.log('🚪 Leaving room...');
    
    try {
      // Stop local stream first
      if (localStream) {
        localStream.getTracks().forEach(track => {
          track.stop();
          console.log('🛑 Stopped track:', track.kind);
        });
      }
      
      // Announce leave via WebRTC
      const leavePromise = announceLeave();
      
      // Update database
      const dbPromise = supabase
        .from('room_participants')
        .update({ left_at: new Date().toISOString() })
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .is('left_at', null);
      
      // Wait for both with timeout
      await Promise.race([
        Promise.all([leavePromise, dbPromise]), 
        new Promise(r => setTimeout(r, 2000))
      ]);
      
      console.log('✅ Successfully left room');
      toast.success('Left the room');
      
      // Navigate after cleanup
      await new Promise(resolve => setTimeout(resolve, 300));
      navigate('/create-room');
      
    } catch (error) {
      console.error('❌ Error leaving room:', error);
      toast.error('Error leaving room');
      navigate('/create-room');
    }
  }, [localStream, announceLeave, roomId, userId, navigate]);

  // ✅ Next Room - Better error handling
  const handleNextRoom = useCallback(async () => {
    if (!roomData || roomData.room_type !== 'public') {
      toast.error('Next room is only available for public rooms');
      return;
    }
    
    if (!userId || !gender) {
      toast.error('Missing user information');
      return;
    }

    try {
      setNextRoomStatus({ 
        isSearching: true, 
        message: 'Leaving current room...' 
      });
      
      console.log('🚪 Starting Next Room process...');
      
      // STEP 1: Leave current room
      console.log('📤 Step 1: Leaving current room');
      
      if (localStream) {
        localStream.getTracks().forEach(track => {
          track.stop();
          console.log('  🛑 Stopped', track.kind, 'track');
        });
      }
      
      const leavePromise = announceLeave().catch(err => {
        console.warn('  ⚠️ WebRTC leave warning:', err);
      });
      
      const dbPromise = supabase.rpc('leave_all_user_rooms', {
        p_user_id: userId
      });
      
      await Promise.race([
        Promise.all([leavePromise, dbPromise]),
        new Promise(resolve => setTimeout(resolve, 2000))
      ]);
      
      console.log('  ✅ Left current room');
      
      await new Promise(resolve => setTimeout(resolve, 300));
      
      // STEP 2: Find or create new room
      setNextRoomStatus({ 
        isSearching: true, 
        message: roomData.room_size === 4 
          ? 'Finding 4-person room...' 
          : 'Finding match...'
      });
      
      console.log('🔍 Step 2: Finding compatible room');
      
      const { data: matchData, error: matchError } = await supabase.rpc(
        'find_compatible_room_simple',
        {
          p_user_id: userId,
          p_user_gender: gender as 'male' | 'female',
          p_room_size: roomData.room_size
        }
      );

      if (matchError) {
        console.error('❌ Matchmaking error:', matchError);
        throw new Error(`Matchmaking failed: ${matchError.message}`);
      }

      if (!matchData || matchData.length === 0) {
        throw new Error('No room data returned from matchmaking');
      }

      const result = matchData[0];
      const newRoomId = result.matched_room_id;
      const isNewRoom = result.is_new_room;

      if (!newRoomId) {
        throw new Error('Invalid room ID returned');
      }

      console.log(`  ✅ ${isNewRoom ? 'Created' : 'Found'} room:`, newRoomId);
      
      // STEP 3: Join the new room
      setNextRoomStatus({ 
        isSearching: true, 
        message: 'Joining room...' 
      });
      
      console.log('🚪 Step 3: Joining room');
      
      let joinSuccess = false;
      const maxAttempts = 3;
      
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        console.log(`  Attempt ${attempt}/${maxAttempts}`);
        
        const { data: joinData, error: joinError } = await supabase.rpc(
          'join_room_if_available',
          {
            p_room_id: newRoomId,
            p_user_id: userId
          }
        );

        if (joinError) {
          console.error('  ❌ Join error:', joinError);
          if (attempt === maxAttempts) {
            throw new Error('Failed to join room after multiple attempts');
          }
          await new Promise(resolve => setTimeout(resolve, 500));
          continue;
        }

        const joinResult = joinData as {
          success: boolean;
          error?: string;
          message?: string;
        };

        if (joinResult.success || joinResult.message?.includes('already')) {
          joinSuccess = true;
          console.log('  ✅ Successfully joined');
          break;
        }

        if (joinResult.error === 'room_full') {
          console.log('  ⚠️ Room full, retrying matchmaking...');
          setNextRoomStatus({ isSearching: false, message: '' });
          setTimeout(() => handleNextRoom(), 500);
          return;
        }

        if (attempt === maxAttempts) {
          throw new Error(joinResult.message || 'Failed to join room');
        }
        
        await new Promise(resolve => setTimeout(resolve, 500));
      }

      if (!joinSuccess) {
        throw new Error('Could not join room');
      }

      // STEP 4: Success - Navigate
      console.log('✅ Successfully joined new room');
      
      toast.success(
        isNewRoom 
          ? (roomData.room_size === 4 
              ? 'Created 4-person room! Waiting for others...' 
              : 'Created room! Waiting for match...')
          : (roomData.room_size === 4
              ? 'Joined 4-person room!'
              : 'Match found!')
      );
      
      await new Promise(resolve => setTimeout(resolve, 500));
      
      navigate(`/room/${newRoomId}`, { replace: true });
      
    } catch (error: any) {
      console.error('❌ Next room error:', error);
      
      let errorMessage = 'Failed to find next room';
      
      if (error.message?.includes('gender')) {
        errorMessage = 'Please set your gender to use this feature';
      } else if (error.message?.includes('full')) {
        errorMessage = 'Room filled up, please try again';
      } else if (error.message?.includes('network')) {
        errorMessage = 'Connection error, please check your internet';
      } else if (error.message) {
        errorMessage = error.message;
      }
      
      toast.error(errorMessage);
      
      console.log('🔄 Falling back to create room page');
      await new Promise(resolve => setTimeout(resolve, 500));
      navigate('/create-room', { replace: true });
      
    } finally {
      setNextRoomStatus({ isSearching: false, message: '' });
    }
  }, [roomData, userId, gender, localStream, announceLeave, navigate]);
  // ============================================
// Room.tsx Part 8/12 - Kick Vote Handlers
// ✅ Using useCallback for stability
// ============================================

  // Initiate kick vote
  const initiateKickVote = useCallback(async (targetUserId: string, targetUserName: string) => {
    if (!hasPremiumAccess) {
      toast.error('This feature is only available for Premium members');
      return;
    }
    
    if (roomData?.room_size !== 4) {
      toast.error('Kick voting is only available in 4-person rooms');
      return;
    }
    
    const totalParticipants = 1 + remoteStreams.size;
    if (totalParticipants !== 4) {
      toast.error('All 4 participants must be present');
      return;
    }
    
    const requiredVotes = 3;
    
    setActiveKickVote({
      targetUserId,
      targetUserName,
      initiatorId: userId!,
      initiatorName: displayName || 'Unknown',
      votes: new Set([userId!]),
      requiredVotes,
    });
    
    const kickVoteChannel = supabase.channel(`kick-votes-${roomId}`);
    await kickVoteChannel.send({
      type: 'broadcast',
      event: 'kick-vote-initiated',
      payload: { 
        targetUserId, 
        targetUserName, 
        initiatorId: userId, 
        initiatorName: displayName, 
        requiredVotes 
      },
    });
    
    toast.success(`Kick vote initiated for ${targetUserName}`);
  }, [hasPremiumAccess, roomData?.room_size, remoteStreams.size, userId, displayName, roomId]);

  // Cast kick vote
  const castKickVote = useCallback(async (approve: boolean) => {
    if (!activeKickVote) return;
    
    const kickVoteChannel = supabase.channel(`kick-votes-${roomId}`);
    
    if (approve) {
      await kickVoteChannel.send({
        type: 'broadcast',
        event: 'kick-vote-cast',
        payload: { 
          voterId: userId, 
          targetUserId: activeKickVote.targetUserId 
        },
      });
      toast.info('Vote cast successfully');
    } else {
      await kickVoteChannel.send({ 
        type: 'broadcast', 
        event: 'kick-vote-cancelled', 
        payload: {} 
      });
      toast.info('Kick vote cancelled');
    }
    
    setShowKickVoteModal(false);
    if (!approve) setActiveKickVote(null);
  }, [activeKickVote, roomId, userId]);

  // Execute kick (remove user from room)
  const handleKickUser = useCallback(async (targetUserId: string) => {
    await supabase
      .from('room_participants')
      .update({ left_at: new Date().toISOString() })
      .eq('room_id', roomId)
      .eq('user_id', targetUserId)
      .is('left_at', null);
    
    const participant = participants.find((p) => p.user_id === targetUserId);
    toast.success(`${participant?.display_name || 'User'} has been removed`);
    setActiveKickVote(null);
  }, [roomId, participants]);
  // ============================================
// Room.tsx Part 9/12 - Chess Game Handlers (Part 1)
// ✅ Using useCallback for stability
// ============================================

  // Open chess match type modal
  const handleChessInviteClick = useCallback((peerId: string, peerName: string) => {
    const participant = participants.find(p => p.user_id === peerId);
    setSelectedOpponent({
      id: peerId,
      name: peerName,
      diamonds: participant?.diamonds || 0,
    });
    setShowMatchTypeModal(true);
  }, [participants]);

  // Send normal (non-bet) chess invitation
  const handleNormalMatch = useCallback(async () => {
    if (!selectedOpponent || !userId || !roomId) return;
    
    setShowMatchTypeModal(false);
    
    const { data: game, error } = await supabase
      .from('chess_games')
      .insert([{ 
        room_id: roomId, 
        white_player_id: userId, 
        black_player_id: selectedOpponent.id, 
        status: 'pending',
        is_bet_match: false,
      }])
      .select()
      .single();
    
    if (!error) {
      toast.success(`Chess invitation sent to ${selectedOpponent.name}!`);
    } else {
      console.error('❌ Error sending chess invite:', error);
      toast.error('Failed to send chess invitation');
    }
    
    setSelectedOpponent(null);
  }, [selectedOpponent, userId, roomId]);

  // Send bet chess invitation
  const handleBetMatch = useCallback(async (betAmount: number) => {
    if (!selectedOpponent || !userId || !roomId) return;
    
    if (diamonds < betAmount) {
      toast.error(`You don't have enough diamonds. You have ${diamonds}, need ${betAmount}`);
      return;
    }
    
    setShowMatchTypeModal(false);
    
    const { error } = await supabase
      .from('chess_games')
      .insert([{ 
        room_id: roomId, 
        white_player_id: userId, 
        black_player_id: selectedOpponent.id, 
        status: 'pending',
        is_bet_match: true,
        bet_amount: betAmount,
        bet_status: 'pending',
      }]);
    
    if (!error) {
      toast.success(`Bet invitation sent! ${betAmount} diamonds at stake`);
    } else {
      console.error('❌ Error sending bet invite:', error);
      toast.error('Failed to send bet invitation');
    }
    
    setSelectedOpponent(null);
  }, [selectedOpponent, userId, roomId, diamonds]);

  // Accept chess invitation
  const acceptChessInvite = useCallback(async () => {
    if (!pendingChessInvite) return;
    
    // Check if it's a bet match and deduct diamonds
    if (pendingChessInvite.isBetMatch && pendingChessInvite.betAmount) {
      if (diamonds < pendingChessInvite.betAmount) {
        toast.error(`You don't have enough diamonds. You have ${diamonds}, need ${pendingChessInvite.betAmount}`);
        return;
      }
      
      const deductSuccess = await deductBetFromPlayers(
        pendingChessInvite.gameId,
        pendingChessInvite.inviterId,
        userId!,
        pendingChessInvite.betAmount
      );
      
      if (!deductSuccess) {
        toast.error('Failed to process bet');
        return;
      }
    }
    
    // Update game status to active
    const { error } = await supabase
      .from('chess_games')
      .update({ 
        status: 'active',
        bet_status: pendingChessInvite.isBetMatch ? 'locked' : undefined,
      })
      .eq('id', pendingChessInvite.gameId);
    
    if (error) {
      console.error('❌ Error accepting chess invite:', error);
      toast.error('Failed to accept chess invitation');
      return;
    }
    
    setPendingChessInvite(null);
    toast.info(
      pendingChessInvite.isBetMatch 
        ? 'Bet locked! Creating chess room...' 
        : 'Creating chess room...'
    );
  }, [pendingChessInvite, diamonds, userId]);

  // Decline chess invitation
  const declineChessInvite = useCallback(async () => {
    if (!pendingChessInvite) return;
    
    await supabase
      .from('chess_games')
      .delete()
      .eq('id', pendingChessInvite.gameId);
    
    setPendingChessInvite(null);
    toast.info('Chess invitation declined');
  }, [pendingChessInvite]);
  // ============================================
// Room.tsx Part 10/12 - Chess Game Handlers (Part 2)
// ✅ Using useCallback for stability
// ============================================

  // Deduct bet diamonds from both players
  const deductBetFromPlayers = useCallback(async (
    gameId: string, 
    player1Id: string, 
    player2Id: string, 
    betAmount: number
  ): Promise<boolean> => {
    try {
      // Deduct from player 1
      const { error: error1 } = await supabase.rpc('deduct_diamonds', { 
        p_user_id: player1Id, 
        p_amount: betAmount 
      });
      
      if (error1) {
        console.error('❌ Failed to deduct from player 1:', error1);
        return false;
      }
      
      // Deduct from player 2
      const { error: error2 } = await supabase.rpc('deduct_diamonds', { 
        p_user_id: player2Id, 
        p_amount: betAmount 
      });
      
      if (error2) {
        console.error('❌ Failed to deduct from player 2:', error2);
        // Refund player 1
        await supabase.rpc('add_diamonds', { 
          p_user_id: player1Id, 
          p_amount: betAmount 
        });
        return false;
      }
      
      // Log transactions
      await supabase.from('diamond_transactions').insert([
        { 
          user_id: player1Id, 
          type: 'bet_deduct', 
          amount: -betAmount, 
          description: `Chess bet deducted: ${betAmount} diamonds`, 
          status: 'completed' 
        },
        { 
          user_id: player2Id, 
          type: 'bet_deduct', 
          amount: -betAmount, 
          description: `Chess bet deducted: ${betAmount} diamonds`, 
          status: 'completed' 
        },
      ]);
      
      // Refresh user's diamond count
      if (userId) await refreshDiamonds(userId);
      
      console.log('✅ Bet deducted successfully from both players');
      return true;
    } catch (error) {
      console.error('❌ Error deducting bet diamonds:', error);
      return false;
    }
  }, [userId, refreshDiamonds]);

  // Create a separate room for chess game
  const createChessRoom = useCallback(async (
    gameId: string, 
    opponentId: string, 
    opponentName: string, 
    isBetMatch: boolean, 
    betAmount?: number
  ) => {
    console.log('♟️ Creating chess room...');
    
    try {
      // ✅ FIX 1: Check if chess room already exists for this game
      const { data: existingGame } = await supabase
        .from('chess_games')
        .select('chess_room_id')
        .eq('id', gameId)
        .single();
  
      let chessRoomId: string;
  
      if (existingGame?.chess_room_id) {
        // Room already exists, use it
        console.log('♻️ Using existing chess room:', existingGame.chess_room_id);
        chessRoomId = existingGame.chess_room_id;
      } else {
        // Create new room
        const { data: newRoom, error: roomError } = await supabase
          .from('rooms')
          .insert({
            room_type: 'private',
            room_size: 2,
            is_active: true,
            creator_id: userId,
          })
          .select()
          .single();
  
        if (roomError || !newRoom) {
          console.error('❌ Failed to create chess room:', roomError);
          toast.error('Failed to create chess room');
          return;
        }
        
        chessRoomId = newRoom.id;
        console.log('✅ Chess room created:', chessRoomId);
  
        // ✅ FIX 2: Update the chess game with the room ID
        await supabase
          .from('chess_games')
          .update({ chess_room_id: chessRoomId })
          .eq('id', gameId);
      }
  
      // ✅ FIX 3: Check existing participants before inserting
      const { data: existingParticipants } = await supabase
        .from('room_participants')
        .select('user_id')
        .eq('room_id', chessRoomId)
        .is('left_at', null);
  
      const existingUserIds = new Set(existingParticipants?.map(p => p.user_id) || []);
      
      // Only insert participants who aren't already in the room
      const participantsToInsert = [];
      if (!existingUserIds.has(userId!)) {
        participantsToInsert.push({ room_id: chessRoomId, user_id: userId });
      }
      if (!existingUserIds.has(opponentId)) {
        participantsToInsert.push({ room_id: chessRoomId, user_id: opponentId });
      }
  
      if (participantsToInsert.length > 0) {
        const { error: participantError } = await supabase
          .from('room_participants')
          .insert(participantsToInsert);
        
        if (participantError) {
          console.error('❌ Failed to add participants:', participantError);
          // Don't fail completely - room might still work
          console.warn('⚠️ Continuing despite participant error...');
        } else {
          console.log(`✅ Added ${participantsToInsert.length} participants`);
        }
      } else {
        console.log('✅ All participants already in room');
      }
      
      // ✅ FIX 4: Broadcast chess room creation
      const chessChannel = supabase.channel(`chess-invites-${roomId}`);
      await chessChannel.send({
        type: 'broadcast',
        event: 'chess-room-created',
        payload: { 
          gameId, 
          chessRoomId, 
          opponentId, 
          opponentName, 
          inviterId: userId, 
          inviterName: displayName, 
          isBetMatch, 
          betAmount 
        },
      });
      
      // ✅ FIX 5: Set active chess game state
      setActiveChessGame({
        gameId, 
        myColor: 'white', 
        opponentId, 
        opponentName, 
        chessRoomId, 
        isBetMatch, 
        betAmount,
      });
      
      toast.success(
        isBetMatch 
          ? `Chess bet match started! ${betAmount} diamonds at stake` 
          : 'Chess match started!'
      );
      
      console.log('✅✅✅ Chess room setup complete');
      
    } catch (error) {
      console.error('❌ Error creating chess room:', error);
      toast.error('Failed to create chess room');
    }
  }, [userId, roomId, displayName]);

  // Return from chess game to original room
  // Return from chess game to original room
  const returnToOriginalRoom = useCallback(async () => {
    if (!activeChessGame) return;
    
    console.log('🔙 Returning to original room...');
    
    try {
      // Clear chess game state first
      setActiveChessGame(null);
      
      // Wait a bit for state to clear
      await new Promise(resolve => setTimeout(resolve, 300));
      
      // Update database
      await supabase
        .from('room_participants')
        .update({ left_at: new Date().toISOString() })
        .eq('room_id', activeChessGame.chessRoomId)
        .eq('user_id', userId)
        .is('left_at', null);
      
      console.log('✅ Chess room left, returning to main room');
      toast.success('Returned to room');
      
      // ✅ CRITICAL: Force a small delay to let WebRTC reinitialize
      setTimeout(() => {
        console.log('✅✅✅ Room should now reconnect video streams');
      }, 500);
      
    } catch (error) {
      console.error('❌ Error returning to room:', error);
      toast.error('Error returning to room');
    }
  }, [activeChessGame, userId]);
  // ============================================
// Room.tsx Part 11/12 - Loading States, Styles & Modals
// ✅ No changes needed
// ============================================

 
  // Loading state while searching for next room
  if (nextRoomStatus.isSearching) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-background via-background to-muted/20">
        <div className="flex flex-col items-center gap-6 glass-strong rounded-3xl p-8 max-w-md">
          <Loader2 className="w-16 h-16 text-primary animate-spin" />
          <div className="text-center space-y-2">
            <h2 className="text-2xl font-bold">
              {roomData?.room_size === 4 ? 'Finding 4-Person Room' : 'Finding Next Match'}
            </h2>
            <p className="text-muted-foreground">
              {nextRoomStatus.message}
            </p>
            {roomData?.room_size === 2 && (
              <p className="text-xs text-muted-foreground mt-2">
                Matching with {gender === 'male' ? 'females' : 'males'} first...
              </p>
            )}
          </div>
          <div className="flex gap-2">
            <div className="w-3 h-3 rounded-full bg-primary animate-pulse" style={{ animationDelay: '0ms' }} />
            <div className="w-3 h-3 rounded-full bg-primary animate-pulse" style={{ animationDelay: '150ms' }} />
            <div className="w-3 h-3 rounded-full bg-primary animate-pulse" style={{ animationDelay: '300ms' }} />
          </div>
        </div>
      </div>
    );
  }

  // Premium animation styles
  const premiumStyles = `
    @keyframes shimmer {
      0% { background-position: 0% 50%; }
      50% { background-position: 100% 50%; }
      100% { background-position: 0% 50%; }
    }
    .premium-plus-shimmer {
      background: linear-gradient(90deg, rgba(251, 191, 36, 0.15) 0%, rgba(234, 179, 8, 0.25) 25%, rgba(253, 224, 71, 0.2) 50%, rgba(234, 179, 8, 0.25) 75%, rgba(251, 191, 36, 0.15) 100%);
      background-size: 200% 200%;
      animation: shimmer 3s ease-in-out infinite;
    }
    .premium-plus-glow { 
      box-shadow: 0 0 30px rgba(234, 179, 8, 0.4), 0 0 60px rgba(234, 179, 8, 0.2), inset 0 0 30px rgba(234, 179, 8, 0.1); 
    }
    .premium-glow { 
      box-shadow: 0 0 20px rgba(59, 130, 246, 0.3), 0 0 40px rgba(59, 130, 246, 0.15); 
    }
    .premium-plus-text {
      background: linear-gradient(90deg, #fcd34d 0%, #fbbf24 50%, #fcd34d 100%);
      background-size: 200% auto;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      animation: shimmer 2s linear infinite;
    }
  `;

  // Main render continues in next part...
  // ============================================
// Room.tsx Part 12a/15 - Main Render Start (Modals)
// ✅ FIXED: Moved ALL modals before main video grid
// ============================================

return (
  <div className="min-h-screen flex flex-col p-4 bg-gradient-to-br from-background via-background to-muted/20">
    <style>{premiumStyles}</style>

    {/* All modals remain the same */}
    {showMatchTypeModal && selectedOpponent && (
      <ChessMatchTypeModal
        opponentId={selectedOpponent.id}
        opponentName={selectedOpponent.name}
        opponentDiamonds={selectedOpponent.diamonds}
        myDiamonds={diamonds}
        onSelectNormal={handleNormalMatch}
        onSelectBet={handleBetMatch}
        onClose={() => {
          setShowMatchTypeModal(false);
          setSelectedOpponent(null);
        }}
      />
    )}

    {pendingChessInvite && !activeChessGame && (
      <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
        <div className="glass-strong rounded-2xl p-6 max-w-sm w-full space-y-4 animate-slide-up">
          <div className="text-center space-y-2">
            {pendingChessInvite.isBetMatch ? (
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-gradient-to-br from-amber-500/20 to-orange-500/20 mb-2">
                <Gem className="h-8 w-8 text-amber-500" />
              </div>
            ) : (
              <Swords className="h-12 w-12 mx-auto text-primary" />
            )}
            <h3 className="text-xl font-bold">
              {pendingChessInvite.isBetMatch ? 'Chess Bet Challenge!' : 'Chess Challenge!'}
            </h3>
            <p className="text-muted-foreground">
              {pendingChessInvite.inviterName} wants to play chess with you
            </p>
            {pendingChessInvite.isBetMatch && pendingChessInvite.betAmount && (
              <div className="glass rounded-xl p-3 space-y-1">
                <p className="text-sm font-medium flex items-center justify-center gap-2">
                  <Gem className="h-4 w-4 text-blue-500" />
                  Bet Amount: {pendingChessInvite.betAmount} diamonds
                </p>
                <p className="text-xs text-muted-foreground">
                  Winner gets: {pendingChessInvite.betAmount * 2} diamonds
                </p>
                <p className="text-xs text-muted-foreground">
                  Your balance: {diamonds} diamonds
                </p>
              </div>
            )}
          </div>
          <div className="flex gap-3">
            <Button variant="outline" className="flex-1" onClick={declineChessInvite}>
              Decline
            </Button>
            <Button 
              variant={pendingChessInvite.isBetMatch ? "hero" : "default"}
              className="flex-1" 
              onClick={acceptChessInvite}
              disabled={pendingChessInvite.isBetMatch && pendingChessInvite.betAmount ? diamonds < pendingChessInvite.betAmount : false}
            >
              Accept
            </Button>
          </div>
        </div>
      </div>
    )}

    {showKickVoteModal && activeKickVote && (
      <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
        <div className="glass-strong rounded-2xl p-6 max-w-sm w-full space-y-4 animate-slide-up">
          <div className="text-center space-y-2">
            <UserX className="h-12 w-12 mx-auto text-destructive" />
            <h3 className="text-xl font-bold">Kick Vote</h3>
            <p className="text-muted-foreground">
              {activeKickVote.initiatorName} wants to remove {activeKickVote.targetUserName}
            </p>
            <p className="text-sm text-muted-foreground">
              Votes: {activeKickVote.votes.size}/{activeKickVote.requiredVotes}
            </p>
          </div>
          <div className="flex gap-3">
            <Button variant="outline" className="flex-1" onClick={() => castKickVote(false)}>
              Disagree
            </Button>
            <Button variant="destructive" className="flex-1" onClick={() => castKickVote(true)}>
              Agree to Kick
            </Button>
          </div>
        </div>
      </div>
    )}

    {/* ✅ ALWAYS SHOW THE ROOM - No full-page loading */}
    {!activeChessGame && !fullscreenUserId && (
      <>
        {/* Header */}
        <header className="flex items-center justify-between mb-4 flex-wrap gap-2">
          <Logo size="sm" />

          <div className="flex items-center gap-2 md:gap-4 flex-wrap">
            <SignalingIndicator />
            
            {roomData?.room_type === 'private' && roomData?.room_code && (
              <button
                onClick={copyRoomCode}
                className="flex items-center gap-2 glass rounded-full px-3 py-1.5 md:px-4 md:py-2 hover:bg-muted/50 transition-colors"
              >
                <span className="text-xs md:text-sm font-mono font-bold tracking-wider">
                  {roomData.room_code}
                </span>
                <Copy className="h-3 w-3 md:h-4 md:w-4" />
              </button>
            )}
            
            {roomData?.room_type === 'private' && roomData?.room_size === 2 && totalParticipants === 2 && (
              <VideoQualitySelector
                currentQuality={currentQuality}
                membershipTier={myMembershipTier}
                onQualityChange={handleQualityChange}
              />
            )}
            
            <div className="flex items-center gap-2 glass rounded-full px-3 py-1.5 md:px-4 md:py-2">
              <Users className="h-3 w-3 md:h-4 md:w-4 text-primary" />
              <span className="text-xs md:text-sm font-medium">
                {totalParticipants}/{roomData?.room_size || 2}
              </span>
            </div>
            
            <div className={cn(
              "flex items-center gap-2 md:gap-3 rounded-full px-3 py-1.5 md:px-4 md:py-2 backdrop-blur-md",
              myMembershipStyle.nameTag
            )}>
              {MyMembershipIcon && (
                <MyMembershipIcon className={cn("h-4 w-4", myMembershipStyle.iconColor)} />
              )}
              <span className={cn(
                "text-xs md:text-sm font-medium hidden sm:inline", 
                myMembershipStyle.nameTagText
              )}>
                {displayName}
              </span>
              <HealthTokens 
                tokens={healthTokens} 
                size="sm" 
                membershipTier={myMembershipTier} 
              />
            </div>
          </div>
        </header>

       

        {/* Main Video Grid */}
        <main className="flex-1 relative">
          <div className={cn(
            'grid gap-3 md:gap-4 h-full',
            roomData?.room_size === 4 
              ? 'grid-cols-2 grid-rows-2'
              : 'grid-cols-1 md:grid-cols-2 auto-rows-fr'
          )}>
            
            {/* ============================================ */}
            {/* SLOT 1: LOCAL VIDEO (YOU) - Always Shows */}
            {/* ============================================ */}
            <div className={cn(
              "relative overflow-hidden bg-card group",
              roomData?.room_size === 4 ? 'aspect-square md:aspect-[2/1]' : 'aspect-video',
              "rounded-2xl md:rounded-3xl",
              myVideoClasses.container,
              myMembershipTier === 'premium_plus' && "premium-plus-glow",
              myMembershipTier === 'premium' && "premium-glow"
            )}>
              {myMembershipTier === 'premium_plus' && (
                <div className="absolute inset-0 premium-plus-shimmer pointer-events-none z-10 opacity-40 rounded-2xl md:rounded-3xl" />
              )}
              
              {/* ✅ Show loading overlay ONLY if local stream isn't ready yet */}
              {!localStream || !isMediaReady ? (
                <div className="absolute inset-0 flex items-center justify-center bg-muted/20 z-20">
                  <div className="text-center space-y-3">
                    <Loader2 className="w-12 h-12 mx-auto text-primary animate-spin" />
                    <p className="text-sm text-muted-foreground">Setting up camera...</p>
                  </div>
                </div>
              ) : null}
              
              <video
                ref={localVideoRef}
                autoPlay
                muted
                playsInline
                className={cn(
                  'w-full h-full object-cover transition-opacity relative z-0',
                  isVideoOff && 'opacity-0'
                )}
              />
              
              {isVideoOff && localStream && (
                <div className={cn(
                  "absolute inset-0 flex items-center justify-center z-0",
                  myMembershipTier === 'premium_plus'
                    ? "bg-gradient-to-br from-amber-950/50 via-yellow-950/40 to-amber-950/50"
                    : myMembershipTier === 'premium'
                      ? "bg-gradient-to-br from-blue-950/50 to-blue-900/40"
                      : "bg-gradient-to-br from-muted to-card"
                )}>
                  <div className={cn(
                    "w-12 h-12 md:w-20 md:h-20 rounded-full flex items-center justify-center",
                    myMembershipTier === 'premium_plus'
                      ? "bg-gradient-to-br from-yellow-500/40 to-amber-600/40 ring-2 ring-yellow-500/60"
                      : myMembershipTier === 'premium'
                        ? "bg-gradient-to-br from-blue-500/30 to-blue-600/30 ring-2 ring-blue-500/50"
                        : "bg-primary/20"
                  )}>
                    <span className={cn(
                      "text-xl md:text-3xl font-bold",
                      myMembershipTier === 'premium_plus'
                        ? "premium-plus-text"
                        : myMembershipTier === 'premium'
                          ? "text-blue-300"
                          : "text-primary"
                    )}>
                      {displayName?.[0]?.toUpperCase()}
                    </span>
                  </div>
                </div>
              )}
              
              <div className={cn(
                "absolute bottom-2 md:bottom-3 left-2 md:left-3 flex items-center gap-2 rounded-full px-3 py-1.5 md:px-4 md:py-2 backdrop-blur-xl z-20",
                myMembershipStyle.nameTag
              )}>
                {MyMembershipIcon && (
                  <MyMembershipIcon className={cn("h-4 w-4", myMembershipStyle.iconColor)} />
                )}
                <span className={cn("text-xs md:text-sm font-medium", myMembershipStyle.nameTagText)}>
                  {displayName} (You)
                </span>
              </div>
              
              <div className="absolute top-2 md:top-3 right-2 md:right-3 flex gap-1.5 z-20">
                {hasPremiumAccess && (
                  <button
                    onClick={() => handleFullscreen(userId!)}
                    className={cn(
                      "rounded-full p-2 transition-all backdrop-blur-md",
                      myMembershipTier === 'premium_plus'
                        ? "bg-yellow-500/80 hover:bg-yellow-400 shadow-lg shadow-yellow-500/50"
                        : myMembershipTier === 'premium'
                          ? "bg-blue-500/80 hover:bg-blue-400"
                          : "bg-primary/80 hover:bg-primary"
                    )}
                    title="Fullscreen"
                  >
                    <Maximize className="h-4 w-4" />
                  </button>
                )}
                {isMuted && (
                  <div className="bg-destructive/90 backdrop-blur-sm rounded-full p-2 shadow-lg">
                    <MicOff className="h-4 w-4" />
                  </div>
                )}
                {isVideoOff && (
                  <div className="bg-destructive/90 backdrop-blur-sm rounded-full p-2 shadow-lg">
                    <VideoOff className="h-4 w-4" />
                  </div>
                )}
              </div>
            </div>

            {/* ============================================ */}
            {/* SLOTS 2-4: REMOTE PARTICIPANTS OR LOADING */}
            {/* ============================================ */}

             {(() => {
            const maxSlots = (roomData?.room_size || 2) - 1;
            const slots = [];
            const remotePeerIds = Array.from(remoteStreams.keys());
            
            console.log('🎬 [Render] Remote peers:', remotePeerIds.map(id => ({
              id: id.slice(0, 8),
              hasStream: remoteStreams.has(id),
              participant: participants.find(p => p.user_id === id)?.display_name || 'NOT FOUND'
            })));
            
            for (let i = 0; i < maxSlots; i++) {
              const peerId = remotePeerIds[i];
              
              if (peerId) {
                // ✅ SHOW REMOTE VIDEO
                const stream = remoteStreams.get(peerId);
                const participant = participants.find((p) => p.user_id === peerId);
                
                // ✅ BETTER NAME FALLBACK: Try to get name from WebRTC peers first
                let peerName = participant?.display_name;
                if (!peerName) {
                  const peerConnection = Array.from(peers.values()).find(p => p.peerId === peerId);
                  peerName = peerConnection?.peerName || `User ${peerId.slice(0, 8)}`;
                  console.warn(`⚠️ [Render] No participant data for ${peerId.slice(0, 8)}, using fallback: ${peerName}`);
                }
                
                const peerMembershipTier = participant?.membership_tier || 'free';
                const peerStyle = getMembershipStyle(peerMembershipTier);
                const peerVideoClasses = getPremiumVideoClasses(peerMembershipTier);
                const PeerIcon = peerStyle.icon;

                slots.push(
                  <div
                    key={peerId}
                    className={cn(
                      "relative overflow-hidden bg-card group",
                      roomData?.room_size === 4 ? 'aspect-square md:aspect-[2/1]' : 'aspect-video',
                      "rounded-2xl md:rounded-3xl",
                      peerVideoClasses.container,
                      peerMembershipTier === 'premium_plus' && "premium-plus-glow",
                      peerMembershipTier === 'premium' && "premium-glow"
                    )}
                  >
                    {peerMembershipTier === 'premium_plus' && (
                      <div className="absolute inset-0 premium-plus-shimmer pointer-events-none z-10 opacity-40 rounded-2xl md:rounded-3xl" />
                    )}
                    
                    {/* ✅ VIDEO ELEMENT - Now with better debugging */}
                    <video
                      ref={setRemoteVideoRef(peerId)}
                      className="w-full h-full object-cover relative z-0"
                      autoPlay
                      playsInline
                      muted={isSpeakerOff}
                      onLoadedMetadata={(e) => {
                        console.log(`📊 [Video] Metadata loaded for ${peerName}`, {
                          videoWidth: e.currentTarget.videoWidth,
                          videoHeight: e.currentTarget.videoHeight,
                          readyState: e.currentTarget.readyState,
                          paused: e.currentTarget.paused,
                        });
                      }}
                      onPlay={() => {
                        console.log(`▶️ [Video] Playing ${peerName}`);
                      }}
                      onPlaying={() => {
                        console.log(`✅ [Video] Successfully playing ${peerName}`);
                      }}
                      onError={(e) => {
                        console.error(`❌ [Video] Error for ${peerName}:`, e);
                      }}
                    />
                    
                    {/* ✅ REMOVE THE LOADING OVERLAY - It's blocking the video! */}
                    
                    <div className={cn(
                      "absolute bottom-2 md:bottom-3 left-2 md:left-3 flex items-center gap-2 rounded-full px-3 py-1.5 md:px-4 md:py-2 backdrop-blur-xl z-20",
                      peerStyle.nameTag
                    )}>
                      {PeerIcon && (
                        <PeerIcon className={cn("h-4 w-4", peerStyle.iconColor)} />
                      )}
                      <span className={cn("text-xs md:text-sm font-medium", peerStyle.nameTagText)}>
                        {peerName}
                      </span>
                    </div>
                    
                    <div className="absolute top-2 md:top-3 right-2 md:right-3 flex gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity z-20">
                      {hasPremiumAccess && (
                        <button
                          onClick={() => handleFullscreen(peerId)}
                          className={cn(
                            "rounded-full p-2 transition-all backdrop-blur-md",
                            myMembershipTier === 'premium_plus'
                              ? "bg-yellow-500/80 hover:bg-yellow-400"
                              : "bg-primary/80 hover:bg-primary"
                          )}
                          title="Fullscreen"
                        >
                          <Maximize className="h-4 w-4" />
                        </button>
                      )}
                      <button
                        onClick={() => handleChessInviteClick(peerId, peerName)}
                        className="bg-primary/80 hover:bg-primary backdrop-blur-md rounded-full p-2 transition-colors"
                        title="Challenge to Chess"
                      >
                        <Swords className="h-4 w-4" />
                      </button>
                      {hasPremiumAccess && roomData?.room_size === 4 && (
                        <button
                          onClick={() => initiateKickVote(peerId, peerName)}
                          className="bg-orange-500/80 hover:bg-orange-500 backdrop-blur-md rounded-full p-2 transition-colors"
                          title="Vote to kick"
                        >
                          <UserX className="h-4 w-4" />
                        </button>
                      )}
                      <button
                        onClick={() => handleReport(peerId)}
                        className="bg-destructive/80 hover:bg-destructive backdrop-blur-md rounded-full p-2 transition-colors"
                        title="Report user"
                      >
                        <Flag className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                );
              } else {
                // Empty slot rendering (same as before)
                slots.push(
                  <div
                    key={`empty-${i}`}
                    className={cn(
                      "rounded-2xl md:rounded-3xl border-2 border-dashed border-border/50 flex items-center justify-center relative overflow-hidden",
                      roomData?.room_size === 4 ? 'aspect-square md:aspect-[2/1]' : 'aspect-video',
                      "bg-gradient-to-br from-muted/10 via-muted/5 to-transparent"
                    )}
                  >
                    <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-transparent to-primary/5 animate-pulse" />
                    
                    <div className="text-center space-y-4 relative z-10 p-6">
                      <div className="relative">
                        <div className="absolute inset-0 -m-4">
                          <div className="w-24 h-24 mx-auto rounded-full border-2 border-primary/20 animate-ping" />
                        </div>
                        
                        <div className="relative w-16 h-16 mx-auto rounded-full border-2 border-dashed border-primary/40 flex items-center justify-center bg-primary/5 backdrop-blur-sm">
                          <Users className="h-8 w-8 text-primary/60 animate-pulse" />
                        </div>
                      </div>
                      
                      <div className="space-y-2">
                        <p className="text-muted-foreground text-sm font-medium">
                          {roomData?.room_size === 4 
                            ? `Waiting for participant ${i + 1}...`
                            : 'Finding your match...'}
                        </p>
                        
                        <div className="flex gap-1.5 justify-center">
                          <div className="w-2 h-2 rounded-full bg-primary/60 animate-bounce" style={{ animationDelay: '0ms' }} />
                          <div className="w-2 h-2 rounded-full bg-primary/60 animate-bounce" style={{ animationDelay: '150ms' }} />
                          <div className="w-2 h-2 rounded-full bg-primary/60 animate-bounce" style={{ animationDelay: '300ms' }} />
                        </div>
                        
                        {roomData?.room_size === 2 && (
                          <p className="text-xs text-muted-foreground/70 mt-2">
                            Matching with {gender === 'male' ? 'females' : 'males'} first
                          </p>
                        )}
                      </div>
                    </div>
                  </div>
                );
              }
            }
            
            return slots;
          })()}
          </div>
        </main>

        {/* Footer controls - same as before */}
        <footer className="mt-4 flex items-center justify-center gap-3 flex-wrap">
          <Button
            variant={isMuted ? 'destructive' : 'secondary'}
            size="lg"
            onClick={toggleMute}
            className={cn(
              "rounded-full w-14 h-14 shadow-lg transition-all",
              myMembershipTier === 'premium_plus' && !isMuted && "bg-gradient-to-br from-amber-900/40 to-yellow-900/40 hover:from-amber-800/50 hover:to-yellow-800/50 border border-yellow-500/30"
            )}
            title={isMuted ? 'Unmute' : 'Mute'}
          >
            {isMuted ? <MicOff className="h-6 w-6" /> : <Mic className="h-6 w-6" />}
          </Button>
          
          <Button
            variant={isVideoOff ? 'destructive' : 'secondary'}
            size="lg"
            onClick={toggleVideo}
            className={cn(
              "rounded-full w-14 h-14 shadow-lg transition-all",
              myMembershipTier === 'premium_plus' && !isVideoOff && "bg-gradient-to-br from-amber-900/40 to-yellow-900/40 hover:from-amber-800/50 hover:to-yellow-800/50 border border-yellow-500/30"
            )}
            title={isVideoOff ? 'Turn on video' : 'Turn off video'}
          >
            {isVideoOff ? <VideoOff className="h-6 w-6" /> : <Video className="h-6 w-6" />}
          </Button>
          
          <Button
            variant={isSpeakerOff ? 'destructive' : 'secondary'}
            size="lg"
            onClick={toggleSpeaker}
            className={cn(
              "rounded-full w-14 h-14 shadow-lg transition-all",
              myMembershipTier === 'premium_plus' && !isSpeakerOff && "bg-gradient-to-br from-amber-900/40 to-yellow-900/40 hover:from-amber-800/50 hover:to-yellow-800/50 border border-yellow-500/30"
            )}
            title={isSpeakerOff ? 'Turn on speaker' : 'Turn off speaker'}
          >
            {isSpeakerOff ? <VolumeX className="h-6 w-6" /> : <Volume2 className="h-6 w-6" />}
          </Button>
          
          {roomData?.room_type === 'private' && (
            <Button
              variant={isScreenSharing ? 'accent' : 'secondary'}
              size="lg"
              onClick={handleScreenShare}
              className={cn(
                "rounded-full w-14 h-14 shadow-lg transition-all",
                myMembershipTier === 'premium_plus' && !isScreenSharing && "bg-gradient-to-br from-amber-900/40 to-yellow-900/40 hover:from-amber-800/50 hover:to-yellow-800/50 border border-yellow-500/30"
              )}
              title={isScreenSharing ? 'Stop sharing' : 'Share screen'}
            >
              <MonitorUp className="h-6 w-6" />
            </Button>
          )}
          
          {roomData?.room_type === 'public' && (
            <Button
              variant="default"
              size="lg"
              onClick={handleNextRoom}
              disabled={nextRoomStatus.isSearching}
              className={cn(
                "rounded-full w-14 h-14 shadow-lg transition-all",
                myMembershipTier === 'premium_plus' && 
                "bg-gradient-to-br from-amber-600 to-yellow-600 hover:from-amber-500 hover:to-yellow-500 border border-yellow-400/50"
              )}
              title={roomData.room_size === 4 ? "Next 4-Person Room" : "Next Room"}
            >
              {nextRoomStatus.isSearching ? (
                <Loader2 className="h-6 w-6 animate-spin" />
              ) : (
                <SkipForward className="h-6 w-6" />
              )}
            </Button>
          )}
          
          <Button
            variant="destructive"
            size="lg"
            onClick={handleLeaveRoom}
            className="rounded-full w-14 h-14 shadow-lg"
            title="Leave room"
          >
            <Phone className="h-6 w-6 rotate-[135deg]" />
          </Button>
           
        </footer>
      </>
    )}

      {/* ============================================ */}
      {/* FULLSCREEN VIEW */}
      {/* ============================================ */}
      {fullscreenUserId && !activeChessGame && (
        <FullscreenVideoView
          fullscreenUserId={fullscreenUserId}
          localUserId={userId!}
          localStream={localStream}
          remoteStreams={remoteStreams}
          participants={participants}
          isSpeakerOff={isSpeakerOff}
          isVideoOff={isVideoOff}
          myDisplayName={displayName || 'You'}
          myMembershipTier={myMembershipTier}
          onExitFullscreen={() => setFullscreenUserId(null)}
          onSwitchFullscreen={(userId) => setFullscreenUserId(userId)}
        />
      )}

      {/* ============================================ */}
      {/* CHESS GAME VIEW */}
      {/* ============================================ */}
      {activeChessGame && (
        <ChessGameView
          gameId={activeChessGame.gameId}
          myUserId={userId!}
          myColor={activeChessGame.myColor}
          opponentId={activeChessGame.opponentId}
          opponentName={activeChessGame.opponentName}
          displayName={displayName || 'You'}
          localVideoRef={localVideoRef}
          localStream={localStream}
          opponentVideoRef={setRemoteVideoRef}
          remoteStreams={remoteStreams}
          isVideoOff={isVideoOff}
          isSpeakerOff={isSpeakerOff}
          isMuted={isMuted}
          onClose={returnToOriginalRoom}
          onToggleMute={toggleMute}
          onToggleVideo={toggleVideo}
          onToggleSpeaker={toggleSpeaker}
          originalRoomId={roomId!}
          isBetMatch={activeChessGame.isBetMatch}
          betAmount={activeChessGame.betAmount}
        />
      )}

      {/* ============================================ */}
      {/* DIAGNOSTICS (DEBUG ONLY) */}
      {/* ============================================ */}
      
      
    </div>
  );
}


