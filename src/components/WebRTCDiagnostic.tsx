import React from 'react';
import { Card } from '@/components/ui/card';

interface WebRTCDiagnosticProps {
  peerConnections: Map<string, RTCPeerConnection>;
  remoteStreams: Map<string, MediaStream>;
}

export function WebRTCDiagnostic({ peerConnections, remoteStreams }: WebRTCDiagnosticProps) {
  const [stats, setStats] = React.useState<any>({});
  const [expanded, setExpanded] = React.useState(false);

  React.useEffect(() => {
    const interval = setInterval(async () => {
      const newStats: any = {};

      for (const [peerId, pc] of peerConnections.entries()) {
        const peerStats: any = {
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
          iceGatheringState: pc.iceGatheringState,
          signalingState: pc.signalingState,
          localDescription: pc.localDescription?.type || 'none',
          remoteDescription: pc.remoteDescription?.type || 'none',
        };

        // Get transceiver info
        const transceivers = pc.getTransceivers();
        peerStats.transceivers = transceivers.map(t => ({
          mid: t.mid,
          direction: t.direction,
          currentDirection: t.currentDirection,
          sender: {
            track: t.sender.track ? {
              kind: t.sender.track.kind,
              enabled: t.sender.track.enabled,
              readyState: t.sender.track.readyState,
              muted: t.sender.track.muted
            } : null
          },
          receiver: {
            track: t.receiver.track ? {
              kind: t.receiver.track.kind,
              enabled: t.receiver.track.enabled,
              readyState: t.receiver.track.readyState,
              muted: t.receiver.track.muted
            } : null
          }
        }));

        // Get remote stream info
        const stream = remoteStreams.get(peerId);
        if (stream) {
          peerStats.remoteStream = {
            id: stream.id,
            active: stream.active,
            videoTracks: stream.getVideoTracks().map(t => ({
              id: t.id,
              label: t.label,
              enabled: t.enabled,
              readyState: t.readyState,
              muted: t.muted
            })),
            audioTracks: stream.getAudioTracks().map(t => ({
              id: t.id,
              label: t.label,
              enabled: t.enabled,
              readyState: t.readyState,
              muted: t.muted
            }))
          };
        }

        // Get ICE candidates
        try {
          const statsReport = await pc.getStats();
          let localCandidates = 0;
          let remoteCandidates = 0;
          let activePair: any = null;

          statsReport.forEach((stat: any) => {
            if (stat.type === 'local-candidate') localCandidates++;
            if (stat.type === 'remote-candidate') remoteCandidates++;
            if (stat.type === 'candidate-pair' && stat.state === 'succeeded') {
              activePair = {
                localType: stat.localCandidateType,
                remoteType: stat.remoteCandidateType,
                protocol: stat.protocol,
                bytesReceived: stat.bytesReceived,
                bytesSent: stat.bytesSent
              };
            }
          });

          peerStats.iceCandidates = { local: localCandidates, remote: remoteCandidates };
          peerStats.activePair = activePair;
        } catch (error) {
          console.error('Error getting stats:', error);
        }

        newStats[peerId.slice(0, 8)] = peerStats;
      }

      setStats(newStats);
    }, 1000);

    return () => clearInterval(interval);
  }, [peerConnections, remoteStreams]);

  if (!expanded) {
    return (
      <button
        onClick={() => setExpanded(true)}
        className="fixed bottom-4 right-4 z-50 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg shadow-lg text-sm font-medium"
      >
        🔍 Show WebRTC Debug
      </button>
    );
  }

  return (
    <div className="fixed bottom-4 right-4 z-50 max-w-2xl max-h-[80vh] overflow-auto">
      <Card className="p-4 bg-black/90 text-white text-xs font-mono">
        <div className="flex justify-between items-center mb-3">
          <h3 className="font-bold text-sm">WebRTC Diagnostics</h3>
          <button
            onClick={() => setExpanded(false)}
            className="text-red-400 hover:text-red-300"
          >
            ✕
          </button>
        </div>

        {Object.keys(stats).length === 0 ? (
          <div className="text-yellow-400">No peer connections</div>
        ) : (
          Object.entries(stats).map(([peerId, peerStats]: [string, any]) => (
            <div key={peerId} className="mb-4 border border-gray-700 rounded p-3">
              <div className="font-bold text-blue-400 mb-2">Peer: {peerId}</div>

              <div className="space-y-1">
                <div className="flex gap-2">
                  <span className="text-gray-400">Connection:</span>
                  <span className={
                    peerStats.connectionState === 'connected' ? 'text-green-400' :
                    peerStats.connectionState === 'connecting' ? 'text-yellow-400' :
                    'text-red-400'
                  }>
                    {peerStats.connectionState}
                  </span>
                </div>

                <div className="flex gap-2">
                  <span className="text-gray-400">ICE:</span>
                  <span className={
                    peerStats.iceConnectionState === 'connected' || peerStats.iceConnectionState === 'completed' ? 'text-green-400' :
                    peerStats.iceConnectionState === 'checking' ? 'text-yellow-400' :
                    'text-red-400'
                  }>
                    {peerStats.iceConnectionState}
                  </span>
                </div>

                <div className="flex gap-2">
                  <span className="text-gray-400">Signaling:</span>
                  <span className={peerStats.signalingState === 'stable' ? 'text-green-400' : 'text-yellow-400'}>
                    {peerStats.signalingState}
                  </span>
                </div>

                <div className="flex gap-2">
                  <span className="text-gray-400">Descriptions:</span>
                  <span>Local: {peerStats.localDescription}, Remote: {peerStats.remoteDescription}</span>
                </div>

                {peerStats.iceCandidates && (
                  <div className="flex gap-2">
                    <span className="text-gray-400">ICE Candidates:</span>
                    <span>Local: {peerStats.iceCandidates.local}, Remote: {peerStats.iceCandidates.remote}</span>
                  </div>
                )}

                {peerStats.activePair && (
                  <div className="mt-2 p-2 bg-green-900/30 rounded">
                    <div className="text-green-400 font-bold mb-1">✓ Active Connection</div>
                    <div>Type: {peerStats.activePair.localType} → {peerStats.activePair.remoteType}</div>
                    <div>Protocol: {peerStats.activePair.protocol}</div>
                    <div>RX: {Math.round(peerStats.activePair.bytesReceived / 1024)}KB</div>
                    <div>TX: {Math.round(peerStats.activePair.bytesSent / 1024)}KB</div>
                  </div>
                )}

                {peerStats.transceivers && (
                  <div className="mt-2">
                    <div className="text-purple-400 font-bold">Transceivers:</div>
                    {peerStats.transceivers.map((t: any, idx: number) => (
                      <div key={idx} className="ml-2 mt-1 p-2 bg-gray-900/50 rounded">
                        <div>MID: {t.mid || 'null'}</div>
                        <div>Direction: {t.direction} (current: {t.currentDirection || 'none'})</div>
                        {t.sender.track && (
                          <div className="text-green-400">
                            Sender: {t.sender.track.kind} 
                            ({t.sender.track.readyState})
                            {t.sender.track.enabled ? ' ✓' : ' ✗'}
                            {t.sender.track.muted ? ' 🔇' : ''}
                          </div>
                        )}
                        {t.receiver.track && (
                          <div className="text-blue-400">
                            Receiver: {t.receiver.track.kind} 
                            ({t.receiver.track.readyState})
                            {t.receiver.track.enabled ? ' ✓' : ' ✗'}
                            {t.receiver.track.muted ? ' 🔇' : ''}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}

                {peerStats.remoteStream && (
                  <div className="mt-2">
                    <div className="text-cyan-400 font-bold">Remote Stream:</div>
                    <div className="ml-2">
                      <div>ID: {peerStats.remoteStream.id}</div>
                      <div>Active: {peerStats.remoteStream.active ? '✓' : '✗'}</div>
                      <div className="mt-1">
                        <div className="text-orange-400">Video Tracks ({peerStats.remoteStream.videoTracks.length}):</div>
                        {peerStats.remoteStream.videoTracks.map((t: any, idx: number) => (
                          <div key={idx} className="ml-2">
                            {t.label || t.id.slice(0, 8)}
                            : {t.readyState}
                            {t.enabled ? ' ✓' : ' ✗'}
                            {t.muted ? ' 🔇' : ''}
                          </div>
                        ))}
                      </div>
                      <div className="mt-1">
                        <div className="text-orange-400">Audio Tracks ({peerStats.remoteStream.audioTracks.length}):</div>
                        {peerStats.remoteStream.audioTracks.map((t: any, idx: number) => (
                          <div key={idx} className="ml-2">
                            {t.label || t.id.slice(0, 8)}
                            : {t.readyState}
                            {t.enabled ? ' ✓' : ' ✗'}
                            {t.muted ? ' 🔇' : ''}
                          </div>
                        ))}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          ))
        )}
      </Card>
    </div>
  );
}