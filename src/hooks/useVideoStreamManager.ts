// src/hooks/useVideoStreamManager.ts - WITH AUTO-RECOVERY
// ✅ Adds automatic recovery for remote streams when returning from chess

import { useEffect, useRef, useCallback } from 'react';

interface VideoStreamManagerProps {
  stream: MediaStream | null;
  isEnabled: boolean;
  isMuted?: boolean;
  shouldAttach: boolean;
  debugLabel?: string;
}

// LOCAL VIDEO MANAGER
export function useVideoStreamManager({
  stream,
  isEnabled,
  isMuted = false,
  shouldAttach,
  debugLabel = 'video',
}: VideoStreamManagerProps) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const attachedStreamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    const videoElement = videoRef.current;
    if (!videoElement || !stream || !shouldAttach || !isEnabled) {
      return;
    }
    
    if (attachedStreamRef.current === stream && videoElement.srcObject === stream) {
      return;
    }
    
    console.log(`🎥 [${debugLabel}] Attaching stream`);
    
    videoElement.srcObject = stream;
    videoElement.muted = isMuted;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    attachedStreamRef.current = stream;
    
    videoElement.play().catch(() => {
      setTimeout(() => videoElement.play().catch(console.error), 500);
    });
  }, [stream, isEnabled, shouldAttach, isMuted, debugLabel]);

  return { videoRef };
}

// ✅ ENHANCED: REMOTE VIDEO MANAGER WITH AUTO-RECOVERY
export function useRemoteVideoManager(
  remoteStreams: Map<string, MediaStream>,
  shouldAttach: boolean,
  isMuted: boolean
) {
  const videoRefsMap = useRef<Map<string, HTMLVideoElement>>(new Map());
  const attachedStreamsRef = useRef<Map<string, MediaStream>>(new Map());
  const healthCheckIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // ✅ Simple ref setter - stable callback
  const setVideoRef = useCallback((peerId: string) => {
    return (el: HTMLVideoElement | null) => {
      if (el) {
        console.log(`🔌 [Remote ${peerId.slice(0, 8)}] Video ref set`);
        videoRefsMap.current.set(peerId, el);
        
        // ✅ IMMEDIATELY attach stream if available
        const stream = remoteStreams.get(peerId);
        if (stream && shouldAttach) {
          console.log(`⚡ [Remote ${peerId.slice(0, 8)}] Attaching immediately`);
          attachStreamToElement(el, stream, peerId);
        }
      } else {
        videoRefsMap.current.delete(peerId);
        attachedStreamsRef.current.delete(peerId);
      }
    };
  }, [remoteStreams, shouldAttach]);

  // ✅ SIMPLIFIED: Attach stream like VideoChat.tsx
  const attachStreamToElement = useCallback((
    el: HTMLVideoElement, 
    stream: MediaStream, 
    peerId: string
  ) => {
    if (attachedStreamsRef.current.get(peerId) === stream && el.srcObject === stream) {
      return;
    }
    
    console.log(`🎥🎥🎥 [Remote ${peerId.slice(0, 8)}] ATTACHING STREAM`);
    
    // ✅ Like VideoChat.tsx
    el.srcObject = stream;
    el.muted = isMuted;
    el.playsInline = true;
    el.autoplay = true;
    el.setAttribute('playsinline', '');
    el.setAttribute('webkit-playsinline', '');
    
    attachedStreamsRef.current.set(peerId, stream);
    
    // ✅ Simple play
    el.play().catch(() => {
      console.warn(`⚠️ [Remote ${peerId.slice(0, 8)}] Play blocked, retrying...`);
      setTimeout(() => el.play().catch(console.error), 500);
    });
  }, [isMuted]);

  // ✅ Process streams when they change
  useEffect(() => {
    if (!shouldAttach) return;

    remoteStreams.forEach((stream, peerId) => {
      const el = videoRefsMap.current.get(peerId);
      if (el) {
        attachStreamToElement(el, stream, peerId);
      }
    });
  }, [remoteStreams, shouldAttach, attachStreamToElement]);

  // ✅ NEW: AUTO-RECOVERY - Check and fix detached videos every 3 seconds
  useEffect(() => {
    if (!shouldAttach) {
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
        healthCheckIntervalRef.current = null;
      }
      return;
    }

    console.log('🏥 [Remote Video] Starting auto-recovery health checks...');

    const checkAndRecover = () => {
      videoRefsMap.current.forEach((el, peerId) => {
        const stream = remoteStreams.get(peerId);
        
        if (!stream) return;

        const isAttached = el.srcObject === stream;
        const isPlaying = !el.paused && el.readyState >= 2;
        const videoTrack = stream.getVideoTracks()[0];
        const isTrackLive = videoTrack && videoTrack.readyState === 'live';

        // ✅ If track is live but video is not playing, re-attach
        if (isTrackLive && (!isAttached || !isPlaying)) {
          console.log(`🔄 [Remote ${peerId.slice(0, 8)}] Auto-recovering video...`);
          attachStreamToElement(el, stream, peerId);
        }
      });
    };

    // Run check immediately
    setTimeout(checkAndRecover, 1000);

    // Then every 3 seconds
    healthCheckIntervalRef.current = setInterval(checkAndRecover, 3000);

    return () => {
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
        healthCheckIntervalRef.current = null;
      }
    };
  }, [shouldAttach, remoteStreams, attachStreamToElement]);

  return { setVideoRef };
}

// FULLSCREEN VIDEO MANAGER
export function useFullscreenVideoManager(
  fullscreenUserId: string | null,
  localUserId: string,
  localStream: MediaStream | null,
  remoteStreams: Map<string, MediaStream>,
  isSpeakerOff: boolean
) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const attachedStreamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    if (!fullscreenUserId || !videoRef.current) return;

    const videoElement = videoRef.current;
    const isLocalUser = fullscreenUserId === localUserId;
    const streamToAttach = isLocalUser ? localStream : remoteStreams.get(fullscreenUserId);

    if (!streamToAttach) return;
    if (attachedStreamRef.current === streamToAttach) return;

    videoElement.srcObject = streamToAttach;
    videoElement.muted = isLocalUser || isSpeakerOff;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    attachedStreamRef.current = streamToAttach;
    
    videoElement.play().catch(() => {
      setTimeout(() => videoElement.play().catch(console.error), 300);
    });
  }, [fullscreenUserId, localUserId, localStream, remoteStreams, isSpeakerOff]);

  return { videoRef };
}

// THUMBNAIL VIDEO MANAGER
export function useThumbnailVideoManager(
  userId: string,
  isLocal: boolean,
  localStream: MediaStream | null,
  remoteStreams: Map<string, MediaStream>
) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const attachedStreamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    if (!videoRef.current) return;

    const stream = isLocal ? localStream : remoteStreams.get(userId);
    if (!stream) return;

    const videoElement = videoRef.current;
    if (attachedStreamRef.current === stream) return;

    videoElement.srcObject = stream;
    videoElement.muted = true;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    attachedStreamRef.current = stream;
    
    videoElement.play().catch(() => {
      setTimeout(() => videoElement.play().catch(console.error), 200);
    });
  }, [userId, isLocal, localStream, remoteStreams]);

  return { videoRef };
}