// src/hooks/useVideoStreamManager.ts - FIXED: Simple, reliable like VideoChat.tsx
// ✅ Removes auto-recovery that causes detachment
// ✅ Direct srcObject assignment like VideoChat.tsx

import { useEffect, useRef, useCallback } from 'react';

interface VideoStreamManagerProps {
  stream: MediaStream | null;
  isEnabled: boolean;
  isMuted?: boolean;
  shouldAttach: boolean;
  debugLabel?: string;
}

// ============================================
// LOCAL VIDEO MANAGER (for your own video)
// ============================================
export function useVideoStreamManager({
  stream,
  isEnabled,
  isMuted = false,
  shouldAttach,
  debugLabel = 'video',
}: VideoStreamManagerProps) {
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    const videoElement = videoRef.current;
    if (!videoElement || !stream || !shouldAttach || !isEnabled) {
      return;
    }
    
    console.log(`🎥 [${debugLabel}] Attaching local stream`);
    
    // ✅ SIMPLE: Direct assignment like VideoChat.tsx
    videoElement.srcObject = stream;
    videoElement.muted = isMuted;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    videoElement.play().catch((err) => {
      console.warn(`⚠️ [${debugLabel}] Play failed, retrying...`, err);
      setTimeout(() => videoElement.play().catch(console.error), 500);
    });

    return () => {
      console.log(`🧹 [${debugLabel}] Cleaning up`);
      // Don't stop tracks, just clear srcObject
      if (videoElement.srcObject === stream) {
        videoElement.srcObject = null;
      }
    };
  }, [stream, isEnabled, shouldAttach, isMuted, debugLabel]);

  return { videoRef };
}

// ============================================
// REMOTE VIDEO MANAGER (for other people's videos)
// ✅ FIXED: Removed auto-recovery, using VideoChat.tsx approach
// ============================================
export function useRemoteVideoManager(
  remoteStreams: Map<string, MediaStream>,
  shouldAttach: boolean,
  isMuted: boolean
) {
  const videoRefsMap = useRef<Map<string, HTMLVideoElement>>(new Map());

  // ✅ Simple stable callback
  const setVideoRef = useCallback((peerId: string) => {
    return (el: HTMLVideoElement | null) => {
      if (el) {
        console.log(`🔌 [Remote ${peerId.slice(0, 8)}] Video ref set`);
        videoRefsMap.current.set(peerId, el);
        
        // ✅ IMMEDIATELY attach if stream exists (like VideoChat.tsx)
        const stream = remoteStreams.get(peerId);
        if (stream && shouldAttach) {
          console.log(`⚡ [Remote ${peerId.slice(0, 8)}] Attaching stream immediately`);
          
          // ✅ DIRECT assignment like VideoChat.tsx
          el.srcObject = stream;
          el.muted = isMuted;
          el.playsInline = true;
          el.autoplay = true;
          el.setAttribute('playsinline', '');
          el.setAttribute('webkit-playsinline', '');
          
          // ✅ Simple play
          el.play().catch(() => {
            console.warn(`⚠️ [Remote ${peerId.slice(0, 8)}] Play blocked, retrying...`);
            setTimeout(() => el.play().catch(console.error), 500);
          });
        }
      } else {
        const existing = videoRefsMap.current.get(peerId);
        if (existing) {
          console.log(`🔌 [Remote ${peerId.slice(0, 8)}] Clearing video ref`);
          // Clean up
          if (existing.srcObject) {
            existing.srcObject = null;
          }
          videoRefsMap.current.delete(peerId);
        }
      }
    };
  }, [remoteStreams, shouldAttach, isMuted]);

  // ✅ SIMPLE: Process streams when they change (like VideoChat.tsx)
  useEffect(() => {
    if (!shouldAttach) return;

    console.log(`🔄 [Remote Video] Processing ${remoteStreams.size} streams`);

    remoteStreams.forEach((stream, peerId) => {
      const el = videoRefsMap.current.get(peerId);
      if (!el) {
        console.log(`⚠️ [Remote ${peerId.slice(0, 8)}] No video element yet`);
        return;
      }

      // ✅ Check if already attached
      if (el.srcObject === stream) {
        // Already attached, just ensure it's playing
        if (el.paused) {
          console.log(`▶️ [Remote ${peerId.slice(0, 8)}] Resuming playback`);
          el.play().catch(console.error);
        }
        return;
      }

      // ✅ Attach stream (like VideoChat.tsx)
      console.log(`🎥🎥🎥 [Remote ${peerId.slice(0, 8)}] ATTACHING STREAM`);
      
      el.srcObject = stream;
      el.muted = isMuted;
      el.playsInline = true;
      el.autoplay = true;
      el.setAttribute('playsinline', '');
      el.setAttribute('webkit-playsinline', '');
      
      el.play().catch(() => {
        console.warn(`⚠️ [Remote ${peerId.slice(0, 8)}] Play blocked, retrying...`);
        setTimeout(() => el.play().catch(console.error), 500);
      });
    });
  }, [remoteStreams, shouldAttach, isMuted]);

  // ✅ Handle mute changes
  useEffect(() => {
    videoRefsMap.current.forEach((el, peerId) => {
      if (el.muted !== isMuted) {
        console.log(`🔊 [Remote ${peerId.slice(0, 8)}] Mute: ${isMuted}`);
        el.muted = isMuted;
      }
    });
  }, [isMuted]);

  // ✅ Cleanup on unmount
  useEffect(() => {
    return () => {
      console.log('🧹 [Remote Video] Cleaning up all videos');
      videoRefsMap.current.forEach((el, peerId) => {
        if (el.srcObject) {
          console.log(`🧹 [Remote ${peerId.slice(0, 8)}] Clearing srcObject`);
          el.srcObject = null;
        }
      });
      videoRefsMap.current.clear();
    };
  }, []);

  return { setVideoRef };
}

