// src/types/diamond.ts

export interface ChessBetProposal {
    gameId: string;
    proposerId: string;
    proposerName: string;
    proposerDiamonds: number;
    betAmount: number;
    responderId: string;
    responderName: string;
    responderDiamonds: number;
    status: 'pending' | 'accepted' | 'declined' | 'expired';
    expiresAt: string;
  }
  
  export interface ChessGameWithBet {
    id: string;
    room_id: string;
    white_player_id: string;
    black_player_id: string;
    fen: string;
    pgn?: string;
    status: 'pending' | 'active' | 'checkmate' | 'stalemate' | 'draw' | 'resigned' | 'abandoned';
    winner_id?: string;
    bet_amount?: number;
    is_bet_match: boolean;
    bet_status?: 'pending' | 'locked' | 'paid_out';
    last_move?: { from: string; to: string };
    created_at: string;
    updated_at: string;
  }
  
  export type ChessMatchType = 'normal' | 'bet';
  
  export interface DiamondTransaction {
    id: string;
    user_id: string;
    type: 'purchase' | 'withdrawal' | 'bet_deduct' | 'bet_win' | 'bet_refund';
    amount: number;
    description: string;
    status: 'pending' | 'completed' | 'failed';
    payment_reference?: string;
    created_at: string;
  }