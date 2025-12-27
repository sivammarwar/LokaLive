import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';

export default function MatchmakingDebugger() {
  const [results, setResults] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(false);

  const runDiagnostics = async () => {
    setIsLoading(true);
    const diagnostics: any = {
      timestamp: new Date().toISOString(),
      checks: {}
    };

    try {
      // 1. Check if function exists
      console.log('🔍 Checking if find_compatible_room exists...');
      const { data: funcExists, error: funcError } = await supabase
        .rpc('get_ludo_vote_count'); // Test if RPC works at all
      
      diagnostics.checks.rpcWorking = !funcError;
      diagnostics.checks.rpcError = funcError?.message;

      // 2. Check user data
      const { data: { user } } = await supabase.auth.getUser();
      diagnostics.user = {
        id: user?.id,
        email: user?.email
      };

      if (user?.id) {
        const { data: userData, error: userError } = await supabase
          .from('users')
          .select('*')
          .eq('id', user.id)
          .single();
        
        diagnostics.checks.userExists = !userError;
        diagnostics.checks.userGender = userData?.gender;
        diagnostics.checks.userError = userError?.message;
      }

      // 3. Test find_compatible_room with dummy data
      console.log('🧪 Testing find_compatible_room...');
      const { data: testResult, error: testError } = await supabase
        .rpc('find_compatible_room', {
          p_user_id: user?.id || '00000000-0000-0000-0000-000000000000',
          p_user_gender: 'male',
          p_interested_in: 'female',
          p_interest: 'random',
          p_room_size: 2
        });

      diagnostics.checks.functionWorks = !testError;
      diagnostics.checks.functionError = testError ? {
        message: testError.message,
        code: testError.code,
        details: testError.details,
        hint: testError.hint
      } : null;
      diagnostics.checks.functionResult = testResult;

      // 4. Check active rooms
      const { data: rooms, error: roomsError } = await supabase
        .from('rooms')
        .select('*, room_participants(count)')
        .eq('is_active', true)
        .eq('room_type', 'public')
        .limit(10);

      diagnostics.checks.activeRooms = rooms?.length || 0;
      diagnostics.checks.roomsError = roomsError?.message;
      diagnostics.checks.roomsList = rooms;

      // 5. Check database functions
      const { data: functions, error: functionsError } = await supabase
        .from('pg_proc')
        .select('proname')
        .ilike('proname', '%find_compatible%');

      diagnostics.checks.functionExists = functions?.length > 0;
      diagnostics.checks.functionNames = functions?.map(f => f.proname);

    } catch (error: any) {
      diagnostics.error = {
        message: error.message,
        stack: error.stack
      };
    }

    setResults(diagnostics);
    setIsLoading(false);
  };

  return (
    <div className="fixed bottom-4 right-4 z-50">
      <Button
        onClick={runDiagnostics}
        disabled={isLoading}
        variant="outline"
        className="mb-2"
      >
        {isLoading ? '🔍 Running...' : '🔧 Debug Matchmaking'}
      </Button>

      {results && (
        <div className="mt-2 p-4 bg-black/90 text-white rounded-lg max-w-2xl max-h-96 overflow-auto">
          <h3 className="text-lg font-bold mb-2">Diagnostics Results</h3>
          
          <div className="space-y-2 text-xs font-mono">
            <div>
              <strong>RPC Working:</strong>{' '}
              {results.checks.rpcWorking ? '✅' : '❌'}
              {results.checks.rpcError && ` (${results.checks.rpcError})`}
            </div>

            <div>
              <strong>User ID:</strong> {results.user?.id?.slice(0, 8)}...
            </div>

            <div>
              <strong>User Gender:</strong>{' '}
              {results.checks.userGender || 'not set'}
              {results.checks.userGender === 'other' && ' ⚠️ (must be male/female)'}
            </div>

            <div>
              <strong>Function Exists:</strong>{' '}
              {results.checks.functionExists ? '✅' : '❌'}
            </div>

            <div>
              <strong>Function Test:</strong>{' '}
              {results.checks.functionWorks ? '✅' : '❌'}
            </div>

            {results.checks.functionError && (
              <div className="bg-red-900/50 p-2 rounded mt-2">
                <strong>Function Error:</strong>
                <pre className="text-xs mt-1 overflow-auto">
                  {JSON.stringify(results.checks.functionError, null, 2)}
                </pre>
              </div>
            )}

            <div>
              <strong>Active Public Rooms:</strong>{' '}
              {results.checks.activeRooms}
            </div>

            {results.checks.roomsList && results.checks.roomsList.length > 0 && (
              <div className="mt-2">
                <strong>Room Details:</strong>
                <pre className="text-xs mt-1 overflow-auto max-h-40">
                  {JSON.stringify(results.checks.roomsList, null, 2)}
                </pre>
              </div>
            )}

            <div className="mt-4 pt-4 border-t border-white/20">
              <Button
                onClick={() => navigator.clipboard.writeText(JSON.stringify(results, null, 2))}
                variant="secondary"
                size="sm"
              >
                📋 Copy Full Report
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}