// ============================================
// FULLSCREEN VIDEO MANAGER
// ============================================
export function useFullscreenVideoManager(
  fullscreenUserId: string | null,
  localUserId: string,
  localStream: MediaStream | null,
  remoteStreams: Map<string, MediaStream>,
  isSpeakerOff: boolean
) {
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    if (!fullscreenUserId || !videoRef.current) return;

    const videoElement = videoRef.current;
    const isLocalUser = fullscreenUserId === localUserId;
    const streamToAttach = isLocalUser ? localStream : remoteStreams.get(fullscreenUserId);

    if (!streamToAttach) {
      console.log(`⚠️ [Fullscreen] No stream for ${fullscreenUserId.slice(0, 8)}`);
      return;
    }

    console.log(`🎥 [Fullscreen] Attaching ${isLocalUser ? 'local' : 'remote'} stream`);

    // ✅ Direct assignment
    videoElement.srcObject = streamToAttach;
    videoElement.muted = isLocalUser || isSpeakerOff;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    videoElement.play().catch(() => {
      setTimeout(() => videoElement.play().catch(console.error), 300);
    });

    return () => {
      if (videoElement.srcObject === streamToAttach) {
        videoElement.srcObject = null;
      }
    };
  }, [fullscreenUserId, localUserId, localStream, remoteStreams, isSpeakerOff]);

  return { videoRef };
}

// ============================================
// THUMBNAIL VIDEO MANAGER (for fullscreen thumbnails)
// ============================================
export function useThumbnailVideoManager(
  userId: string,
  isLocal: boolean,
  localStream: MediaStream | null,
  remoteStreams: Map<string, MediaStream>
) {
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    if (!videoRef.current) return;

    const stream = isLocal ? localStream : remoteStreams.get(userId);
    if (!stream) return;

    const videoElement = videoRef.current;

    videoElement.srcObject = stream;
    videoElement.muted = true;
    videoElement.playsInline = true;
    videoElement.autoplay = true;
    
    videoElement.play().catch(() => {
      setTimeout(() => videoElement.play().catch(console.error), 200);
    });

    return () => {
      if (videoElement.srcObject === stream) {
        videoElement.srcObject = null;
      }
    };
  }, [userId, isLocal, localStream, remoteStreams]);

  return { videoRef };
}