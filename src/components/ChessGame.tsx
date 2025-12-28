// src/components/ChessGame.tsx - FIXED: Properly handles room transitions with win alerts
import { useState, useEffect, useCallback } from 'react';
import { Chess, Square, PieceSymbol, Color } from 'chess.js';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';
import { Flag, Trophy, Crown, Gem } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useDiamondStore } from '@/lib/diamondStore';

interface ChessGameProps {
  gameId: string;
  myUserId: string;
  myColor: 'white' | 'black';
  opponentId: string; // ✅ ADD THIS
  opponentName: string;
  onClose: () => void;
  isEmbedded?: boolean;
  originalRoomId: string;
  isBetMatch?: boolean;
  betAmount?: number;
  onGameEnd?: (winner: string | null, message: string) => void;
}

const PIECES: Record<Color, Record<PieceSymbol, string>> = {
  w: { p: '♙', n: '♘', b: '♗', r: '♖', q: '♕', k: '♔' },
  b: { p: '♟', n: '♞', b: '♝', r: '♜', q: '♛', k: '♚' },
};

export function ChessGame({ 
  gameId, 
  myUserId, 
  myColor, 
  opponentId, // ✅ ADD THIS
  opponentName, 
  onClose,
  isEmbedded = false,
  originalRoomId,
  isBetMatch = false,
  betAmount = 0,
  onGameEnd,
}: ChessGameProps) {
  const [game, setGame] = useState(new Chess());
  const [gameStatus, setGameStatus] = useState<'active' | 'checkmate' | 'stalemate' | 'draw' | 'resigned'>('active');
  const [winner, setWinner] = useState<'white' | 'black' | null>(null);
  const [lastMove, setLastMove] = useState<{ from: string; to: string } | null>(null);
  const [moveFrom, setMoveFrom] = useState<Square | null>(null);
  const [moveTo, setMoveTo] = useState<Square | null>(null);
  const [showPromotionDialog, setShowPromotionDialog] = useState(false);
  const [myDisplayName, setMyDisplayName] = useState('You');
  const [moveCount, setMoveCount] = useState(0);
  const [checkSquare, setCheckSquare] = useState<string | null>(null);
  const [validMoves, setValidMoves] = useState<string[]>([]);
  
  const { refreshDiamonds } = useDiamondStore();

  // ✅ NEW: Helper function to trigger win alerts
  const triggerWinAlert = useCallback((winnerId: string | null, message: string) => {
    if (onGameEnd) {
      onGameEnd(winnerId, message);
    }
    
    // Also dispatch custom event for ChessGameView to catch
    const event = new CustomEvent('chess-game-ended', { 
      detail: { 
        winner: winnerId,
        message 
      } 
    });
    window.dispatchEvent(event);
    
    console.log('🏆 Game ended alert triggered:', { winnerId, message });
  }, [onGameEnd]);

  useEffect(() => {
    const fetchMyName = async () => {
      const { data } = await supabase
        .from('users')
        .select('display_name')
        .eq('id', myUserId)
        .single();
      
      if (data) {
        setMyDisplayName(data.display_name);
      }
    };
    fetchMyName();
  }, [myUserId]);

  const findCheckSquare = useCallback((gameInstance: Chess) => {
    if (!gameInstance.inCheck()) return null;
    for (let row = 0; row < 8; row++) {
      for (let col = 0; col < 8; col++) {
        const piece = gameInstance.board()[row][col];
        if (piece?.type === 'k' && piece.color === gameInstance.turn()) {
          return `${'abcdefgh'[col]}${8 - row}`;
        }
      }
    }
    return null;
  }, []);

  useEffect(() => {
    const loadGame = async () => {
      const { data, error } = await supabase
        .from('chess_games')
        .select('*')
        .eq('id', gameId)
        .maybeSingle();

      if (error || !data) {
        console.error('Error loading game:', error);
        toast.error('Failed to load game');
        return;
      }

      const newGame = new Chess(data.fen);
      setGame(newGame);
      setGameStatus(data.status as any);
      setMoveCount(newGame.moveNumber());
      setCheckSquare(findCheckSquare(newGame));
      
      if (data.last_move) {
        setLastMove(data.last_move as { from: string; to: string });
      }

      if (data.status === 'resigned' && data.winner_id) {
        const didIWin = data.winner_id === myUserId;
        setWinner(didIWin ? myColor : (myColor === 'white' ? 'black' : 'white'));
        
        if (didIWin && isBetMatch && betAmount > 0) {
          const message = `You won ${betAmount * 2} diamonds! 💎`;
          toast.success(message);
          triggerWinAlert(myUserId, message);
        } else if (didIWin) {
          const message = 'Opponent resigned. You won!';
          toast.success(message);
          triggerWinAlert(myUserId, message);
        } else {
          const message = 'You lost the game';
          triggerWinAlert(data.winner_id, message);
        }
      }

      if ((data.status === 'checkmate' || data.status === 'resigned') && 
          data.winner_id && isBetMatch && data.bet_status === 'paid_out') {
        await refreshDiamonds(myUserId);
      }
    };

    loadGame();

    const channel = supabase
      .channel(`chess-game-${gameId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'chess_games',
          filter: `id=eq.${gameId}`,
        },
        async (payload) => {
          const updated = payload.new as any;
          const newGame = new Chess(updated.fen);
          setGame(newGame);
          setGameStatus(updated.status);
          setMoveCount(newGame.moveNumber());
          setCheckSquare(findCheckSquare(newGame));
          
          if (updated.last_move) {
            setLastMove(updated.last_move as { from: string; to: string });
          }
          
          // ✅ CHECKMATE
          if (updated.status === 'checkmate') {
            const winnerColor = newGame.turn() === 'w' ? 'black' : 'white';
            setWinner(winnerColor);
            const didIWin = winnerColor === myColor;
            
            if (didIWin) {
              if (isBetMatch && betAmount > 0) {
                const message = `Checkmate! You won ${betAmount * 2} diamonds! 💎`;
                toast.success(message);
                triggerWinAlert(myUserId, message);
              } else {
                const message = 'You won by checkmate!';
                toast.success(message);
                triggerWinAlert(myUserId, message);
              }
            } else {
              if (isBetMatch && betAmount > 0) {
                const message = `Checkmate! You lost ${betAmount} diamonds`;
                toast.error(message);
                triggerWinAlert(null, message);
              } else {
                const message = 'You lost by checkmate';
                toast.error(message);
                triggerWinAlert(null, message);
              }
            }
            await refreshDiamonds(myUserId);
          } 
          
          // ✅ STALEMATE
          else if (updated.status === 'stalemate') {
            const message = 'Game ended in stalemate';
            toast.info(message);
            triggerWinAlert(null, message);
            
            if (isBetMatch && betAmount > 0) {
              toast.info('Bet refunded due to stalemate');
              await refreshDiamonds(myUserId);
            }
          } 
          
          // ✅ RESIGNED
          else if (updated.status === 'resigned') {
            if (updated.winner_id === myUserId) {
              setWinner(myColor);
              if (isBetMatch && betAmount > 0) {
                const message = `Opponent resigned. You won ${betAmount * 2} diamonds! 💎`;
                toast.success(message);
                triggerWinAlert(myUserId, message);
              } else {
                const message = 'Opponent resigned. You won!';
                toast.success(message);
                triggerWinAlert(myUserId, message);
              }
              await refreshDiamonds(myUserId);
            } else {
              setWinner(myColor === 'white' ? 'black' : 'white');
              if (isBetMatch && betAmount > 0) {
                const message = `You resigned and lost ${betAmount} diamonds`;
                toast.error(message);
                triggerWinAlert(updated.winner_id, message);
              } else {
                const message = 'You resigned';
                triggerWinAlert(updated.winner_id, message);
              }
            }
            
            // ✅ FIX: Give time for user to see the result before closing
            setTimeout(() => {
              onClose();
            }, 3000);
          }
          
          // ✅ DRAW
          else if (updated.status === 'draw') {
            const message = 'Game ended in a draw';
            toast.info(message);
            triggerWinAlert(null, message);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [gameId, myColor, myUserId, onClose, isBetMatch, betAmount, refreshDiamonds, findCheckSquare, triggerWinAlert]);

  const isMyTurn = () => {
    return (game.turn() === 'w' && myColor === 'white') || (game.turn() === 'b' && myColor === 'black');
  };

  const handleSquareClick = (square: Square) => {
    if (!isMyTurn() || gameStatus !== 'active') return;

    if (!moveFrom) {
      const piece = game.get(square);
      if (piece && ((myColor === 'white' && piece.color === 'w') || (myColor === 'black' && piece.color === 'b'))) {
        setMoveFrom(square);
        const moves = game.moves({ square, verbose: true });
        setValidMoves(moves.map(m => m.to));
      }
      return;
    }

    if (moveFrom === square) {
      setMoveFrom(null);
      setValidMoves([]);
      return;
    }

    const moves = game.moves({ square: moveFrom, verbose: true });
    const foundMove = moves.find((m) => m.from === moveFrom && m.to === square);

    if (!foundMove) {
      const piece = game.get(square);
      if (piece && ((myColor === 'white' && piece.color === 'w') || (myColor === 'black' && piece.color === 'b'))) {
        setMoveFrom(square);
        const newMoves = game.moves({ square, verbose: true });
        setValidMoves(newMoves.map(m => m.to));
      } else {
        setMoveFrom(null);
        setValidMoves([]);
      }
      return;
    }

    if (
      ((foundMove.color === 'w' && foundMove.piece === 'p' && square[1] === '8') ||
        (foundMove.color === 'b' && foundMove.piece === 'p' && square[1] === '1'))
    ) {
      setMoveTo(square);
      setShowPromotionDialog(true);
      return;
    }

    makeMove(moveFrom, square);
  };

  const makeMove = async (from: Square, to: Square, promotion?: string) => {
    try {
      const gameCopy = new Chess(game.fen());
      const move = gameCopy.move({ from, to, promotion: promotion || 'q' });

      if (move === null) {
        setMoveFrom(null);
        setValidMoves([]);
        return;
      }

      let status: string = 'active';
      let winnerId: string | null = null;

      if (gameCopy.isCheckmate()) {
        status = 'checkmate';
        winnerId = myUserId;
        setWinner(myColor);
        
        // ✅ Trigger win alert for checkmate
        if (isBetMatch && betAmount > 0) {
          triggerWinAlert(winnerId, `Checkmate! You won ${betAmount * 2} diamonds! 💎`);
        } else {
          triggerWinAlert(winnerId, 'Checkmate! You won!');
        }
        
        // ✅ NEW: Broadcast game end
        const chessEndChannel = supabase.channel(`chess-end-${gameId}`);
        await chessEndChannel.send({
          type: 'broadcast',
          event: 'game-over',
          payload: {
            gameId,
            status: 'checkmate',
            winnerId: winnerId
          }
        });
        
      } else if (gameCopy.isStalemate()) {
        status = 'stalemate';
        triggerWinAlert(null, 'Game ended in stalemate');
        
        // ✅ NEW: Broadcast stalemate
        const chessEndChannel = supabase.channel(`chess-end-${gameId}`);
        await chessEndChannel.send({
          type: 'broadcast',
          event: 'game-over',
          payload: {
            gameId,
            status: 'stalemate',
            winnerId: null
          }
        });
        
      } else if (gameCopy.isDraw()) {
        status = 'draw';
        triggerWinAlert(null, 'Game ended in a draw');
        
        // ✅ NEW: Broadcast draw
        const chessEndChannel = supabase.channel(`chess-end-${gameId}`);
        await chessEndChannel.send({
          type: 'broadcast',
          event: 'game-over',
          payload: {
            gameId,
            status: 'draw',
            winnerId: null
          }
        });
      }

      setGame(gameCopy);
      setLastMove({ from, to });
      setMoveFrom(null);
      setMoveTo(null);
      setValidMoves([]);
      setShowPromotionDialog(false);
      setMoveCount(gameCopy.moveNumber());
      setCheckSquare(findCheckSquare(gameCopy));

      const { error } = await supabase
        .from('chess_games')
        .update({
          fen: gameCopy.fen(),
          pgn: gameCopy.pgn(),
          status,
          winner_id: winnerId,
          last_move: { from, to },
          updated_at: new Date().toISOString(),
        })
        .eq('id', gameId);

      if (error) {
        console.error('Error updating game:', error);
        setGame(game);
        toast.error('Failed to save move');
      }
    } catch (error) {
      console.error('Move error:', error);
      setMoveFrom(null);
      setValidMoves([]);
    }
  };

  const handleResign = async () => {
    if (gameStatus !== 'active') return;
    
    try {
      const { data } = await supabase
        .from('chess_games')
        .select('white_player_id, black_player_id')
        .eq('id', gameId)
        .single();
  
      if (!data) return;
  
      const winnerId = myColor === 'white' ? data.black_player_id : data.white_player_id;
      const opponentId = myColor === 'white' ? data.black_player_id : data.white_player_id;
      
      // ✅ Trigger win alert for resignation
      if (winnerId === myUserId) {
        if (isBetMatch && betAmount > 0) {
          triggerWinAlert(winnerId, `Opponent resigned. You won ${betAmount * 2} diamonds! 💎`);
        } else {
          triggerWinAlert(winnerId, 'Opponent resigned. You won!');
        }
      } else {
        if (isBetMatch && betAmount > 0) {
          triggerWinAlert(winnerId, `You resigned and lost ${betAmount} diamonds`);
        } else {
          triggerWinAlert(winnerId, 'You resigned');
        }
      }
  
      // Update game in database
      await supabase
        .from('chess_games')
        .update({
          status: 'resigned',
          winner_id: winnerId,
          updated_at: new Date().toISOString(),
        })
        .eq('id', gameId);
  
      // ✅ NEW: Broadcast to chess-specific channel for opponent
      const chessEndChannel = supabase.channel(`chess-end-${gameId}`);
      await chessEndChannel.send({
        type: 'broadcast',
        event: 'chess-resigned',
        payload: {
          gameId,
          resignerId: myUserId,
          resignerName: myDisplayName,
          winnerId: winnerId
        }
      });
  
      // ✅ KEEP: Original broadcast for backward compatibility
      const chessChannel = supabase.channel(`chess-invites-${originalRoomId}`);
      await chessChannel.send({
        type: 'broadcast',
        event: 'chess-resigned',
        payload: {
          gameId,
          resignerId: myUserId,
          resignerName: myDisplayName,
        },
      });
  
      setGameStatus('resigned');
      setWinner(myColor === 'white' ? 'black' : 'white');
      
      if (isBetMatch && betAmount > 0 && winnerId !== myUserId) {
        toast.error(`You resigned and lost ${betAmount} diamonds`);
      } else if (isBetMatch && betAmount > 0) {
        toast.success(`Opponent resigned. You won ${betAmount * 2} diamonds! 💎`);
      } else if (winnerId !== myUserId) {
        toast.error('You resigned. Returning to room...');
      } else {
        toast.success('Opponent resigned. You won!');
      }
  
      // ✅ FIX: Close after a delay to let user see the message
      setTimeout(() => {
        onClose();
      }, 2000);
    } catch (error) {
      console.error('Resign error:', error);
      toast.error('Failed to resign');
    }
  };

  const renderBoard = () => {
    const files = myColor === 'white' ? ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] : ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'];
    const ranks = myColor === 'white' ? [8, 7, 6, 5, 4, 3, 2, 1] : [1, 2, 3, 4, 5, 6, 7, 8];

    return (
      <div className="w-full aspect-square rounded-lg overflow-hidden shadow-lg border-2 border-gray-800 bg-gray-800">
        {ranks.map((rank, rankIdx) => (
          <div key={rank} className="flex w-full h-[12.5%]">
            {files.map((file, fileIdx) => {
              const square = `${file}${rank}` as Square;
              const piece = game.get(square);
              const isDark = (rankIdx + fileIdx) % 2 === 1;
              const isLastMoveFrom = lastMove?.from === square;
              const isLastMoveTo = lastMove?.to === square;
              const isSelected = moveFrom === square;
              const isCheck = checkSquare === square;
              const isValidMove = validMoves.includes(square);

              return (
                <div
                  key={square}
                  onClick={() => handleSquareClick(square)}
                  className={cn(
                    'relative w-[12.5%] h-full flex items-center justify-center cursor-pointer transition-colors',
                    isDark ? 'bg-[#769656]' : 'bg-[#eeeed2]',
                    isLastMoveFrom && 'bg-[#baca44]',
                    isLastMoveTo && 'bg-[#baca44]',
                    isSelected && 'bg-[#f7f769]',
                    isCheck && 'bg-red-500',
                    isMyTurn() && gameStatus === 'active' && 'hover:bg-opacity-80'
                  )}
                >
                  {piece && (
                    <span 
                      className={cn(
                        "text-4xl sm:text-5xl md:text-6xl select-none pointer-events-none transition-transform",
                        isSelected && "scale-110",
                        piece.color === 'w' 
                          ? 'text-white drop-shadow-[0_2px_4px_rgba(0,0,0,0.8)]' 
                          : 'text-black drop-shadow-[0_2px_4px_rgba(255,255,255,0.5)]'
                      )}
                    >
                      {PIECES[piece.color][piece.type]}
                    </span>
                  )}
                  
                  {isValidMove && !piece && (
                    <div className="absolute w-4 h-4 md:w-6 md:h-6 rounded-full bg-black/20 border-2 border-black/30" />
                  )}
                  
                  {rankIdx === 7 && (
                    <span className={cn(
                      "absolute bottom-0 left-1 text-xs font-medium select-none pointer-events-none",
                      isDark ? 'text-white/80' : 'text-black/80'
                    )}>
                      {file}
                    </span>
                  )}
                  
                  {fileIdx === (myColor === 'white' ? 7 : 0) && (
                    <span className={cn(
                      "absolute top-0 right-1 text-xs font-medium select-none pointer-events-none",
                      isDark ? 'text-white/80' : 'text-black/80'
                    )}>
                      {rank}
                    </span>
                  )}
                </div>
              );
            })}
          </div>
        ))}
      </div>
    );
  };

  if (isEmbedded) {
    return (
      <div className="w-full max-w-2xl space-y-4">
        <div className="bg-white dark:bg-gray-800 rounded-lg p-4 shadow">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div className="flex items-center gap-3">
              <Crown className={cn(
                'h-5 w-5',
                myColor === 'white' ? 'text-amber-500' : 'text-gray-500'
              )} />
              <div>
                <div className="flex items-center gap-2">
                  <p className="font-semibold text-sm">
                    {isBetMatch ? 'Bet Match' : 'Chess Match'}
                  </p>
                  {isBetMatch && betAmount > 0 && (
                    <div className="flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900/30">
                      <Gem className="h-3 w-3 text-amber-600 dark:text-amber-400" />
                      <span className="text-xs font-bold text-amber-700 dark:text-amber-300">{betAmount * 2}</span>
                    </div>
                  )}
                </div>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  You ({myColor}) vs {opponentName}
                </p>
              </div>
            </div>
            <div className="flex flex-col items-end gap-1">
              {gameStatus === 'active' ? (
                <span className={cn(
                  'px-3 py-1 rounded-full text-sm font-medium',
                  isMyTurn()
                    ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300'
                    : 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-300'
                )}>
                  {isMyTurn() ? 'Your turn' : "Opponent's turn"}
                </span>
              ) : (
                <span className="flex items-center gap-2 px-3 py-1 rounded-full text-sm font-medium bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300">
                  <Trophy className="h-3 w-3" />
                  {gameStatus === 'checkmate' && `${winner} wins!`}
                  {gameStatus === 'resigned' && (winner === myColor ? 'You won!' : 'You lost')}
                </span>
              )}
              <span className="text-xs text-gray-500 dark:text-gray-400">
                Move {moveCount}
              </span>
            </div>
          </div>
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-lg p-4 shadow">
          {renderBoard()}
        </div>

        {gameStatus === 'active' && (
          <div className="flex justify-center">
            <Button 
              variant="destructive" 
              size="sm" 
              onClick={handleResign}
              className="gap-2"
            >
              <Flag className="h-4 w-4" />
              Resign
              {isBetMatch && betAmount > 0 && (
                <span className="text-xs opacity-80">(-{betAmount}💎)</span>
              )}
            </Button>
          </div>
        )}

        {showPromotionDialog && (
          <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
            <div className="bg-white dark:bg-gray-800 rounded-lg p-6 space-y-4 shadow-xl">
              <h3 className="text-lg font-bold text-center">Choose Promotion</h3>
              <div className="flex gap-4">
                {['q', 'r', 'b', 'n'].map((piece) => (
                  <button
                    key={piece}
                    onClick={() => {
                      if (moveFrom && moveTo) {
                        makeMove(moveFrom, moveTo, piece);
                      }
                      setShowPromotionDialog(false);
                    }}
                    className="w-16 h-16 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 rounded-lg flex items-center justify-center text-4xl transition-colors"
                  >
                    {piece === 'q' && '♕'}
                    {piece === 'r' && '♖'}
                    {piece === 'b' && '♗'}
                    {piece === 'n' && '♘'}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return null;
}