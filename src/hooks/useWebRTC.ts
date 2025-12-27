// src/hooks/useWebRTC.ts - FIXED: Chess room video + Return to room video
// ✅ Works in both private and public chess rooms
// ✅ Re-establishes video when returning from chess

import { useState, useEffect, useRef, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

interface PeerConnection {
  peerId: string;
  peerName: string;
  connection: RTCPeerConnection;
  stream?: MediaStream;
}

interface UseWebRTCProps {
  roomId: string;
  userId: string;
  displayName: string;
  localStream: MediaStream | null;
}

export type VideoQuality = 'sd' | 'hd' | 'fullhd';

const QUALITY_CONSTRAINTS = {
  sd: {
    width: { ideal: 640, max: 640 },
    height: { ideal: 480, max: 480 },
    frameRate: { ideal: 24, max: 24 },
  },
  hd: {
    width: { ideal: 1280, max: 1280 },
    height: { ideal: 720, max: 720 },
    frameRate: { ideal: 30, max: 30 },
  },
  fullhd: {
    width: { ideal: 1920, max: 1920 },
    height: { ideal: 1080, max: 1080 },
    frameRate: { ideal: 30, max: 30 },
  },
};

const ICE_SERVERS: RTCConfiguration = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' },
    { urls: 'stun:stun3.l.google.com:19302' },
  ],
};

