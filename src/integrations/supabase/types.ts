export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      chess_games: {
        Row: {
          black_player_id: string
          created_at: string
          fen: string
          id: string
          last_move: Json | null
          pgn: string | null
          room_id: string | null
          status: string
          updated_at: string
          white_player_id: string
          winner_id: string | null
        }
        Insert: {
          black_player_id: string
          created_at?: string
          fen?: string
          id?: string
          last_move?: Json | null
          pgn?: string | null
          room_id?: string | null
          status?: string
          updated_at?: string
          white_player_id: string
          winner_id?: string | null
        }
        Update: {
          black_player_id?: string
          created_at?: string
          fen?: string
          id?: string
          last_move?: Json | null
          pgn?: string | null
          room_id?: string | null
          status?: string
          updated_at?: string
          white_player_id?: string
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chess_games_black_player_id_fkey"
            columns: ["black_player_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chess_games_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chess_games_white_player_id_fkey"
            columns: ["white_player_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chess_games_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          created_at: string
          id: string
          is_validated: boolean | null
          reason: string | null
          reported_user_id: string
          reporter_id: string | null
          room_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_validated?: boolean | null
          reason?: string | null
          reported_user_id: string
          reporter_id?: string | null
          room_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_validated?: boolean | null
          reason?: string | null
          reported_user_id?: string
          reporter_id?: string | null
          room_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reports_reported_user_id_fkey"
            columns: ["reported_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      room_participants: {
        Row: {
          id: string
          joined_at: string
          left_at: string | null
          room_id: string
          user_id: string
        }
        Insert: {
          id?: string
          joined_at?: string
          left_at?: string | null
          room_id: string
          user_id: string
        }
        Update: {
          id?: string
          joined_at?: string
          left_at?: string | null
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "room_participants_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      rooms: {
        Row: {
          created_at: string
          creator_gender: string | null
          creator_id: string | null
          gender_preference:
            | Database["public"]["Enums"]["gender_preference"]
            | null
          id: string
          interest_category:
            | Database["public"]["Enums"]["interest_category"]
            | null
          is_active: boolean
          room_code: string | null
          room_size: number
          room_type: Database["public"]["Enums"]["room_type"]
        }
        Insert: {
          created_at?: string
          creator_gender?: string | null
          creator_id?: string | null
          gender_preference?:
            | Database["public"]["Enums"]["gender_preference"]
            | null
          id?: string
          interest_category?:
            | Database["public"]["Enums"]["interest_category"]
            | null
          is_active?: boolean
          room_code?: string | null
          room_size?: number
          room_type?: Database["public"]["Enums"]["room_type"]
        }
        Update: {
          created_at?: string
          creator_gender?: string | null
          creator_id?: string | null
          gender_preference?:
            | Database["public"]["Enums"]["gender_preference"]
            | null
          id?: string
          interest_category?:
            | Database["public"]["Enums"]["interest_category"]
            | null
          is_active?: boolean
          room_code?: string | null
          room_size?: number
          room_type?: Database["public"]["Enums"]["room_type"]
        }
        Relationships: [
          {
            foreignKeyName: "rooms_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      signaling: {
        Row: {
          created_at: string
          id: string
          message_type: string
          payload: Json
          room_id: string
          sender_id: string
          target_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          message_type: string
          payload: Json
          room_id: string
          sender_id: string
          target_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          message_type?: string
          payload?: Json
          room_id?: string
          sender_id?: string
          target_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "signaling_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "signaling_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "signaling_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          ban_count: number
          banned_until: string | null
          browser_fingerprint: string | null
          created_at: string
          display_name: string
          gender: string | null
          health_tokens: number
          id: string
          ip_address: string | null
          is_permanently_banned: boolean
          session_token: string | null
          updated_at: string
        }
        Insert: {
          ban_count?: number
          banned_until?: string | null
          browser_fingerprint?: string | null
          created_at?: string
          display_name: string
          gender?: string | null
          health_tokens?: number
          id?: string
          ip_address?: string | null
          is_permanently_banned?: boolean
          session_token?: string | null
          updated_at?: string
        }
        Update: {
          ban_count?: number
          banned_until?: string | null
          browser_fingerprint?: string | null
          created_at?: string
          display_name?: string
          gender?: string | null
          health_tokens?: number
          id?: string
          ip_address?: string | null
          is_permanently_banned?: boolean
          session_token?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      cleanup_old_signals: { Args: never; Returns: undefined }
      generate_room_code: { Args: never; Returns: string }
    }
    Enums: {
      gender_preference: "male" | "female" | "other"
      interest_category:
        | "student"
        | "music"
        | "entertainment"
        | "friend"
        | "random"
        | "iitians"
        | "nitians"
      room_type: "public" | "private"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      gender_preference: ["male", "female", "other"],
      interest_category: [
        "student",
        "music",
        "entertainment",
        "friend",
        "random",
        "iitians",
        "nitians",
      ],
      room_type: ["public", "private"],
    },
  },
} as const
