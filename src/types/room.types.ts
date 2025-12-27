// src/types/room.types.ts
// ✅ All type definitions for Room component

import { MembershipTier } from '@/lib/premiumStyles';

export interface Participant {
  id: string;
  user_id: string;
  display_name: string;
  membership_tier: MembershipTier;
  diamonds: number;
}

export interface ChessInvite {
  gameId: string;
  inviterId: string;
  inviterName: string;
  inviterDiamonds: number;
  isBetMatch: boolean;
  betAmount?: number;
}

export interface KickVote {
  targetUserId: string;
  targetUserName: string;
  initiatorId: string;
  initiatorName: string;
  votes: Set<string>;
  requiredVotes: number;
}

export interface RoomData {
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

export interface ActiveChessGame {
  gameId: string;
  myColor: 'white' | 'black';
  opponentId: string;
  opponentName: string;
  chessRoomId: string;
  isBetMatch: boolean;
  betAmount?: number;
}

export interface SelectedOpponent {
  id: string;
  name: string;
  diamonds: number;
}

export interface NextRoomStatus {
  isSearching: boolean;
  message: string;
}