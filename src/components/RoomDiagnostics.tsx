// Add this to your existing RoomDiagnostics component
// Replace the entire component with this enhanced version:

import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export default function RoomDiagnostics({ roomId, userId, remoteStreams, localStream }) {
  const [diagnostics, setDiagnostics] = useState({
    dbParticipants: [],
    webrtcPeers: [],
    syncIssues: [],
    roomData: null,
    lastUpdate: null,
    streamDetails: []
  });

  useEffect(() => {
    if (!roomId || !userId) return;

    const runDiagnostics = async () => {
      try {
        // Check database participants
        const { data: dbParts } = await supabase
          .from('room_participants')
          .select(`
            user_id,
            left_at,
            joined_at,
            users!inner(display_name)
          `)
          .eq('room_id', roomId);

        // Check room data
        const { data: room } = await supabase
          .from('rooms')
          .select('*')
          .eq('id', roomId)
          .single();

        // Get active participants
        const activeDbParts = (dbParts || []).filter(p => !p.left_at);

        // Get WebRTC stream details
        const streamDetails = [];
        
        if (localStream) {
          const videoTrack = localStream.getVideoTracks()[0];
          const audioTrack = localStream.getAudioTracks()[0];
          streamDetails.push({
            type: 'local',
            userId: userId,
            video: videoTrack ? {
              enabled: videoTrack.enabled,
              muted: videoTrack.muted,
              readyState: videoTrack.readyState
            } : null,
            audio: audioTrack ? {
              enabled: audioTrack.enabled,
              muted: audioTrack.muted,
              readyState: audioTrack.readyState
            } : null
          });
        }

        if (remoteStreams) {
          remoteStreams.forEach((stream, peerId) => {
            const videoTrack = stream.getVideoTracks()[0];
            const audioTrack = stream.getAudioTracks()[0];
            streamDetails.push({
              type: 'remote',
              userId: peerId,
              video: videoTrack ? {
                enabled: videoTrack.enabled,
                muted: videoTrack.muted,
                readyState: videoTrack.readyState
              } : null,
              audio: audioTrack ? {
                enabled: audioTrack.enabled,
                muted: audioTrack.muted,
                readyState: audioTrack.readyState
              } : null
            });
          });
        }

        // Detect issues
        const issues = [];
        
        if (activeDbParts.length === 0) {
          issues.push('❌ No active participants in database');
        }
        
        if (!activeDbParts.find(p => p.user_id === userId)) {
          issues.push('❌ Current user not in database participants');
        }

        if (room && !room.is_active) {
          issues.push('❌ Room is marked as inactive');
        }

        const remoteCount = remoteStreams ? remoteStreams.size : 0;
        const dbCount = activeDbParts.length - 1; // Exclude self
        
        if (remoteCount !== dbCount) {
          issues.push(`⚠️ Stream mismatch: ${remoteCount} WebRTC streams vs ${dbCount} DB peers`);
        }

        setDiagnostics({
          dbParticipants: activeDbParts,
          webrtcPeers: remoteCount,
          syncIssues: issues,
          roomData: room,
          streamDetails,
          lastUpdate: new Date().toLocaleTimeString()
        });
      } catch (error) {
        console.error('Diagnostics error:', error);
      }
    };

    // Run immediately
    runDiagnostics();

    // Run every 2 seconds
    const interval = setInterval(runDiagnostics, 2000);

    return () => clearInterval(interval);
  }, [roomId, userId, remoteStreams, localStream]);

  return (
    <div className="fixed bottom-4 right-4 bg-black/90 text-white p-4 rounded-lg max-w-md text-xs font-mono z-50 max-h-96 overflow-y-auto">
      <div className="font-bold mb-2 text-green-400">
        🔍 Room Diagnostics
        <span className="ml-2 text-gray-400">{diagnostics.lastUpdate}</span>
      </div>

      <div className="space-y-2">
        <div>
          <div className="text-yellow-400 font-bold">Room Status:</div>
          <div>ID: {roomId?.slice(0, 8)}...</div>
          <div>Active: {diagnostics.roomData?.is_active ? '✅' : '❌'}</div>
          <div>Size: {diagnostics.roomData?.room_size}</div>
        </div>

        <div>
          <div className="text-yellow-400 font-bold">
            Database Participants ({diagnostics.dbParticipants.length}):
          </div>
          {diagnostics.dbParticipants.map((p, i) => (
            <div key={i} className={p.user_id === userId ? 'text-green-400' : ''}>
              • {p.users?.display_name || 'Unknown'}
              {p.user_id === userId && ' (YOU)'}
            </div>
          ))}
        </div>

        <div>
          <div className="text-yellow-400 font-bold">
            WebRTC Peers ({diagnostics.webrtcPeers}):
          </div>
          {diagnostics.webrtcPeers === 0 && (
            <div className="text-red-300">❌ No remote streams connected!</div>
          )}
        </div>

        <div>
          <div className="text-yellow-400 font-bold">Stream Details:</div>
          {diagnostics.streamDetails.map((detail, i) => {
            const participantName = diagnostics.dbParticipants.find(
              p => p.user_id === detail.userId
            )?.users?.display_name || 'Unknown';
            
            return (
              <div key={i} className="ml-2 border-l-2 border-gray-600 pl-2 mb-2">
                <div className={detail.type === 'local' ? 'text-green-400' : 'text-blue-400'}>
                  {detail.type === 'local' ? '📹 Local' : '📺 Remote'}: {participantName}
                </div>
                {detail.video ? (
                  <div className="text-gray-300">
                    Video: {detail.video.readyState} | 
                    {detail.video.enabled ? ' ✅' : ' ❌'} |
                    {detail.video.muted ? ' 🔇' : ' 🔊'}
                  </div>
                ) : (
                  <div className="text-red-300">Video: ❌ No track</div>
                )}
                {detail.audio ? (
                  <div className="text-gray-300">
                    Audio: {detail.audio.readyState} | 
                    {detail.audio.enabled ? ' ✅' : ' ❌'} |
                    {detail.audio.muted ? ' 🔇' : ' 🔊'}
                  </div>
                ) : (
                  <div className="text-red-300">Audio: ❌ No track</div>
                )}
              </div>
            );
          })}
        </div>

        {diagnostics.syncIssues.length > 0 && (
          <div>
            <div className="text-red-400 font-bold">Issues:</div>
            {diagnostics.syncIssues.map((issue, i) => (
              <div key={i} className="text-red-300">{issue}</div>
            ))}
          </div>
        )}

        <div className="text-gray-400 text-xs mt-2">
          F12 → Console for detailed logs
        </div>
      </div>
    </div>
  );
}