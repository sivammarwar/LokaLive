import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export default function EnhancedRoomDiagnostics({ roomId, userId }) {
  const [diagnostics, setDiagnostics] = useState({
    dbParticipants: [],
    roomData: null,
    userGender: null,
    syncIssues: [],
    lastUpdate: null,
    availableRooms: [],
  });

  useEffect(() => {
    if (!userId) return;

    const runDiagnostics = async () => {
      try {
        // Get user's gender
        const { data: userData } = await supabase
          .from('users')
          .select('gender, display_name')
          .eq('id', userId)
          .single();

        // Get current room if in one
        let roomData = null;
        let dbParts = [];
        if (roomId) {
          const { data: room } = await supabase
            .from('rooms')
            .select('*')
            .eq('id', roomId)
            .single();
          roomData = room;

          const { data: parts } = await supabase
            .from('room_participants')
            .select(`
              user_id,
              left_at,
              joined_at,
              users!inner(display_name, gender)
            `)
            .eq('room_id', roomId);

          dbParts = (parts || []).filter(p => !p.left_at);
        }

        // Get all available public rooms (for debugging matching)
        const { data: publicRooms } = await supabase
          .from('rooms')
          .select('*')
          .eq('room_type', 'public')
          .eq('is_active', true)
          .limit(10);

        // For each room, get participant count
        const roomsWithCounts = await Promise.all(
          (publicRooms || []).map(async (room) => {
            const { data: parts } = await supabase
              .from('room_participants')
              .select('user_id')
              .eq('room_id', room.id)
              .is('left_at', null);
            
            return {
              ...room,
              participantCount: parts?.length || 0,
            };
          })
        );

        // Detect issues
        const issues = [];
        
        if (roomId) {
          if (dbParts.length === 0) {
            issues.push('❌ No active participants in database');
          }
          
          if (!dbParts.find(p => p.user_id === userId)) {
            issues.push('❌ Current user not in database participants');
          }

          if (roomData && !roomData.is_active) {
            issues.push('❌ Room is marked as inactive');
          }

          if (roomData && roomData.creator_gender === 'other') {
            issues.push('⚠️ Room creator_gender is "other" - matching may fail');
          }
        }

        if (userData && userData.gender === 'other') {
          issues.push('⚠️ User gender is "other" - this may limit matches');
        }

        setDiagnostics({
          dbParticipants: dbParts,
          roomData,
          userGender: userData?.gender || null,
          syncIssues: issues,
          lastUpdate: new Date().toLocaleTimeString(),
          availableRooms: roomsWithCounts.slice(0, 5),
        });
      } catch (error) {
        console.error('Diagnostics error:', error);
      }
    };

    runDiagnostics();
    const interval = setInterval(runDiagnostics, 3000);

    return () => clearInterval(interval);
  }, [roomId, userId]);

  return (
    <div className="fixed bottom-4 right-4 bg-black/95 text-white p-4 rounded-lg max-w-md text-xs font-mono z-[9999] max-h-[80vh] overflow-y-auto shadow-2xl border border-white/20">
      <div className="font-bold mb-3 text-green-400 flex items-center justify-between">
        <span>🔍 Enhanced Diagnostics</span>
        <span className="text-gray-400 text-[10px]">{diagnostics.lastUpdate}</span>
      </div>

      <div className="space-y-3">
        {/* User Info */}
        <div className="bg-blue-500/10 border border-blue-500/30 rounded p-2">
          <div className="text-blue-400 font-bold mb-1">Your Info:</div>
          <div>Gender: <span className="text-yellow-300">{diagnostics.userGender || 'unknown'}</span></div>
          {diagnostics.userGender === 'other' && (
            <div className="text-orange-400 text-[10px] mt-1">
              ⚠️ Set gender to 'male' or 'female' for better matches
            </div>
          )}
        </div>

        {/* Current Room */}
        {roomId && diagnostics.roomData && (
          <div className="bg-purple-500/10 border border-purple-500/30 rounded p-2">
            <div className="text-purple-400 font-bold mb-1">Current Room:</div>
            <div>ID: {roomId.slice(0, 8)}...</div>
            <div>Active: {diagnostics.roomData.is_active ? '✅' : '❌'}</div>
            <div>Size: {diagnostics.roomData.room_size}</div>
            <div>Creator Gender: <span className="text-yellow-300">{diagnostics.roomData.creator_gender}</span></div>
            <div>Wants Gender: <span className="text-yellow-300">{diagnostics.roomData.gender_preference}</span></div>
            <div>Interest: <span className="text-yellow-300">{diagnostics.roomData.interest_category}</span></div>
          </div>
        )}

        {/* Participants */}
        {roomId && diagnostics.dbParticipants.length > 0 && (
          <div className="bg-green-500/10 border border-green-500/30 rounded p-2">
            <div className="text-green-400 font-bold mb-1">
              Participants ({diagnostics.dbParticipants.length}):
            </div>
            {diagnostics.dbParticipants.map((p, i) => (
              <div key={i} className={p.user_id === userId ? 'text-green-300' : 'text-gray-300'}>
                • {p.users?.display_name || 'Unknown'} ({p.users?.gender})
                {p.user_id === userId && ' 👈 YOU'}
              </div>
            ))}
          </div>
        )}

        {/* Available Rooms */}
        {!roomId && diagnostics.availableRooms.length > 0 && (
          <div className="bg-yellow-500/10 border border-yellow-500/30 rounded p-2">
            <div className="text-yellow-400 font-bold mb-1">
              Available Public Rooms ({diagnostics.availableRooms.length}):
            </div>
            {diagnostics.availableRooms.map((room, i) => (
              <div key={i} className="text-[10px] mb-1 pb-1 border-b border-white/10 last:border-0">
                <div className="flex justify-between">
                  <span>Room {i + 1}</span>
                  <span className="text-yellow-300">{room.participantCount}/{room.room_size}</span>
                </div>
                <div className="text-gray-400">
                  Creator: {room.creator_gender} → Wants: {room.gender_preference}
                </div>
                <div className="text-gray-400">
                  Interest: {room.interest_category}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Issues */}
        {diagnostics.syncIssues.length > 0 && (
          <div className="bg-red-500/10 border border-red-500/30 rounded p-2">
            <div className="text-red-400 font-bold mb-1">Issues Detected:</div>
            {diagnostics.syncIssues.map((issue, i) => (
              <div key={i} className="text-red-300 text-[10px]">{issue}</div>
            ))}
          </div>
        )}

        {diagnostics.syncIssues.length === 0 && roomId && (
          <div className="bg-green-500/10 border border-green-500/30 rounded p-2">
            <div className="text-green-400 font-bold">✅ Everything looks good!</div>
          </div>
        )}

        {/* Instructions */}
        <div className="text-gray-400 text-[10px] mt-2 pt-2 border-t border-white/10">
          <div className="font-bold text-white mb-1">Debug Tips:</div>
          <div>• Check console (F12) for WebRTC logs</div>
          <div>• Gender must be 'male' or 'female' for matching</div>
          <div>• Creator_gender in rooms table matters</div>
          <div>• Participant count must be accurate</div>
        </div>
      </div>
    </div>
  );
}

/*
HOW TO USE:

1. In CreateRoom.tsx, add at the bottom before closing </div>:
   <EnhancedRoomDiagnostics roomId={null} userId={userId} />

2. In Room.tsx, add at the bottom before closing </div>:
   <EnhancedRoomDiagnostics roomId={roomId} userId={userId} />

3. This will show you:
   - Your current gender setting
   - Available rooms and their requirements
   - Current room status
   - Participant sync status
   - Any detected issues

This helps identify exactly why matching isn't working!
*/