export function useWebRTC({ roomId, userId, displayName, localStream }: UseWebRTCProps) {
  const [peers, setPeers] = useState<Map<string, PeerConnection>>(new Map());
  const [remoteStreams, setRemoteStreams] = useState<Map<string, MediaStream>>(new Map());
  const [currentQuality, setCurrentQuality] = useState<VideoQuality>('sd');
  
  const peerConnectionsRef = useRef<Map<string, RTCPeerConnection>>(new Map());
  const localStreamRef = useRef(localStream);
  const displayNameRef = useRef(displayName);
  const isInitializedRef = useRef(false);
  const initiatedConnectionsRef = useRef<Set<string>>(new Set());
  const currentRoomIdRef = useRef(roomId);
  
  // Auto-recovery tracking
  const connectionTimeoutsRef = useRef<Map<string, NodeJS.Timeout>>(new Map());
  const streamCheckIntervalsRef = useRef<Map<string, NodeJS.Timeout>>(new Map());
  const connectionAttemptsRef = useRef<Map<string, number>>(new Map());
  const lastStreamCheckRef = useRef<Map<string, number>>(new Map());
  
  useEffect(() => {
    localStreamRef.current = localStream;
  }, [localStream]);
  
  useEffect(() => {
    displayNameRef.current = displayName;
  }, [displayName]);

  // ✅ NEW: Detect room change and reset connections
  useEffect(() => {
    const prevRoomId = currentRoomIdRef.current;
    
    if (prevRoomId !== roomId && isInitializedRef.current) {
      console.log(`🔄 [WebRTC] Room changed from ${prevRoomId.slice(0, 8)} to ${roomId.slice(0, 8)}`);
      console.log(`🧹 [WebRTC] Cleaning up old connections and reinitializing...`);
      
      // Clear all existing connections
      connectionTimeoutsRef.current.forEach(timeout => clearTimeout(timeout));
      connectionTimeoutsRef.current.clear();
      
      streamCheckIntervalsRef.current.forEach(interval => clearInterval(interval));
      streamCheckIntervalsRef.current.clear();
      
      connectionAttemptsRef.current.clear();
      lastStreamCheckRef.current.clear();
      initiatedConnectionsRef.current.clear();
      
      // Close all peer connections
      peerConnectionsRef.current.forEach((pc) => {
        pc.close();
      });
      peerConnectionsRef.current.clear();
      
      // Clear state
      setPeers(new Map());
      setRemoteStreams(new Map());
      
      // Reset initialization flag to allow re-init
      isInitializedRef.current = false;
      
      console.log(`✅ [WebRTC] Cleanup complete, ready to reinitialize`);
    }
    
    currentRoomIdRef.current = roomId;
  }, [roomId]);

  const handlePeerDisconnect = useCallback((peerId: string) => {
    console.log(`❌ [WebRTC] Peer ${peerId.slice(0, 8)} disconnected`);
    
    const timeout = connectionTimeoutsRef.current.get(peerId);
    if (timeout) {
      clearTimeout(timeout);
      connectionTimeoutsRef.current.delete(peerId);
    }
    
    const interval = streamCheckIntervalsRef.current.get(peerId);
    if (interval) {
      clearInterval(interval);
      streamCheckIntervalsRef.current.delete(peerId);
    }
    
    connectionAttemptsRef.current.delete(peerId);
    lastStreamCheckRef.current.delete(peerId);
    
    const pc = peerConnectionsRef.current.get(peerId);
    if (pc) {
      pc.close();
      peerConnectionsRef.current.delete(peerId);
    }
    
    initiatedConnectionsRef.current.delete(peerId);
    
    setPeers((prev) => {
      const newPeers = new Map(prev);
      newPeers.delete(peerId);
      return newPeers;
    });
    setRemoteStreams((prev) => {
      const newStreams = new Map(prev);
      newStreams.delete(peerId);
      return newStreams;
    });
  }, []);

  const attemptReconnection = useCallback((peerId: string, peerName: string) => {
    const attempts = connectionAttemptsRef.current.get(peerId) || 0;
    
    if (attempts >= 3) {
      console.error(`❌ [WebRTC] Max reconnection attempts reached for ${peerName}`);
      return;
    }
    
    console.log(`🔄 [WebRTC] Reconnection attempt ${attempts + 1}/3 for ${peerName}`);
    connectionAttemptsRef.current.set(peerId, attempts + 1);
    
    const oldPc = peerConnectionsRef.current.get(peerId);
    if (oldPc) {
      oldPc.close();
      peerConnectionsRef.current.delete(peerId);
    }
    
    initiatedConnectionsRef.current.delete(peerId);
    
    setTimeout(() => {
      console.log(`🔄 [WebRTC] Creating new connection for ${peerName}`);
      const newPc = createPeerConnection(peerId, peerName, true);
      setPeers((prev) => {
        const newPeers = new Map(prev);
        newPeers.set(peerId, { peerId, peerName, connection: newPc });
        return newPeers;
      });
    }, 1000);
  }, []);

  const createPeerConnection = useCallback(
    (peerId: string, peerName: string, shouldInitiate: boolean): RTCPeerConnection => {
      console.log(`🔵 [WebRTC] Creating connection for ${peerName} (${peerId.slice(0, 8)}) - ${shouldInitiate ? 'INITIATOR' : 'RECEIVER'}`);
      
      const existingPc = peerConnectionsRef.current.get(peerId);
      if (existingPc && existingPc.connectionState !== 'closed' && existingPc.connectionState !== 'failed') {
        console.log(`♻️ [WebRTC] Reusing existing connection`);
        return existingPc;
      }
      
      const pc = new RTCPeerConnection(ICE_SERVERS);

      if (localStreamRef.current) {
        console.log(`📹 [WebRTC] Adding local tracks`);
        localStreamRef.current.getTracks().forEach(track => {
          console.log(`  ➕ Adding ${track.kind} track`);
          pc.addTrack(track, localStreamRef.current!);
        });
      }

      pc.ontrack = (event) => {
        console.log(`🎥🎥🎥 [WebRTC] ✅✅✅ Track received from ${peerName}`, {
          kind: event.track.kind,
          streams: event.streams?.length
        });

        if (event.streams && event.streams[0]) {
          const remoteStream = event.streams[0];
          console.log(`📺 [WebRTC] Setting remote stream`);
          
          setRemoteStreams((prev) => {
            const newStreams = new Map(prev);
            newStreams.set(peerId, remoteStream);
            console.log(`✅ [WebRTC] Remote stream set. Total: ${newStreams.size}`);
            return newStreams;
          });
          
          const timeout = connectionTimeoutsRef.current.get(peerId);
          if (timeout) {
            clearTimeout(timeout);
            connectionTimeoutsRef.current.delete(peerId);
          }
          
          connectionAttemptsRef.current.set(peerId, 0);
          startStreamHealthCheck(peerId, remoteStream, peerName);
        }
      };

      pc.onicecandidate = async (event) => {
        if (event.candidate) {
          console.log(`🧊 [WebRTC] Sending ICE candidate to ${peerName}`);
          try {
            await supabase.from('signaling').insert({
              room_id: roomId,
              sender_id: userId,
              target_id: peerId,
              message_type: 'ice-candidate',
              payload: { candidate: event.candidate.toJSON() }
            });
          } catch (error) {
            console.error('❌ Error sending ICE:', error);
          }
        }
      };

      pc.oniceconnectionstatechange = () => {
        const state = pc.iceConnectionState;
        console.log(`🔗 [WebRTC] ICE state for ${peerName}: ${state}`);
        
        if (state === 'connected' || state === 'completed') {
          console.log(`✅ [WebRTC] Connection established with ${peerName}`);
          const timeout = connectionTimeoutsRef.current.get(peerId);
          if (timeout) {
            clearTimeout(timeout);
            connectionTimeoutsRef.current.delete(peerId);
          }
          connectionAttemptsRef.current.set(peerId, 0);
        } else if (state === 'failed') {
          console.warn(`⚠️ [WebRTC] Connection failed with ${peerName}, attempting recovery...`);
          setTimeout(() => attemptReconnection(peerId, peerName), 2000);
        } else if (state === 'disconnected') {
          console.warn(`⚠️ [WebRTC] Connection disconnected with ${peerName}, waiting...`);
          setTimeout(() => {
            if (pc.iceConnectionState === 'disconnected') {
              console.log(`🔄 [WebRTC] Still disconnected, attempting recovery...`);
              attemptReconnection(peerId, peerName);
            }
          }, 5000);
        }
      };

      pc.onconnectionstatechange = () => {
        console.log(`🔌 [WebRTC] Connection state for ${peerName}: ${pc.connectionState}`);
        if (pc.connectionState === 'failed') {
          attemptReconnection(peerId, peerName);
        }
      };

      peerConnectionsRef.current.set(peerId, pc);

      if (shouldInitiate && !initiatedConnectionsRef.current.has(peerId)) {
        initiatedConnectionsRef.current.add(peerId);
        console.log(`📤 [WebRTC] Creating offer`);
        
        const timeout = setTimeout(() => {
          console.warn(`⏰ [WebRTC] Connection timeout for ${peerName}, no stream received`);
          attemptReconnection(peerId, peerName);
        }, 15000);
        
        connectionTimeoutsRef.current.set(peerId, timeout);
        
        setTimeout(async () => {
          try {
            const offer = await pc.createOffer();
            await pc.setLocalDescription(offer);
            
            console.log(`📤 [WebRTC] Sending offer`);
            await supabase.from('signaling').insert({
              room_id: roomId,
              sender_id: userId,
              target_id: peerId,
              message_type: 'offer',
              payload: { sdp: offer }
            });
          } catch (error) {
            console.error(`❌ Error creating offer:`, error);
            attemptReconnection(peerId, peerName);
          }
        }, 500);
      }

      return pc;
    },
    [roomId, userId, handlePeerDisconnect, attemptReconnection]
  );

  const startStreamHealthCheck = useCallback((peerId: string, stream: MediaStream, peerName: string) => {
    const existingInterval = streamCheckIntervalsRef.current.get(peerId);
    if (existingInterval) {
      clearInterval(existingInterval);
    }
    
    console.log(`💊 [WebRTC] Starting health check for ${peerName}`);
    
    const interval = setInterval(() => {
      const videoTrack = stream.getVideoTracks()[0];
      
      if (!videoTrack || videoTrack.readyState === 'ended') {
        console.warn(`⚠️ [WebRTC] Video track ended for ${peerName}, attempting recovery...`);
        clearInterval(interval);
        streamCheckIntervalsRef.current.delete(peerId);
        attemptReconnection(peerId, peerName);
        return;
      }
      
      const videoElements = document.querySelectorAll('video');
      let foundVideo = false;
      videoElements.forEach(video => {
        const videoStream = video.srcObject as MediaStream | null;
        if (videoStream === stream && !video.paused) {
          foundVideo = true;
        }
      });
      
      const now = Date.now();
      const lastCheck = lastStreamCheckRef.current.get(peerId) || now;
      
      if (!foundVideo && now - lastCheck > 10000) {
        console.warn(`⚠️ [WebRTC] Video not playing for ${peerName} for 10s, attempting recovery...`);
        clearInterval(interval);
        streamCheckIntervalsRef.current.delete(peerId);
        attemptReconnection(peerId, peerName);
        return;
      }
      
      lastStreamCheckRef.current.set(peerId, now);
    }, 5000);
    
    streamCheckIntervalsRef.current.set(peerId, interval);
  }, [attemptReconnection]);

  const handleOffer = useCallback(
    async (senderId: string, senderName: string, sdp: RTCSessionDescriptionInit) => {
      console.log(`📥 [WebRTC] Received offer from ${senderName}`);
      
      let pc = peerConnectionsRef.current.get(senderId);
      
      if (!pc || pc.connectionState === 'closed' || pc.connectionState === 'failed') {
        pc = createPeerConnection(senderId, senderName, false);
      }

      try {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp));
        
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        console.log(`📤 [WebRTC] Sending answer`);
        await supabase.from('signaling').insert({
          room_id: roomId,
          sender_id: userId,
          target_id: senderId,
          message_type: 'answer',
          payload: { sdp: answer }
        });

        setPeers((prev) => {
          const newPeers = new Map(prev);
          newPeers.set(senderId, { peerId: senderId, peerName: senderName, connection: pc! });
          return newPeers;
        });
      } catch (error) {
        console.error('❌ Error handling offer:', error);
        attemptReconnection(senderId, senderName);
      }
    },
    [createPeerConnection, roomId, userId, attemptReconnection]
  );

  const handleAnswer = useCallback(
    async (senderId: string, sdp: RTCSessionDescriptionInit) => {
      console.log(`📥 [WebRTC] Received answer`);
      const pc = peerConnectionsRef.current.get(senderId);
      
      if (!pc) {
        console.warn(`⚠️ No peer connection for answer`);
        return;
      }

      try {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp));
      } catch (error) {
        console.error('❌ Error handling answer:', error);
      }
    },
    []
  );

  const handleIceCandidate = useCallback(
    async (senderId: string, candidate: RTCIceCandidateInit) => {
      const pc = peerConnectionsRef.current.get(senderId);
      
      if (!pc) {
        console.warn(`⚠️ No peer connection for ICE`);
        return;
      }

      try {
        await pc.addIceCandidate(new RTCIceCandidate(candidate));
      } catch (error) {
        console.warn(`⚠️ Error adding ICE:`, error);
      }
    },
    []
  );

  const checkExistingParticipants = useCallback(async () => {
    try {
      const { data: participants, error } = await supabase
        .from('room_participants')
        .select(`user_id, users!inner(display_name)`)
        .eq('room_id', roomId)
        .is('left_at', null)
        .neq('user_id', userId);

      if (error || !participants || participants.length === 0) {
        console.log('👥 [WebRTC] No existing participants');
        return;
      }

      console.log(`👥 [WebRTC] Found ${participants.length} existing participants`);

      for (const p of participants) {
        const peerId = p.user_id;
        const userData = Array.isArray(p.users) ? p.users[0] : p.users;
        const peerName = userData?.display_name || 'Unknown';
        
        console.log(`🔗 [WebRTC] Creating connection to ${peerName}`);
        const pc = createPeerConnection(peerId, peerName, true);
        
        setPeers((prev) => {
          const newPeers = new Map(prev);
          newPeers.set(peerId, { peerId, peerName, connection: pc });
          return newPeers;
        });
        
        await new Promise(resolve => setTimeout(resolve, 300));
      }
    } catch (error) {
      console.error('❌ Error checking participants:', error);
    }
  }, [roomId, userId, createPeerConnection]);

  const announceJoin = useCallback(async () => {
    console.log('📢 [WebRTC] Announcing join');
    
    try {
      await supabase.from('signaling').insert({
        room_id: roomId,
        sender_id: userId,
        message_type: 'join',
        payload: { displayName: displayNameRef.current }
      });
    } catch (error) {
      console.error('❌ Error announcing join:', error);
    }
  }, [roomId, userId]);

  const announceLeave = useCallback(async () => {
    connectionTimeoutsRef.current.forEach(timeout => clearTimeout(timeout));
    connectionTimeoutsRef.current.clear();
    
    streamCheckIntervalsRef.current.forEach(interval => clearInterval(interval));
    streamCheckIntervalsRef.current.clear();
    
    try {
      await supabase.from('signaling').insert({
        room_id: roomId,
        sender_id: userId,
        message_type: 'leave',
        payload: { displayName: displayNameRef.current }
      });
    } catch (error) {
      console.error('❌ Error announcing leave:', error);
    }
  }, [roomId, userId]);

  // Main initialization
  useEffect(() => {
    if (!roomId || !userId || !localStream) {
      console.log('⏳ [WebRTC] Waiting...');
      return;
    }
    
    if (isInitializedRef.current) return;
    isInitializedRef.current = true;

    console.log('🚀🚀🚀 [WebRTC] Initializing with auto-recovery...');

    const channel = supabase
      .channel(`signaling-${userId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'signaling',
          filter: `room_id=eq.${roomId}`,
        },
        async (payload) => {
          const signal = payload.new as any;
          
          if (signal.sender_id === userId) return;

          console.log(`📨 [WebRTC] Signal: ${signal.message_type} from ${signal.sender_id.slice(0, 8)}`);

          switch (signal.message_type) {
            case 'join':
              console.log(`👋 [WebRTC] New peer: ${signal.payload.displayName}`);
              break;

            case 'offer':
              await handleOffer(signal.sender_id, signal.payload.displayName || 'Unknown', signal.payload.sdp);
              break;

            case 'answer':
              if (signal.target_id === userId) {
                await handleAnswer(signal.sender_id, signal.payload.sdp);
              }
              break;

            case 'ice-candidate':
              if (signal.target_id === userId) {
                await handleIceCandidate(signal.sender_id, signal.payload.candidate);
              }
              break;

            case 'leave':
              handlePeerDisconnect(signal.sender_id);
              break;
          }
        }
      )
      .subscribe();

    const initialize = async () => {
      await checkExistingParticipants();
      await new Promise(resolve => setTimeout(resolve, 500));
      await announceJoin();
      console.log('✅ Initialization complete with auto-recovery enabled');
    };

    setTimeout(initialize, 300);

    return () => {
      console.log('🧹 Cleaning up...');
      isInitializedRef.current = false;
      
      connectionTimeoutsRef.current.forEach(timeout => clearTimeout(timeout));
      connectionTimeoutsRef.current.clear();
      
      streamCheckIntervalsRef.current.forEach(interval => clearInterval(interval));
      streamCheckIntervalsRef.current.clear();
      
      announceLeave();
      peerConnectionsRef.current.forEach((pc) => pc.close());
      peerConnectionsRef.current.clear();
      supabase.removeChannel(channel);
    };
  }, [roomId, userId, localStream, checkExistingParticipants, announceJoin, announceLeave, handleOffer, handleAnswer, handleIceCandidate, handlePeerDisconnect]);

  const changeVideoQuality = useCallback(async (quality: VideoQuality) => {
    if (!localStreamRef.current) return false;

    try {
      const videoTrack = localStreamRef.current.getVideoTracks()[0];
      if (!videoTrack) return false;

      await videoTrack.applyConstraints(QUALITY_CONSTRAINTS[quality]);
      setCurrentQuality(quality);
      return true;
    } catch (error) {
      console.error('❌ Error changing quality:', error);
      return false;
    }
  }, []);

  const replaceVideoTrack = useCallback(async (newTrack: MediaStreamTrack) => {
    peerConnectionsRef.current.forEach((pc) => {
      const senders = pc.getSenders();
      const videoSender = senders.find(s => s.track?.kind === 'video');
      if (videoSender) {
        videoSender.replaceTrack(newTrack).catch(console.error);
      }
    });
  }, []);

  return {
    peers,
    remoteStreams,
    currentQuality,
    announceLeave,
    replaceVideoTrack,
    changeVideoQuality,
    peerConnectionsRef,
  };
}